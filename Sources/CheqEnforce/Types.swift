//
//  Types.swift
//  Enforce
//
//  Created by Connor Parfitt on 14/01/2025.
//

// MARK: - Configuration
/// SST Configuration
public struct Config {
    let clientName: String
    let publishPath: String
    let environment: String
    let debug: Bool
    let dataRetentionPeriod: Int
    let autoShow: Bool
    let version: String
    let defaultConsent: [String: Bool]?
    let appearance: Appearance
    
    /// Creates an Enforce Configuration
    /// - Parameters:
    ///   - clientName: client name
    ///   - publishPath: publish path
    ///   - environment: environment
    ///   - debug: optional flag to enable debug logging, default `false`
    ///   - dataRetentionPeriod: optional retention ms, default `31536000000`
    ///   - autoShow: optional show banner/modal if consent not already given, default `true`
    ///   - version: optional version that retriggers consent on change, default `1`
    ///   - defaultConsent: optional flag to set default consent, default `nil`
    ///   - appearance: UI appearance for banner & modal:
    ///     - `.light`   — light‑mode look (white background, dark text)
    ///     - `.dark`    — dark‑mode look (dark background, light text)
    ///     - `.default` — use the system’s current interface style
    public init(_ clientName: String,
                publishPath: String,
                environment: String,
                debug: Bool = false,
                dataRetentionPeriod: Int = 31536000000,
                autoShow: Bool = true,
                version: String = "1",
                defaultConsent: [String: Bool]? = nil,
                appearance: Appearance = .default) {
        self.clientName = clientName
        self.publishPath = publishPath
        self.environment = environment
        self.debug = debug
        self.dataRetentionPeriod = dataRetentionPeriod
        self.autoShow = autoShow
        self.version = version
        self.defaultConsent = defaultConsent
        self.appearance = appearance
    }
}

public enum Appearance {
  case light
  case dark
  case `default`
}

// MARK: - JSON Response
struct JSONResponse: Codable {
    let clientId: String
    let version: String
    let enforcement: Bool
    let enablePrivacyNotice: Bool
    let enableConsentModal: Bool
    let translation: Translation
    let bannerConfig: BannerConfig?
    let consentModalConfig: ConsentModalConfig?
}


// MARK: - Translations
struct Translation: Codable {
    let notificationBannerContent: String?
    let notificationBannerAllowAll: String?
    let notificationBannerDenyAll: String?
    let notificationBannerPreferences: String?
    let consentTitle: String?
    let consentDescription: String?
    let consentModalAllowAll: String?
    let consentModalDenyAll: String?
    let save: String?
    let cancel: String?
    let close: String?
    let cookies: [String: CookieDetails]?
}

struct CookieDetails: Codable {
    let title: String?
    let description: String?
};

// MARK: - Banner & Modal Configurations
struct BannerConfig: Codable {
    let ensAcceptAll: BannerConfigItem?
    let ensRejectAll: BannerConfigItem?
    let ensOpenModal: BannerConfigItem?
    let ensCloseBanner: BannerConfigItem?
}

struct ConsentModalConfig: Codable {
    let ensConsentAcceptAll: BannerConfigItem?
    let ensConsentRejectAll: BannerConfigItem?
    let ensSaveModal: BannerConfigItem?
    let ensCloseModal: BannerConfigItem?
}

struct BannerConfigItem: Codable {
    let show: Bool
}

// MARK: - Consent Beacons
struct EnforceBeacon: Encodable {
    let version: String
    let gateway: String
    let clientId: String
    let clientName: String?
    let publishPath: String
    let instanceId: String?
    let packet: Int?
    let mode: String
    let cookies: [String: String]
    let environment: String?
    let documentReferrer: String?
    let dt: Int64?
    let settings: Settings?
    let events: [Event]?
    let requests: [Request]?
}

struct Settings: Codable {
    let modal: String
    let environment: String
    let defaults: [String: Int]
}

struct Event: Encodable {
    let event: String
    let dt: Int64
    let cookie: [String: String]
    
    enum CodingKeys: CodingKey {
        case event, dt
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event, forKey: .event)
        try container.encode(dt, forKey: .dt)
        
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in cookie {
            try dynamicContainer.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
        }
    }
    
    struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    
    init(key: String, value: Bool, timestamp: Int64) {
        self.event = "cookieChanged"
        self.dt = timestamp
        self.cookie = [key: value ? "1" : "0"]
    }
}

struct Request: Codable {
    let destination: String
    let type: String
    let start: Int64
    let end: Int
    let source: String
    let status: String
    let reasons: [String]
    let dataPatterns: [String]
    let list: [String]
    let id: Int64
}

enum BeaconType: String {
    case billing
    case consent
}
