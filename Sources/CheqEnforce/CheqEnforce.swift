import os
import Foundation
import UIKit

public class Enforce {
    static internal let log = Logger(subsystem: "Cheq", category: "CheqEnforce")

    /// Serializes the environment statics below: written from fetch tasks,
    /// read from integrator threads.
    private static let stateQueue = DispatchQueue(label: "com.cheq.CheqEnforce.state")
    private static var _storedConfig: Config?
    private static var _lastResponse: JSONResponse?
    /// The environment `_lastResponse` was fetched for. `getConfiguration()`
    /// serves the response only while this matches the effective environment.
    private static var _lastResponseEnvironment: String?
    private static var _configuredEnvironmentResponse: JSONResponse?
    private static var _configuredEnvironment: String?
    /// A refetch owed after an environment change. Retries are demand-driven,
    /// from `getConfiguration()` or a repeat `resetEnvironment()`.
    private static var _pendingRefetchConfig: Config?
    private static var _refetchInFlight = false
    /// Identifies the cycle holding `_refetchInFlight`. A superseded cycle
    /// must not release the guard, stamp a give-up, or keep retrying: all of
    /// that belongs to whichever cycle is current.
    private static var _refetchGeneration = 0
    /// Bound the cost of an unreachable environment: one cycle per cool-down
    /// however often it is read, and one beacon per owed refetch. Stamped on
    /// the monotonic clock, since a wall-clock jump backwards would leave a
    /// cool-down that never expires.
    private static var _refetchExhaustedAt: DispatchTime?
    private static var _refetchExhaustionReported = false

    static var storedConfig: Config? {
        get { stateQueue.sync { _storedConfig } }
        set { stateQueue.sync { _storedConfig = newValue } }
    }

    /// The currently presented consent banner (alert or themed bottom sheet),
    /// if any. Tracked so it can be dismissed by `clearConsent()`.
    static weak var currentBanner: UIViewController?

    /// The currently presented consent modal, if any. Tracked so it can be dismissed by `clearConsent()`.
    static weak var currentModal: UIViewController?
    
    /// signature for consent-change callbacks
    public typealias ConsentChangeHandler = ([String: Bool]) -> Void

    /// all user-registered onConsent() closures; guarded by
    /// `consentHandlersQueue` since notification also runs from async tasks
    private static var consentHandlers: [ConsentChangeHandler] = []
    private static let consentHandlersQueue = DispatchQueue(label: "com.cheq.CheqEnforce.consentHandlers")

    /// Invokes every registered handler with `consent`, on a snapshot of the
    /// handler list so concurrent registration can't race the iteration.
    private static func notifyConsentHandlers(_ consent: [String: Bool]) {
        let handlers = consentHandlersQueue.sync { consentHandlers }
        for handler in handlers {
            handler(consent)
        }
    }

    /// register a callback to run *every* time consent is updated
    ///
    /// If the SDK is already configured and consent is available, the handler
    /// is also invoked immediately with the current consent, so registration
    /// before or after ``configure(_:)`` behaves the same.
    /// - Parameter handler: receives the *current* full consent dictionary
    public static func onConsent(_ handler: @escaping ConsentChangeHandler) {
        consentHandlersQueue.sync { consentHandlers.append(handler) }
        if storedConfig != nil {
            let current = getConsent()
            if !current.isEmpty {
                handler(current)
            }
        }
    }
    
    #if DEBUG
    /// Clears all registered onConsent handlers. Only for tests.
    internal static func _resetConsentHandlers() {
        consentHandlersQueue.sync { consentHandlers.removeAll() }
    }
    #endif
    
    /// The response currently in effect. Read-only: it is written only by
    /// ``adoptResponse(_:for:)`` and its launch/switch variants, which set
    /// the response and its environment tag together, so the two can never
    /// drift apart and serve one environment's document under another's tag.
    static var lastResponse: JSONResponse? {
        stateQueue.sync { _lastResponse }
    }

    /// The configured (non-override) environment's response, kept so
    /// ``resetEnvironment()`` can restore it without a refetch.
    static var configuredEnvironmentResponse: JSONResponse? {
        get { stateQueue.sync { _configuredEnvironmentResponse } }
        set { stateQueue.sync { _configuredEnvironmentResponse = newValue } }
    }

