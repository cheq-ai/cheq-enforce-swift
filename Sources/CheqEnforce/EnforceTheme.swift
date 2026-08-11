import UIKit
import os

private let log = Logger(subsystem: "Cheq", category: "EnforceTheme")

// MARK: - EnforceTheme
/// Visual customization for the consent experience.
///
/// Supplying an `EnforceTheme` in ``Config`` switches the banner to the custom
/// bottom-sheet style and applies the theme to the consent modal. When no
/// theme is provided the SDK keeps its default `UIAlertController` banner
/// and system-styled modal.
///
/// All properties are optional: any value that is omitted (or fails to
/// parse) falls back to a light-mode default. The structure is `Codable`
/// and matches the shared cross-SDK JSON shape, e.g.:
///
/// ```json
/// {
///   "banner": {
///     "logoUrl": "", "logoImage": "", "logoAlignment": "center",
///     "backgroundColor": "#FFFFFF", "separatorColor": "#E5E5E5", "overlayColor": "#00000080",
///     "summary": { "description": { "fontSize": 14, "textColor": "#000000" } },
///     "buttons": {
///       "acceptAll": { "backgroundColor": "#1E478F", "textColor": "#FFFFFF" },
///       "global":    { "backgroundColor": "#EBEBEB", "textColor": "#000000", "borderRadius": 8 }
///     }
///   },
///   "modal": { "categories": { "toggleOnColor": "#1E478F" } }
/// }
/// ```
public struct EnforceTheme: Codable {
    public let banner: Banner?
    public let modal: Modal?

    public init(banner: Banner? = nil, modal: Modal? = nil) {
        self.banner = banner
        self.modal = modal
    }

    // MARK: - Enums

    /// Horizontal placement of the logo at the top of the banner/modal.
    public enum LogoAlignment: String, Codable {
        case left, center, right, full
    }

    /// Font weight used when no custom `fontName` is provided.
    public enum FontWeight: String, Codable {
        case regular, medium, semibold, bold

        var uiFontWeight: UIFont.Weight {
            switch self {
            case .regular:  return .regular
            case .medium:   return .medium
            case .semibold: return .semibold
            case .bold:     return .bold
            }
        }
    }

    /// How the themed consent modal is presented.
    public enum ModalPresentationStyle: String, Codable {
        /// Centered card over a dimmed background (default).
        case card
        /// Covers the entire screen.
        case fullScreen
    }

    /// Text alignment for styled labels.
    public enum TextAlignment: String, Codable {
        case left, center, right, justified, natural

        var nsTextAlignment: NSTextAlignment {
            switch self {
            case .left:      return .left
            case .center:    return .center
            case .right:     return .right
            case .justified: return .justified
            case .natural:   return .natural
            }
        }
    }

    // MARK: - Building blocks

    /// Text styling for a label (summary title/description, category rows).
    public struct TextStyle: Codable {
        public let fontName: String?
        public let fontSize: CGFloat?
        public let fontWeight: FontWeight?
        public let textAlignment: TextAlignment?
        public let textColor: String?          // hex, e.g. "#000000"

        public init(fontName: String? = nil,
                    fontSize: CGFloat? = nil,
                    fontWeight: FontWeight? = nil,
                    textAlignment: TextAlignment? = nil,
                    textColor: String? = nil) {
            self.fontName = fontName
            self.fontSize = fontSize
            self.fontWeight = fontWeight
            self.textAlignment = textAlignment
            self.textColor = textColor
        }
    }

    /// Styling for a single button. Any missing value falls back to the
    /// `global` button style, then to the framework's light-mode default.
    public struct ButtonStyle: Codable {
        public let backgroundColor: String?    // hex
        public let fontName: String?
        public let fontSize: CGFloat?
        public let fontWeight: FontWeight?
        public let textColor: String?          // hex
        public let borderColor: String?        // hex
        public let borderWidth: CGFloat?
        public let borderRadius: CGFloat?

        public init(backgroundColor: String? = nil,
                    fontName: String? = nil,
                    fontSize: CGFloat? = nil,
                    fontWeight: FontWeight? = nil,
                    textColor: String? = nil,
                    borderColor: String? = nil,
                    borderWidth: CGFloat? = nil,
                    borderRadius: CGFloat? = nil) {
            self.backgroundColor = backgroundColor
            self.fontName = fontName
            self.fontSize = fontSize
            self.fontWeight = fontWeight
            self.textColor = textColor
            self.borderColor = borderColor
            self.borderWidth = borderWidth
            self.borderRadius = borderRadius
        }
    }

