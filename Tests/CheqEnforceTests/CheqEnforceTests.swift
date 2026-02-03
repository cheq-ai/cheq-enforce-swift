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
}
