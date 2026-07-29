import XCTest
import UIKit
@testable import CheqEnforce

final class ThemeTests: XCTestCase {

    // MARK: - JSON decoding

    func testDecodeFullCanonicalJSON() throws {
        let json = """
        {
          "banner": {
            "logoUrl": "https://example.com/logo.png",
            "logoImage": "BrandLogo",
            "logoAlignment": "center",
            "backgroundColor": "#FFFFFF",
            "separatorColor": "#E5E5E5",
            "overlayColor": "#00000080",
            "summary": {
              "description": { "fontName": "Avenir-Book", "fontSize": 14, "fontWeight": "regular", "textAlignment": "left", "textColor": "#000000" }
            },
            "buttons": {
              "acceptAll": { "backgroundColor": "#1E478F", "textColor": "#FFFFFF", "fontSize": 16, "fontWeight": "semibold", "borderColor": "#000000", "borderWidth": 1, "borderRadius": 8 },
              "rejectAll": {},
              "openModal": {},
              "close": {},
              "global": { "backgroundColor": "#EBEBEB", "textColor": "#000000", "borderRadius": 8 }
            }
          },
          "modal": {
            "presentationStyle": "fullScreen",
            "logoUrl": "",
            "logoImage": "",
            "logoAlignment": "full",
            "backgroundColor": "#FFFFFF",
            "separatorColor": "#E5E5E5",
            "overlayColor": "#00000080",
            "summary": {
              "title":       { "fontSize": 18, "fontWeight": "bold", "textColor": "#000000" },
              "description": { "fontSize": 14, "textColor": "#000000" }
            },
            "buttons": { "acceptAll": {}, "rejectAll": {}, "save": {}, "close": {}, "global": {} },
            "categories": {
              "toggleOnColor": "#1E478F",
              "toggleOffColor": "#D9D9D9",
              "title":       { "fontSize": 16, "fontWeight": "bold", "textColor": "#000000" },
              "description": { "fontSize": 14, "textColor": "#666666" }
            }
          }
        }
        """
        let theme = try JSONDecoder().decode(EnforceTheme.self, from: Data(json.utf8))

        XCTAssertEqual(theme.banner?.logoURL, "https://example.com/logo.png")
        XCTAssertEqual(theme.banner?.logoImage, "BrandLogo")
        XCTAssertEqual(theme.banner?.logoAlignment, .center)
        XCTAssertEqual(theme.banner?.backgroundColor, "#FFFFFF")
        XCTAssertEqual(theme.banner?.separatorColor, "#E5E5E5")
        XCTAssertEqual(theme.banner?.overlayColor, "#00000080")
        XCTAssertEqual(theme.banner?.summary?.description?.fontName, "Avenir-Book")
        XCTAssertEqual(theme.banner?.summary?.description?.textAlignment, .left)
        XCTAssertEqual(theme.banner?.buttons?.acceptAll?.backgroundColor, "#1E478F")
        XCTAssertEqual(theme.banner?.buttons?.acceptAll?.fontWeight, .semibold)
        XCTAssertEqual(theme.banner?.buttons?.acceptAll?.borderWidth, 1)
        XCTAssertEqual(theme.banner?.buttons?.global?.borderRadius, 8)

        XCTAssertEqual(theme.modal?.presentationStyle, .fullScreen)
        XCTAssertEqual(theme.modal?.logoAlignment, .full)
        XCTAssertEqual(theme.modal?.summary?.title?.fontWeight, .bold)
        XCTAssertEqual(theme.modal?.categories?.toggleOnColor, "#1E478F")
        XCTAssertEqual(theme.modal?.categories?.toggleOffColor, "#D9D9D9")
        XCTAssertEqual(theme.modal?.categories?.description?.textColor, "#666666")
        XCTAssertNil(theme.modal?.logoUIImage, "Programmatic logo must not decode from JSON")
    }

    func testDecodePartialJSONFallsBackToNil() throws {
        let json = """
        { "banner": { "buttons": { "acceptAll": { "backgroundColor": "#FF0000" } } } }
        """
        let theme = try JSONDecoder().decode(EnforceTheme.self, from: Data(json.utf8))

        XCTAssertNil(theme.modal)
        XCTAssertNil(theme.banner?.backgroundColor)
        XCTAssertNil(EnforceTheme.Modal().presentationStyle, "presentationStyle must default to nil (card)")
        XCTAssertNil(theme.banner?.summary)
        XCTAssertEqual(theme.banner?.buttons?.acceptAll?.backgroundColor, "#FF0000")
        XCTAssertNil(theme.banner?.buttons?.global)
    }

    // MARK: - Button ordering

    private let defaultButtons: [(key: String, value: String)] = [
        ("acceptAll", "A"), ("rejectAll", "R"), ("openModal", "O"), ("close", "C")
    ]

