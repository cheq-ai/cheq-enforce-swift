import SwiftUI
import UIKit
import CheqEnforce
import os

private let log = Logger(subsystem: "Cheq", category: "CheqEnforce")

struct ContentView: View {
    @State private var checkConsentInput: String = ""
    @State private var getConsentInput: String = ""
    @State private var setConsentInput: String = ""
    @State private var environmentInput: String = ""
    @State private var useCustomTheme: Bool = false
    @State private var themeChoice: SampleThemeChoice = .allFields
    /// The environment currently applied to the SDK. Must be passed through
    /// when reconfiguring, otherwise configure() would revert an environment
    /// previously changed via setEnvironment().
    @State private var currentEnvironment: String = "English"

    /// The selectable sample themes when "Use Custom EnforceTheme" is on.
    enum SampleThemeChoice: String, CaseIterable, Identifiable {
        case allFields = "All Fields"
        case cheq = "Cheq Brand"
        case defaults = "All Defaults"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 20) { // Adds spacing between elements
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            
            // Input field for Check Consent
            TextField("Enter category for Check Consent", text: $checkConsentInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button("Check Consent") { checkConsent() }
            
            // Input field for Get Consent
            TextField("Enter category for Get Consent", text: $getConsentInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button("Get Consent") { getConsent() }
            
            // Set Consent Input Field
            TextField("Enter consent (e.g., Analytics:true, Marketing:false)", text: $setConsentInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button("Set Consent") { setConsent() }
            
            // Input field for Set Environment
            TextField("Enter environment name", text: $environmentInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button("Set Environment") { setEnvironment() }

            // Toggling reconfigures Enforce with/without a sample theme.
            // Themed → custom bottom-sheet banner; unthemed → system alert banner.
            Toggle("Use Custom Theme", isOn: $useCustomTheme)
                .padding(.horizontal)
                .onChange(of: useCustomTheme) { _, _ in
                    reconfigure()
                }

            if useCustomTheme {
                Picker("Theme", selection: $themeChoice) {
                    ForEach(SampleThemeChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .onChange(of: themeChoice) { _, _ in
                    reconfigure()
                }
            }

            Button("Show Banner") { showBanner() }
            Button("Show Modal") { showModal() }
            Button("Get Configuration") { getConfiguration() }
            Button("Clear Consent") { clearConsent() }
                .buttonStyle(ClearButtonStyle())

        }
        .buttonStyle(CustomButtonStyle())
        .padding()
        }
    }
    
    // MARK: - Button Actions
    func checkConsent() {
        log.info("Check Consent tapped - checking: \(checkConsentInput)")
        log.info("Consent check result: \(Enforce.checkConsent(checkConsentInput))")
    }

    func getConsent() {
        log.info("Get Consent tapped")

        let trimmed = getConsentInput.trimmingCharacters(in: .whitespacesAndNewlines)

        let consentData: [String: Bool]
        if trimmed.isEmpty {
            consentData = Enforce.getConsent()
        } else if trimmed.contains(",") {
            let keys = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            consentData = Enforce.getConsent(for: keys)
        } else {
            consentData = Enforce.getConsent(for: trimmed)
        }

        log.info("Consent data: \(consentData, privacy: .public)")
    }

    func setConsent() {
        log.info("Set Consent tapped - input: \(setConsentInput, privacy: .public)")
        
        let consentDict = parseConsentInput(setConsentInput)
        
        if !consentDict.isEmpty {
            Enforce.setConsent(consentDict)
            log.info("Consent set: \(String(describing: consentDict), privacy: .public)")
        } else {
            log.warning("Invalid consent input format.")
        }
    }

    func setEnvironment() {
        log.info("Set Environment tapped - setting: \(environmentInput, privacy: .public)")
        Task {
          do {
            try await Enforce.setEnvironment(environmentInput)
            currentEnvironment = environmentInput
          } catch {
              log.warning("Couldn’t switch environment: \(error)")
          }
        }
    }

    func showBanner() {
        log.info("Show Banner tapped")
        Enforce.showBanner()
    }

    func showModal() {
        log.info("Show Modal tapped")
        Enforce.showModal()
    }

    func clearConsent() {
        log.info("Clear Consent tapped")
        Task {
            await Enforce.clearConsent()
        }
    }

    /// Logs everything getConfiguration() returns, or a warning if the
    /// remote fetch hasn't completed yet.
    func getConfiguration() {
        log.info("Get Configuration tapped")

        guard let configuration = Enforce.getConfiguration() else {
            log.warning("getConfiguration() returned nil; configure() has not finished fetching yet")
            return
        }

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

        log.info("\(lines.joined(separator: "\n"), privacy: .public)")
    }

    /// The theme for the current picker selection.
    var selectedTheme: EnforceTheme {
        switch themeChoice {
        case .allFields: return Self.sampleThemeJSON   // bundled enforce_theme.json, every field set
        case .cheq:      return Self.cheqTheme         // cheq.ai brand styling
        case .defaults:  return EnforceTheme()                // empty theme → all light-mode defaults
        }
    }

    /// Reconfigures Enforce with the selected sample theme (or none) so all
    /// banner styles can be exercised. autoShow is off so the UI only appears
    /// when Show Banner / Show Modal is tapped.
    func reconfigure() {
        log.info("Reconfiguring Enforce (custom theme: \(useCustomTheme), choice: \(themeChoice.rawValue, privacy: .public))")
        Enforce.configure(Config(
            "demoretail",
            publishPath: "mobile_privacy_sdk",
            environment: currentEnvironment,
            debug: true,
            dataRetentionPeriod: 60000,
            autoShow: false,
            version: "1",
            defaultConsent: ["Analytics": true, "Marketing": false, "Functional": true],
            theme: useCustomTheme ? selectedTheme : nil
        ))
    }

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

    /// Same idea as `sampleTheme`, but loaded from the bundled
    /// `enforce_theme.json` file; the recommended way to supply a theme,
    /// using the shared cross-SDK JSON shape. Uses deliberately different
    /// colors (green primary, amber secondaries, red toggles) so it's
    /// obvious which theme is active.
    /// Note: a programmatic `logoUIImage` can't come from JSON, so this
    /// variant has no logo; which also demonstrates omitted-key fallback.
    static let sampleThemeJSON: EnforceTheme = {
        do {
            return try EnforceTheme(bundleFile: "enforce_theme")
        } catch {
            log.error("Failed to load bundled theme: \(error, privacy: .public)")
            return EnforceTheme()
        }
    }()

    // Helper function to parse input into [String: Bool]
    func parseConsentInput(_ input: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        
        let pairs = input.split(separator: ",")
        for pair in pairs {
            let components = pair.split(separator: ":").map { String($0).trimmingCharacters(in: .whitespaces) }
            if components.count == 2, let value = Bool(components[1]) {
                result[components[0]] = value
            }
        }
        
        return result
    }
}

// Custom Button Style
struct CustomButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity) // Expands button width
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0) // Adds a press effect
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// Button style for the Clear Consent action: white background with a red border and text.
struct ClearButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity) // Expands button width
            .padding()
            .background(Color.white)
            .foregroundColor(.red)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.red, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0) // Adds a press effect
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