    #if DEBUG
    /// Test hook: the environment `_lastResponse` is currently tagged for.
    static var lastResponseEnvironment: String? {
        stateQueue.sync { _lastResponseEnvironment }
    }

    /// Test hook: whether an owed refetch is still pending. Only for tests.
    static var refetchPending: Bool {
        stateQueue.sync { _pendingRefetchConfig != nil }
    }

    /// Test hook: whether a refetch is currently running. Only for tests.
    static var refetchInFlightForTests: Bool {
        stateQueue.sync { _refetchInFlight }
    }

    /// Test hook: refetch give-up beacons sent so far.
    static var _refetchExhaustionBeacons = 0

    /// Test hook: clears the environment-refetch bookkeeping.
    static func _resetRefetchState() {
        stateQueue.sync { _clearOwedRefetch(); _cancelRefetchCycle() }
    }

    /// Test hook: the one transition `adoptResponse(_:for:)` can't express —
    /// clearing the response and its environment tag together.
    static func _clearResponse() {
        stateQueue.sync { _lastResponse = nil; _lastResponseEnvironment = nil }
    }
    #endif

    /// Discards the owed refetch, so the next one starts with a fresh
    /// cool-down and beacon budget. Must only be called on `stateQueue`.
    private static func _clearOwedRefetch() {
        _pendingRefetchConfig = nil
        _refetchExhaustedAt = nil
        _refetchExhaustionReported = false
    }

    /// Must only be called on `stateQueue`.
    private static func _beginRefetchCycle() -> Int {
        _refetchInFlight = true
        _refetchGeneration += 1
        return _refetchGeneration
    }

    /// Must only be called on `stateQueue`.
    private static func _cancelRefetchCycle() {
        _refetchInFlight = false
        _refetchGeneration += 1
    }

    private static func refetchCycleIsCurrent(_ generation: Int) -> Bool {
        stateQueue.sync { generation == _refetchGeneration }
    }

    /// Adopt logic shared by the synchronized entry points below.
    /// Must only be called on `stateQueue`.
    private static func _adopt(_ response: JSONResponse, for environment: String) -> Bool {
        guard _storedConfig?.environment == environment else {
            log.info("Discarding fetched environment.json for “\(environment, privacy: .public)”; the effective environment is now “\(_storedConfig?.environment ?? "none", privacy: .public)”.")
            return false
        }
        _lastResponse = response
        _lastResponseEnvironment = environment
        _clearOwedRefetch()
        if environment == _configuredEnvironment {
            _configuredEnvironmentResponse = response
        }
        return true
    }

    /// Adopts a fetched `environment.json` response only when `environment`
    /// is still the effective one; superseded fetches are discarded.
    @discardableResult
    static func adoptResponse(_ response: JSONResponse, for environment: String) -> Bool {
        stateQueue.sync { _adopt(response, for: environment) }
    }

    /// Adopts the fetch (or falls back to the already-effective response when
    /// superseded) and returns the response/config pair the launch flow
    /// should use, as one atomic read.
    static func adoptResponseForLaunch(_ response: JSONResponse, for environment: String) -> (response: JSONResponse, config: Config)? {
        stateQueue.sync {
            let adopted = _adopt(response, for: environment)
            guard let effective = adopted ? response : _lastResponse,
                  let config = _storedConfig else { return nil }
            return (effective, config)
        }
    }

    /// Atomically installs an environment switch: the new config and its
    /// freshly fetched response together, so readers can't observe one
    /// without the other.
    static func adoptEnvironmentSwitch(config: Config, response: JSONResponse) {
        stateQueue.sync {
            _storedConfig = config
            _ = _adopt(response, for: config.environment)
        }
    }
    
    static var  cachedInstanceId: String = {
        return randomBase36InstanceId()
    }()
    static var storedCookieFlags: [String: Bool] {
        get { BeaconState.cookieFlags }
        set { BeaconState.setCookieFlags(newValue) }
    }
    
    let config:Config
    init(config: Config) {
        self.config = config
    }
    