    func testOrderNilKeepsDefaultOrder() {
        let result = ThemeResolver.orderedButtons(defaultButtons, order: nil, token: "test")
        XCTAssertEqual(result, ["A", "R", "O", "C"])
    }

    func testOrderEmptyKeepsDefaultOrder() {
        let result = ThemeResolver.orderedButtons(defaultButtons, order: [], token: "test")
        XCTAssertEqual(result, ["A", "R", "O", "C"])
    }

    func testOrderFullReorder() {
        let result = ThemeResolver.orderedButtons(defaultButtons, order: ["close", "openModal", "rejectAll", "acceptAll"], token: "test")
        XCTAssertEqual(result, ["C", "O", "R", "A"])
    }

    func testOrderPartialListsNamedFirstThenDefaultOrder() {
        let result = ThemeResolver.orderedButtons(defaultButtons, order: ["close"], token: "test")
        XCTAssertEqual(result, ["C", "A", "R", "O"], "Unlisted buttons must follow in default order")
    }

    func testOrderUnknownNameIgnored() {
        let result = ThemeResolver.orderedButtons(defaultButtons, order: ["saveEverything", "rejectAll"], token: "test")
        XCTAssertEqual(result, ["R", "A", "O", "C"])
    }

    func testOrderDuplicateFirstOccurrenceWins() {
        let result = ThemeResolver.orderedButtons(defaultButtons, order: ["rejectAll", "close", "rejectAll"], token: "test")
        XCTAssertEqual(result, ["R", "C", "A", "O"], "Duplicate names must not render a button twice")
    }

    func testOrderDecodesFromJSON() throws {
        let json = """
        { "banner": { "buttons": { "order": ["rejectAll", "acceptAll"] } },
          "modal":  { "buttons": { "order": ["save", "close"] } } }
        """
        let theme = try JSONDecoder().decode(EnforceTheme.self, from: Data(json.utf8))

        XCTAssertEqual(theme.banner?.buttons?.order, ["rejectAll", "acceptAll"])
        XCTAssertEqual(theme.modal?.buttons?.order, ["save", "close"])
    }

    // MARK: - File loading

