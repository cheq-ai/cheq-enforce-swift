//
//  ContentView.swift
//  SwiftUIExample
//
//  Created by Connor Parfitt on 1/16/25.
//

import SwiftUI
import CheqEnforce
import os

private let log = Logger(subsystem: "Cheq", category: "CheqEnforce")

struct ContentView: View {
    @State private var checkConsentInput: String = ""
    @State private var getConsentInput: String = ""
    @State private var setConsentInput: String = ""
    @State private var environmentInput: String = ""
    
    var body: some View {
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
            Button("Show Banner") { showBanner() }
            Button("Show Modal") { showModal() }
            
        }
        .buttonStyle(CustomButtonStyle())
        .padding()
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

#Preview {
    ContentView()
}
