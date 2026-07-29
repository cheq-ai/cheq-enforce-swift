import UIKit
import os

private let log = Logger(subsystem: "Cheq", category: "CustomBanner")

/// The themed consent banner, presented as a bottom sheet that slides up
/// from the bottom of the screen. Used instead of the `UIAlertController`
/// banner whenever an `EnforceTheme` is supplied in the configuration.
///
/// Behavior (button visibility, consent flags, beacons) matches the alert
/// banner exactly; only the presentation is different.
public class CustomBannerViewController: UIViewController {

    private let translation: Translation
    private let bannerConfig: BannerConfig
    private let consentModalConfig: ConsentModalConfig
    private let config: Config
    private let bannerTheme: EnforceTheme.Banner?
    private let logo: UIImage?

    private var containerView: UIView!
    private var hasAnimatedIn = false
    /// The resolved dimming color; the view starts clear and fades to this
    /// in the same animation as the sheet's slide-up.
    private var overlayColor: UIColor = ThemeDefaults.overlay

    internal init(
        translation: Translation,
        bannerConfig: BannerConfig,
        consentModalConfig: ConsentModalConfig,
        config: Config,
        logo: UIImage?
    ) {
        self.translation = translation
        self.bannerConfig = bannerConfig
        self.consentModalConfig = consentModalConfig
        self.config = config
        self.bannerTheme = config.theme?.banner
        self.logo = logo
        super.init(nibName: nil, bundle: nil)
        // Presented without a system transition; entry and exit are animated
        // manually so the overlay fade and sheet slide happen together.
        self.modalPresentationStyle = .overFullScreen
        // Themed UI is light-mode based; `appearance` is intentionally ignored.
        self.overrideUserInterfaceStyle = .light
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        // Fade the overlay in and slide the sheet up together
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            self.view.backgroundColor = self.overlayColor
            self.containerView.transform = .identity
        }
    }

    // MARK: - UI construction

    private func setupUI() {
        overlayColor = ThemeResolver.color(
            bannerTheme?.overlayColor,
            fallback: ThemeDefaults.overlay,
            token: "banner.overlayColor"
        )
        // Starts clear; viewDidAppear fades it to overlayColor alongside the slide-up
        view.backgroundColor = .clear

        // Bottom sheet container, pinned to the bottom edge with rounded top corners
        containerView = UIView()
        containerView.backgroundColor = ThemeResolver.color(
            bannerTheme?.backgroundColor,
            fallback: ThemeDefaults.background,
            token: "banner.backgroundColor"
        )
        containerView.layer.cornerRadius = 16
        containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Vertical content stack: logo, description, separator, buttons
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contentStack)

        if let logo {
            contentStack.addArrangedSubview(makeLogoView(logo))
        }

        let descriptionLabel = UILabel()
        descriptionLabel.text = translation.notificationBannerContent
        descriptionLabel.numberOfLines = 0
        ThemeResolver.textStyle(
            bannerTheme?.summary?.description,
            defaultSize: 14,
            defaultWeight: .regular,
            token: "banner.summary.description"
        ).apply(to: descriptionLabel)
        contentStack.addArrangedSubview(descriptionLabel)

        // Separator line between description and buttons, only when themed
        if let separatorHex = bannerTheme?.separatorColor, !separatorHex.isEmpty {
            let separator = UIView()
            separator.backgroundColor = ThemeResolver.color(
                separatorHex,
                fallback: .clear,
                token: "banner.separatorColor"
            )
            separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            contentStack.addArrangedSubview(separator)
        }

        // Buttons; each independently optional, driven by the remote
        // bannerConfig. Built in the default order, then arranged per the
        // theme's optional buttons.order.
        let globalStyle = bannerTheme?.buttons?.global
        var buttons: [(key: String, value: UIButton)] = []

        if bannerConfig.ensAcceptAll?.show == true {
            buttons.append(("acceptAll", makeButton(
                title: translation.notificationBannerAllowAll ?? "",
                style: ThemeResolver.buttonStyle(
                    bannerTheme?.buttons?.acceptAll,
                    global: globalStyle,
                    defaults: ThemeDefaults.primaryButton,
                    defaultFontWeight: .semibold,
                    token: "banner.buttons.acceptAll"
                ),
                action: #selector(acceptAllTapped)
            )))
        }

        if bannerConfig.ensRejectAll?.show == true {
            buttons.append(("rejectAll", makeButton(
                title: translation.notificationBannerDenyAll ?? "",
                style: ThemeResolver.buttonStyle(
                    bannerTheme?.buttons?.rejectAll,
                    global: globalStyle,
                    defaults: ThemeDefaults.secondaryButton,
                    token: "banner.buttons.rejectAll"
                ),
                action: #selector(rejectAllTapped)
            )))
        }

        if bannerConfig.ensOpenModal?.show == true {
            buttons.append(("openModal", makeButton(
                title: translation.notificationBannerPreferences ?? "",
                style: ThemeResolver.buttonStyle(
                    bannerTheme?.buttons?.openModal,
                    global: globalStyle,
                    defaults: ThemeDefaults.secondaryButton,
                    token: "banner.buttons.openModal"
                ),
                action: #selector(preferencesTapped)
            )))
        }

        if bannerConfig.ensCloseBanner?.show == true {
            buttons.append(("close", makeButton(
                title: translation.close ?? "",
                style: ThemeResolver.buttonStyle(
                    bannerTheme?.buttons?.close,
                    global: globalStyle,
                    defaults: ThemeDefaults.textOnlyButton,
                    token: "banner.buttons.close"
                ),
                action: #selector(closeTapped)
            )))
        }

        for button in ThemeResolver.orderedButtons(buttons, order: bannerTheme?.buttons?.order, token: "banner.buttons.order") {
            contentStack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        // Start off-screen; viewDidAppear animates it up
        containerView.transform = CGAffineTransform(translationX: 0, y: max(view.bounds.height, 600))
    }

    private func makeButton(title: String, style: ResolvedButtonStyle, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        style.apply(to: button)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    /// Wraps the logo in a container so it can be aligned left/center/right/full.
    private func makeLogoView(_ image: UIImage) -> UIView {
        let wrapper = UIView()
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(imageView)

        var constraints = [
            imageView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 40)
        ]

        // Preferred, not required: an over-wide logo (aspect width exceeding the
        // container) compresses to fit instead of conflicting with the edge
        // constraints and overflowing the sheet.
        let aspect = image.size.width / max(image.size.height, 1)
        let aspectConstraint = imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: aspect)
        aspectConstraint.priority = .defaultHigh

        switch bannerTheme?.logoAlignment ?? .center {
        case .left:
            constraints += [
                aspectConstraint,
                imageView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                imageView.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor)
            ]
        case .center:
            constraints += [
                aspectConstraint,
                imageView.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                imageView.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor)
            ]
        case .right:
            constraints += [
                aspectConstraint,
                imageView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                imageView.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor)
            ]
        case .full:
            constraints += [
                imageView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
            ]
        }
        NSLayoutConstraint.activate(constraints)
        return wrapper
    }

    // MARK: - Actions (identical behavior to the alert banner)

    @objc private func acceptAllTapped() {
        log.info("Accept All selected")
        setConsentAndDismiss(BannerPresenter.acceptAllFlags(translation))
    }

    @objc private func rejectAllTapped() {
        log.info("Reject All selected")
        setConsentAndDismiss(BannerPresenter.rejectAllFlags(translation))
    }

    @objc private func preferencesTapped() {
        log.info("Preferences selected")
        let translation = self.translation
        let consentModalConfig = self.consentModalConfig
        let config = self.config
        animateOutAndDismiss {
            ModalPresenter.show(
                translation: translation,
                consentModalConfig: consentModalConfig,
                config: config
            )
        }
        BannerPresenter.report(flags: ["BANNER_VIEWED": true], config: config)
    }

    @objc private func closeTapped() {
        log.info("Close selected")
        if let flags = BannerPresenter.closeFlags(translation, config: config) {
            setConsentAndDismiss(flags)
        } else {
            // Consent already stored: keep it and simply dismiss
            BannerPresenter.report(flags: ["BANNER_VIEWED": true], config: config)
            animateOutAndDismiss()
        }
    }

    private func setConsentAndDismiss(_ flags: [String: Bool]) {
        Enforce.setConsent(flags, beaconExtras: ["BANNER_VIEWED": true])
        animateOutAndDismiss()
    }

    /// Slides the sheet back down while fading the overlay, then dismisses.
    private func animateOutAndDismiss(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn]) {
            self.view.backgroundColor = .clear
            self.containerView.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
        } completion: { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }
}