    /// Configure the SDK with your client-name, paths, environment, and defaults.
    ///
    /// After calling this, Enforce will:
    ///  1. send a “reporting” beacon,
    ///  2. check stored consent (and skip UI if still valid),
    ///  3. if no consent, fetch translations JSON and show the banner or modal.
    ///
    /// - Parameter config: your `Config` object (clientName, publishPath, environment, etc.)
    public static func configure(_ config: Config) {
        // Session boundary: validate stored consent once (expiry + version),
        // synchronously, before anything reads it. In-session reads never
        // re-evaluate expiry, so consent valid now stays live until the
        // next configure().
        let validConsentAtLaunch = ConsentStore.loadValid(currentVersion: config.version)

        // Restore the beacon cookie-flag accumulator (categories plus
        // interaction flags) persisted alongside consent, so beacons sent
        // this session carry the full consent state. loadValid cleared it
        // if the consent record lapsed. Categories from the validated
        // consent are merged in as a fallback for records stored before
        // flag persistence existed.
        var restoredFlags = ConsentStore.cookieFlags()
        if let saved = validConsentAtLaunch {
            for (key, value) in saved where restoredFlags[key] == nil {
                restoredFlags[key] = value
            }
        }
        storedCookieFlags = restoredFlags

        // Remember the app-supplied environment so resetEnvironment() can
        // return to it, then apply any unexpired setEnvironment() override.
        let appEnvironment = config.environment
        let config = applyingStoredEnvironment(config)

        // Build environment.json URL from configuration values. A config
        // that can't produce one leaves the previous state untouched.
        guard let url = TranslationService.buildURL(config: config) else { return }
        log.info("URL to retrieve translations: \(url)")

        // One atomic install: the configured environment, its (not yet
        // fetched) snapshot, the effective config, and a clean refetch slate,
        // so a reader on another thread can't observe one without the others.
        stateQueue.sync {
            _configuredEnvironment = appEnvironment
            _configuredEnvironmentResponse = nil
            _storedConfig = config
            _clearOwedRefetch()
            _cancelRefetchCycle()
        }
        
        // Trigger consent callbacks when there is consent to report; an empty
        // map is reserved for clearConsent()'s "consent revoked" signal.
        let latest = getConsent()
        if !latest.isEmpty {
            notifyConsentHandlers(latest)
        }

        //Get translations and show banner or modal
        Task {
            do {
                let jsonData = try await TranslationService.fetchJSON(from: url, debug: config.debug)
                let jsonResponse = try JSONDecoder().decode(JSONResponse.self, from: jsonData)
                // If superseded by setEnvironment(), continue the launch flow
                // (billing beacon, initial UI) on the now-effective response.
                guard let (response, effectiveConfig) = Self.adoptResponseForLaunch(jsonResponse, for: config.environment) else { return }
                log.info("Successfully decoded JSON file")

                if ConsentStore.migrateTitleKeyedConsent(cookies: response.translation.cookies) {
                    // Re-notify subscribers that received pre-migration keys.
                    let migrated = getConsent()
                    if !migrated.isEmpty {
                        notifyConsentHandlers(migrated)
                    }
                }

                //Send Load beacon
                Task {
                    await ConsentReporting.send(config: effectiveConfig, type: .billing, clientId: response.clientId, version: response.version, enforcement: response.enforcement)
                }
                
                //If consent was found at the session boundary, do nothing further.
                //(Uses the result of configure()'s synchronous validation; expiry is not
                //re-evaluated. The onConsent handlers already fired synchronously in
                //configure() with this validated consent, so no re-fire here.)
                if let saved = validConsentAtLaunch {
                    log.info("Saved consent found: \(saved). No need to show the banner.")
                    return
                }
                
                // If autoShow is false, do nothing further
                guard effectiveConfig.autoShow else {
                    log.info("autoShow is false; skipping initial UI display.")
                    return
                }

                //Show banner or modal
                if response.enablePrivacyNotice {
                    guard let bannerConfig = response.bannerConfig else {
                        log.error("Cannot show banner: Banner on but no banner config found")
                        Task {
                            _ = await ErrorReporting.sendError(msg: "Cannot show banner: Banner on but no banner config found", fn: #function, clientId: response.clientId, config: effectiveConfig)
                        }
                        return
                    }
                    BannerPresenter.show(
                        translation: response.translation,
                        bannerConfig: bannerConfig,
                        consentModalConfig: response.consentModalConfig ?? ConsentModalConfig(ensConsentAcceptAll: nil, ensConsentRejectAll: nil, ensSaveModal: nil, ensCloseModal: nil),
                        config: effectiveConfig,
                        delay: 1.0
                    )
                } else if response.enableConsentModal {
                    log.info("No Banner found. Opening Modal")
                    ModalPresenter.show(
                        translation: response.translation,
                        consentModalConfig: response.consentModalConfig ?? ConsentModalConfig(ensConsentAcceptAll: nil, ensConsentRejectAll: nil, ensSaveModal: nil, ensCloseModal: nil),
                        config: effectiveConfig,
                        delay: 1.0
                    )

                } else {
                    log.error("No translations available: neither banner content nor consent description found.")
                }
                
            } catch {
                log.error("Failed to fetch or decode JSON: \(error.localizedDescription, privacy: .public)")
                Task {
                    _ = await ErrorReporting.sendError(msg: "Failed to fetch or decode JSON", fn: #function, config: config)
                }
            }
        }
    }
    
    ///
    /// - Parameter category: the consent key, e.g. `"Analytics"`.
    /// - Returns: `true` if stored consent for that category is `true`, else `false`.
    public static func checkConsent(_ category: String) -> Bool {
        return ConsentStore.get(category)
    }
    
    /// Retrieve the full stored consent dictionary.
    ///
    /// - Returns: a `[String: Bool]` mapping each category to its consent value.
    public static func getConsent() -> [String: Bool] {
        return ConsentStore.getAll()
    }
    
    // Retrieve stored consent for exactly one key.
    ///
    /// - Parameter key: the consent key, e.g. `"Marketing"`.
    /// - Returns: a single-entry dictionary `[key: value]`.
    public static func getConsent(for key: String) -> [String: Bool] {
        let allowed = ConsentStore.get(key)
        return [ key: allowed ]
    }
    
    /// Retrieve stored consent for multiple keys.
    ///
    /// - Parameter keys: an array of keys, e.g. `["Analytics","Functional"]`.
    /// - Returns: a `[String: Bool]` mapping each requested key to its stored value.
    public static func getConsent(for keys: [String]) -> [String: Bool] {
        return ConsentStore.get(keys)
    }
    
    /// Retrieve the remote consent configuration (translations, banner &
    /// modal button configuration) fetched from the remote JSON file, so a
    /// customer can implement their own consent experience.
    ///
    /// - Returns: the configuration for the environment currently in effect,
    ///   or `nil` when no document for that environment has been fetched yet —
    ///   before ``configure(_:)``'s fetch completes, or after a
    ///   ``setEnvironment(_:)`` / ``resetEnvironment()`` change whose refetch
    ///   has not yet succeeded. It never returns another environment's
    ///   document. A failed refetch is retried here on demand, at most one
    ///   cycle per cool-down however often this is called.
    public static func getConfiguration() -> EnforceConfiguration? {
        let (response, retry): (JSONResponse?, (config: Config, generation: Int)?) = stateQueue.sync {
            guard _lastResponseEnvironment == _storedConfig?.environment else {
                // Tag mismatch: report nil, and re-arm the owed refetch so a
                // later call recovers once the network does.
                guard let pending = _pendingRefetchConfig, !_refetchInFlight else { return (nil, nil) }
                // A per-render or polling reader must not turn an unreachable
                // environment into continuous request traffic.
                if let exhaustedAt = _refetchExhaustedAt,
                   monotonicSeconds(since: exhaustedAt) < _refetchCoolDown {
                    return (nil, nil)
                }
                return (nil, (pending, _beginRefetchCycle()))
            }
            return (_lastResponse, nil)
        }
        if let retry { refetchResponse(for: retry.config, generation: retry.generation) }
        guard let response else { return nil }
        return EnforceConfiguration(from: response)
    }

    /// Overwrite (or merge) one or more consent categories.
    ///
    /// - Parameter consent: a `[String:Bool]` of the categories & values to set.
    ///   e.g. `["Analytics":true, "Marketing":false]`.
    public static func setConsent(_ consent: [String: Bool]) {
        setConsent(consent, beaconExtras: [:]) // funnel to internal
    }
    
    internal static func setConsent(_ consent: [String: Bool], beaconExtras: [String: Bool] = [:]) {
        log.info("Setting provided consent: \(consent).")
        
        guard let currentConfig = storedConfig else {
            log.error("Config not found. Ensure `configure` was called first.")
            return
        }
        
        ConsentStore.save(
            consent,
            version: currentConfig.version,
            expirationMilliseconds: currentConfig.dataRetentionPeriod
        )
        
        //Trigger consent callbacks
        notifyConsentHandlers(getConsent())
        
        guard let resp = Enforce.lastResponse else { return }
        var reportFlags = consent
        for (k, v) in beaconExtras { reportFlags[k] = v }
        Task { await ConsentReporting.send(config: currentConfig, type: .consent, clientId: resp.clientId, version: resp.version, enforcement: resp.enforcement, cookieFlags: reportFlags) }
    }
    
    /// Remove all stored consent, reverting the user to a "no consent" state.
    ///
    /// Intended for flows such as logout, account switch, or an in-app "reset privacy" action.
    /// In order, this:
    ///  1. deletes the persisted consent record from storage,
    ///  2. notifies every ``onConsent(_:)`` subscriber with an empty map (`[:]`),
    ///  3. dismisses any currently visible consent banner or modal.
    ///
    /// After clearing, ``getConsent()`` returns `[:]` and ``checkConsent(_:)`` returns `false`
    /// for every category. On the next ``configure(_:)`` call the SDK finds no stored consent and
    /// follows its normal auto-show logic (banner or modal, depending on remote config).
    public static func clearConsent() async {
        log.info("Clearing all stored consent.")

        // Remove the persisted consent record from storage.
        ConsentStore.clearAll()

        // Reset the in-memory cookie-flag accumulator so subsequent reporting
        // beacons don't carry over consent flags from before the clear.
        storedCookieFlags = [:]

        // Notify onConsent subscribers that consent is now absent.
        notifyConsentHandlers([:])

        // Dismiss any currently visible consent banner or modal.
        await MainActor.run {
            currentBanner?.dismiss(animated: true)
            currentModal?.dismiss(animated: true)
        }
    }

    /// The environment currently in effect, including a persisted
    /// ``setEnvironment(_:)`` override applied during ``configure(_:)``.
    ///
    /// - Returns: the effective environment, or `nil` if ``configure(_:)``
    ///   has not been called yet.
    public static func getEnvironment() -> String? {
        return storedConfig?.environment
    }

    /// Discard a persisted ``setEnvironment(_:)`` override and return to the
    /// environment supplied to ``configure(_:)``, both for the current
    /// session and future launches.
    ///
    /// If a previous reset's refetch is still owed because the network was
    /// unreachable, calling this again retries it immediately, so recovery
    /// doesn't depend on ``getConfiguration()`` being called.
    public static func resetEnvironment() {
        ConsentStore.clearEnvironmentOverride()

        // One atomic transition. The override's response stays until a
        // replacement is adopted, because beacons are gated on lastResponse
        // and nilling it would drop consent reporting.
        let refetch: (config: Config, generation: Int)? = stateQueue.sync {
            guard let currentConfig = _storedConfig else {
                log.info("resetEnvironment(): no stored config; nothing to reset.")
                return nil
            }
            guard let original = _configuredEnvironment else {
                log.info("resetEnvironment(): no configured environment recorded; nothing to reset.")
                return nil
            }
            guard original != currentConfig.environment else {
                // Already reverted, but an earlier revert's refetch may still
                // be owed — and an integrator using only the built-in banner
                // never calls getConfiguration() to retry it. An explicit
                // reset is a fresh attempt, so it skips the cool-down; the
                // beacon budget stays spent so a caller looping here can't
                // turn it into repeated error reports.
                guard let pending = _pendingRefetchConfig, !_refetchInFlight else {
                    log.info("resetEnvironment(): already using the configured environment.")
                    return nil
                }
                log.info("resetEnvironment(): already using configured “\(original, privacy: .public)”; retrying its owed refetch now.")
                _refetchExhaustedAt = nil
                return (pending, _beginRefetchCycle())
            }
            let revertedConfig = replacingEnvironment(of: currentConfig, with: original)
            _storedConfig = revertedConfig
            log.info("resetEnvironment(): environment reverted to configured “\(original, privacy: .public)”.")

            if let snapshot = _configuredEnvironmentResponse {
                _ = _adopt(snapshot, for: original)
                return nil
            }
            // No snapshot: owe a refetch. Until it lands the tag mismatch
            // keeps getConfiguration() at nil rather than the abandoned
            // document, while beacons keep using lastResponse.
            _clearOwedRefetch()
            _pendingRefetchConfig = revertedConfig
            return (revertedConfig, _beginRefetchCycle())
        }
        if let refetch {
            refetchResponse(for: refetch.config, generation: refetch.generation)
        }
    }

    private static let refetchAttempts = 3
    /// Wait between attempts within a cycle, and the minimum wait after a
    /// cycle gives up before `getConfiguration()` may start another.
    #if DEBUG
    /// Shortened by tests.
    static var _refetchRetryDelay: TimeInterval = 2
    static var _refetchCoolDown: TimeInterval = 60
    #else
    private static let _refetchRetryDelay: TimeInterval = 2
    private static let _refetchCoolDown: TimeInterval = 60
    #endif

    /// Seconds elapsed since `start` on the monotonic uptime clock. The
    /// ordering guard keeps the unsigned subtraction from underflowing into
    /// a decades-long interval; zero elapsed holds the cool-down.
    private static func monotonicSeconds(since start: DispatchTime) -> TimeInterval {
        let now = DispatchTime.now().uptimeNanoseconds
        let then = start.uptimeNanoseconds
        guard now > then else { return 0 }
        return TimeInterval(now - then) / 1_000_000_000
    }

    /// Stamps a give-up for the cool-down and beacons it once per owed
    /// refetch, not once per cycle. `fn` defaults at the call site so the
    /// beacon names the refetch entry point, not this helper.
    private static func noteRefetchGiveUp(config: Config, generation: Int, msg: String, fn: String = #function) {
        let firstGiveUp: Bool = stateQueue.sync {
            guard generation == _refetchGeneration else { return false }
            _refetchExhaustedAt = DispatchTime.now()
            guard !_refetchExhaustionReported else { return false }
            _refetchExhaustionReported = true
            return true
        }
        guard firstGiveUp else { return }
        #if DEBUG
        stateQueue.sync { _refetchExhaustionBeacons += 1 }
        #endif
        Task {
            _ = await ErrorReporting.sendError(msg: msg, fn: fn, config: config)
        }
    }

    /// Fetches and adopts `environment.json` for the given config in the
    /// background, retrying a bounded number of times; a response for a
    /// since-superseded environment is discarded and ends the attempts.
    private static func refetchResponse(for config: Config, generation: Int) {
        Task {
            // Release only while this cycle still owns the flag, leaving
            // `_pendingRefetchConfig` set for a later on-demand retry; a
            // superseded cycle must not release it, since the newer cycle
            // holds it. The URL is built inside the Task so an unbuildable
            // one releases too, rather than wedging getConfiguration() at nil.
            defer {
                stateQueue.sync {
                    guard generation == _refetchGeneration else { return }
                    _refetchInFlight = false
                }
            }
            guard let url = TranslationService.buildURL(config: config) else {
                log.error("Refetch of environment.json skipped: no URL could be built for “\(config.environment, privacy: .public)”.")
                // Nothing to retry until the config changes, so stamp and
                // report it like an exhausted cycle.
                noteRefetchGiveUp(config: config, generation: generation, msg: "Failed to refetch environment.json after resetEnvironment: no URL could be built")
                return
            }
            for attempt in 1...refetchAttempts {
                guard refetchCycleIsCurrent(generation) else { return }
                do {
                    let data = try await TranslationService.fetchJSON(from: url, debug: config.debug)
                    let response = try JSONDecoder().decode(JSONResponse.self, from: data)
                    adoptResponse(response, for: config.environment)
                    return
                } catch {
                    log.error("Refetch of environment.json for “\(config.environment, privacy: .public)” failed (attempt \(attempt)/\(refetchAttempts)): \(error.localizedDescription, privacy: .public)")
                    if attempt == refetchAttempts {
                        noteRefetchGiveUp(config: config, generation: generation, msg: "Failed to refetch environment.json after resetEnvironment")
                    } else {
                        try? await Task.sleep(nanoseconds: UInt64(_refetchRetryDelay * 1_000_000_000))
                    }
                }
            }
        }
    }

    /// The environment passed to `configure(_:)`, before any stored
    /// override was applied. Used by `resetEnvironment()`.
    internal static var configuredEnvironment: String? {
        get { stateQueue.sync { _configuredEnvironment } }
        set { stateQueue.sync { _configuredEnvironment = newValue } }
    }

    /// Returns the config with a persisted, unexpired `setEnvironment()`
    /// override applied; otherwise returns the config as-is. The override
    /// carries its own expiration (snapshotted from the consent expiration
    /// when it was saved), so it falls back automatically when that period
    /// ends.
    internal static func applyingStoredEnvironment(_ config: Config) -> Config {
        guard let override = ConsentStore.validEnvironmentOverride(),
              override != config.environment else {
            return config
        }
        log.info("Using stored environment override “\(override, privacy: .public)” from setEnvironment(); reverts to “\(config.environment, privacy: .public)” on expiry or resetEnvironment().")
        return replacingEnvironment(of: config, with: override)
    }

    /// Rebuilds a Config with a different environment, all other fields unchanged.
    private static func replacingEnvironment(of config: Config, with environment: String) -> Config {
        return Config(
            config.clientName,
            publishPath: config.publishPath,
            environment: environment,
            debug: config.debug,
            dataRetentionPeriod: config.dataRetentionPeriod,
            autoShow: config.autoShow,
            version: config.version,
            defaultConsent: config.defaultConsent,
            appearance: config.appearance,
            theme: config.theme
        )
    }

    /// Errors thrown by ``setEnvironment(_:)``.
    public enum EnvironmentError: Error, LocalizedError, Equatable {
        /// ``configure(_:)`` has not been called yet.
        case notConfigured
        /// The environment string is empty or cannot form a valid URL.
        case invalidEnvironment(String)

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Enforce.configure() must be called before setEnvironment()."
            case .invalidEnvironment(let environment):
                return "Invalid environment string: “\(environment)”."
            }
        }
    }

