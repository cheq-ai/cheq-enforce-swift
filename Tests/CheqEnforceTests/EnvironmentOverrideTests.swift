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
        Enforce.lastResponse = nil
        Enforce.configuredEnvironmentResponse = nil
        Enforce.revertPending = false
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
            Enforce.lastResponse = nil
        }
        URLProtocolMock.responder = { _ in
            let json = """
            {"clientId":"newEnvClient","version":"9","enforcement":false,
             "enablePrivacyNotice":false,"enableConsentModal":false,"translation":{}}
            """
            return (200, Data(json.utf8))
        }

        Enforce.storedConfig = makeConfig(environment: "English")
        Enforce.lastResponse = nil

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
        Enforce.lastResponse = nil

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
        Enforce.lastResponse = makeResponse(clientId: "frenchClient")

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

    func testFailedResetRefetchReportsNilConfigurationButKeepsBeaconResponse() {
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
        Enforce.lastResponse = makeResponse(clientId: "frenchClient")

        Enforce.resetEnvironment()

        XCTAssertEqual(Enforce.getEnvironment(), "English")
        XCTAssertNil(Enforce.getConfiguration(),
                     "While the revert is pending, the abandoned document must not be served")
        XCTAssertNotNil(Enforce.lastResponse,
                        "Beacons keep the previous response while the revert is pending")

        // Let all (shortened) retries fail, then confirm the pending state
        // persists and a later successful adoption recovers it.
        let exp = expectation(description: "revert recovers once a fetch succeeds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertNil(Enforce.getConfiguration(),
                         "After all retries fail, getConfiguration() must stay nil rather than serve the abandoned document")

            Enforce.adoptResponse(self.makeResponse(clientId: "englishClient"), for: "English")

            XCTAssertEqual(Enforce.getConfiguration()?.clientId, "englishClient",
                           "A successful adoption must clear the pending revert")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
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
