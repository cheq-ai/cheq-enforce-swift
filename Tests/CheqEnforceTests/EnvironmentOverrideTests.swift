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
    }

    override func tearDown() {
        wipeStore()
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
}