    /// Summary text block: the banner uses `description` only; the modal
    /// uses both `title` and `description`.
    public struct Summary: Codable {
        public let title: TextStyle?
        public let description: TextStyle?

        public init(title: TextStyle? = nil, description: TextStyle? = nil) {
            self.title = title
            self.description = description
        }
    }

    /// Styles for the banner's buttons. Each is optional; `global` provides
    /// fallback values for the others. `order` lists button names top to
    /// bottom ("acceptAll", "rejectAll", "openModal", "close"); names not
    /// listed follow in the default order, unknown or duplicate names are
    /// logged and ignored, and omitting it keeps the default order.
    public struct BannerButtons: Codable {
        public let order: [String]?
        public let acceptAll: ButtonStyle?
        public let rejectAll: ButtonStyle?
        public let openModal: ButtonStyle?
        public let close: ButtonStyle?
        public let global: ButtonStyle?

        public init(order: [String]? = nil,
                    acceptAll: ButtonStyle? = nil,
                    rejectAll: ButtonStyle? = nil,
                    openModal: ButtonStyle? = nil,
                    close: ButtonStyle? = nil,
                    global: ButtonStyle? = nil) {
            self.order = order
            self.acceptAll = acceptAll
            self.rejectAll = rejectAll
            self.openModal = openModal
            self.close = close
            self.global = global
        }
    }

    /// Styles for the modal's buttons. Each is optional; `global` provides
    /// fallback values for the others. `order` lists button names
    /// ("acceptAll", "rejectAll", "save", "close") with the same rules as
    /// the banner's.
    public struct ModalButtons: Codable {
        public let order: [String]?
        public let acceptAll: ButtonStyle?
        public let rejectAll: ButtonStyle?
        public let save: ButtonStyle?
        public let close: ButtonStyle?
        public let global: ButtonStyle?

        public init(order: [String]? = nil,
                    acceptAll: ButtonStyle? = nil,
                    rejectAll: ButtonStyle? = nil,
                    save: ButtonStyle? = nil,
                    close: ButtonStyle? = nil,
                    global: ButtonStyle? = nil) {
            self.order = order
            self.acceptAll = acceptAll
            self.rejectAll = rejectAll
            self.save = save
            self.close = close
            self.global = global
        }
    }

    /// Styling for the modal's cookie-category rows.
    public struct Categories: Codable {
        public let toggleOnColor: String?      // hex - UISwitch on tint
        public let toggleOffColor: String?     // hex - UISwitch off-state track
        public let separatorColor: String?     // hex - divider between category rows (none after the last)
        public let title: TextStyle?           // category name label
        public let description: TextStyle?     // category description label

        public init(toggleOnColor: String? = nil,
                    toggleOffColor: String? = nil,
                    separatorColor: String? = nil,
                    title: TextStyle? = nil,
                    description: TextStyle? = nil) {
            self.toggleOnColor = toggleOnColor
            self.toggleOffColor = toggleOffColor
            self.separatorColor = separatorColor
            self.title = title
            self.description = description
        }
    }

    // MARK: - Banner / Modal sub-themes

    /// EnforceTheme for the bottom-sheet consent banner.
    public struct Banner: Codable {
        public let logoURL: String?            // JSON key "logoUrl"
        public let logoImage: String?          // asset-catalog image name
        public let logoAlignment: LogoAlignment?
        public let backgroundColor: String?    // hex
        public let separatorColor: String?     // hex - divider line
        public let overlayColor: String?       // hex - dimming overlay behind the sheet
        public let summary: Summary?
        public let buttons: BannerButtons?

        /// Programmatic logo image. Takes precedence over `logoImage` and
        /// `logoURL`. Not part of the JSON representation.
        public var logoUIImage: UIImage?

        enum CodingKeys: String, CodingKey {
            case logoURL = "logoUrl"
            case logoImage, logoAlignment, backgroundColor, separatorColor, overlayColor, summary, buttons
        }

