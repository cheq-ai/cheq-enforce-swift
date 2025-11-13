import UIKit
import os

private let log = Logger(subsystem: "Cheq", category: "BannerPresenter")

/// Responsible for constructing and presenting the consent banner UI
struct BannerPresenter {
    /// Builds and shows the banner after a short delay, including scene lookup.
    static func show(
        translation: Translation,
        bannerConfig: BannerConfig,
        consentModalConfig: ConsentModalConfig,
        config: Config,
        delay: TimeInterval = 0
    ) {
        // Delay and present on the active window's root view controller
        let work = {
            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                let rootVC = windowScene.windows
                    .first(where: { $0.isKeyWindow })?
                    .rootViewController
            else {
                log.error("Cannot present banner: no active scene or rootViewController.")
                Task {
                    _ = await ErrorReporting.sendError(msg: "Cannot present banner: no active scene or rootViewController.", fn: #function, config: config)
                }
                return
            }
            
            let alert = makeAlert(
                translation: translation,
                bannerConfig: bannerConfig,
                consentModalConfig: consentModalConfig,
                config: config,
                rootVC: rootVC
            )
            
            switch config.appearance {
            case .light:
                alert.overrideUserInterfaceStyle = .light
            case .dark:
                alert.overrideUserInterfaceStyle = .dark
            case .default:
                alert.overrideUserInterfaceStyle = .unspecified
            }
            
            rootVC.present(alert, animated: true)
        }
        
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
    
    /// Creates the UIAlertController for the banner, wiring up all actions
    static func makeAlert(
        translation: Translation,
        bannerConfig: BannerConfig,
        consentModalConfig: ConsentModalConfig,
        config: Config,
        rootVC: UIViewController
    ) -> UIAlertController {
        log.info("Creating banner alert")
        let alert = UIAlertController(
            title: nil,
            message: translation.notificationBannerContent,
            preferredStyle: .alert
        )
        
        // Beacon on load
        report(flags: ["BANNER_LOADED": true], config: config)
        
        // Precompute all-true and all-false consent maps
        let allTrueFlags  = translation.cookies?.mapValues { _ in true }  ?? [:]
        let allFalseFlags = translation.cookies?.mapValues { _ in false } ?? [:]
        
        // Accept All
        if bannerConfig.ensAcceptAll?.show == true {
            addAction(
                to: alert,
                title: translation.notificationBannerAllowAll ?? "",
                style: .default,
                flags: allTrueFlags,
                config: config
            )
        }
        
        // Reject All
        if bannerConfig.ensRejectAll?.show == true {
            addAction(
                to: alert,
                title: translation.notificationBannerDenyAll ?? "",
                style: .default,
                flags: allFalseFlags,
                config: config
            )
        }
        
        // Preferences
        if bannerConfig.ensOpenModal?.show == true {
            let action = UIAlertAction(
                title: translation.notificationBannerPreferences,
                style: .default
            ) { _ in
                log.info("Preferences selected")
                // show modal
                ModalPresenter.show(
                    translation: translation,
                    consentModalConfig: consentModalConfig,
                    config: config
                )
                report(flags: ["BANNER_VIEWED": true], config: config)
            }
            alert.addAction(action)
        }
        
        // Close Banner
        if bannerConfig.ensCloseBanner?.show == true {
            // If defaultConsent exists, use that; otherwise fallback to all-false
            let baseFlags = (config.defaultConsent?.isEmpty == false) ? (config.defaultConsent!) : allFalseFlags
            addAction(
                to: alert,
                title: translation.close ?? "",
                style: .cancel,
                flags: baseFlags,
                config: config
            )
        }
        
        return alert
    }
    
    // MARK: - Helpers
    
    /// Adds a button to the alert that saves flags and sends a beacon including "BANNER_VIEWED".
    private static func addAction(
        to alert: UIAlertController,
        title: String,
        style: UIAlertAction.Style,
        flags: [String: Bool],
        config: Config
    ) {
        let action = UIAlertAction(title: title, style: style) { _ in
            log.info("\(title) selected")
            Enforce.setConsent(flags, beaconExtras: ["BANNER_VIEWED": true])
        }
        alert.addAction(action)
    }
    
    /// Encodes and sends the consent-reporting beacon for the given flags.
    private static func report(flags: [String: Bool], config: Config) {
        guard let resp = Enforce.lastResponse else { return }
        Task { await ConsentReporting.send(config: config, type: .consent, clientId: resp.clientId, version: resp.version, enforcement: resp.enforcement, cookieFlags: flags) }
    }
}
