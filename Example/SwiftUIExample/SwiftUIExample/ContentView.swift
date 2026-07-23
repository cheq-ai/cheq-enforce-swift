import SwiftUI
import CheqEnforce

struct ContentView: View {
    @Environment(SampleAppModel.self) private var model

    @State private var checkConsentInput: String = ""
    @State private var getConsentInput: String = ""
    @State private var setConsentInput: String = ""
    @State private var environmentInput: String = ""
    @State private var useCustomTheme: Bool = false
    @State private var themeChoice: SampleThemeChoice = .allFields

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                consentStateCard
                actionsCard
                logCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Consent State card

    private var consentStateCard: some View {
        Card(title: "Consent State") {
            if model.consent.isEmpty {
                Text("No consent stored")
                    .foregroundColor(.secondary)
            } else {
                ForEach(model.consent.sorted(by: { $0.key < $1.key }), id: \.key) { category, allowed in
                    HStack {
                        Text(category)
                        Spacer()
                        ConsentBadge(allowed: allowed)
                    }
                }
            }
        }
    }

    // MARK: - Actions card

    private var actionsCard: some View {
        Card(title: "Actions") {
            Button("Show Banner") { model.showBanner() }
            Button("Show Modal") { model.showModal() }

            // Toggling reconfigures Enforce with/without a sample theme.
            // Themed = custom bottom-sheet banner; unthemed = system alert banner.
            Toggle("Use Custom Theme", isOn: $useCustomTheme)
                .onChange(of: useCustomTheme) { _, _ in
                    model.configure(themed: useCustomTheme, choice: themeChoice)
                }

            if useCustomTheme {
                Picker("Theme", selection: $themeChoice) {
                    ForEach(SampleThemeChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: themeChoice) { _, _ in
                    model.configure(themed: useCustomTheme, choice: themeChoice)
                }
            }

            fieldLabel("Environment")
            TextField("Enter environment name", text: $environmentInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Set Environment") { model.setEnvironment(environmentInput) }
            ResultText(result: model.environmentResult)
            Button("Get Environment") { model.getEnvironment() }
            ResultText(result: model.getEnvironmentResult)
            Button("Reset Environment") { model.resetEnvironment() }

            fieldLabel("Check Consent")
            TextField("Enter category for Check Consent", text: $checkConsentInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Check Consent") { model.checkConsent(checkConsentInput) }
            ResultText(result: model.checkConsentResult)

            fieldLabel("Get Consent")
            TextField("Enter category (empty for all)", text: $getConsentInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Get Consent") { model.getConsent(getConsentInput) }
            ResultText(result: model.getConsentResult)

            fieldLabel("Set Consent")
            TextField("Enter consent (e.g., Analytics:true, Marketing:false)", text: $setConsentInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Set Consent") { model.setConsent(setConsentInput) }
            ResultText(result: model.setConsentResult)

            Button("Get Configuration") { model.getConfiguration() }
            ResultText(result: model.configurationResult)

            Button("Clear Consent") { model.clearConsent() }
                .buttonStyle(ClearButtonStyle())
        }
        .buttonStyle(CustomButtonStyle())
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Log card

    private var logCard: some View {
        Card(title: "Log") {
            if model.logEntries.isEmpty {
                Text("No activity yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(model.logEntries) { entry in
                    Text("[\(entry.timestamp)] \(entry.message)")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Reusable views

/// Rounded-rect grouped card with a headline title, matching the React
/// sample app's layout.
private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

/// Green "Allowed" / red "Denied" capsule badge for one consent category.
private struct ConsentBadge: View {
    let allowed: Bool

    var body: some View {
        Text(allowed ? "Allowed" : "Denied")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background((allowed ? Color.green : Color.red).opacity(0.15))
            .foregroundColor(allowed ? .green : .red)
            .clipShape(Capsule())
    }
}

/// Inline action result rendered under a button: green for success, red
/// for errors, secondary for informational output.
private struct ResultText: View {
    let result: SampleAppModel.ActionResult?

    var body: some View {
        if let result {
            Text(result.message)
                .font(.footnote)
                .foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var color: Color {
        switch result?.style {
        case .success: return .green
        case .error:   return .red
        case .info, .none: return .secondary
        }
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
        .environment(SampleAppModel())
}
