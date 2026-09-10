import XCTest
@testable import CheqEnforce

/// Tests for the consent-flag helpers shared by the alert banner and the
/// themed custom banner. These decide what consent is actually recorded
/// when a banner button is tapped, so regressions here are compliance
/// bugs rather than cosmetic ones.
final class BannerPresenterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ConsentStore.clearAll()
        ConsentStore.hasValidatedExpiry = false
    }

    override func tearDown() {
        ConsentStore.clearAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTranslation(cookies: [String: CookieDetails]?) -> Translation {
        Translation(
            notificationBannerContent: "content",
            notificationBannerAllowAll: "Allow All",
            notificationBannerDenyAll: "Deny All",
            notificationBannerPreferences: "Preferences",
            consentTitle: nil,
            consentDescription: nil,
            consentModalAllowAll: nil,
            consentModalDenyAll: nil,
            save: nil,
            cancel: nil,
            close: "Close",
            cookies: cookies
        )
    }

    private func makeConfig(defaultConsent: [String: Bool]?) -> Config {
        Config(
            "testClient",
            publishPath: "testPath",
            environment: "testEnv",
            defaultConsent: defaultConsent
        )
    }

    private let threeCategories: [String: CookieDetails] = [
        "Analytics":  CookieDetails(title: "Analytics", description: "a"),
        "Marketing":  CookieDetails(title: "Marketing", description: "m"),
        "Functional": CookieDetails(title: "Functional", description: "f")
    ]

    // MARK: - acceptAllFlags

    func testAcceptAllFlagsSetsEveryCategoryTrue() {
        let translation = makeTranslation(cookies: threeCategories)

        let flags = BannerPresenter.acceptAllFlags(translation)

        XCTAssertEqual(flags, ["Analytics": true, "Marketing": true, "Functional": true])
    }

    func testAcceptAllFlagsWithNoCategoriesIsEmpty() {
        let translation = makeTranslation(cookies: nil)

        XCTAssertEqual(BannerPresenter.acceptAllFlags(translation), [:])
    }

    // MARK: - rejectAllFlags

    func testRejectAllFlagsSetsEveryCategoryFalse() {
        let translation = makeTranslation(cookies: threeCategories)

        let flags = BannerPresenter.rejectAllFlags(translation)

        XCTAssertEqual(flags, ["Analytics": false, "Marketing": false, "Functional": false])
    }

    func testRejectAllFlagsWithNoCategoriesIsEmpty() {
        let translation = makeTranslation(cookies: nil)

        XCTAssertEqual(BannerPresenter.rejectAllFlags(translation), [:])
    }

    // MARK: - closeFlags

    func testCloseFlagsUsesDefaultConsentWhenProvided() {
        let translation = makeTranslation(cookies: threeCategories)
        let config = makeConfig(defaultConsent: ["Analytics": true, "Marketing": false])

        let flags = BannerPresenter.closeFlags(translation, config: config)

        // Exactly the configured defaults; categories not mentioned in
        // defaultConsent (Functional) are not added from the translation.
        XCTAssertEqual(flags, ["Analytics": true, "Marketing": false])
    }

    func testCloseFlagsFallsBackToAllFalseWithoutDefaultConsent() {
        let translation = makeTranslation(cookies: threeCategories)
        let config = makeConfig(defaultConsent: nil)

        let flags = BannerPresenter.closeFlags(translation, config: config)

        XCTAssertEqual(flags, ["Analytics": false, "Marketing": false, "Functional": false])
    }

    func testCloseFlagsTreatsEmptyDefaultConsentAsAbsent() {
        let translation = makeTranslation(cookies: threeCategories)
        let config = makeConfig(defaultConsent: [:])

        let flags = BannerPresenter.closeFlags(translation, config: config)

        // An empty defaultConsent is "not configured", not "record nothing".
        XCTAssertEqual(flags, ["Analytics": false, "Marketing": false, "Functional": false])
    }

    func testCloseFlagsUsesDefaultConsentEvenWithoutCategories() {
        let translation = makeTranslation(cookies: nil)
        let config = makeConfig(defaultConsent: ["Analytics": true])

        let flags = BannerPresenter.closeFlags(translation, config: config)

        XCTAssertEqual(flags, ["Analytics": true])
    }

    func testCloseFlagsNilWhenConsentAlreadyStored() {
        // With stored consent, Close must keep it (nil = dismiss only),
        // not overwrite it with defaultConsent.
        ConsentStore.save(["Analytics": true, "Marketing": true], version: "1", expirationMilliseconds: 60_000)
        let translation = makeTranslation(cookies: threeCategories)
        let config = makeConfig(defaultConsent: ["Analytics": false])

        XCTAssertNil(BannerPresenter.closeFlags(translation, config: config))
    }
}
