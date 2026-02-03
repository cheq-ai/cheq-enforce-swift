import XCTest
@testable import CheqEnforce

@available(macOS 11.0, *)
final class TranslationServiceTests: XCTestCase {
  
    func testBuildURL_whenDebugIsFalse_usesProductionHost() throws {
        let cfg = Config(
          "myClient",
          publishPath: "myPath",
          environment: "myEnv",
          debug: false
        )
        guard let url = TranslationService.buildURL(config: cfg) else {
          XCTFail("Expected non-nil URL")
          return
        }

        XCTAssertEqual(
          url.absoluteString,
          "https://nexus.ensighten.com/privacy/environments/myClient/myPath/myEnv/environment.json"
        )
    }

    func testBuildURL_whenDebugIsTrue_usesTestHost() throws {
        let cfg = Config(
          "myClient",
          publishPath: "myPath",
          environment: "myEnv",
          debug: true
        )
        guard let url = TranslationService.buildURL(config: cfg) else {
          XCTFail("Expected non-nil URL")
          return
        }

        XCTAssertEqual(
          url.absoluteString,
          "https://nexus-test.ensighten.com/privacy/environments/myClient/myPath/myEnv/environment.json"
        )
    }
  
    func testBuildURL_percentEncodesPathComponents() throws {
        // spaces & unicode should be escaped, but "/" remains unescaped
        let cfg = Config(
          "cli ent/名",
          publishPath: "pa th/ß",
          environment: "en vir/on",
          debug: false
        )
        guard let url = TranslationService.buildURL(config: cfg) else {
          return XCTFail("Expected non-nil URL")
        }
        
        // manually encode to compare (notice the "/" are literal)
        let expectedClient = "cli%20ent/%E5%90%8D"
        let expectedPath   = "pa%20th/%C3%9F"
        let expectedEnv    = "en%20vir/on"
        let expected = """
          https://nexus.ensighten.com/privacy/environments/\
          \(expectedClient)/\(expectedPath)/\(expectedEnv)/environment.json
          """

        XCTAssertEqual(url.absoluteString, expected)
    }
}
