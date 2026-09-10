import XCTest
@testable import CheqEnforce

final class GetConfigurationTests: XCTestCase {

    /// Environment these tests adopt responses for. Distinct from the names
    /// other suites use, so a leaked `configuredEnvironment` can't make
    /// `adoptResponse` also stash a configured-environment snapshot here.
    private let environment = "getConfigurationEnv"

    private func makeConfig() -> Config {
        Config("testClient", publishPath: "testPath", environment: environment, autoShow: false)
    }

    /// Installs `response` as the effective one, the way a completed fetch
    /// does — response and environment tag written together.
    private func adopt(_ response: JSONResponse) {
        Enforce.storedConfig = makeConfig()
        Enforce.adoptResponse(response, for: environment)
    }

    override func tearDown() {
        Enforce._clearResponse()
        Enforce.storedConfig = nil
        Enforce.configuredEnvironmentResponse = nil
        super.tearDown()
    }

    func testGetConfigurationNilBeforeFetchCompletes() {
        Enforce._clearResponse()
        XCTAssertNil(Enforce.getConfiguration(), "getConfiguration() must be nil before configure() finishes fetching")
    }

    func testGetConfigurationMapsRemoteResponse() {
        let translation = Translation(
            notificationBannerContent: "banner content",
            notificationBannerAllowAll: "Allow All",
            notificationBannerDenyAll: "Deny All",
            notificationBannerPreferences: "Preferences",
            consentTitle: "Consent Title",
            consentDescription: "Consent Description",
            consentModalAllowAll: "Modal Allow",
            consentModalDenyAll: "Modal Deny",
            save: "Save",
            cancel: "Cancel",
            close: "Close",
            cookies: ["Analytics": CookieDetails(title: "Analytics", description: "Tracks usage")]
        )
        adopt(JSONResponse(
            clientId: "client-123",
            version: "7",
            enforcement: true,
            enablePrivacyNotice: true,
            enableConsentModal: false,
            translation: translation,
            bannerConfig: BannerConfig(
                ensAcceptAll: BannerConfigItem(show: true),
                ensRejectAll: BannerConfigItem(show: false),
                ensOpenModal: nil,
                ensCloseBanner: BannerConfigItem(show: true)
            ),
            consentModalConfig: ConsentModalConfig(
                ensConsentAcceptAll: BannerConfigItem(show: true),
                ensConsentRejectAll: nil,
                ensSaveModal: BannerConfigItem(show: true),
                ensCloseModal: nil
            )
        ))

        let configuration = Enforce.getConfiguration()

        XCTAssertNotNil(configuration)
        XCTAssertEqual(configuration?.clientId, "client-123")
        XCTAssertEqual(configuration?.version, "7")
        XCTAssertEqual(configuration?.enforcement, true)
        XCTAssertEqual(configuration?.enablePrivacyNotice, true)
        XCTAssertEqual(configuration?.enableConsentModal, false)

        XCTAssertEqual(configuration?.translation.notificationBannerContent, "banner content")
        XCTAssertEqual(configuration?.translation.notificationBannerAllowAll, "Allow All")
        XCTAssertEqual(configuration?.translation.close, "Close")
        XCTAssertEqual(configuration?.translation.cookies?["Analytics"]?.title, "Analytics")
        XCTAssertEqual(configuration?.translation.cookies?["Analytics"]?.description, "Tracks usage")

        XCTAssertEqual(configuration?.bannerConfig?.ensAcceptAll, true)
        XCTAssertEqual(configuration?.bannerConfig?.ensRejectAll, false)
        XCTAssertNil(configuration?.bannerConfig?.ensOpenModal)
        XCTAssertEqual(configuration?.bannerConfig?.ensCloseBanner, true)

        XCTAssertEqual(configuration?.consentModalConfig?.ensConsentAcceptAll, true)
        XCTAssertNil(configuration?.consentModalConfig?.ensConsentRejectAll)
        XCTAssertEqual(configuration?.consentModalConfig?.ensSaveModal, true)
        XCTAssertNil(configuration?.consentModalConfig?.ensCloseModal)
    }

    func testGetConfigurationOmitsMissingBannerAndModalConfig() {
        adopt(JSONResponse(
            clientId: "client-123",
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
        ))

        let configuration = Enforce.getConfiguration()

        XCTAssertNotNil(configuration)
        XCTAssertNil(configuration?.bannerConfig)
        XCTAssertNil(configuration?.consentModalConfig)
        XCTAssertNil(configuration?.translation.cookies)
    }
}