        public init(logoURL: String? = nil,
                    logoImage: String? = nil,
                    logoAlignment: LogoAlignment? = nil,
                    backgroundColor: String? = nil,
                    separatorColor: String? = nil,
                    overlayColor: String? = nil,
                    summary: Summary? = nil,
                    buttons: BannerButtons? = nil,
                    logoUIImage: UIImage? = nil) {
            self.logoURL = logoURL
            self.logoImage = logoImage
            self.logoAlignment = logoAlignment
            self.backgroundColor = backgroundColor
            self.separatorColor = separatorColor
            self.overlayColor = overlayColor
            self.summary = summary
            self.buttons = buttons
            self.logoUIImage = logoUIImage
        }
    }

    /// EnforceTheme for the consent preferences modal.
    public struct Modal: Codable {
        public let presentationStyle: ModalPresentationStyle?  // default .card
        public let logoURL: String?            // JSON key "logoUrl"
        public let logoImage: String?          // asset-catalog image name
        public let logoAlignment: LogoAlignment?
        public let backgroundColor: String?    // hex
        public let separatorColor: String?     // hex - divider line
        public let overlayColor: String?       // hex - dimming overlay behind the modal
        public let summary: Summary?
        public let buttons: ModalButtons?
        public let categories: Categories?

        /// Programmatic logo image. Takes precedence over `logoImage` and
        /// `logoURL`. Not part of the JSON representation.
        public var logoUIImage: UIImage?

        enum CodingKeys: String, CodingKey {
            case logoURL = "logoUrl"
            case presentationStyle, logoImage, logoAlignment, backgroundColor, separatorColor, overlayColor, summary, buttons, categories
        }

        public init(presentationStyle: ModalPresentationStyle? = nil,
                    logoURL: String? = nil,
                    logoImage: String? = nil,
                    logoAlignment: LogoAlignment? = nil,
                    backgroundColor: String? = nil,
                    separatorColor: String? = nil,
                    overlayColor: String? = nil,
                    summary: Summary? = nil,
                    buttons: ModalButtons? = nil,
                    categories: Categories? = nil,
                    logoUIImage: UIImage? = nil) {
            self.presentationStyle = presentationStyle
            self.logoURL = logoURL
            self.logoImage = logoImage
            self.logoAlignment = logoAlignment
            self.backgroundColor = backgroundColor
            self.separatorColor = separatorColor
            self.overlayColor = overlayColor
            self.summary = summary
            self.buttons = buttons
            self.categories = categories
            self.logoUIImage = logoUIImage
        }
    }
}

// MARK: - Loading a theme from a JSON file

public extension EnforceTheme {
    /// Errors thrown when loading a theme from a file.
    enum LoadError: Error, LocalizedError {
        /// No file with the given name was found in the bundle.
        case fileNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let name):
                return "Theme file '\(name)' not found in bundle."
            }
        }
    }

    /// Creates a theme from a JSON file at the given URL.
    ///
    /// The file uses the shared cross-SDK theme shape; the same document
    /// works with the web and Android SDKs.
    ///
    /// - Parameter url: location of the theme JSON file.
    /// - Throws: an error if the file can't be read, or `DecodingError` if
    ///   its contents are not valid theme JSON.
    init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(EnforceTheme.self, from: Data(contentsOf: url))
    }

    /// Creates a theme from a JSON file bundled with the app. This is the
    /// recommended way to supply a theme.
    ///
    /// The conventional cross-SDK file name is `enforce_theme.json`:
    ///
    /// ```swift
    /// let theme = try EnforceTheme(bundleFile: "enforce_theme")
    /// Enforce.configure(Config("client", publishPath: "...", environment: "...", theme: theme))
    /// ```
    ///
    /// - Parameters:
    ///   - name: the file name without the `.json` extension.
    ///   - bundle: the bundle to search, default `.main`.
    /// - Throws: ``LoadError/fileNotFound(_:)`` if the file isn't in the
    ///   bundle, or `DecodingError` if its contents are not valid theme JSON.
    init(bundleFile name: String, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LoadError.fileNotFound("\(name).json")
        }
        try self.init(contentsOf: url)
    }
}

// MARK: - Hex color parsing

extension UIColor {
    /// Creates a color from a hex string: `#RGB`, `#RRGGBB` or `#RRGGBBAA`
    /// (leading `#` optional). Returns `nil` for anything else.
    convenience init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard !string.isEmpty, string.allSatisfy({ $0.isHexDigit }) else { return nil }

