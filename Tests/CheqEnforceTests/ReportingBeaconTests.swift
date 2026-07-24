import XCTest
@testable import CheqEnforce

@available(macOS 11.0, *)
final class ReportingBeaconTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(URLProtocolMock.self)
        URLProtocolMock.reset()

        // Clear consent storage if your tests rely on “first run”
        UserDefaults.standard.removePersistentDomain(
            forName: Bundle.main.bundleIdentifier ?? ""
        )
    }

    override func tearDown() {
        URLProtocol.unregisterClass(URLProtocolMock.self)
        URLProtocolMock.reset()
        super.tearDown()
    }

    private func makeConfig(autoShow: Bool = false) -> Config {
        Config(
            "demoretail",
            publishPath: "mobile_privacy_sdk",
            environment: "English",
            debug: true,
            dataRetentionPeriod: 60_000,
            autoShow: autoShow,
            version: "1",
            defaultConsent: ["Analytics": false]
        )
    }

    // 1) configure() should send a BILLING beacon (path /privacy/v1/b/b.rnc)
    func test_configure_sends_billing_beacon() {
        // Act
        Enforce.configure(makeConfig(autoShow: false))

        // Assert (poll briefly for async work)
        let exp = expectation(description: "billing beacon observed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let hit = URLProtocolMock.captured.contains { req in
                guard let u = req.url else { return false }
                return u.host == "data.privacy.ensighten.com" &&
                       u.path.contains("/privacy/v1/b/b.rnc")
            }
            if hit { exp.fulfill() }
        }
        wait(for: [exp], timeout: 2.0)

        // Decode the first billing URL and validate fields
        if let req = URLProtocolMock.captured.first(where: { $0.url?.path.contains("/privacy/v1/b/b.rnc") == true }),
           let url = req.url {
            let json = try! BeaconDecode.decodeJSONPayload(from: url)

            // Make a few focused assertions about the payload
            XCTAssertEqual(json["publishPath"] as? String, "mobile_privacy_sdk")
            XCTAssertEqual(json["mode"] as? String, "observe")
            // requests array present, etc.
            XCTAssertNotNil(json["requests"])
        }
    }

    // 2) setConsent(...) should send a CONSENT beacon (path /privacy/v1/c/b.rnc)
    func test_setConsent_sends_consent_beacon_and_payload_has_flags() {
        // First configure so lastResponse/client metadata exist
        Enforce.configure(makeConfig(autoShow: false))

        let exp = expectation(description: "consent beacon observed")

        Enforce.setConsent(["Analytics": true], beaconExtras: ["BANNER_VIEWED": true])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let hit = URLProtocolMock.captured.first { req in
                guard let u = req.url else { return false }
                return u.host == "data.privacy.ensighten.com" &&
                       u.path.contains("/privacy/v1/c/b.rnc")
            }

            if let req = hit, let url = req.url {
                // Decode payload and verify cookie/event flags made it in
                let json = try! BeaconDecode.decodeJSONPayload(from: url)

                // cookies: map like FOO_ENSIGHTEN_PRIVACY_X: "1"/"0"
                if let cookies = json["cookies"] as? [String: String] {
                    // We expect keys derived from clientName + flags
                    let cookieKey = "DEMORETAIL_ENSIGHTEN_PRIVACY_BANNER_VIEWED"
                    XCTAssertEqual(cookies[cookieKey], "1")
                }

                // events: array of { key, value, timestamp }
                if let events = json["events"] as? [[String: Any]] {
                    // collect all dynamic cookie keys across events
                    var changedKeys = Set<String>()
                    for evt in events {
                        for (k, v) in evt {
                            guard k != "event", k != "dt" else { continue }
                            // values are "1"/"0" strings
                            if let s = v as? String, s == "1" {
                                changedKeys.insert(k)
                            }
                        }
                    }
                    XCTAssertTrue(changedKeys.contains("Analytics"))
                }

                exp.fulfill()
            }
        }

        wait(for: [exp], timeout: 2.0)
    }

    // 3) Simulate “modal interacted”
    func test_modal_interaction_consent_beacon() {
        Enforce.configure(makeConfig(autoShow: false))

        let exp = expectation(description: "consent beacon after modal")

        // Simulate the same thing your modal does on save:
        Enforce.setConsent(["Marketing": false], beaconExtras: ["MODAL_VIEWED": true])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let hit = URLProtocolMock.captured.contains { req in
                req.url?.path.contains("/privacy/v1/c/b.rnc") == true
            }
            if hit { exp.fulfill() }
        }

        wait(for: [exp], timeout: 2.0)
    }

    // Beacon URLs must carry the SDK utm parameters, and the payload's
    // "gateway" field must use the (gateway-version)-(platform)-(sdk-version) format.
    func test_beacon_has_utm_params_and_gateway_format() async throws {
        let config = makeConfig(autoShow: false)

        await ConsentReporting.send(config: config, type: .consent,
                                    clientId: "client", version: "3", enforcement: false,
                                    cookieFlags: ["Analytics": true])

        let req = URLProtocolMock.captured.first { $0.url?.path.contains("/privacy/v1/c/b.rnc") == true }
        let url = try XCTUnwrap(req?.url)

        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "utm_platform" }?.value, "ios")
        XCTAssertEqual(items.first { $0.name == "utm_sdk_version" }?.value, Info.version)

        let json = try BeaconDecode.decodeJSONPayload(from: url)
        XCTAssertEqual(json["gateway"] as? String, "3-ios-\(Info.version)")
    }

    // Same checks for the billing beacon path.
    func test_billing_beacon_has_utm_params_and_gateway_format() async throws {
        let config = makeConfig(autoShow: false)

        await ConsentReporting.send(config: config, type: .billing,
                                    clientId: "client", version: "3", enforcement: true)

        let req = URLProtocolMock.captured.first { $0.url?.path.contains("/privacy/v1/b/b.rnc") == true }
        let url = try XCTUnwrap(req?.url)

        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "utm_platform" }?.value, "ios")
        XCTAssertEqual(items.first { $0.name == "utm_sdk_version" }?.value, Info.version)

        let json = try BeaconDecode.decodeJSONPayload(from: url)
        XCTAssertEqual(json["gateway"] as? String, "3-ios-\(Info.version)")
    }

    // 4) clearConsent() should reset the in-memory cookie accumulator so a
    //    subsequent beacon only carries the current event's flags, not stale ones.
    func test_clearConsent_resets_beacon_cookie_flags() async throws {
        let config = makeConfig(autoShow: false)
        Enforce.configure(config)

        // Accumulate some consent flags into the in-memory cookie accumulator.
        await ConsentReporting.send(config: config, type: .consent,
                                    clientId: "client", version: "1", enforcement: false,
                                    cookieFlags: ["Analytics": true, "Marketing": true])
        XCTAssertFalse(Enforce.storedCookieFlags.isEmpty,
                       "Precondition: flags should be accumulated before clearing")

        // Clear consent; this must wipe the accumulator.
        await Enforce.clearConsent()
        XCTAssertTrue(Enforce.storedCookieFlags.isEmpty,
                      "clearConsent should reset the in-memory cookie-flag accumulator")

        // A subsequent beacon (e.g. banner load) should only carry the new flag.
        URLProtocolMock.reset()
        await ConsentReporting.send(config: config, type: .consent,
                                    clientId: "client", version: "1", enforcement: false,
                                    cookieFlags: ["BANNER_LOADED": true])

        let req = URLProtocolMock.captured.first { $0.url?.path.contains("/privacy/v1/c/b.rnc") == true }
        let url = try XCTUnwrap(req?.url)
        let json = try BeaconDecode.decodeJSONPayload(from: url)
        let cookies = try XCTUnwrap(json["cookies"] as? [String: String])

        XCTAssertEqual(cookies["DEMORETAIL_ENSIGHTEN_PRIVACY_BANNER_LOADED"], "1",
                       "The current event's flag should be present")
        XCTAssertNil(cookies["DEMORETAIL_ENSIGHTEN_PRIVACY_Analytics"],
                     "Stale consent flags should not survive clearConsent")
        XCTAssertNil(cookies["DEMORETAIL_ENSIGHTEN_PRIVACY_Marketing"],
                     "Stale consent flags should not survive clearConsent")
    }
}
