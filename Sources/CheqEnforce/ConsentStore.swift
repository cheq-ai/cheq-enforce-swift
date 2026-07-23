import Foundation

/// Encapsulates all UserDefaults logic for storing + validating consent.
struct ConsentStore {
    
    private static let dataKey              = "cheqEnforceConsentData"
    private static let expiryKey            = "cheqEnforceConsentExpirationTime"
    private static let versionKey           = "cheqEnforceConsentVersion"
    private static let environmentKey       = "cheqEnforceEnvironmentOverride"
    private static let environmentExpiryKey = "cheqEnforceEnvironmentOverrideExpiry"
    
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
        
        // Determine new expiration
        let newExpiry: Double
        if let ms = expirationMilliseconds {
            newExpiry = now + Double(ms)
        } else if let existing = defaults.value(forKey: expiryKey) as? Double {
            newExpiry = existing
        } else {
            newExpiry = now + 365 * 24 * 60 * 60 * 1_000
        }
        
        // Merge with any existing consent data
        var existing = defaults.dictionary(forKey: dataKey) as? [String: Bool] ?? [:]
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
    
    /// Load saved consent only if not expired and version matches.
    /// - Parameter version: current SDK version
    /// - Returns: stored consent or nil if expired/mismatched/not present
    static func loadValid(currentVersion version: String) -> [String: Bool]? {
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
    
    /// Retrieve full consent dictionary or empty.
    static func getAll() -> [String: Bool] {
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
    }
    
}
