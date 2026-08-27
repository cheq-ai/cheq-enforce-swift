import XCTest
@testable import CheqEnforce

/// The modal must read and write consent under the cookies dictionary key
/// (the stable category identifier the banner and checkConsent use), not the
/// display title, which may be localized and differ from the key.
final class ModalConsentKeyingTests: XCTestCase {

    private let dataKey    = "cheqEnforceConsentData"
    private let expiryKey  = "cheqEnforceConsentExpirationTime"
    private let versionKey = "cheqEnforceConsentVersion"

    override func setUp() {
        super.setUp()
        wipeStore()
        ConsentStore.hasValidatedExpiry = false
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
    }

    @MainActor
    private func makeModal(sections: [(key: String, title: String, description: String)]) -> CustomConsentModalViewController {
        CustomConsentModalViewController(
            title: "Privacy",
            description: "Description",
            modalConfig: ConsentModalConfig(
                ensConsentAcceptAll: nil,
                ensConsentRejectAll: nil,
                ensSaveModal: nil,
                ensCloseModal: nil
            ),
            sections: sections,
            config: Config(
                "testClient",
                publishPath: "testPath",
                environment: "English",
                autoShow: false,
                version: "1"
            ),
            allowAllTitle: "",
            denyAllTitle: "",
            saveTitle: "",
            cancelTitle: ""
        )
    }

    @MainActor
    func testTogglesSeedFromCategoryKeyNotTitle() {
        // Consent stored under the category key, as the banner writes it.
        ConsentStore.save(["analytics": true], version: "1", expirationMilliseconds: 60_000)

        let modal = makeModal(sections: [
            (key: "analytics", title: "Analytique", description: "Localized title differs from key")
        ])

        XCTAssertEqual(modal.toggleStates, [true],
                       "Toggle seeding must read consent by category key, not display title")
    }

    @MainActor
    func testTogglesUnseededWhenConsentStoredUnderTitle() {
        // Consent stored under the display title must NOT seed the toggle;
        // this is the divergence the banner/modal previously disagreed on.
        ConsentStore.save(["Analytique": true], version: "1", expirationMilliseconds: 60_000)

        let modal = makeModal(sections: [
            (key: "analytics", title: "Analytique", description: "Localized title differs from key")
        ])

        XCTAssertEqual(modal.toggleStates, [false])
    }
}
