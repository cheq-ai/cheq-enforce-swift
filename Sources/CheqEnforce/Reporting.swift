import Foundation
import os

private let log = Logger(subsystem: "Cheq", category: "CheqEnforce")

struct ConsentReporting {
    /// Public API: send a billing or consent beacon
    static func send(
        config: Config,
        type: BeaconType,
        clientId: String,
        version: String,
        enforcement: Bool,
        cookieFlags: [String: Bool] = [:],
        session: URLSession = .shared
    ) async {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let instanceId = Enforce.cachedInstanceId
        
        do {
            // Build the beacon model
            let beacon = makeBeacon(config: config,
                                    type: type,
                                    flags: cookieFlags,
                                    timestamp: timestamp,
                                    instanceId: instanceId,
                                    clientId:    clientId,
                                    version:     version,
                                    enforcement: enforcement)
            
            // Encode beacon to JSON string
            let jsonString = try encodeBeacon(beacon)
            
            // Compress & Base64URL-encode
            let (payload, uncompressedLen) = try compress(jsonString)
            
            // Build the request URL
            let url = try buildURL(
                config: config,
                type: type,
                payload: payload,
                uncompressedLength: uncompressedLen,
                instanceId: instanceId,
                clientId: clientId
            )
            log.info("\(type.rawValue, privacy: .public) beacon URL: \(url.absoluteString)")
            
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            
            // Fire the network request
            HTTPLogger.logRequest(req, enabled: config.debug)
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                HTTPLogger.logResponse(http, data: data, enabled: config.debug)
            }
            log.info("Reporting payload sent, status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            
        } catch {
            log.error("Error encoding or sending beacon: \(error)")
            Task {
                _ = await ErrorReporting.sendError(msg: "Error encoding or sending beacon: \(error)", fn: #function, config: config)
            }
        }
    }
    
    // MARK: - Helpers
    
    private static func makeBeacon(
        config: Config,
        type: BeaconType,
        flags: [String: Bool],
        timestamp: Int64,
        instanceId: String,
        clientId: String,
        version: String,
        enforcement: Bool
    ) -> EnforceBeacon {
        switch type {
        case .billing:
            let modeString = enforcement ? "enforce" : "observe"
            let request = Request(
                destination: "",
                type: "billing",
                start: timestamp,
                end: -1,
                source: "",
                status: "",
                reasons: [],
                dataPatterns: [],
                list: [],
                id: timestamp
            )
            return EnforceBeacon(
                version: "1.0.0",
                gateway: version,
                clientId: clientId,
                clientName: nil,
                publishPath: config.publishPath,
                instanceId: instanceId,
                packet: 0,
                mode: modeString,
                cookies: [:],
                environment: config.environment,
                documentReferrer: "",
                dt: nil,
                settings: nil,
                events: nil,
                requests: [request]
            )
            
        case .consent:
            // Merge incoming flags
            for (key, value) in flags {
                Enforce.storedCookieFlags[key] = value
            }
            // Build cookies dict
            let cookies = Dictionary(uniqueKeysWithValues:
                                        Enforce.storedCookieFlags.map { flag, enabled in
                ("\(config.clientName.uppercased())_ENSIGHTEN_PRIVACY_\(flag)", enabled ? "1" : "0")
            }
            )
            // Events array
            let events = flags.map { Event(key: $0.key, value: $0.value, timestamp: timestamp) }
            // Defaults
            let defaults = (config.defaultConsent ?? [:]).mapValues { $0 ? 1 : 0 }
            let settings = Settings(modal: "enterprise",
                                    environment: config.environment,
                                    defaults: defaults)
            let modeString = enforcement ? "whitelist" : "blacklist"
            return EnforceBeacon(
                version: "1.0.0",
                gateway: version,
                clientId: clientId,
                clientName: config.clientName,
                publishPath: config.publishPath,
                instanceId: nil,
                packet: nil,
                mode: modeString,
                cookies: cookies,
                environment: nil,
                documentReferrer: nil,
                dt: timestamp,
                settings: settings,
                events: events,
                requests: nil
            )
        }
    }
    
    private static func encodeBeacon(_ beacon: EnforceBeacon) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(beacon)
        guard let str = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ConsentReporting", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to stringify JSON"])
        }
        return str
    }
    
    private static func compress(_ jsonString: String) throws -> (String, Int) {
        // Raw compression + Base64
        guard let result = LZ4Compression.compressToBase64url(jsonString) else {
            throw NSError(
                domain: "ConsentReporting",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Compression failed"]
            )
        }
        // URL‐safe Base64
        let urlSafe = result.encodedBody
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return (urlSafe, result.rawLength)
    }
    
    private static func buildURL(
        config: Config,
        type: BeaconType,
        payload: String,
        uncompressedLength: Int,
        instanceId: String,
        clientId: String
    ) throws -> URL {
        // Path prefix and beaconCount
        let pathPrefix: String
        let n: Int
        switch type {
        case .billing:
            pathPrefix = "b"
            n = 0
            Enforce.beaconCount = 1
        case .consent:
            pathPrefix = "c"
            n = Enforce.beaconCount
            Enforce.beaconCount += 1
        }
        
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "data.privacy.ensighten.com"
        comps.path = "/privacy/v1/\(pathPrefix)/b.rnc"
        comps.queryItems = [
            URLQueryItem(name: "n", value: "\(n)"),
            URLQueryItem(name: "c", value: clientId),
            URLQueryItem(name: "i", value: instanceId),
            URLQueryItem(name: "p", value: config.publishPath),
            URLQueryItem(name: "utm_platform", value: "ios_mobile_sdk"),
            URLQueryItem(name: "utm_sdk_version", value: "1.0.0"),
            URLQueryItem(name: "s", value: "\(uncompressedLength)"),
            URLQueryItem(name: "d", value: payload)
        ]
        guard let url = comps.url else {
            throw NSError(domain: "ConsentReporting", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        return url
    }
}
