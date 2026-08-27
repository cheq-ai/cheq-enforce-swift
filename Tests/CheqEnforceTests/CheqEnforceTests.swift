import XCTest
@testable import CheqEnforce

@available(macOS 11.0, *)
final class EnforceTests: XCTestCase {
  
  // MARK: - Test constants matching ConsentStore keys
  private let dataKey    = "cheqEnforceConsentData"
  private let expiryKey  = "cheqEnforceConsentExpirationTime"
  private let versionKey = "cheqEnforceConsentVersion"
  
  override func setUp() {
    super.setUp()
    // wipe any stored defaults before each test
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: dataKey)
    defaults.removeObject(forKey: expiryKey)
    defaults.removeObject(forKey: versionKey)
      
    // reset any lingering handlers
    Enforce._resetConsentHandlers()
      
    // Give Enforce a storedConfig so setConsent() will actually run
    let testConfig = Config(
      "testClient",               // clientName
      publishPath: "testPath",
      environment: "testEnv",
      debug: true,                // debug on so you can see logs
      autoShow: false,            // Don't need UI
      version: "1",
      defaultConsent: nil
    )
    Enforce.configure(testConfig)
  }
  
  func testGetConsentInitiallyEmpty() {
    // no consent has ever been set
    let all = Enforce.getConsent()
    XCTAssertTrue(all.isEmpty, "Expected no stored consent at startup")
  }
  
  func testCheckConsentDefaultFalse() {
    // query an arbitrary key -> should be false
    XCTAssertFalse(Enforce.checkConsent("Nonexistent"), "Missing keys must default to false")
  }

  func testExpiredConsentIsNotReturnedByFirstReadOfSession() {
    ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: -1_000)
    ConsentStore.hasValidatedExpiry = false   // simulate a fresh session

    XCTAssertTrue(Enforce.getConsent().isEmpty,
                  "The first read of a session must not return expired consent")
    XCTAssertFalse(Enforce.checkConsent("Analytics"),
                   "checkConsent() must not honor consent that expired before the session")
  }

  func testConsentDoesNotExpireMidSession() {
    // Consent that was valid at the session boundary stays live even after
    // its timestamp passes; reads never re-evaluate expiry mid-session.
    ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: -1_000)
    ConsentStore.hasValidatedExpiry = true    // expiry already evaluated this session

    XCTAssertEqual(Enforce.getConsent(), ["Analytics": true],
                   "Consent must not vanish mid-session when its expiry passes")
    XCTAssertTrue(Enforce.checkConsent("Analytics"))
  }

  func testConfigureRevalidatesExpiredConsent() {
    // configure() is the session boundary: it prunes an expired record
    // synchronously, so reads immediately after it are already clean.
    ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: -1_000)
    ConsentStore.hasValidatedExpiry = true    // stale state from a previous session

    Enforce.configure(Config("testClient", publishPath: "testPath", environment: "testEnv", autoShow: false))

    XCTAssertTrue(Enforce.getConsent().isEmpty,
                  "configure() must prune expired consent before any read")
  }

  func testConsentSaveDoesNotResurrectExpiredCategories() {
    // A record that lapsed before the session must not leak its categories
    // into a fresh save made after the session's expiry prune.
    ConsentStore.save(["Analytics": true, "Marketing": true], version: "1", expirationMilliseconds: -1_000)
    ConsentStore.hasValidatedExpiry = false   // fresh session; first access prunes

    ConsentStore.save(["Functional": true], version: "1", expirationMilliseconds: 60_000)

    XCTAssertEqual(Enforce.getConsent(), ["Functional": true],
                   "Pre-session expired categories must not be merged into new consent")
  }

  func testSetConsentAndCheck() {
    // set one category to true
    Enforce.setConsent(["Analytics": true])
    XCTAssertTrue(Enforce.checkConsent("Analytics"),
                  "After setConsent, checkConsent(Analytics) should be true")
    // other keys still false
    XCTAssertFalse(Enforce.checkConsent("Marketing"),
                   "Keys not explicitly set should remain false")
  }
  
  func testGetConsentForKeyAndMultiple() {
    Enforce.setConsent(["A": true, "B": false, "C": true])
    
    // single-key overload
    let single = Enforce.getConsent(for: "B")
    XCTAssertEqual(single, ["B": false])
    
    // multi-key overload
    let subset = Enforce.getConsent(for: ["A", "C", "Z"])
    XCTAssertEqual(subset, ["A": true, "C": true, "Z": false])
    
    // full-dictionary
    let full = Enforce.getConsent()
    XCTAssertEqual(full, ["A": true, "B": false, "C": true])
  }
  
  func testOnConsentHandlerIsCalled() {
    // prepare an expectation
    let exp = expectation(description: "Consent-change handler must be invoked")
    exp.assertForOverFulfill = false
    
    // register a handler
    Enforce.onConsent { updated in
      // we expect our setConsent below to produce exactly this
      XCTAssertEqual(updated, ["X": true])
      exp.fulfill()
    }
    
    // trigger a change
    Enforce.setConsent(["X": true])
    
    // wait for it
    wait(for: [exp], timeout: 1)
  }

  func testOnConsentReplaysCurrentConsentToLateSubscribers() {
    Enforce.setConsent(["Analytics": true])

    var received: [String: Bool]?
    Enforce.onConsent { received = $0 }

    XCTAssertEqual(received, ["Analytics": true],
                   "Handlers registered after configure must immediately receive the current consent")
  }

  func testOnConsentDoesNotReplayWhenNoConsentStored() {
    var callCount = 0
    Enforce.onConsent { _ in callCount += 1 }

    XCTAssertEqual(callCount, 0,
                   "Registration must not fire the handler when no consent is stored")
  }

  func testConfigureDoesNotNotifyHandlersWithEmptyConsent() {
    var callCount = 0
    Enforce.onConsent { _ in callCount += 1 }

    Enforce.configure(Config("testClient", publishPath: "testPath", environment: "testEnv", autoShow: false))

    XCTAssertEqual(callCount, 0,
                   "configure() must not fire handlers when there is no consent to report")
  }

  func testConfigureNotifiesEarlySubscribersWithStoredConsent() {
    ConsentStore.save(["Analytics": true], version: "1", expirationMilliseconds: 60_000)
    Enforce._resetConsentHandlers()

    var received: [String: Bool]?
    Enforce.onConsent { received = $0 }
    received = nil   // discard the registration replay; test configure's own fan-out

    Enforce.configure(Config("testClient", publishPath: "testPath", environment: "testEnv", autoShow: false, version: "1"))

    XCTAssertEqual(received, ["Analytics": true],
                   "configure() must deliver stored consent to handlers registered before it")
  }

  func testClearConsentRemovesStoredData() async {
    // seed some stored consent
    Enforce.setConsent(["Analytics": true, "Marketing": true])
    XCTAssertFalse(Enforce.getConsent().isEmpty, "Precondition: consent should be stored")

    await Enforce.clearConsent()

    XCTAssertTrue(Enforce.getConsent().isEmpty,
                  "After clearConsent, getConsent() should be empty")
    XCTAssertFalse(Enforce.checkConsent("Analytics"),
                   "After clearConsent, checkConsent() should be false for all categories")
    XCTAssertFalse(Enforce.checkConsent("Marketing"),
                   "After clearConsent, checkConsent() should be false for all categories")
  }

  func testClearConsentNotifiesHandlersWithEmptyMap() async {
    // seed some stored consent before registering the handler so the handler
    // only observes the clearConsent() invocation
    Enforce.setConsent(["X": true])

    var received: [String: Bool]?
    Enforce.onConsent { received = $0 }

    await Enforce.clearConsent()

    XCTAssertEqual(received, [:],
                   "clearConsent should notify onConsent handlers with an empty map")
  }
}
