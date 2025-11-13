//
//  CheqEnforce.swift
//  CheqEnforce
//
//  Created by Connor Parfitt on 17/01/2025.
//

import os
import Foundation
import UIKit

public class Enforce {
    static internal let log = Logger(subsystem: "Cheq", category: "CheqEnforce")
    private static var storedConfig: Config?
    private static weak var currentBanner: UIAlertController?
    
    /// signature for consent-change callbacks
    public typealias ConsentChangeHandler = ([String: Bool]) -> Void

    /// all user-registered onConsent() closures
    private static var consentHandlers: [ConsentChangeHandler] = []

    /// register a callback to run *every* time consent is updated
    /// - Parameter handler: receives the *current* full consent dictionary
    public static func onConsent(_ handler: @escaping ConsentChangeHandler) {
        consentHandlers.append(handler)
    }
    
    #if DEBUG
    /// Clears all registered onConsent handlers. Only for tests.
    internal static func _resetConsentHandlers() {
        consentHandlers.removeAll()
    }
    #endif
    
    static var lastResponse: JSONResponse?
    
    static var  cachedInstanceId: String = {
        return randomBase36InstanceId()
    }()
    static var beaconCount: Int = 0
    static var storedCookieFlags: [String: Bool] = [:]
    
    let config:Config
    init(config: Config) {
        self.config = config
    }
    
