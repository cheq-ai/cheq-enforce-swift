//
//  SwiftUIExampleApp.swift
//  SwiftUIExample
//
//  Created by Connor Parfitt on 1/16/25.
//

import SwiftUI
import CheqEnforce

@main
struct SwiftUIExampleApp: App {
    init(){
        Enforce.configure(Config("demoretail", publishPath: "mobile_privacy_sdk", environment: "English", debug: true, dataRetentionPeriod: 60000, autoShow: true, version: "1", defaultConsent: ["Analytics":true, "Marketing":false, "Functional":true], appearance: .default))
        
        let hasAnalytics = Enforce.checkConsent("Analytics")
        if hasAnalytics {
            print("checkConsent 1: hasAnalytics: \(hasAnalytics)")
        } else {
            print("checkConsent 1: noAnalytics: \(hasAnalytics)")
        }
        
        let hasMarketing = Enforce.checkConsent("Marketing")
        if hasMarketing {
            print("checkConsent 1: hasMarketing: \(hasMarketing)")
        } else {
            print("checkConsent 1: noMarketing: \(hasMarketing)")
        }
        
        let hasFunctional = Enforce.checkConsent("Functional")
        if hasFunctional {
            print("checkConsent 1: hasFunctional: \(hasFunctional)")
        } else {
            print("checkConsent 1: noFunctional: \(hasFunctional)")
        }
        
        Enforce.onConsent { consent in
            print("onConsent 1: \(consent)")
        }
        
        Enforce.onConsent { consent in
            print("onConsent 2: \(consent)")
        }
        
        Enforce.onConsent { consent in
            print("onConsent 3: \(consent)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
