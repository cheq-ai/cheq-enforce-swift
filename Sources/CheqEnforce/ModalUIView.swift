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
    
    internal init(
        title: String,
        description: String,
        modalConfig: ConsentModalConfig,
        sections: [(title: String, description: String)],
        config: Config,
        allowAllTitle: String,
        denyAllTitle: String,
        saveTitle: String,
        cancelTitle: String
    ) {
        self.titleText = title
        self.descriptionText = description
        self.modalConfig = modalConfig
        self.sections = sections
        self.config = config
        self.toggleStates = Array(repeating: false, count: sections.count)
        self.allowAllTitle = allowAllTitle
        self.denyAllTitle = denyAllTitle
        self.saveTitle = saveTitle
        self.cancelTitle = cancelTitle
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
        switch config.appearance {
          case .light:    overrideUserInterfaceStyle = .light
          case .dark:     overrideUserInterfaceStyle = .dark
          case .default:  overrideUserInterfaceStyle = .unspecified
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
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        
        // Setup container view
        let containerView = UIView()
        containerView.backgroundColor = .systemBackground
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
        
        // Setup title and description labels
        let titleLabel = UILabel()
        titleLabel.text = titleText
        titleLabel.textColor = .label
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        let descriptionLabel = UILabel()
        descriptionLabel.text = descriptionText
        descriptionLabel.font = UIFont.systemFont(ofSize: 14)
        descriptionLabel.textColor = .label
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descriptionLabel)
        
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
        
        // Button config
        let buttonConfigs: [(shouldShow: Bool, title: String, action: Selector)] = [
            (modalConfig.ensConsentAcceptAll?.show == true, allowAllTitle, #selector(acceptAll)),
            (modalConfig.ensConsentRejectAll?.show == true, denyAllTitle, #selector(rejectAll)),
            (modalConfig.ensSaveModal?.show == true, saveTitle, #selector(saveConsent)),
            (modalConfig.ensCloseModal?.show == true, cancelTitle, #selector(dismissModal))
        ]
        
        var buttonCount = 0
        for config in buttonConfigs {
            if config.shouldShow {
                let button = createButton(title: config.title, action: config.action)
                buttonStackView.addArrangedSubview(button)
                buttonCount += 1
            }
        }
        
        // Adjust button stack orientation
        if buttonCount > 2 {
            buttonStackView.axis = .vertical
        }
        
        NSLayoutConstraint.activate([
            // Container view layout
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300),
            containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.8),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
            
            // ScrollView layout
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
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
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Section stack view
            stackView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            
            // Buttons at bottom
            buttonStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            buttonStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            buttonStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
            buttonStackView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 20)
        ])
        
        // Ensure scroll view expands correctly
        let contentViewHeightConstraint = contentView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        contentViewHeightConstraint.priority = .defaultLow
        contentViewHeightConstraint.isActive = true
    }
    
    private func createButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.label.cgColor
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        return button
    }
    
    private func createSectionView(title: String, description: String, index: Int) -> UIView {
        let sectionView = UIView()
        sectionView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionView.addSubview(titleLabel)
        
        let descriptionLabel = UILabel()
        descriptionLabel.text = description
        descriptionLabel.font = UIFont.systemFont(ofSize: 14)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionView.addSubview(descriptionLabel)
        
        let toggleSwitch = UISwitch()
        toggleSwitch.tag = index
        toggleSwitch.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        toggleSwitch.translatesAutoresizingMaskIntoConstraints = false
        toggleSwitch.tintColor = .secondarySystemFill
        toggleSwitch.layer.cornerRadius = toggleSwitch.frame.height / 2.0
        toggleSwitch.backgroundColor = .secondarySystemFill
        toggleSwitch.clipsToBounds = true
        sectionView.addSubview(toggleSwitch)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: sectionView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor),
            
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descriptionLabel.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor),
            descriptionLabel.widthAnchor.constraint(lessThanOrEqualTo: sectionView.widthAnchor, multiplier: 0.75),
            descriptionLabel.trailingAnchor.constraint(equalTo: toggleSwitch.leadingAnchor, constant: -10),
            descriptionLabel.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor),
            
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
