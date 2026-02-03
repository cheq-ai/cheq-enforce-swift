import Foundation
import os

private let log = Logger(subsystem: "Cheq", category: "CheqEnforce.Error")

/// Fire-and-forget error ping to Nexus (`/error/e.gif`).
enum ErrorReporting {

    /// Minimal app identity for headers/diagnostics
    private struct AppInfo {
        let name: String
        let version: String
        static var current: AppInfo {
            let bundle = Bundle.main
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? bundle.bundleIdentifier
                ?? "UnknownApp"
            let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                ?? "0"
            return AppInfo(name: name, version: version)
        }
    }
    
    /// Build the Referer URL: https://{host}/privacy/environments/{clientName}
    private static func makeReferrer(from config: Config) -> URL? {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host   = config.debug ? "nexus-test.ensighten.com" : "nexus.ensighten.com"

            // ensure clientName is path-safe
            let encodedClient = config.clientName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? config.clientName

            comps.path = "/privacy/environments/\(encodedClient)"
            return comps.url
        }

    /// Send an error beacon.
    /// - Parameters:
    ///   - msg: Human-readable message.
    ///   - fn: Where the error happened.
    ///   - clientId: Client id
    ///   - config: Your `Config` (to choose host & include client/publishPath).
    ///   - session: Inject a session for tests; defaults to `.shared`.
    @discardableResult
    static func sendError(
        msg: String,
        fn: String,
        clientId: String? = nil,
        config: Config,
        session: URLSession = .shared
    ) async -> Bool {
        let host = config.debug ? "nexus-test.ensighten.com" : "nexus.ensighten.com"

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host   = host
        comps.path   = "/error/e.gif"

        let app = AppInfo.current
        let fnParam = truncate("\(fn) \(Info.library):\(Info.version) \(app.name):\(app.version)", 256)

        var items: [URLQueryItem] = [
            URLQueryItem(name: "msg",         value: truncate(msg, 1024)),
            URLQueryItem(name: "fn",          value: fnParam),
            URLQueryItem(name: "client",      value: truncate(config.clientName, 256)),
            URLQueryItem(name: "publishPath", value: truncate(config.publishPath, 256)),
            URLQueryItem(name: "errorName",   value: "SDKError"),
        ]
        
        if let cid = clientId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty {
            items.append(URLQueryItem(name: "cid", value: truncate(cid, 256)))
        }
        
        comps.queryItems = items

        guard let url = comps.url else {
            log.error("Failed to build error URL")
            return false
        }

        var req = URLRequest(url: url)
        if let ref = makeReferrer(from: config)?.absoluteString {
            req.setValue(ref, forHTTPHeaderField: "Referer")
        }
        
        // Simple UA that identifies the SDK + host app
        let ua = "\(Info.library)/\(Info.version) (\(app.name) \(app.version))"
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.httpMethod = "GET"

        do {
            HTTPLogger.logRequest(req, enabled: config.debug)
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            log.info("Error beacon sent, status: \(status)")
            if let http = resp as? HTTPURLResponse {
                HTTPLogger.logResponse(http, data: data, enabled: config.debug)
            }
            return true
        } catch {
            log.error("Error beacon failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Utils

    private static func truncate(_ value: String, _ max: Int) -> String {
        guard value.count > max else { return value }
        let end = value.index(value.startIndex, offsetBy: max - 3)
        return String(value[..<end]) + "..."
    }
}
