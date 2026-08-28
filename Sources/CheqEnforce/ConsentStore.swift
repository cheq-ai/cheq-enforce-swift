import Foundation

/// Encapsulates all UserDefaults logic for storing + validating consent.
struct ConsentStore {
    
    private static let dataKey              = "cheqEnforceConsentData"
    private static let expiryKey            = "cheqEnforceConsentExpirationTime"
    private static let versionKey           = "cheqEnforceConsentVersion"
    private static let cookieFlagsKey       = "cheqEnforceBeaconCookieFlags"
    private static let environmentKey       = "cheqEnforceEnvironmentOverride"
    private static let environmentExpiryKey = "cheqEnforceEnvironmentOverrideExpiry"

    /// Whether expiry has been evaluated this session. Expiry is checked at
    /// most once before configure() (on the first read) and at every
    /// configure() (the session boundary); never on subsequent in-session
    /// reads, so consent valid at session start stays live until the next
    /// configure(). Internal so tests can reset it.
    static var hasValidatedExpiry = false

    /// Expiry-only prune, run at most once per session, covering consent
    /// reads that happen before configure(). Clears the stored record if it
    /// has lapsed. (configure() performs the full expiry + version check via
    /// `loadValid`.)
    static func validateExpiryOnce() {
        guard !hasValidatedExpiry else { return }
        hasValidatedExpiry = true
        let defaults = UserDefaults.standard
        if let expiry = defaults.value(forKey: expiryKey) as? Double,
           Date().timeIntervalSince1970 * 1_000 >= expiry {
            clearAll()
        }
    }
    
    /// Save or merge new consent flags, record version and expiration.
    /// - Parameters:
    ///   - consent: dictionary of consent category → Bool
    ///   - version: the current SDK version to validate against on load
    ///   - expirationMilliseconds: optional TTL from now (ms); defaults to 1 year
    static func save(
        _ consent: [String: Bool],
        version: String,
        expirationMilliseconds: Int? = nil
    ) {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970 * 1_000

        // Read existing consent via getAll(): the session's one-time expiry
        // prune has run by then, so a record that lapsed before this session
        // can't be resurrected by the merge or carry its expiry over below.
        var existing = getAll()

        // Determine new expiration
        let newExpiry: Double
        if let ms = expirationMilliseconds {
            newExpiry = now + Double(ms)
        } else if let current = defaults.value(forKey: expiryKey) as? Double {
            newExpiry = current
        } else {
            newExpiry = now + 365 * 24 * 60 * 60 * 1_000
        }

        // Merge new flags over the existing consent data
        for (k, v) in consent {
            existing[k] = v
        }
        
        // Persist
        defaults.set(existing, forKey: dataKey)
        defaults.set(newExpiry, forKey: expiryKey)
        defaults.set(version, forKey: versionKey)

        // Keep any environment override's lifetime in step with the consent
        // period: every consent save re-aligns the override's expiration to
        // the new consent expiration.
        if defaults.string(forKey: environmentKey) != nil {
            defaults.set(newExpiry, forKey: environmentExpiryKey)
        }
    }
    
    /// Load saved consent only if not expired and version matches; clears
    /// storage when invalid. This is the session-boundary gate: it runs
    /// synchronously in configure(), after which in-session reads never
    /// re-evaluate expiry.
    /// - Parameter version: current SDK version
    /// - Returns: stored consent or nil if expired/mismatched/not present
    static func loadValid(currentVersion version: String) -> [String: Bool]? {
        hasValidatedExpiry = true
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970 * 1_000
        
        // Verify expiry
        guard let expiry = defaults.value(forKey: expiryKey) as? Double,
              now < expiry else {
            clearAll()
            return nil
        }
        
        // Verify version
        guard let savedVersion = defaults.string(forKey: versionKey),
              savedVersion == version else {
            clearAll()
            return nil
        }
        
        // Return stored consent
        return defaults.dictionary(forKey: dataKey) as? [String: Bool]
    }
    
    /// Retrieve full consent dictionary or empty. The first read of a
    /// session prunes an expired record (so early `getConsent`/`checkConsent`
    /// calls never report lapsed consent), but reads never re-evaluate
    /// expiry after that: consent valid at session start remains available
    /// for the whole session and is removed at the next configure().
    static func getAll() -> [String: Bool] {
        validateExpiryOnce()
        return UserDefaults.standard.dictionary(forKey: dataKey) as? [String: Bool] ?? [:]
    }
    
    /// Retrieve consent for a single category.
    static func get(_ key: String) -> Bool {
        return getAll()[key] ?? false
    }
    