    /// Configure the SDK with your client-name, paths, environment, and defaults.
    ///
    /// After calling this, Enforce will:
    ///  1. send a “reporting” beacon,
    ///  2. check stored consent (and skip UI if still valid),
    ///  3. if no consent, fetch translations JSON and show the banner or modal.
    ///
    /// - Parameter config: your `Config` object (clientName, publishPath, environment, etc.)
    public static func configure(_ config: Config) {
        //Build environment.json URL from configuration values
        guard let url = TranslationService.buildURL(config: config) else { return }
        log.info("URL to retrieve translations: \(url)")
        
        // Store the config for later use
        storedConfig = config
        
        //Trigger consent callbacks
        let latest = getConsent()
        for handler in consentHandlers {
            handler(latest)
        }
        
        //Get translations and show banner or modal
        Task {
            do {
                let jsonData = try await TranslationService.fetchJSON(from: url, debug: config.debug)
                let jsonResponse = try JSONDecoder().decode(JSONResponse.self, from: jsonData)
                Self.lastResponse = jsonResponse
                log.info("Successfully decoded JSON file")
                
                //Send Load beacon
                guard let resp = lastResponse else { return }
                Task {
                    await ConsentReporting.send(config: config, type: .billing, clientId: resp.clientId, version: resp.version, enforcement: resp.enforcement)
                }
                
                //If consent is found already (same version and within date), trigger onConsent and do nothing further
                if let saved = ConsentStore.loadValid(currentVersion: config.version) {
                    log.info("Saved consent found: \(saved). No need to show the banner.")
                    
                    //Trigger consent callbacks
                    let latest = getConsent()
                    for handler in consentHandlers {
                        handler(latest)
                    }
                    
                    return
                }
                
                // If autoShow is false, do nothing further
                guard config.autoShow else {
                    log.info("autoShow is false; skipping initial UI display.")
                    return
                }
                
                //Show banner or modal
                if jsonResponse.enablePrivacyNotice {
                    guard let bannerConfig = jsonResponse.bannerConfig else {
                        log.error("Cannot show banner: Banner on but no banner config found")
                        Task {
                            _ = await ErrorReporting.sendError(msg: "Cannot show banner: Banner on but no banner config found", fn: #function, clientId: resp.clientId, config: config)
                        }
                        return
                    }
                    BannerPresenter.show(
                        translation: jsonResponse.translation,
                        bannerConfig: bannerConfig,
                        consentModalConfig: jsonResponse.consentModalConfig ?? ConsentModalConfig(ensConsentAcceptAll: nil, ensConsentRejectAll: nil, ensSaveModal: nil, ensCloseModal: nil),
                        config: config,
                        delay: 1.0
                    )
                } else if jsonResponse.enableConsentModal {
                    log.info("No Banner found. Opening Modal")
                    ModalPresenter.show(
                        translation: jsonResponse.translation,
                        consentModalConfig: jsonResponse.consentModalConfig ?? ConsentModalConfig(ensConsentAcceptAll: nil, ensConsentRejectAll: nil, ensSaveModal: nil, ensCloseModal: nil),
                        config: config,
                        delay: 1.0
                    )

                } else {
                    log.error("No translations available: neither banner content nor consent description found.")
                }
                
            } catch {
                log.error("Failed to fetch or decode JSON: \(error.localizedDescription, privacy: .public)")
                Task {
                    _ = await ErrorReporting.sendError(msg: "Failed to fetch or decode JSON", fn: #function, config: config)
                }
            }
        }
    }
    
    ///
    /// - Parameter category: the consent key, e.g. `"Analytics"`.
    /// - Returns: `true` if stored consent for that category is `true`, else `false`.
    public static func checkConsent(_ category: String) -> Bool {
        return ConsentStore.get(category)
    }
    
    /// Retrieve the full stored consent dictionary.
    ///
    /// - Returns: a `[String: Bool]` mapping each category to its consent value.
    public static func getConsent() -> [String: Bool] {
        return ConsentStore.getAll()
    }
    
    // Retrieve stored consent for exactly one key.
    ///
    /// - Parameter key: the consent key, e.g. `"Marketing"`.
    /// - Returns: a single-entry dictionary `[key: value]`.
    public static func getConsent(for key: String) -> [String: Bool] {
        let allowed = ConsentStore.get(key)
        return [ key: allowed ]
    }
    
    /// Retrieve stored consent for multiple keys.
    ///
    /// - Parameter keys: an array of keys, e.g. `["Analytics","Functional"]`.
    /// - Returns: a `[String: Bool]` mapping each requested key to its stored value.
    public static func getConsent(for keys: [String]) -> [String: Bool] {
        return ConsentStore.get(keys)
    }
    
    /// Overwrite (or merge) one or more consent categories.
    ///
    /// - Parameter consent: a `[String:Bool]` of the categories & values to set.
    ///   e.g. `["Analytics":true, "Marketing":false]`.
    public static func setConsent(_ consent: [String: Bool]) {
        setConsent(consent, beaconExtras: [:]) // funnel to internal
    }
    
    internal static func setConsent(_ consent: [String: Bool], beaconExtras: [String: Bool] = [:]) {
        log.info("Setting provided consent: \(consent).")
        
        guard let currentConfig = storedConfig else {
            log.error("Config not found. Ensure `configure` was called first.")
            return
        }
        
        ConsentStore.save(
            consent,
            version: currentConfig.version,
            expirationMilliseconds: currentConfig.dataRetentionPeriod
        )
        
        //Trigger consent callbacks
        let latest = getConsent()
        for handler in consentHandlers {
            handler(latest)
        }
        
        guard let resp = Enforce.lastResponse else { return }
        var reportFlags = consent
        for (k, v) in beaconExtras { reportFlags[k] = v }
        Task { await ConsentReporting.send(config: currentConfig, type: .consent, clientId: resp.clientId, version: resp.version, enforcement: resp.enforcement, cookieFlags: reportFlags) }
    }
    
    ///Change the environment string (you must call `configure` first).
    ///
    /// - Parameter environment: the new `environment` value.
    /// - Throws: `URLError` or `DecodingError` if the JSON at the new URL can’t be fetched/parsed.
    public static func setEnvironment(_ environment: String) async throws {
        guard let currentConfig = storedConfig else {
            log.error("Config not found. Ensure `configure` was called first.")
            return
        }
        
        // Create a new Config instance with the updated environment
        let updatedConfig = Config(
            currentConfig.clientName,
            publishPath: currentConfig.publishPath,
            environment: environment, // Update environment here
            debug: currentConfig.debug,
            dataRetentionPeriod: currentConfig.dataRetentionPeriod,
            autoShow: currentConfig.autoShow,
            version: currentConfig.version,
            defaultConsent: currentConfig.defaultConsent,
            appearance: currentConfig.appearance
        )
        
        guard let resp = Enforce.lastResponse else { return }
        
        // construct the URL
        guard let url = TranslationService.buildURL(config: updatedConfig) else {
            log.error("Invalid environment string: \(environment, privacy: .public)")
            Task {
                _ = await ErrorReporting.sendError(msg: "Invalid environment string", fn: #function, clientId: resp.clientId, config: currentConfig)
            }
            return
        }
        
        do {
            // try to fetch & parse the JSON — this validates that the env really exists
            let data = try await TranslationService.fetchJSON(from: url, debug: currentConfig.debug)
            _ = try JSONDecoder().decode(JSONResponse.self, from: data)
            
            // Successfully fetched. Store new config
            storedConfig = updatedConfig
            log.info("Environment updated to: \(environment, privacy: .public)")
        } catch {
            // fetch or decode failed — roll back
            log.error("Environment ‘\(environment)’ isn’t valid, keeping previous “\(currentConfig.environment)” — error: \(error.localizedDescription, privacy: .public)")
            Task {
                _ = await ErrorReporting.sendError(msg: "Environment ‘\(environment)’ isn’t valid, keeping previous", fn: #function, clientId: resp.clientId, config: currentConfig)
            }
            throw error
        }
    }
    
    /// Immediately fetch & show the banner (for manual control).
    public static func showBanner() {
        guard let cfg = storedConfig,
              let url = TranslationService.buildURL(config: cfg)
        else {
            log.error("Enforce not configured.")
            return
        }
        
        Task {
            let data     = try await TranslationService.fetchJSON(from: url, debug: cfg.debug)
            let response = try JSONDecoder().decode(JSONResponse.self, from: data)
            
            if response.enablePrivacyNotice {
                guard let bannerConfig = response.bannerConfig else {
                    log.error("Cannot show banner: Banner on but no banner config found")
                    Task {
                        _ = await ErrorReporting.sendError(msg: "Cannot show banner: Banner on but no banner config found", fn: #function, clientId: response.clientId, config: cfg)
                    }
                    return
                }
                BannerPresenter.show(
                    translation:           response.translation,
                    bannerConfig:          bannerConfig,
                    consentModalConfig:    response.consentModalConfig ?? .init(ensConsentAcceptAll: nil, ensConsentRejectAll: nil, ensSaveModal: nil, ensCloseModal: nil),
                    config: cfg
                )
            } else {
                log.info("Banner not turned on. Skipping showing banner.")
            }
        }
    }
    
    /// Immediately fetch & show the modal (for manual control).
    public static func showModal() {
        guard let cfg = storedConfig,
              let url = TranslationService.buildURL(config: cfg)
        else {
            log.error("Enforce not configured.")
            return
        }
        
        Task {
            let data     = try await TranslationService.fetchJSON(from: url, debug: cfg.debug)
            let response = try JSONDecoder().decode(JSONResponse.self, from: data)
            
            if response.enableConsentModal {
                guard let modalConfig = response.consentModalConfig else {
                    log.error("Cannot show Modal: Modal on but no Modal config found")
                    Task {
                        _ = await ErrorReporting.sendError(msg: "Cannot show Modal: Modal on but no Modal config found", fn: #function, clientId: response.clientId, config: cfg)
                    }
                    return
                }
                ModalPresenter.show(
                    translation:           response.translation,
                    consentModalConfig:    modalConfig,
                    config:                cfg
                )
            } else {
                log.info("Modal not turned on. Skipping showing Modal.")
            }
        }
    }
    
    // MARK: - internal
    
    /// Generate a random base-36 ID for this session.
    private static func randomBase36InstanceId() -> String {
        let randomDouble = Double.random(in: 1..<2)
        let number = Int(268_435_456 * randomDouble)
        return String(number, radix: 36)
    }
}
