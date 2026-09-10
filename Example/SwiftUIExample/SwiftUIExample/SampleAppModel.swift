import SwiftUI
import CheqEnforce
import os

private let osLog = Logger(subsystem: "Cheq", category: "CheqEnforce")

/// The selectable sample themes when "Use Custom Theme" is on.
enum SampleThemeChoice: String, CaseIterable, Identifiable {
    case allFields = "All Fields"
    case cheq = "Cheq Brand"
    case defaults = "All Defaults"
    var id: String { rawValue }
}

/// App-lifetime state for the sample app: the live consent dictionary,
/// the on-screen log, and one inline result per action. All SDK calls go
/// through here so their outcomes are visible in the app as well as the
/// console. This demonstrates the SDK's public API only; no SDK internals.
@MainActor
@Observable
final class SampleAppModel {

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: String
        let message: String
    }

    struct ActionResult {
        enum Style { case success, error, info }
        let message: String
        let style: Style
    }

    // MARK: - State the UI renders

    /// Current consent per category; drives the Consent State card.
    private(set) var consent: [String: Bool] = [:]

    /// On-screen log, newest first.
    private(set) var logEntries: [LogEntry] = []

    // Inline results shown under each action's button.
    var environmentResult: ActionResult?
    var getEnvironmentResult: ActionResult?
    var checkConsentResult: ActionResult?
    var getConsentResult: ActionResult?
    var setConsentResult: ActionResult?
    var configurationResult: ActionResult?

    /// The environment this app configures. setEnvironment() overrides are
    /// persisted and re-applied by the SDK itself, so reconfigurations always
    /// pass this fixed value and resetEnvironment() can revert to it.
    private static let configuredEnvironment = "English"

    /// The effective environment (configured value or active override),
    /// synced from the SDK for display.
    private(set) var currentEnvironment = configuredEnvironment

    private static let maxLogEntries = 200

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: - Setup

    init() {
        // Live consent state: registered once here for the app's lifetime,
        // because onConsent handlers cannot be unregistered. Callbacks can
        // arrive off the main thread, so hop before touching state.
        Enforce.onConsent { [weak self] consent in
            Task { @MainActor in
                guard let self else { return }
                self.consent = consent
                self.log("onConsent 1: \(Self.format(consent))")
            }
        }
        Enforce.onConsent { [weak self] consent in
            Task { @MainActor in
                self?.log("onConsent 2: \(Self.format(consent))")
            }
        }

        log("Configuring Enforce…")
        configure(themed: false, choice: .allFields, autoShow: true)
        consent = Enforce.getConsent()
    }

    // MARK: - Logging

    /// Adds a timestamped entry to the on-screen log (newest first) and
    /// mirrors it to the console via os.Logger.
    func log(_ message: String) {
        let entry = LogEntry(timestamp: Self.timeFormatter.string(from: Date()), message: message)
        logEntries.insert(entry, at: 0)
        if logEntries.count > Self.maxLogEntries {
            logEntries.removeLast(logEntries.count - Self.maxLogEntries)
        }
        osLog.info("\(message, privacy: .public)")
    }

    /// Formats a consent dictionary like the React sample: {"Analytics":true}
    static func format(_ consent: [String: Bool]) -> String {
        guard !consent.isEmpty else { return "{}" }
        let body = consent.sorted { $0.key < $1.key }
            .map { "\"\($0.key)\":\($0.value)" }
            .joined(separator: ",")
        return "{\(body)}"
    }

    // MARK: - Actions

    /// Configures Enforce with the selected sample theme (or none) so all
    /// banner styles can be exercised. Reconfigurations use autoShow: false
    /// so the UI only appears when Show Banner / Show Modal is tapped.
    func configure(themed: Bool, choice: SampleThemeChoice, autoShow: Bool = false) {
        log("configure() called (theme: \(themed ? choice.rawValue : "none"), environment: \(Self.configuredEnvironment))")
        Enforce.configure(Config(
            "demoretail",
            publishPath: "mobile_privacy_sdk",
            environment: Self.configuredEnvironment,
            debug: true,
            dataRetentionPeriod: 60000,
            autoShow: autoShow,
            version: "1",
            defaultConsent: ["Analytics": true, "Marketing": false, "Functional": true],
            appearance: .default,
            theme: themed ? Self.theme(for: choice) : nil
        ))

        // The SDK may apply a persisted setEnvironment() override during
        // configure; sync so the sample app reflects the effective value.
        if let effective = Enforce.getEnvironment(), effective != currentEnvironment {
            currentEnvironment = effective
            log("configure(): stored environment override in effect: \"\(effective)\"")
        }
    }

    func getEnvironment() {
        let message: String
        if let environment = Enforce.getEnvironment() {
            message = "getEnvironment(): \"\(environment)\""
        } else {
            message = "getEnvironment(): nil (configure() not called yet)"
        }
        getEnvironmentResult = ActionResult(message: message, style: .info)
        log(message)
    }

    func resetEnvironment() {
        Enforce.resetEnvironment()
        currentEnvironment = Enforce.getEnvironment() ?? currentEnvironment
        let message = "resetEnvironment(): environment is now \"\(currentEnvironment)\""
        environmentResult = ActionResult(message: message, style: .success)
        log(message)
    }

    func setEnvironment(_ name: String) {
        log("setEnvironment(\"\(name)\") started")
        Task {
            do {
                try await Enforce.setEnvironment(name)
                currentEnvironment = name
                environmentResult = ActionResult(message: "Environment updated to \"\(name)\".", style: .success)
                log("setEnvironment(\"\(name)\") complete")
            } catch {
                environmentResult = ActionResult(message: "Unable to switch environment - it may not exist", style: .error)
                log("setEnvironment(\"\(name)\") error: \(error.localizedDescription)")
            }
        }
    }

    func checkConsent(_ category: String) {
        let message = "checkConsent(\"\(category)\"): \(Enforce.checkConsent(category))"
        checkConsentResult = ActionResult(message: message, style: .info)
        log(message)
    }

    func getConsent(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let data: [String: Bool]
        let label: String
        if trimmed.isEmpty {
            data = Enforce.getConsent()
            label = "getConsent()"
        } else if trimmed.contains(",") {
            let keys = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            data = Enforce.getConsent(for: keys)
            label = "getConsent(for: [\(keys.map { "\"\($0)\"" }.joined(separator: ", "))])"
        } else {
            data = Enforce.getConsent(for: trimmed)
            label = "getConsent(\"\(trimmed)\")"
        }

        let message = "\(label): \(Self.format(data))"
        getConsentResult = ActionResult(message: message, style: .info)
        log(message)
    }

    func setConsent(_ input: String) {
        let dict = Self.parseConsentInput(input)
        guard !dict.isEmpty else {
            setConsentResult = ActionResult(message: "Invalid input. Use e.g. Analytics:true, Marketing:false", style: .error)
            log("setConsent() invalid input: \"\(input)\"")
            return
        }
        log("setConsent(\(Self.format(dict)))")
        Enforce.setConsent(dict)
        setConsentResult = ActionResult(message: "setConsent() complete: \(Self.format(dict))", style: .success)
        log("setConsent() complete: \(Self.format(dict))")
    }

    func showBanner() {
        log("showBanner()")
        Enforce.showBanner()
    }

    func showModal() {
        log("showModal()")
        Enforce.showModal()
    }

    func clearConsent() {
        log("clearConsent() started")
        Task {
            await Enforce.clearConsent()
            log("clearConsent() complete")
        }
    }

    /// Shows a compact inline summary and appends the full configuration
    /// dump to the on-screen log.
    func getConfiguration() {
        guard let configuration = Enforce.getConfiguration() else {
            configurationResult = ActionResult(
                message: "getConfiguration() returned nil; configure() has not finished fetching yet",
                style: .error
            )
            log("getConfiguration(): nil (fetch not finished)")
            return
        }

        let categoryCount = configuration.translation.cookies?.count ?? 0
        configurationResult = ActionResult(
            message: "getConfiguration(): clientId \(configuration.clientId), version \(configuration.version), banner \(configuration.enablePrivacyNotice), modal \(configuration.enableConsentModal), \(categoryCount) categories. Full output in Log.",
            style: .info
        )
        log(Self.fullDump(configuration))
    }

    // MARK: - Helpers

    static func theme(for choice: SampleThemeChoice) -> EnforceTheme {
        switch choice {
        case .allFields: return sampleThemeJSON   // bundled enforce_theme.json, every field set
        case .cheq:      return cheqTheme         // cheq.ai brand styling
        case .defaults:  return EnforceTheme()    // empty theme; all light-mode defaults
        }
    }

    /// Parses "Analytics:true, Marketing:false" into [String: Bool].
    static func parseConsentInput(_ input: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for pair in input.split(separator: ",") {
            let components = pair.split(separator: ":").map { String($0).trimmingCharacters(in: .whitespaces) }
            if components.count == 2, let value = Bool(components[1]) {
                result[components[0]] = value
            }
        }
        return result
    }

    /// Multi-line dump of everything getConfiguration() returns.
    static func fullDump(_ configuration: EnforceConfiguration) -> String {
        func show(_ value: String?) -> String { value ?? "nil" }
        func show(_ value: Bool?) -> String { value.map(String.init) ?? "nil" }

        var lines: [String] = ["getConfiguration():"]
        lines.append("  clientId: \(configuration.clientId)")
        lines.append("  version: \(configuration.version)")
        lines.append("  enforcement: \(configuration.enforcement)")
        lines.append("  enablePrivacyNotice: \(configuration.enablePrivacyNotice)")
        lines.append("  enableConsentModal: \(configuration.enableConsentModal)")

        let t = configuration.translation
        lines.append("  translation:")
        lines.append("    notificationBannerContent: \(show(t.notificationBannerContent))")
        lines.append("    notificationBannerAllowAll: \(show(t.notificationBannerAllowAll))")
        lines.append("    notificationBannerDenyAll: \(show(t.notificationBannerDenyAll))")
        lines.append("    notificationBannerPreferences: \(show(t.notificationBannerPreferences))")
        lines.append("    consentTitle: \(show(t.consentTitle))")
        lines.append("    consentDescription: \(show(t.consentDescription))")
        lines.append("    consentModalAllowAll: \(show(t.consentModalAllowAll))")
        lines.append("    consentModalDenyAll: \(show(t.consentModalDenyAll))")
        lines.append("    save: \(show(t.save)), cancel: \(show(t.cancel)), close: \(show(t.close))")
        if let cookies = t.cookies, !cookies.isEmpty {
            lines.append("    cookies:")
            for (key, details) in cookies.sorted(by: { $0.key < $1.key }) {
                lines.append("      \(key): title=\(show(details.title)), description=\(show(details.description))")
            }
        } else {
            lines.append("    cookies: nil")
        }

        if let banner = configuration.bannerConfig {
            lines.append("  bannerConfig: acceptAll=\(show(banner.ensAcceptAll)), rejectAll=\(show(banner.ensRejectAll)), openModal=\(show(banner.ensOpenModal)), closeBanner=\(show(banner.ensCloseBanner))")
        } else {
            lines.append("  bannerConfig: nil")
        }

        if let modal = configuration.consentModalConfig {
            lines.append("  consentModalConfig: acceptAll=\(show(modal.ensConsentAcceptAll)), rejectAll=\(show(modal.ensConsentRejectAll)), save=\(show(modal.ensSaveModal)), close=\(show(modal.ensCloseModal))")
        } else {
            lines.append("  consentModalConfig: nil")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Sample themes

    /// EnforceTheme matching the cheq.ai brand: magenta (#FE0072) primary actions,
    /// deep purple (#34163E) text, light lavender surfaces, Avenir Next
    /// (iOS's closest match to the brand's Avenir Next LT Pro), pill buttons,
    /// and the CheqLogo asset.
    static let cheqTheme = EnforceTheme(
        banner: EnforceTheme.Banner(
            logoImage: "CheqLogo",
            logoAlignment: .left,
            backgroundColor: "#FFFFFF",
            separatorColor: "#D7D5E1",
            overlayColor: "#34163E80",
            summary: EnforceTheme.Summary(
                description: EnforceTheme.TextStyle(fontName: "AvenirNext-Regular", fontSize: 15, textAlignment: .left, textColor: "#34163E")
            ),
            buttons: EnforceTheme.BannerButtons(
                acceptAll: EnforceTheme.ButtonStyle(backgroundColor: "#FE0072", fontName: "AvenirNext-DemiBold", textColor: "#FFFFFF"),
                rejectAll: EnforceTheme.ButtonStyle(backgroundColor: "#FE0072", fontName: "AvenirNext-DemiBold", textColor: "#FFFFFF"),
                close: EnforceTheme.ButtonStyle(backgroundColor: "#00000000", textColor: "#FE0072"),
                global: EnforceTheme.ButtonStyle(backgroundColor: "#EEF1FA", fontName: "AvenirNext-Medium", fontSize: 16, textColor: "#34163E", borderRadius: 22)
            )
        ),
        modal: EnforceTheme.Modal(
            logoImage: "CheqLogo",
            logoAlignment: .center,
            backgroundColor: "#FFFFFF",
            separatorColor: "#D7D5E1",
            overlayColor: "#34163E80",
            summary: EnforceTheme.Summary(
                title: EnforceTheme.TextStyle(fontName: "AvenirNext-Bold", fontSize: 18, textColor: "#34163E"),
                description: EnforceTheme.TextStyle(fontName: "AvenirNext-Regular", fontSize: 14, textColor: "#34163E")
            ),
            buttons: EnforceTheme.ModalButtons(
                acceptAll: EnforceTheme.ButtonStyle(backgroundColor: "#FE0072", fontName: "AvenirNext-DemiBold", textColor: "#FFFFFF"),
                rejectAll: EnforceTheme.ButtonStyle(backgroundColor: "#FE0072", fontName: "AvenirNext-DemiBold", textColor: "#FFFFFF"),
                close: EnforceTheme.ButtonStyle(backgroundColor: "#00000000", textColor: "#FE0072"),
                global: EnforceTheme.ButtonStyle(backgroundColor: "#EEF1FA", fontName: "AvenirNext-Medium", fontSize: 16, textColor: "#34163E", borderRadius: 22)
            ),
            categories: EnforceTheme.Categories(
                toggleOnColor: "#FE0072",
                toggleOffColor: "#D7D5E1",
                title: EnforceTheme.TextStyle(fontName: "AvenirNext-DemiBold", fontSize: 16, textColor: "#34163E"),
                description: EnforceTheme.TextStyle(fontName: "AvenirNext-Regular", fontSize: 13, textColor: "#4C2766")
            )
        )
    )

    /// Loaded from the bundled `enforce_theme.json` file; the recommended way
    /// to supply a theme, using the shared cross-SDK JSON shape. Uses
    /// deliberately different colors (green primary, amber secondaries, red
    /// toggles) so it's obvious which theme is active.
    /// Note: a programmatic `logoUIImage` can't come from JSON, so this
    /// variant has no logo; which also demonstrates omitted-key fallback.
    static let sampleThemeJSON: EnforceTheme = {
        do {
            return try EnforceTheme(bundleFile: "enforce_theme")
        } catch {
            osLog.error("Failed to load bundled theme: \(error, privacy: .public)")
            return EnforceTheme()
        }
    }()
}
