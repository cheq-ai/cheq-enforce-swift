import UIKit

public class CustomConsentModalViewController: UIViewController {
    
    private let titleText: String
    private let descriptionText: String
    private let modalConfig: ConsentModalConfig
    private let sections: [(title: String, description: String)]
    private let config: Config

    private let allowAllTitle: String
    private let denyAllTitle: String
    private let saveTitle: String
    private let cancelTitle: String
    private var buttonStackView: UIStackView!

    private var toggleStates: [Bool]

    /// Modal theme tokens; non-nil handling only applies when `isThemed`.
    private let modalTheme: EnforceTheme.Modal?
    /// Whether an `EnforceTheme` was supplied in the configuration (themed modal).
    private let isThemed: Bool
    /// Whether the themed modal covers the whole screen instead of a card.
    private var isFullScreen: Bool { isThemed && modalTheme?.presentationStyle == .fullScreen }
    /// Pre-loaded logo image, resolved by `ModalPresenter` when themed.
    private let logo: UIImage?

    internal init(
        title: String,
        description: String,
        modalConfig: ConsentModalConfig,
        sections: [(title: String, description: String)],
        config: Config,
        allowAllTitle: String,
        denyAllTitle: String,
        saveTitle: String,
        cancelTitle: String,
        logo: UIImage? = nil
    ) {
        self.titleText = title
        self.descriptionText = description
        self.modalConfig = modalConfig
        self.sections = sections
        self.config = config
        // Seed the toggles from stored consent so the modal reflects the
        // user's current choices (categories without stored consent are off).
        self.toggleStates = sections.map { ConsentStore.get($0.title) }
        self.allowAllTitle = allowAllTitle
        self.denyAllTitle = denyAllTitle
        self.saveTitle = saveTitle
        self.cancelTitle = cancelTitle
        self.modalTheme = config.theme?.modal
        self.isThemed = config.theme != nil
        self.logo = logo
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
        if isThemed {
            // Themed UI is light-mode based; `appearance` is intentionally ignored.
            overrideUserInterfaceStyle = .light
        } else {
            switch config.appearance {
              case .light:    overrideUserInterfaceStyle = .light
              case .dark:     overrideUserInterfaceStyle = .dark
              case .default:  overrideUserInterfaceStyle = .unspecified
            }
        }
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
        
        //send Modal Loaded Beacon
        Task {
            guard let resp = Enforce.lastResponse else { return }
            await ConsentReporting.send(config: config, type: .consent, clientId: resp.clientId, version: resp.version, enforcement: resp.enforcement, cookieFlags: ["MODAL_LOADED": true])
        }
    }
    