    /// Retrieve consent for multiple categories.
    static func get(_ keys: [String]) -> [String: Bool] {
        let all = getAll()
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, all[$0] ?? false) })
    }
    
    /// Persist the beacon cookie-flag accumulator (consent categories plus
    /// interaction flags like BANNER_VIEWED) so beacons after a relaunch
    /// still carry the full consent state. Shares the consent lifecycle:
    /// cleared by `clearAll()` on expiry, version change, or clearConsent().
    static func saveCookieFlags(_ flags: [String: Bool]) {
        UserDefaults.standard.set(flags, forKey: cookieFlagsKey)
    }

    /// The persisted beacon cookie-flag accumulator, or empty.
    static func cookieFlags() -> [String: Bool] {
        return UserDefaults.standard.dictionary(forKey: cookieFlagsKey) as? [String: Bool] ?? [:]
    }

    /// One-time migration for consent records written by versions whose modal
    /// keyed consent by display title instead of category key, applied to the
    /// consent record and the beacon cookie-flag accumulator (persisted and
    /// in-memory).
    /// - Returns: `true` when the consent record changed, so callers can
    ///   re-notify onConsent subscribers that received pre-migration keys.
    @discardableResult
    static func migrateTitleKeyedConsent(cookies: [String: CookieDetails]?) -> Bool {
        guard let cookies, !cookies.isEmpty else { return false }
        let defaults = UserDefaults.standard

        var consentChanged = false
        if let stored = defaults.dictionary(forKey: dataKey) as? [String: Bool] {
            let migrated = renamingTitleKeys(in: stored, using: cookies)
            if migrated != stored {
                defaults.set(migrated, forKey: dataKey)
                consentChanged = true
            }
        }

        BeaconState.renameCookieFlags { renamingTitleKeys(in: $0, using: cookies) }

        return consentChanged
    }

    /// Rewrites keys that are not category keys but uniquely match a
    /// category's title to that category's key. Ambiguous titles (shared by
    /// several categories) are left untouched, and an existing key-keyed
    /// entry is never overwritten.
    private static func renamingTitleKeys(in record: [String: Bool], using cookies: [String: CookieDetails]) -> [String: Bool] {
        var renamed = record
        for (storedKey, value) in record {
            guard cookies[storedKey] == nil else { continue }
            let matchingKeys = cookies.compactMap { key, details in
                details.title == storedKey ? key : nil
            }
            guard matchingKeys.count == 1, let key = matchingKeys.first else { continue }
            if renamed[key] == nil {
                renamed[key] = value
            }
            renamed.removeValue(forKey: storedKey)
        }
        return renamed
    }

    /// Persist the environment set via `setEnvironment()` so it can override
    /// the configured environment on future launches. The override carries
    /// its own expiration: initially the consent expiration in effect when
    /// it is saved (or the default TTL if no consent is stored), and then
    /// re-aligned to the consent expiration every time consent is saved (see
    /// `save`). It is not affected by `clearConsent()`; only expiry or
    /// `resetEnvironment()` remove it.
    static func saveEnvironmentOverride(_ environment: String) {
        let defaults = UserDefaults.standard
        let expiry: Double
        if let consentExpiry = defaults.value(forKey: expiryKey) as? Double {
            expiry = consentExpiry
        } else {
            let now = Date().timeIntervalSince1970 * 1_000
            expiry = now + 365 * 24 * 60 * 60 * 1_000
        }
        defaults.set(environment, forKey: environmentKey)
        defaults.set(expiry, forKey: environmentExpiryKey)
    }

    /// The persisted `setEnvironment()` override, if still within its
    /// expiration; an expired override is cleared and nil is returned.
    static func validEnvironmentOverride() -> String? {
        let defaults = UserDefaults.standard
        guard let environment = defaults.string(forKey: environmentKey) else { return nil }
        let now = Date().timeIntervalSince1970 * 1_000
        guard let expiry = defaults.value(forKey: environmentExpiryKey) as? Double,
              now < expiry else {
            clearEnvironmentOverride()
            return nil
        }
        return environment
    }

    /// Remove the persisted environment override (used by `resetEnvironment()`
    /// and on override expiry).
    static func clearEnvironmentOverride() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: environmentKey)
        defaults.removeObject(forKey: environmentExpiryKey)
    }

    /// Clear all stored consent data (used on expiry, version change, or an explicit `clearConsent()`).
    /// The environment override is deliberately untouched; it has its own
    /// expiration and is only removed by that or `resetEnvironment()`.
    static func clearAll() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dataKey)
        defaults.removeObject(forKey: expiryKey)
        defaults.removeObject(forKey: versionKey)
        defaults.removeObject(forKey: cookieFlagsKey)
    }
    
}
