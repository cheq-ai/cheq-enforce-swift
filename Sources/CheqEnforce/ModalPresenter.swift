import UIKit
import os

private let log = Logger(subsystem: "Cheq", category: "ModalPresenter")

/// Responsible for constructing and presenting the consent modal UI
struct ModalPresenter {
    /// Finds the active root view controller and presents the consent modal
    static func show(
        translation: Translation,
        consentModalConfig: ConsentModalConfig,
        config: Config,
        delay: TimeInterval = 0
    ) {
        let work = {
            // Scene & root view controller lookup
            guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                  let rootVC = windowScene.windows
                .first(where: { $0.isKeyWindow })?
                .rootViewController
            else {
                log.error("Cannot present modal: no active scene or rootViewController.")
                Task {
                    _ = await ErrorReporting.sendError(msg: "Cannot present modal: no active scene or rootViewController.", fn: #function, config: config)
                }
                return
            }
            
            log.info("Presenting consent modal")
            
            let sections: [(title: String, description: String)] =
            (translation.cookies ?? [:])
                .sorted { $0.key < $1.key }
                .compactMap { (_, details) in
                    guard let title = details.title,
                          let desc  = details.description
                    else { return nil }
                    return (title: title, description: desc)
                }
            
            // Ensure modal title & description exist
            guard let consentTitle = translation.consentTitle,
                  let consentDescription = translation.consentDescription else {
                log.error("Missing translation data for modal. Cannot present.")
                Task {
                    _ = await ErrorReporting.sendError(msg: "Missing translation data for modal. Cannot present.", fn: #function, config: config)
                }
                return
            }
            
            // Optional button titles
            let allowAllTitle = translation.consentModalAllowAll ?? ""
            let denyAllTitle  = translation.consentModalDenyAll ?? ""
            let saveTitle      = translation.save ?? ""
            let cancelTitle    = translation.cancel ?? ""
            
            // Instantiate and present
            let modal = CustomConsentModalViewController(
                title: consentTitle,
                description: consentDescription,
                modalConfig: consentModalConfig,
                sections: sections,
                config: config,
                allowAllTitle: allowAllTitle,
                denyAllTitle: denyAllTitle,
                saveTitle: saveTitle,
                cancelTitle: cancelTitle
            )
            rootVC.present(modal, animated: true, completion: nil)
        }
        
        if delay > 0 {
          DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
          DispatchQueue.main.async(execute: work)
        }
    }
}