        // Expand shorthand #RGB -> #RRGGBB
        if string.count == 3 {
            string = string.map { "\($0)\($0)" }.joined()
        }

        var value: UInt64 = 0
        guard Scanner(string: string).scanHexInt64(&value) else { return nil }

        switch string.count {
        case 6:
            self.init(red:   CGFloat((value >> 16) & 0xFF) / 255,
                      green: CGFloat((value >> 8)  & 0xFF) / 255,
                      blue:  CGFloat(value         & 0xFF) / 255,
                      alpha: 1)
        case 8:
            self.init(red:   CGFloat((value >> 24) & 0xFF) / 255,
                      green: CGFloat((value >> 16) & 0xFF) / 255,
                      blue:  CGFloat((value >> 8)  & 0xFF) / 255,
                      alpha: CGFloat(value         & 0xFF) / 255)
        default:
            return nil
        }
    }
}

// MARK: - Resolved styles (internal)

/// Fully-resolved, non-optional style for one button after applying
/// `specific ?? global ?? default` per property.
struct ResolvedButtonStyle {
    let backgroundColor: UIColor
    let textColor: UIColor
    let font: UIFont
    let borderColor: UIColor
    let borderWidth: CGFloat
    let cornerRadius: CGFloat

    func apply(to button: UIButton) {
        button.backgroundColor = backgroundColor
        button.setTitleColor(textColor, for: .normal)
        button.titleLabel?.font = font
        button.layer.borderColor = borderColor.cgColor
        button.layer.borderWidth = borderWidth
        button.layer.cornerRadius = cornerRadius
        button.clipsToBounds = true
    }
}

/// Fully-resolved, non-optional style for one label.
struct ResolvedTextStyle {
    let font: UIFont
    let textColor: UIColor
    let textAlignment: NSTextAlignment

    func apply(to label: UILabel) {
        label.font = font
        label.textColor = textColor
        label.textAlignment = textAlignment
    }
}

// MARK: - Light-mode framework defaults (internal)

enum ThemeDefaults {
    static let background = UIColor.white
    static let text       = UIColor.black
    static let overlay    = UIColor.black.withAlphaComponent(0.5)
    static let toggleOn   = UIColor.systemBlue
    static let toggleOff  = UIColor(white: 0.85, alpha: 1)

    /// Filled brand button (Accept All, Reject All — matched so neither
    /// consent choice is visually privileged, per GDPR guidance).
    static let primaryButton = ResolvedButtonStyle(
        backgroundColor: .systemBlue,
        textColor: .white,
        font: .systemFont(ofSize: 16, weight: .semibold),
        borderColor: .clear,
        borderWidth: 0,
        cornerRadius: 8
    )

    /// Light gray filled button (Preferences, Save).
    static let secondaryButton = ResolvedButtonStyle(
        backgroundColor: UIColor(white: 0.92, alpha: 1),
        textColor: .black,
        font: .systemFont(ofSize: 16),
        borderColor: .clear,
        borderWidth: 0,
        cornerRadius: 8
    )

    /// Text-only button (Close).
    static let textOnlyButton = ResolvedButtonStyle(
        backgroundColor: .clear,
        textColor: .gray,
        font: .systemFont(ofSize: 16),
        borderColor: .clear,
        borderWidth: 0,
        cornerRadius: 8
    )
}

// MARK: - EnforceTheme resolution (internal)

enum ThemeResolver {
    /// Parses a hex color token, falling back to `fallback` when the token
    /// is absent, empty, or invalid (invalid values are logged).
    static func color(_ hex: String?, fallback: UIColor, token: String) -> UIColor {
        guard let hex, !hex.isEmpty else { return fallback }
        guard let color = UIColor(hex: hex) else {
            log.info("Invalid hex color '\(hex, privacy: .public)' for theme token '\(token, privacy: .public)'; using default.")
            return fallback
        }
        return color
    }