    ///Change the environment string (you must call `configure` first).
    ///
    /// The new environment is persisted and overrides the configured one on
    /// future launches. Its lifetime follows the consent period: each time
    /// consent is saved, the override's expiration is re-aligned to the new
    /// consent expiration, and once that period lapses the SDK reverts to
    /// the configured environment. It is not affected by ``clearConsent()``;
    /// use ``resetEnvironment()`` to discard it explicitly.
    ///
    /// - Parameter environment: the new `environment` value.
    /// - Throws: ``EnvironmentError`` if `configure` hasn’t been called or the
    ///   environment string is empty/invalid; `URLError` or `DecodingError` if
    ///   the JSON at the new URL can’t be fetched/parsed.
    public static func setEnvironment(_ environment: String) async throws {
        let fn = #function
        guard let currentConfig = storedConfig else {
            log.error("Config not found. Ensure `configure` was called first.")
            throw EnvironmentError.notConfigured
        }

        // Error beacons need a clientId, which only exists once the initial
        // fetch has decoded; without one the beacon is skipped, never the
        // validation.
        let clientId = Enforce.lastResponse?.clientId
        func reportError(_ msg: String) {
            guard let clientId else { return }
            Task {
                _ = await ErrorReporting.sendError(msg: msg, fn: fn, clientId: clientId, config: currentConfig)
            }
        }

        // Reject empty input up front: an empty path component would silently
        // drop out of the URL and fetch a different (env-less) document.
        guard !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.error("Invalid environment string: empty")
            reportError("Invalid environment string: empty")
            throw EnvironmentError.invalidEnvironment(environment)
        }

