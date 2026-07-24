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
            
            // Beacon on load (fires once, for both banner styles)
            report(flags: ["BANNER_LOADED": true], config: config)

            if let theme = config.theme {
                // Themed bottom-sheet banner. Themed UI is light-mode based.
                if config.appearance != .default {
                    log.info("Theme provided; ignoring 'appearance' setting; themed UI uses light mode.")
                }
                Task {
                    let logo = await ThemeLogoLoader.load(
                        uiImage: theme.banner?.logoUIImage,
                        assetName: theme.banner?.logoImage,
                        urlString: theme.banner?.logoURL
                    )
                    await MainActor.run {
                        let banner = CustomBannerViewController(
                            translation: translation,
                            bannerConfig: bannerConfig,
                            consentModalConfig: consentModalConfig,
                            config: config,
                            logo: logo
                        )
                        Enforce.currentBanner = banner
                        // No system transition; the banner animates its own
                        // overlay fade + slide-up in viewDidAppear.
                        rootVC.present(banner, animated: false)
                    }
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

            Enforce.currentBanner = alert
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

        // Precompute all-true and all-false consent maps
        let allTrueFlags  = acceptAllFlags(translation)
        let allFalseFlags = rejectAllFlags(translation)
        
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
        
        // Close Banner: the flags are resolved when the button is tapped so
        // consent given via other buttons in the meantime is respected.
        if bannerConfig.ensCloseBanner?.show == true {
            let action = UIAlertAction(title: translation.close ?? "", style: .cancel) { _ in
                log.info("Close selected")
                if let flags = closeFlags(translation, config: config) {
                    Enforce.setConsent(flags, beaconExtras: ["BANNER_VIEWED": true])
                } else {
                    // Consent already stored: keep it and simply dismiss
                    report(flags: ["BANNER_VIEWED": true], config: config)
                }
            }
            alert.addAction(action)
        }

        return alert
    }

    // MARK: - Helpers

    /// Consent map with every cookie category set to `true`.
    static func acceptAllFlags(_ translation: Translation) -> [String: Bool] {
        translation.cookies?.mapValues { _ in true } ?? [:]
    }

    /// Consent map with every cookie category set to `false`.
    static func rejectAllFlags(_ translation: Translation) -> [String: Bool] {
        translation.cookies?.mapValues { _ in false } ?? [:]
    }

    /// Consent map for the Close action, or nil when consent is already
    /// stored; Close then keeps the existing consent and simply dismisses.
    /// With no stored consent it records `defaultConsent` if provided,
    /// otherwise all-false.
    static func closeFlags(_ translation: Translation, config: Config) -> [String: Bool]? {
        guard ConsentStore.getAll().isEmpty else { return nil }
        return (config.defaultConsent?.isEmpty == false) ? config.defaultConsent! : rejectAllFlags(translation)
    }

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
    static func report(flags: [String: Bool], config: Config) {
        guard let resp = Enforce.lastResponse else { return }
        Task { await ConsentReporting.send(config: config, type: .consent, clientId: resp.clientId, version: resp.version, enforcement: resp.enforcement, cookieFlags: flags) }
    }
}