    private func setupUI() {
        if isThemed {
            view.backgroundColor = ThemeResolver.color(modalTheme?.overlayColor, fallback: ThemeDefaults.overlay, token: "modal.overlayColor")
        } else {
            view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        }

        // Setup container view
        let containerView = UIView()
        if isThemed {
            containerView.backgroundColor = ThemeResolver.color(modalTheme?.backgroundColor, fallback: ThemeDefaults.background, token: "modal.backgroundColor")
        } else {
            containerView.backgroundColor = .systemBackground
        }
        containerView.layer.cornerRadius = 12
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Setup scroll view and content view
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        // Optional themed logo above the title
        var logoView: UIView?
        if isThemed, let logo {
            let wrapper = makeLogoView(logo)
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(wrapper)
            logoView = wrapper
        }

        // Setup title and description labels
        let titleLabel = UILabel()
        titleLabel.text = titleText
        titleLabel.textColor = .label
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        if isThemed {
            ThemeResolver.textStyle(
                modalTheme?.summary?.title,
                defaultSize: 18,
                defaultWeight: .bold,
                defaultAlignment: .center,
                token: "modal.summary.title"
            ).apply(to: titleLabel)
        }
        contentView.addSubview(titleLabel)

        let descriptionLabel = UILabel()
        descriptionLabel.text = descriptionText
        descriptionLabel.font = UIFont.systemFont(ofSize: 14)
        descriptionLabel.textColor = .label
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        if isThemed {
            ThemeResolver.textStyle(
                modalTheme?.summary?.description,
                defaultSize: 14,
                defaultWeight: .regular,
                defaultAlignment: .center,
                token: "modal.summary.description"
            ).apply(to: descriptionLabel)
        }
        contentView.addSubview(descriptionLabel)
        
        // Optional themed separator between the summary and the categories
        var separatorView: UIView?
        if isThemed, let separatorHex = modalTheme?.separatorColor, !separatorHex.isEmpty {
            let separator = UIView()
            separator.backgroundColor = ThemeResolver.color(separatorHex, fallback: .clear, token: "modal.separatorColor")
            separator.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(separator)
            separatorView = separator
        }

        // Setup stack view for sections
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        for (index, section) in sections.enumerated() {
            let sectionView = createSectionView(title: section.title, description: section.description, index: index)
            stackView.addArrangedSubview(sectionView)
        }

        // Setup button stack (outside scrollView)
        buttonStackView = UIStackView()
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fillEqually
        buttonStackView.spacing = 10
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(buttonStackView)

        // Button config; each style resolves `specific ?? global ?? default` when themed
        let globalStyle = modalTheme?.buttons?.global
        let buttonConfigs: [(shouldShow: Bool, title: String, action: Selector, style: ResolvedButtonStyle?)] = [
            (modalConfig.ensConsentAcceptAll?.show == true, allowAllTitle, #selector(acceptAll),
             isThemed ? ThemeResolver.buttonStyle(modalTheme?.buttons?.acceptAll, global: globalStyle, defaults: ThemeDefaults.primaryButton, defaultFontWeight: .semibold, token: "modal.buttons.acceptAll") : nil),
            (modalConfig.ensConsentRejectAll?.show == true, denyAllTitle, #selector(rejectAll),
             isThemed ? ThemeResolver.buttonStyle(modalTheme?.buttons?.rejectAll, global: globalStyle, defaults: ThemeDefaults.secondaryButton, token: "modal.buttons.rejectAll") : nil),
            (modalConfig.ensSaveModal?.show == true, saveTitle, #selector(saveConsent),
             isThemed ? ThemeResolver.buttonStyle(modalTheme?.buttons?.save, global: globalStyle, defaults: ThemeDefaults.secondaryButton, token: "modal.buttons.save") : nil),
            (modalConfig.ensCloseModal?.show == true, cancelTitle, #selector(dismissModal),
             isThemed ? ThemeResolver.buttonStyle(modalTheme?.buttons?.close, global: globalStyle, defaults: ThemeDefaults.textOnlyButton, token: "modal.buttons.close") : nil)
        ]

        var buttonCount = 0
        for config in buttonConfigs {
            if config.shouldShow {
                let button = createButton(title: config.title, action: config.action, style: config.style)
                buttonStackView.addArrangedSubview(button)
                buttonCount += 1
            }
        }
        
        // Adjust button stack orientation
        if buttonCount > 2 {
            buttonStackView.axis = .vertical
        }
        
        // Container: full-screen overlay or centered card, per the theme
        if isFullScreen {
            containerView.layer.cornerRadius = 0
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: view.topAnchor),
                containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                scrollView.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
                buttonStackView.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -12)
            ])
        } else {
            NSLayoutConstraint.activate([
                containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                containerView.widthAnchor.constraint(equalToConstant: 300),
                containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.8),
                scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                buttonStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
            ])
        }

        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),

            // ScrollView layout
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonStackView.topAnchor, constant: -20),
            
            // ContentView inside ScrollView
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Title label
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            // Section stack view
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            
            // Buttons at bottom (bottom anchor set in the card/fullScreen branch above)
            buttonStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            buttonStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            buttonStackView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 20)
        ])

        // Title top: below the themed logo when present, else at the content top
        if let logoView {
            NSLayoutConstraint.activate([
                logoView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
                logoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                logoView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                titleLabel.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: 12)
            ])
        } else {
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16).isActive = true
        }

        // Section stack top: below the themed separator when present, else below the description
        if let separatorView {
            NSLayoutConstraint.activate([
                separatorView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 16),
                separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                separatorView.heightAnchor.constraint(equalToConstant: 1),
                stackView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 16)
            ])
        } else {
            stackView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 20).isActive = true
        }

        // Ensure scroll view expands correctly
        let contentViewHeightConstraint = contentView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        contentViewHeightConstraint.priority = .defaultLow
        contentViewHeightConstraint.isActive = true
    }

    private func createButton(title: String, action: Selector, style: ResolvedButtonStyle? = nil) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        if let style {
            style.apply(to: button)
        } else {
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.label.cgColor
            button.layer.cornerRadius = 8
        }
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
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
        // constraints and overflowing the modal.
        let aspect = image.size.width / max(image.size.height, 1)
        let aspectConstraint = imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: aspect)
        aspectConstraint.priority = .defaultHigh

        switch modalTheme?.logoAlignment ?? .center {
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
    
    private func createSectionView(title: String, description: String, index: Int) -> UIView {
        let sectionView = UIView()
        sectionView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        if isThemed {
            ThemeResolver.textStyle(
                modalTheme?.categories?.title,
                defaultSize: 16,
                defaultWeight: .bold,
                token: "modal.categories.title"
            ).apply(to: titleLabel)
        }
        sectionView.addSubview(titleLabel)

        let descriptionLabel = UILabel()
        descriptionLabel.text = description
        descriptionLabel.font = UIFont.systemFont(ofSize: 14)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        if isThemed {
            ThemeResolver.textStyle(
                modalTheme?.categories?.description,
                defaultSize: 14,
                defaultWeight: .regular,
                token: "modal.categories.description"
            ).apply(to: descriptionLabel)
        }
        sectionView.addSubview(descriptionLabel)

        let toggleSwitch = UISwitch()
        toggleSwitch.tag = index
        toggleSwitch.isOn = toggleStates[index]
        toggleSwitch.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        toggleSwitch.translatesAutoresizingMaskIntoConstraints = false
        if isThemed {
            let offColor = ThemeResolver.color(modalTheme?.categories?.toggleOffColor, fallback: ThemeDefaults.toggleOff, token: "modal.categories.toggleOffColor")
            toggleSwitch.onTintColor = ThemeResolver.color(modalTheme?.categories?.toggleOnColor, fallback: ThemeDefaults.toggleOn, token: "modal.categories.toggleOnColor")
            toggleSwitch.tintColor = offColor
            toggleSwitch.backgroundColor = offColor
        } else {
            toggleSwitch.tintColor = .secondarySystemFill
            toggleSwitch.backgroundColor = .secondarySystemFill
        }
        toggleSwitch.layer.cornerRadius = toggleSwitch.frame.height / 2.0
        toggleSwitch.clipsToBounds = true
        // The switch must never compress or stretch; the labels yield instead.
        toggleSwitch.setContentCompressionResistancePriority(.required, for: .horizontal)
        toggleSwitch.setContentHuggingPriority(.required, for: .horizontal)
        sectionView.addSubview(toggleSwitch)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: sectionView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: toggleSwitch.leadingAnchor, constant: -10),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descriptionLabel.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: toggleSwitch.leadingAnchor, constant: -10),
            descriptionLabel.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor),

            // Toggles pin to the trailing edge so every row's switch aligns
            // at the same point regardless of text length. The labels' equal
            // trailing constraints give them a fixed width to wrap within
            // (text draws left-aligned, so short text simply leaves a gap).
            toggleSwitch.trailingAnchor.constraint(equalTo: sectionView.trailingAnchor),
            toggleSwitch.centerYAnchor.constraint(equalTo: sectionView.centerYAnchor),
        ])
        
        return sectionView
    }
    
    @objc private func acceptAll() {
        print("Accepted all consents")
        
        //Set all consent to true
        let consentData = createConsentData(state: true)
        saveAndDismiss(consentData: consentData)
    }
    
    @objc private func rejectAll() {
        print("Rejected all consents")
        
        // Set all consent to false
        let consentData = createConsentData(state: false)
        saveAndDismiss(consentData: consentData)
    }
    
    @objc private func saveConsent() {
        print("Consent saved: \(toggleStates)")
        
        // Create a dictionary with categories and state (user defined)
        var consentData: [String: Bool] = [:]
        for (index, section) in sections.enumerated() {
            let sectionTitle = section.title
            let toggleState = toggleStates[index]
            consentData[sectionTitle] = toggleState
        }
        
        saveAndDismiss(consentData: consentData)
    }
    
    @objc private func dismissModal() {
        // Consent already stored: keep it and simply close
        guard ConsentStore.getAll().isEmpty else {
            BannerPresenter.report(flags: ["MODAL_VIEWED": true], config: config)
            dismiss(animated: true, completion: nil)
            return
        }

        //If default consent provided in configuration, else set all to false
        if let defaultConsent = config.defaultConsent,
           defaultConsent.values.allSatisfy({ $0 == false || $0 == true }) {
            saveAndDismiss(consentData: defaultConsent)
        } else {
            let consentData = createConsentData(state: false)
            saveAndDismiss(consentData: consentData)
        }
    }
    
    @objc private func toggleChanged(_ sender: UISwitch) {
        toggleStates[sender.tag] = sender.isOn
    }
    
    private func createConsentData(state: Bool) -> [String: Bool] {
        var consentData: [String: Bool] = [:]
        for (_, section) in sections.enumerated() {
            consentData[section.title] = state
        }
        return consentData
    }
    
    private func saveAndDismiss(consentData: [String: Bool]) {
        Enforce.setConsent(consentData, beaconExtras: ["MODAL_VIEWED": true])
        dismiss(animated: true, completion: nil)
    }
}