        // Create a new Config instance with the updated environment
        let updatedConfig = Config(
            currentConfig.clientName,
            publishPath: currentConfig.publishPath,
            environment: environment, // Update environment here
            debug: currentConfig.debug,
            dataRetentionPeriod: currentConfig.dataRetentionPeriod,
            autoShow: currentConfig.autoShow,
            version: currentConfig.version,
            defaultConsent: currentConfig.defaultConsent,
            appearance: currentConfig.appearance,
            theme: currentConfig.theme
        )

        // construct the URL
        guard let url = TranslationService.buildURL(config: updatedConfig) else {
            log.error("Invalid environment string: \(environment, privacy: .public)")
            reportError("Invalid environment string")
            throw EnvironmentError.invalidEnvironment(environment)
        }

        do {
            // try to fetch & parse the JSON; this validates that the env really exists
            let data = try await TranslationService.fetchJSON(from: url, debug: currentConfig.debug)
            let response = try JSONDecoder().decode(JSONResponse.self, from: data)

            // Successfully fetched. Store new config, adopt the new
            // environment's response, and persist the override so future
            // launches keep this environment (until consent expires).
            adoptEnvironmentSwitch(config: updatedConfig, response: response)
            ConsentStore.saveEnvironmentOverride(environment)
            log.info("Environment updated to: \(environment, privacy: .public)")
        } catch {
            // fetch or decode failed; roll back
            log.error("Environment ‘\(environment)’ isn’t valid, keeping previous “\(currentConfig.environment)”; error: \(error.localizedDescription, privacy: .public)")
            reportError("Environment ‘\(environment)’ isn’t valid, keeping previous")
            throw error
        }
    }
    
    /// Immediately fetch & show the banner (for manual control).
    public static func showBanner() {
        guard let cfg = storedConfig,
              let url = TranslationService.buildURL(config: cfg)
        else {
            log.error("Enforce not configured.")
            return
        }
        
        Task {
            let data     = try await TranslationService.fetchJSON(from: url, debug: cfg.debug)
            let response = try JSONDecoder().decode(JSONResponse.self, from: data)
            
            if response.enablePrivacyNotice {
                guard let bannerConfig = response.bannerConfig else {
                    log.error("Cannot show banner: Banner on but no banner config found")
                    Task {
                        _ = await ErrorReporting.sendError(msg: "Cannot show banner: Banner on but no banner config found", fn: #function, clientId: response.clientId, config: cfg)
                    }
                    return
                }
                BannerPresenter.show(
                    translation:           response.translation,
                    bannerConfig:          bannerConfig,
                    consentModalConfig:    response.consentModalConfig ?? .init(ensConsentAcceptAll: nil, ensConsentRejectAll: nil, ensSaveModal: nil, ensCloseModal: nil),
                    config: cfg
                )
            } else {
                log.info("Banner not turned on. Skipping showing banner.")
            }
        }
    }
    
    /// Immediately fetch & show the modal (for manual control).
    public static func showModal() {
        guard let cfg = storedConfig,
              let url = TranslationService.buildURL(config: cfg)
        else {
            log.error("Enforce not configured.")
            return
        }
        
        Task {
            let data     = try await TranslationService.fetchJSON(from: url, debug: cfg.debug)
            let response = try JSONDecoder().decode(JSONResponse.self, from: data)
            
            if response.enableConsentModal {
                guard let modalConfig = response.consentModalConfig else {
                    log.error("Cannot show Modal: Modal on but no Modal config found")
                    Task {
                        _ = await ErrorReporting.sendError(msg: "Cannot show Modal: Modal on but no Modal config found", fn: #function, clientId: response.clientId, config: cfg)
                    }
                    return
                }
                ModalPresenter.show(
                    translation:           response.translation,
                    consentModalConfig:    modalConfig,
                    config:                cfg
                )
            } else {
                log.info("Modal not turned on. Skipping showing Modal.")
            }
        }
    }
    
    // MARK: - internal
    
    /// Generate a random base-36 ID for this session.
    private static func randomBase36InstanceId() -> String {
        let randomDouble = Double.random(in: 1..<2)
        let number = Int(268_435_456 * randomDouble)
        return String(number, radix: 36)
    }
}
