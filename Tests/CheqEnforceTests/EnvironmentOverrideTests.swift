import XCTest
@testable import CheqEnforce

/// Tests for the persisted setEnvironment() override: stored with its own
/// expiration (snapshotted from the consent expiration when saved), applied
/// during configure(), unaffected by clearConsent(), and removed by expiry
/// or resetEnvironment().
final class EnvironmentOverrideTests: XCTestCase {

    private let dataKey              = "cheqEnforceConsentData"
    private let expiryKey            = "cheqEnforceConsentExpirationTime"
    private let versionKey           = "cheqEnforceConsentVersion"
    private let environmentKey       = "cheqEnforceEnvironmentOverride"
    private let environmentExpiryKey = "cheqEnforceEnvironmentOverrideExpiry"

    override func setUp() {
        super.setUp()
        wipeStore()
        ConsentStore.hasValidatedExpiry = false
    }

    override func tearDown() {
        wipeStore()
        Enforce._clearResponse()
        Enforce.configuredEnvironmentResponse = nil
        Enforce._resetRefetchState()
        Enforce._refetchCoolDown = 60
        Enforce._refetchExhaustionBeacons = 0
        super.tearDown()
    }

    private func wipeStore() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dataKey)
        defaults.removeObject(forKey: expiryKey)
        defaults.removeObject(forKey: versionKey)
        defaults.removeObject(forKey: environmentKey)
        defaults.removeObject(forKey: environmentExpiryKey)
    }

    private func makeResponse(clientId: String) -> JSONResponse {
        JSONResponse(
            clientId: clientId,
            version: "1",
            enforcement: false,
            enablePrivacyNotice: false,
            enableConsentModal: false,
            translation: Translation(
                notificationBannerContent: nil,
                notificationBannerAllowAll: nil,
                notificationBannerDenyAll: nil,
                notificationBannerPreferences: nil,
                consentTitle: nil,
                consentDescription: nil,
                consentModalAllowAll: nil,
                consentModalDenyAll: nil,
                save: nil,
                cancel: nil,
                close: nil,
                cookies: nil
            ),
            bannerConfig: nil,
            consentModalConfig: nil
        )
    }

    private func makeConfig(environment: String = "English", version: String = "1") -> Config {
        Config(
            "testClient",
            publishPath: "testPath",
            environment: environment,
            autoShow: false,
            version: version,
            defaultConsent: ["Analytics": true],
            theme: EnforceTheme(banner: EnforceTheme.Banner(backgroundColor: "#FFFFFF"))
        )
    }

    // MARK: - ConsentStore storage

    func testOverrideRoundTrip() {
        XCTAssertNil(ConsentStore.validEnvironmentOverride())
        ConsentStore.saveEnvironmentOverride("staging")
        XCTAssertEqual(ConsentStore.validEnvironmentOverride(), "staging")
    }

    func testOverrideExpirySnapshotsConsentExpiry() {
        // Consent that expires in the past: the override saved alongside it
        // inherits that expiry and is therefore already invalid.
        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: -1_000)
        ConsentStore.saveEnvironmentOverride("staging")

        XCTAssertNil(ConsentStore.validEnvironmentOverride(), "Override must expire with the consent period it was saved under")
        XCTAssertNil(UserDefaults.standard.string(forKey: environmentKey), "Expired override must be removed from storage")
    }

    func testOverrideValidWithinConsentExpiry() {
        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: 60_000)
        ConsentStore.saveEnvironmentOverride("staging")

        XCTAssertEqual(ConsentStore.validEnvironmentOverride(), "staging")
    }

    func testOverrideWithoutConsentUsesDefaultTTL() {
        // No consent stored: the override gets the default one-year TTL and
        // therefore persists (it no longer dies with missing consent).
        ConsentStore.saveEnvironmentOverride("staging")

        XCTAssertEqual(ConsentStore.validEnvironmentOverride(), "staging")
    }

    func testClearAllKeepsOverride() {
        // clearConsent() (which calls clearAll) must not touch the override.
        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: 60_000)
        ConsentStore.saveEnvironmentOverride("staging")

        ConsentStore.clearAll()

        XCTAssertEqual(ConsentStore.validEnvironmentOverride(), "staging")
    }

    func testClearEnvironmentOverrideRemovesIt() {
        ConsentStore.saveEnvironmentOverride("staging")
        ConsentStore.clearEnvironmentOverride()
        XCTAssertNil(ConsentStore.validEnvironmentOverride())
    }

    func testConsentSaveRealignsOverrideExpiry() {
        // Scenario: setEnvironment, clearConsent, consent set again in the
        // same session; the override's expiry must match the new consent expiry.
        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: 60_000)
        ConsentStore.saveEnvironmentOverride("staging")
        ConsentStore.clearAll()   // clearConsent()

        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: 120_000)

        let defaults = UserDefaults.standard
        let consentExpiry = defaults.value(forKey: expiryKey) as? Double
        let overrideExpiry = defaults.value(forKey: environmentExpiryKey) as? Double
        XCTAssertNotNil(consentExpiry)
        XCTAssertEqual(overrideExpiry, consentExpiry, "Override expiry must re-align to the new consent expiry")
        XCTAssertEqual(ConsentStore.validEnvironmentOverride(), "staging")
    }

    func testConsentSaveAfterOrphanedOverrideAdoptsConsentExpiry() {
        // Scenario: setEnvironment with no consent stored (default TTL), then
        // consent is given later; the override adopts the consent expiry.
        ConsentStore.saveEnvironmentOverride("staging")

        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: 60_000)

        let defaults = UserDefaults.standard
        let consentExpiry = defaults.value(forKey: expiryKey) as? Double
        let overrideExpiry = defaults.value(forKey: environmentExpiryKey) as? Double
        XCTAssertEqual(overrideExpiry, consentExpiry, "Override expiry must adopt the consent expiry once consent is given")
    }

    func testConsentSaveWithoutOverrideDoesNotCreateOverrideExpiry() {
        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: 60_000)

        XCTAssertNil(UserDefaults.standard.value(forKey: environmentExpiryKey),
                     "Consent saves must not create an override expiry when no override exists")
    }

    // MARK: - applyingStoredEnvironment

    func testOverrideAppliedWhenValid() {
        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: 60_000)
        ConsentStore.saveEnvironmentOverride("staging")

        let resolved = Enforce.applyingStoredEnvironment(makeConfig())

        XCTAssertEqual(resolved.environment, "staging")
        // All other fields pass through untouched
        XCTAssertEqual(resolved.clientName, "testClient")
        XCTAssertEqual(resolved.publishPath, "testPath")
        XCTAssertEqual(resolved.version, "1")
        XCTAssertEqual(resolved.defaultConsent, ["Analytics": true])
        XCTAssertEqual(resolved.theme?.banner?.backgroundColor, "#FFFFFF")
    }

    func testOverrideAppliedRegardlessOfConfigVersion() {
        // The override is not consent data; a config version change does not drop it.
        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: 60_000)
        ConsentStore.saveEnvironmentOverride("staging")

        let resolved = Enforce.applyingStoredEnvironment(makeConfig(version: "2"))

        XCTAssertEqual(resolved.environment, "staging")
    }

    func testNoOverrideStoredLeavesConfigUnchanged() {
        let resolved = Enforce.applyingStoredEnvironment(makeConfig())
        XCTAssertEqual(resolved.environment, "English")
    }

    func testExpiredOverrideIgnoredAndCleared() {
        ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: -1_000)
        ConsentStore.saveEnvironmentOverride("staging")

        let resolved = Enforce.applyingStoredEnvironment(makeConfig())

        XCTAssertEqual(resolved.environment, "English")
        XCTAssertNil(UserDefaults.standard.string(forKey: environmentKey))
    }

    func testOverrideEqualToConfiguredEnvironmentIsNoOp() {
        ConsentStore.saveEnvironmentOverride("English")

        let resolved = Enforce.applyingStoredEnvironment(makeConfig(environment: "English"))

        XCTAssertEqual(resolved.environment, "English")
    }

    // MARK: - getEnvironment / resetEnvironment

    func testGetEnvironmentReflectsConfigure() {
        Enforce.configure(makeConfig(environment: "English"))
        XCTAssertEqual(Enforce.getEnvironment(), "English")
    }

    func testGetEnvironmentReflectsStoredOverrideAfterConfigure() {
        ConsentStore.saveEnvironmentOverride("staging")

        Enforce.configure(makeConfig(environment: "English"))

        XCTAssertEqual(Enforce.getEnvironment(), "staging")
    }

    func testResetEnvironmentRevertsToConfiguredAndClearsOverride() {
        ConsentStore.saveEnvironmentOverride("staging")
        Enforce.configure(makeConfig(environment: "English"))
        XCTAssertEqual(Enforce.getEnvironment(), "staging")

        Enforce.resetEnvironment()

        XCTAssertEqual(Enforce.getEnvironment(), "English")
        XCTAssertNil(ConsentStore.validEnvironmentOverride())
    }

    func testResetEnvironmentWithoutOverrideIsNoOp() {
        Enforce.configure(makeConfig(environment: "English"))

        Enforce.resetEnvironment()

        XCTAssertEqual(Enforce.getEnvironment(), "English")
    }

    // MARK: - setEnvironment validation

    func testSetEnvironmentBeforeConfigureThrowsNotConfigured() async {
        Enforce.storedConfig = nil

        do {
            try await Enforce.setEnvironment("staging")
            XCTFail("setEnvironment must throw when configure() has not been called")
        } catch let error as Enforce.EnvironmentError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSetEnvironmentEmptyStringThrowsInvalidEnvironment() async {
        Enforce.configure(makeConfig(environment: "English"))

        do {
            try await Enforce.setEnvironment("")
            XCTFail("setEnvironment must throw for an empty environment")
        } catch let error as Enforce.EnvironmentError {
            XCTAssertEqual(error, .invalidEnvironment(""))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(Enforce.getEnvironment(), "English", "A failed setEnvironment must not change the environment")
        XCTAssertNil(ConsentStore.validEnvironmentOverride(), "A failed setEnvironment must not persist an override")
    }

    func testSetEnvironmentSuccessAdoptsNewEnvironmentsResponse() async throws {
        TranslationService._testProtocolClasses = [URLProtocolMock.self]
        defer {
            TranslationService._testProtocolClasses = nil
            URLProtocolMock.reset()
            Enforce._clearResponse()
        }
        URLProtocolMock.responder = { _ in
            let json = """
            {"clientId":"newEnvClient","version":"9","enforcement":false,
             "enablePrivacyNotice":false,"enableConsentModal":false,"translation":{}}
            """
            return (200, Data(json.utf8))
        }

        Enforce.storedConfig = makeConfig(environment: "English")
        Enforce._clearResponse()

        try await Enforce.setEnvironment("French")

        XCTAssertEqual(Enforce.getEnvironment(), "French")
        XCTAssertEqual(Enforce.lastResponse?.clientId, "newEnvClient",
                       "setEnvironment must adopt the fetched response so getConfiguration() reflects the new environment")
        XCTAssertEqual(Enforce.getConfiguration()?.version, "9")
        XCTAssertEqual(ConsentStore.validEnvironmentOverride(), "French")
    }

    // MARK: - lastResponse ownership across environment switches

    func testAdoptResponseDiscardsSupersededEnvironment() {
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce._clearResponse()

        XCTAssertFalse(Enforce.adoptResponse(makeResponse(clientId: "english"), for: "English"),
                       "A response fetched for a no-longer-effective environment must be discarded")
        XCTAssertNil(Enforce.lastResponse)

        XCTAssertTrue(Enforce.adoptResponse(makeResponse(clientId: "french"), for: "French"))
        XCTAssertEqual(Enforce.lastResponse?.clientId, "french")
    }

    func testResetEnvironmentRestoresConfiguredEnvironmentsResponse() async throws {
        Enforce.configuredEnvironment = "English"
        Enforce.storedConfig = makeConfig(environment: "English")
        Enforce.adoptResponse(makeResponse(clientId: "englishClient"), for: "English")

        TranslationService._testProtocolClasses = [URLProtocolMock.self]
        defer {
            TranslationService._testProtocolClasses = nil
            URLProtocolMock.reset()
        }
        URLProtocolMock.responder = { _ in
            let json = """
            {"clientId":"frenchClient","version":"2","enforcement":false,
             "enablePrivacyNotice":false,"enableConsentModal":false,"translation":{}}
            """
            return (200, Data(json.utf8))
        }
        try await Enforce.setEnvironment("French")
        XCTAssertEqual(Enforce.lastResponse?.clientId, "frenchClient")

        Enforce.resetEnvironment()

        XCTAssertEqual(Enforce.getEnvironment(), "English")
        XCTAssertEqual(Enforce.lastResponse?.clientId, "englishClient",
                       "resetEnvironment must restore the configured environment's response")
    }

    func testResetEnvironmentWithoutSnapshotKeepsResponseUntilRefetchAdopts() {
        TranslationService._testProtocolClasses = [URLProtocolMock.self]
        defer {
            TranslationService._testProtocolClasses = nil
            URLProtocolMock.reset()
        }
        URLProtocolMock.responder = { _ in
            let json = """
            {"clientId":"englishClient","version":"3","enforcement":false,
             "enablePrivacyNotice":false,"enableConsentModal":false,"translation":{}}
            """
            return (200, Data(json.utf8))
        }

        Enforce.configuredEnvironment = "English"
        Enforce.configuredEnvironmentResponse = nil
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce.adoptResponse(makeResponse(clientId: "frenchClient"), for: "French")

        Enforce.resetEnvironment()

        XCTAssertEqual(Enforce.getEnvironment(), "English")
        // Beacons are gated on lastResponse, so it must never be nil here:
        // the override's response stays until the refetch replaces it.
        XCTAssertNotNil(Enforce.lastResponse)

        let exp = expectation(description: "refetch adopts the configured environment's response")
        Task {
            while Enforce.lastResponse?.clientId != "englishClient" {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testFailedResetRefetchNeverServesTheAbandonedEnvironmentsDocument() {
        TranslationService._testProtocolClasses = [URLProtocolMock.self]
        Enforce._refetchRetryDelay = 0.01
        defer {
            TranslationService._testProtocolClasses = nil
            Enforce._refetchRetryDelay = 2
            URLProtocolMock.reset()
        }
        URLProtocolMock.responder = { _ in (500, Data("//HTTP:error".utf8)) }

        Enforce.configuredEnvironment = "English"
        Enforce.configuredEnvironmentResponse = nil
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce.adoptResponse(makeResponse(clientId: "frenchClient"), for: "French")

        Enforce.resetEnvironment()

        XCTAssertEqual(Enforce.getEnvironment(), "English")
        XCTAssertNil(Enforce.getConfiguration(),
                     "The abandoned French document must not be served for English")
        XCTAssertNotNil(Enforce.lastResponse,
                        "Beacons keep the previous response across the revert")

        // Let all (shortened) retries fail.
        let exp = expectation(description: "refetch exhausts its retries")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        // Even after giving up, getConfiguration() must still report nil for
        // English rather than the French document, and the owed refetch stays
        // pending so a later call can recover.
        XCTAssertNil(Enforce.getConfiguration(),
                     "After the retries exhaust, the French document must still not be served for English")
        XCTAssertNotNil(Enforce.lastResponse, "Beacons keep working across the failed revert")

        // A later successful adoption recovers it, so it can't wedge at nil.
        Enforce.adoptResponse(makeResponse(clientId: "englishClient"), for: "English")
        XCTAssertEqual(Enforce.getConfiguration()?.clientId, "englishClient",
                       "A successful adoption for the effective environment recovers getConfiguration()")
    }

    func testResetRefetchWithUnbuildableURLReleasesTheInFlightGuard() {
        // A configured environment that can't build a URL makes the owed
        // refetch impossible. The in-flight guard must still be released, or
        // getConfiguration() reports nil for the rest of the session with no
        // way to retry.
        Enforce.configuredEnvironment = ""
        Enforce.configuredEnvironmentResponse = nil
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce.adoptResponse(makeResponse(clientId: "frenchClient"), for: "French")

        Enforce.resetEnvironment()

        XCTAssertEqual(Enforce.getEnvironment(), "")

        let released = expectation(description: "the in-flight guard is released")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            released.fulfill()
        }
        wait(for: [released], timeout: 2.0)

        XCTAssertTrue(Enforce.refetchPending, "The owed refetch stays pending for a later retry")
        XCTAssertNil(Enforce.getConfiguration(), "The abandoned French document must not be served")
        XCTAssertNotNil(Enforce.lastResponse, "Beacons keep the previous response across the revert")

        // Not wedged: a successful adoption for the effective environment
        // still recovers getConfiguration().
        Enforce.adoptResponse(makeResponse(clientId: "revertedClient"), for: "")
        XCTAssertEqual(Enforce.getConfiguration()?.clientId, "revertedClient")
    }

    func testGetConfigurationDemandRetryRecoversAfterTransientFailure() {
        TranslationService._testProtocolClasses = [URLProtocolMock.self]
        Enforce._refetchRetryDelay = 0.01
        Enforce._refetchCoolDown = 0
        defer {
            TranslationService._testProtocolClasses = nil
            Enforce._refetchRetryDelay = 2
            URLProtocolMock.reset()
        }
        // Fail every attempt of the first refetch cycle, then succeed.
        let shouldFail = NSLock()
        var failing = true
        URLProtocolMock.responder = { _ in
            shouldFail.lock(); defer { shouldFail.unlock() }
            if failing { return (500, Data("//HTTP:error".utf8)) }
            let json = """
            {"clientId":"englishClient","version":"9","enforcement":false,
             "enablePrivacyNotice":false,"enableConsentModal":false,"translation":{}}
            """
            return (200, Data(json.utf8))
        }

        Enforce.configuredEnvironment = "English"
        Enforce.configuredEnvironmentResponse = nil
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce.adoptResponse(makeResponse(clientId: "frenchClient"), for: "French")

        Enforce.resetEnvironment()

        // Wait for the initial (failing) cycle to give up.
        let failed = expectation(description: "initial refetch cycle exhausts")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 2.0)
        XCTAssertNil(Enforce.getConfiguration(), "Still nil while the refetch is owed")
        XCTAssertTrue(Enforce.refetchPending, "The owed refetch stays pending after a failed cycle")

        // Let the network recover; a getConfiguration() call re-arms the retry.
        shouldFail.lock(); failing = false; shouldFail.unlock()
        _ = Enforce.getConfiguration()   // triggers the demand-driven retry

        let recovered = expectation(description: "demand-driven retry recovers")
        Task {
            while Enforce.getConfiguration()?.clientId != "englishClient" {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            recovered.fulfill()
        }
        wait(for: [recovered], timeout: 2.0)
    }

    func testExhaustedRefetchCoolsDownBeforeAnotherCycle() {
        // A repeated getConfiguration() reader (a SwiftUI body, a polling
        // loop) must not turn an unreachable environment into continuous
        // request traffic and a beacon per cycle.
        TranslationService._testProtocolClasses = [URLProtocolMock.self]
        Enforce._refetchRetryDelay = 0.01
        defer {
            TranslationService._testProtocolClasses = nil
            Enforce._refetchRetryDelay = 2
            URLProtocolMock.reset()
        }

        let counter = NSLock()
        var requests = 0
        URLProtocolMock.responder = { _ in
            counter.lock(); requests += 1; counter.unlock()
            return (500, Data("//HTTP:error".utf8))
        }
        func requestCount() -> Int {
            counter.lock(); defer { counter.unlock() }
            return requests
        }

        Enforce.configuredEnvironment = "English"
        Enforce.configuredEnvironmentResponse = nil
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce.adoptResponse(makeResponse(clientId: "frenchClient"), for: "French")

        Enforce.resetEnvironment()

        let exhausted = expectation(description: "the first refetch cycle gives up")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            exhausted.fulfill()
        }
        wait(for: [exhausted], timeout: 2.0)

        let afterFirstCycle = requestCount()
        XCTAssertEqual(afterFirstCycle, 3, "One cycle is three attempts")
        XCTAssertEqual(Enforce._refetchExhaustionBeacons, 1,
                       "The give-up is beaconed once")

        // Inside the cool-down, no read may start a new cycle or serve the
        // abandoned French document.
        for _ in 0..<20 {
            XCTAssertNil(Enforce.getConfiguration())
        }
        XCTAssertFalse(Enforce.refetchInFlightForTests,
                       "No new cycle starts inside the cool-down")
        XCTAssertEqual(requestCount(), afterFirstCycle,
                       "Reads inside the cool-down issue no further requests")
        XCTAssertEqual(Enforce._refetchExhaustionBeacons, 1,
                       "No further beacons inside the cool-down")

        // Once it elapses, a read starts exactly one more cycle.
        Enforce._refetchCoolDown = 0
        XCTAssertNil(Enforce.getConfiguration())

        let secondCycle = expectation(description: "the re-armed cycle gives up")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            secondCycle.fulfill()
        }
        wait(for: [secondCycle], timeout: 2.0)

        XCTAssertEqual(requestCount(), afterFirstCycle * 2,
                       "Exactly one more cycle ran after the cool-down elapsed")
        XCTAssertEqual(Enforce._refetchExhaustionBeacons, 1,
                       "The exhaustion beacon is sent once per owed refetch, not once per cycle")

        // A success clears the owed refetch, so the next one starts fresh.
        Enforce.adoptResponse(makeResponse(clientId: "englishClient"), for: "English")
        XCTAssertEqual(Enforce.getConfiguration()?.clientId, "englishClient")
        XCTAssertFalse(Enforce.refetchPending)
    }

    func testUnbuildableRefetchURLIsNotRetriedOnEveryRead() {
        // No URL means nothing to retry until the config changes, so reads
        // must not re-enter the refetch task per call.
        Enforce.configuredEnvironment = ""
        Enforce.configuredEnvironmentResponse = nil
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce.adoptResponse(makeResponse(clientId: "frenchClient"), for: "French")

        Enforce.resetEnvironment()

        let released = expectation(description: "the in-flight guard is released")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            released.fulfill()
        }
        wait(for: [released], timeout: 2.0)

        for _ in 0..<20 {
            XCTAssertNil(Enforce.getConfiguration())
        }
        XCTAssertFalse(Enforce.refetchInFlightForTests,
                       "Reads inside the cool-down don't re-enter the refetch")
        XCTAssertTrue(Enforce.refetchPending, "The owed refetch stays pending")
    }

    func testUnbuildableRefetchURLBeaconsTheGiveUpOnce() {
        // A give-up with no URL to try must be beaconed like an exhausted
        // cycle, not left silent in the log.
        Enforce.configuredEnvironment = ""
        Enforce.configuredEnvironmentResponse = nil
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce.adoptResponse(makeResponse(clientId: "frenchClient"), for: "French")

        Enforce.resetEnvironment()

        let released = expectation(description: "the in-flight guard is released")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            released.fulfill()
        }
        wait(for: [released], timeout: 2.0)

        XCTAssertEqual(Enforce._refetchExhaustionBeacons, 1,
                       "An unbuildable refetch URL is beaconed, not only logged")

        // The re-armed cycle is still hopeless, and must not beacon again.
        Enforce._refetchCoolDown = 0
        XCTAssertNil(Enforce.getConfiguration())

        let secondCycle = expectation(description: "the re-armed cycle gives up")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            secondCycle.fulfill()
        }
        wait(for: [secondCycle], timeout: 2.0)

        XCTAssertEqual(Enforce._refetchExhaustionBeacons, 1,
                       "The give-up is beaconed once per owed refetch, not once per cycle")
    }

    func testResetEnvironmentRetriesAnOwedRefetchImmediately() {
        // An integrator using only the built-in banner never calls
        // getConfiguration(), so a repeat resetEnvironment() has to drive the
        // owed refetch itself rather than no-op on the reverted environment.
        TranslationService._testProtocolClasses = [URLProtocolMock.self]
        Enforce._refetchRetryDelay = 0.01
        defer {
            TranslationService._testProtocolClasses = nil
            Enforce._refetchRetryDelay = 2
            URLProtocolMock.reset()
        }

        let lock = NSLock()
        var failing = true
        var requests = 0
        URLProtocolMock.responder = { _ in
            lock.lock(); defer { lock.unlock() }
            requests += 1
            if failing { return (500, Data("//HTTP:error".utf8)) }
            let json = """
            {"clientId":"englishClient","version":"9","enforcement":false,
             "enablePrivacyNotice":false,"enableConsentModal":false,"translation":{}}
            """
            return (200, Data(json.utf8))
        }
        func requestCount() -> Int {
            lock.lock(); defer { lock.unlock() }
            return requests
        }

        Enforce.configuredEnvironment = "English"
        Enforce.configuredEnvironmentResponse = nil
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce.adoptResponse(makeResponse(clientId: "frenchClient"), for: "French")

        Enforce.resetEnvironment()

        let failed = expectation(description: "the first refetch cycle gives up")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 2.0)

        let afterFirstCycle = requestCount()
        XCTAssertEqual(afterFirstCycle, 3, "One cycle is three attempts")
        XCTAssertTrue(Enforce.refetchPending, "The owed refetch stays pending")
        XCTAssertEqual(Enforce.getEnvironment(), "English")

        // Cool-down left at its full 60s: only the reset may skip it.
        XCTAssertNil(Enforce.getConfiguration())
        XCTAssertEqual(requestCount(), afterFirstCycle,
                       "A read inside the cool-down issues no further requests")

        // Network back: the reset retries even though the environment
        // already matches the configured one.
        lock.lock(); failing = false; lock.unlock()
        Enforce.resetEnvironment()

        let recovered = expectation(description: "the reset-driven retry recovers")
        Task {
            while Enforce.getConfiguration()?.clientId != "englishClient" {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            recovered.fulfill()
        }
        wait(for: [recovered], timeout: 2.0)

        XCTAssertFalse(Enforce.refetchPending, "A success clears the owed refetch")
        XCTAssertEqual(Enforce._refetchExhaustionBeacons, 1,
                       "The reset-driven retry doesn't spend another beacon")
    }

    func testRepeatedResetEnvironmentDoesNotStackOverlappingRefetches() {
        // The in-flight guard has to hold across the explicit-retry path.
        TranslationService._testProtocolClasses = [URLProtocolMock.self]
        Enforce._refetchRetryDelay = 0.2
        defer {
            TranslationService._testProtocolClasses = nil
            Enforce._refetchRetryDelay = 2
            URLProtocolMock.reset()
        }

        let lock = NSLock()
        var requests = 0
        URLProtocolMock.responder = { _ in
            lock.lock(); requests += 1; lock.unlock()
            return (500, Data("//HTTP:error".utf8))
        }
        func requestCount() -> Int {
            lock.lock(); defer { lock.unlock() }
            return requests
        }

        Enforce.configuredEnvironment = "English"
        Enforce.configuredEnvironmentResponse = nil
        Enforce.storedConfig = makeConfig(environment: "French")
        Enforce.adoptResponse(makeResponse(clientId: "frenchClient"), for: "French")

        Enforce.resetEnvironment()
        for _ in 0..<10 {
            Enforce.resetEnvironment()   // no-ops while the cycle is in flight
        }

        let settled = expectation(description: "the single cycle gives up")
        Task {
            while Enforce.refetchInFlightForTests {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            settled.fulfill()
        }
        wait(for: [settled], timeout: 5.0)

        XCTAssertEqual(requestCount(), 3, "Exactly one cycle of three attempts ran")
        XCTAssertEqual(Enforce._refetchExhaustionBeacons, 1)
    }

    func testSetEnvironmentWhitespaceOnlyThrowsInvalidEnvironment() async {
        Enforce.configure(makeConfig(environment: "English"))

        do {
            try await Enforce.setEnvironment("   ")
            XCTFail("setEnvironment must throw for a whitespace-only environment")
        } catch let error as Enforce.EnvironmentError {
            XCTAssertEqual(error, .invalidEnvironment("   "))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(Enforce.getEnvironment(), "English")
        XCTAssertNil(ConsentStore.validEnvironmentOverride())
    }
}