    /// Resolves a font from an optional custom font name, falling back to
    /// the system font at the given size/weight (missing fonts are logged).
    static func font(name: String?, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        if let name, !name.isEmpty {
            if let custom = UIFont(name: name, size: size) { return custom }
            log.info("Font '\(name, privacy: .public)' not found; using system font.")
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    /// Resolves one button's style: `specific ?? global ?? defaults` per property.
    static func buttonStyle(_ specific: EnforceTheme.ButtonStyle?,
                            global: EnforceTheme.ButtonStyle?,
                            defaults: ResolvedButtonStyle,
                            defaultFontSize: CGFloat = 16,
                            defaultFontWeight: UIFont.Weight = .regular,
                            token: String) -> ResolvedButtonStyle {
        func pick<T>(_ keyPath: KeyPath<EnforceTheme.ButtonStyle, T?>) -> T? {
            specific?[keyPath: keyPath] ?? global?[keyPath: keyPath]
        }
        let size = pick(\.fontSize) ?? defaultFontSize
        let weight = pick(\.fontWeight)?.uiFontWeight ?? defaultFontWeight
        return ResolvedButtonStyle(
            backgroundColor: color(pick(\.backgroundColor), fallback: defaults.backgroundColor, token: "\(token).backgroundColor"),
            textColor: color(pick(\.textColor), fallback: defaults.textColor, token: "\(token).textColor"),
            font: font(name: pick(\.fontName), size: size, weight: weight),
            borderColor: color(pick(\.borderColor), fallback: defaults.borderColor, token: "\(token).borderColor"),
            borderWidth: pick(\.borderWidth) ?? defaults.borderWidth,
            cornerRadius: pick(\.borderRadius) ?? defaults.cornerRadius
        )
    }

    /// Applies a theme's button `order` to items keyed by button name.
    /// Names in `order` come first, in the given order; buttons not listed
    /// follow in their default order. Duplicate names (first occurrence
    /// wins) and names that are unknown or not shown by the remote config
    /// are logged and skipped. A nil or empty order keeps the default.
    static func orderedButtons<T>(_ items: [(key: String, value: T)], order: [String]?, token: String) -> [T] {
        guard let order, !order.isEmpty else { return items.map(\.value) }

        var remaining = items
        var result: [T] = []
        var seen = Set<String>()
        for name in order {
            guard seen.insert(name).inserted else {
                log.info("Duplicate button '\(name, privacy: .public)' in \(token, privacy: .public); first occurrence wins.")
                continue
            }
            if let index = remaining.firstIndex(where: { $0.key == name }) {
                result.append(remaining.remove(at: index).value)
            } else {
                log.info("Button '\(name, privacy: .public)' in \(token, privacy: .public) is unknown or not shown; ignored.")
            }
        }
        result.append(contentsOf: remaining.map(\.value))
        return result
    }

    /// Resolves a text style against per-role defaults.
    static func textStyle(_ style: EnforceTheme.TextStyle?,
                          defaultSize: CGFloat,
                          defaultWeight: UIFont.Weight,
                          defaultColor: UIColor = ThemeDefaults.text,
                          defaultAlignment: NSTextAlignment = .natural,
                          token: String) -> ResolvedTextStyle {
        let size = style?.fontSize ?? defaultSize
        let weight = style?.fontWeight?.uiFontWeight ?? defaultWeight
        return ResolvedTextStyle(
            font: font(name: style?.fontName, size: size, weight: weight),
            textColor: color(style?.textColor, fallback: defaultColor, token: "\(token).textColor"),
            textAlignment: style?.textAlignment?.nsTextAlignment ?? defaultAlignment
        )
    }
}

// MARK: - Logo loading (internal)

enum ThemeLogoLoader {
    /// Resolves the logo image with precedence: programmatic UIImage →
    /// asset-catalog name → remote URL (short timeout). Any failure logs
    /// and returns `nil` so the UI renders without a logo.
    static func load(uiImage: UIImage?, assetName: String?, urlString: String?) async -> UIImage? {
        if let uiImage { return uiImage }

        if let assetName, !assetName.isEmpty {
            if let image = UIImage(named: assetName) { return image }
            log.info("Logo asset '\(assetName, privacy: .public)' not found in main bundle.")
        }

        if let urlString, !urlString.isEmpty {
            guard let url = URL(string: urlString) else {
                log.info("Invalid logo URL '\(urlString, privacy: .public)'.")
                return nil
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                let (data, _) = try await URLSession.shared.data(for: request)
                if let image = UIImage(data: data) { return image }
                log.info("Logo URL did not return image data: \(urlString, privacy: .public)")
            } catch {
                log.info("Failed to fetch logo from '\(urlString, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }
}