    func testLoadThemeFromFileURL() throws {
        let json = """
        { "banner": { "backgroundColor": "#123456",
                      "buttons": { "acceptAll": { "backgroundColor": "#2E7D32" } } } }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-test-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let theme = try EnforceTheme(contentsOf: url)

        XCTAssertEqual(theme.banner?.backgroundColor, "#123456")
        XCTAssertEqual(theme.banner?.buttons?.acceptAll?.backgroundColor, "#2E7D32")
    }

    func testLoadThemeFromInvalidFileThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-test-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try EnforceTheme(contentsOf: url))
    }

    func testLoadThemeFromMissingBundleFileThrows() {
        XCTAssertThrowsError(try EnforceTheme(bundleFile: "no_such_theme_file")) { error in
            guard case EnforceTheme.LoadError.fileNotFound(let name) = error else {
                return XCTFail("Expected LoadError.fileNotFound, got \(error)")
            }
            XCTAssertEqual(name, "no_such_theme_file.json")
        }
    }

    // MARK: - Hex parsing

    func testHexColorSixDigits() {
        let color = UIColor(hex: "#1E478F")
        XCTAssertNotNil(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0x1E / 255, accuracy: 0.001)
        XCTAssertEqual(g, 0x47 / 255, accuracy: 0.001)
        XCTAssertEqual(b, 0x8F / 255, accuracy: 0.001)
        XCTAssertEqual(a, 1, accuracy: 0.001)
    }

    func testHexColorEightDigitsIncludesAlpha() {
        let color = UIColor(hex: "#00000080")
        XCTAssertNotNil(color)
        var a: CGFloat = 0
        color?.getRed(nil, green: nil, blue: nil, alpha: &a)
        XCTAssertEqual(a, 0x80 / 255, accuracy: 0.001)
    }

    func testHexColorShorthandThreeDigits() {
        let color = UIColor(hex: "#F00")
        XCTAssertNotNil(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1, accuracy: 0.001)
        XCTAssertEqual(g, 0, accuracy: 0.001)
        XCTAssertEqual(b, 0, accuracy: 0.001)
    }

    func testHexColorWithoutLeadingHash() {
        XCTAssertNotNil(UIColor(hex: "FFFFFF"))
    }

    func testInvalidHexColorReturnsNil() {
        XCTAssertNil(UIColor(hex: ""))
        XCTAssertNil(UIColor(hex: "#GGGGGG"))
        XCTAssertNil(UIColor(hex: "#12345"))     // invalid length
        XCTAssertNil(UIColor(hex: "not a color"))
    }

    // MARK: - Resolution: specific ?? global ?? default

    func testButtonStyleResolutionPrefersSpecific() {
        let specific = EnforceTheme.ButtonStyle(backgroundColor: "#FF0000", textColor: "#00FF00")
        let global = EnforceTheme.ButtonStyle(backgroundColor: "#0000FF", textColor: "#FFFFFF", borderRadius: 4)

        let resolved = ThemeResolver.buttonStyle(specific, global: global, defaults: ThemeDefaults.secondaryButton, token: "test")

        XCTAssertEqual(resolved.backgroundColor, UIColor(hex: "#FF0000"))
        XCTAssertEqual(resolved.textColor, UIColor(hex: "#00FF00"))
        // Missing on specific → falls back to global
        XCTAssertEqual(resolved.cornerRadius, 4)
    }

    func testButtonStyleResolutionFallsBackToGlobalThenDefault() {
        let global = EnforceTheme.ButtonStyle(backgroundColor: "#0000FF")

        let resolved = ThemeResolver.buttonStyle(nil, global: global, defaults: ThemeDefaults.secondaryButton, token: "test")

        XCTAssertEqual(resolved.backgroundColor, UIColor(hex: "#0000FF"))
        // Missing everywhere → framework default
        XCTAssertEqual(resolved.textColor, ThemeDefaults.secondaryButton.textColor)
        XCTAssertEqual(resolved.cornerRadius, ThemeDefaults.secondaryButton.cornerRadius)
    }

    func testButtonStyleResolutionAllDefaults() {
        let resolved = ThemeResolver.buttonStyle(nil, global: nil, defaults: ThemeDefaults.primaryButton, token: "test")

        XCTAssertEqual(resolved.backgroundColor, ThemeDefaults.primaryButton.backgroundColor)
        XCTAssertEqual(resolved.textColor, ThemeDefaults.primaryButton.textColor)
        XCTAssertEqual(resolved.borderWidth, 0)
    }

    func testInvalidHexInStyleFallsBackToDefault() {
        let specific = EnforceTheme.ButtonStyle(backgroundColor: "#NOTHEX")

        let resolved = ThemeResolver.buttonStyle(specific, global: nil, defaults: ThemeDefaults.primaryButton, token: "test")

        XCTAssertEqual(resolved.backgroundColor, ThemeDefaults.primaryButton.backgroundColor)
    }

    func testEmptyHexStringTreatedAsAbsent() {
        let specific = EnforceTheme.ButtonStyle(backgroundColor: "")
        let global = EnforceTheme.ButtonStyle(backgroundColor: "#0000FF")

        let resolved = ThemeResolver.buttonStyle(specific, global: global, defaults: ThemeDefaults.primaryButton, token: "test")

        // Empty string is "absent"; but note: `specific ?? global` picks specific's
        // non-nil empty string, then color() falls back. Falls to default, not global.
        XCTAssertEqual(resolved.backgroundColor, ThemeDefaults.primaryButton.backgroundColor)
    }

    func testTextStyleResolution() {
        let style = EnforceTheme.TextStyle(fontSize: 20, fontWeight: .bold, textAlignment: .center, textColor: "#112233")

        let resolved = ThemeResolver.textStyle(style, defaultSize: 14, defaultWeight: .regular, token: "test")

        XCTAssertEqual(resolved.font.pointSize, 20)
        XCTAssertEqual(resolved.textAlignment, .center)
        XCTAssertEqual(resolved.textColor, UIColor(hex: "#112233"))
    }

    func testTextStyleResolutionDefaults() {
        let resolved = ThemeResolver.textStyle(nil, defaultSize: 14, defaultWeight: .regular, token: "test")

        XCTAssertEqual(resolved.font.pointSize, 14)
        XCTAssertEqual(resolved.textColor, ThemeDefaults.text)
        XCTAssertEqual(resolved.textAlignment, .natural)
    }

    func testUnknownFontNameFallsBackToSystemFont() {
        let resolved = ThemeResolver.font(name: "NoSuchFont-Bold", size: 15, weight: .regular)
        XCTAssertEqual(resolved.pointSize, 15)
    }

    // MARK: - Config

    func testConfigThemeDefaultsToNil() {
        let config = Config("client", publishPath: "path", environment: "env")
        XCTAssertNil(config.theme)
    }

    func testConfigCarriesTheme() {
        let theme = EnforceTheme(banner: EnforceTheme.Banner(backgroundColor: "#FFFFFF"))
        let config = Config("client", publishPath: "path", environment: "env", theme: theme)
        XCTAssertNotNil(config.theme)
        XCTAssertEqual(config.theme?.banner?.backgroundColor, "#FFFFFF")
    }
}
