import Foundation

// MARK: - Public configuration (returned by `Enforce.getConfiguration()`)
//
// These are public mirrors of the internal remote-JSON models, so customers
// can build their own consent UI without the SDK freezing its wire format
// as public API. Keep the `init(from:)` mappers below in sync when a field
// is added to the internal models in Types.swift.

/// The consent configuration fetched from the remote `environment.json`,
/// exposed so a customer can implement their own consent experience.
public struct EnforceConfiguration {
    public let clientId: String
    public let version: String
    public let enforcement: Bool
    public let enablePrivacyNotice: Bool
    public let enableConsentModal: Bool
    public let translation: EnforceTranslation
    public let bannerConfig: EnforceBannerConfig?
    public let consentModalConfig: EnforceConsentModalConfig?

    init(from response: JSONResponse) {
        self.clientId = response.clientId
        self.version = response.version
        self.enforcement = response.enforcement
        self.enablePrivacyNotice = response.enablePrivacyNotice
        self.enableConsentModal = response.enableConsentModal
        self.translation = EnforceTranslation(from: response.translation)
        self.bannerConfig = response.bannerConfig.map(EnforceBannerConfig.init(from:))
        self.consentModalConfig = response.consentModalConfig.map(EnforceConsentModalConfig.init(from:))
    }
}

/// All translated strings for the banner and modal.
public struct EnforceTranslation {
    public let notificationBannerContent: String?
    public let notificationBannerAllowAll: String?
    public let notificationBannerDenyAll: String?
    public let notificationBannerPreferences: String?
    public let consentTitle: String?
    public let consentDescription: String?
    public let consentModalAllowAll: String?
    public let consentModalDenyAll: String?
    public let save: String?
    public let cancel: String?
    public let close: String?
    public let cookies: [String: EnforceCookieDetails]?

    init(from translation: Translation) {
        self.notificationBannerContent = translation.notificationBannerContent
        self.notificationBannerAllowAll = translation.notificationBannerAllowAll
        self.notificationBannerDenyAll = translation.notificationBannerDenyAll
        self.notificationBannerPreferences = translation.notificationBannerPreferences
        self.consentTitle = translation.consentTitle
        self.consentDescription = translation.consentDescription
        self.consentModalAllowAll = translation.consentModalAllowAll
        self.consentModalDenyAll = translation.consentModalDenyAll
        self.save = translation.save
        self.cancel = translation.cancel
        self.close = translation.close
        self.cookies = translation.cookies?.mapValues(EnforceCookieDetails.init(from:))
    }
}

/// Title and description for one cookie category.
public struct EnforceCookieDetails {
    public let title: String?
    public let description: String?

    init(from details: CookieDetails) {
        self.title = details.title
        self.description = details.description
    }
}

/// Which banner buttons are enabled in the remote configuration.
public struct EnforceBannerConfig {
    public let ensAcceptAll: Bool?
    public let ensRejectAll: Bool?
    public let ensOpenModal: Bool?
    public let ensCloseBanner: Bool?

    init(from config: BannerConfig) {
        self.ensAcceptAll = config.ensAcceptAll?.show
        self.ensRejectAll = config.ensRejectAll?.show
        self.ensOpenModal = config.ensOpenModal?.show
        self.ensCloseBanner = config.ensCloseBanner?.show
    }
}

/// Which consent-modal buttons are enabled in the remote configuration.
public struct EnforceConsentModalConfig {
    public let ensConsentAcceptAll: Bool?
    public let ensConsentRejectAll: Bool?
    public let ensSaveModal: Bool?
    public let ensCloseModal: Bool?

    init(from config: ConsentModalConfig) {
        self.ensConsentAcceptAll = config.ensConsentAcceptAll?.show
        self.ensConsentRejectAll = config.ensConsentRejectAll?.show
        self.ensSaveModal = config.ensSaveModal?.show
        self.ensCloseModal = config.ensCloseModal?.show
    }
}
