import Foundation
import os

private let log = Logger(subsystem: "Cheq", category: "TranslationService")

struct TranslationService {
    
    // Builds the environment URL from the configuration
    static func buildURL(config: Config) -> URL? {
        
        let client = config.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let path   = config.publishPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let env    = config.environment.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Fail fast + beacon for each missing piece
        if client.isEmpty {
            log.error("Missing clientName from configure")
            return nil
        }
        if path.isEmpty {
            log.error("Missing publishPath from configure")
            return nil
        }
        if env.isEmpty {
            log.error("Missing environment from configure")
            Task {
                _ = await ErrorReporting.sendError(msg: "Missing environment from configure", fn: #function, config: config)
            }
            return nil
        }
        
        let baseURL = config.debug ? "https://nexus-test.ensighten.com" : "https://nexus.ensighten.com"
        
        // start with the base URL
        guard var url = URL(string: baseURL) else { return nil }
        
        // append each path component — handles percent-escaping
        url.appendPathComponent("privacy")
        url.appendPathComponent("environments")
        url.appendPathComponent(client)
        url.appendPathComponent(path)
        url.appendPathComponent(env)
        url.appendPathComponent("environment.json")
        
        return url
    }
    
    /// Fetches JSON from a given URL using async/await.
    /// - Parameter url: The URL to fetch JSON from.
    /// - Returns: The fetched `Data` if successful.
    /// - Throws: An error if the request fails or data is missing.
    static func fetchJSON(from url: URL, debug: Bool) async throws -> Data {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        
        HTTPLogger.logRequest(req, enabled: debug)
        let (data, resp) = try await session.data(for: req)
        
        if let http = resp as? HTTPURLResponse {
            HTTPLogger.logResponse(http, data: data, enabled: debug)
        }
        
        return data
    }
    
}
