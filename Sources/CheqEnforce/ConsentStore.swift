//
//  ConsentStore.swift
//  CheqEnforce
//
//  Created by Connor Parfitt on 03/07/2025.
//

import Foundation

/// Encapsulates all UserDefaults logic for storing + validating consent.
struct ConsentStore {
    
    private static let dataKey       = "cheqEnforceConsentData"
    private static let expiryKey     = "cheqEnforceConsentExpirationTime"
    private static let versionKey    = "cheqEnforceConsentVersion"
    
    /// Save or merge new consent flags, record version and expiration.
    /// - Parameters:
    ///   - consent: dictionary of consent category → Bool
    ///   - version: the current SDK version to validate against on load
    ///   - expirationMilliseconds: optional TTL from now (ms); defaults to 1 year
    static func save(
        _ consent: [String: Bool],
        version: String,
        expirationMilliseconds: Int? = nil
    ) {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970 * 1_000
        
        // Determine new expiration
        let newExpiry: Double
        if let ms = expirationMilliseconds {
            newExpiry = now + Double(ms)
        } else if let existing = defaults.value(forKey: expiryKey) as? Double {
            newExpiry = existing
        } else {
            newExpiry = now + 365 * 24 * 60 * 60 * 1_000
        }
        
        // Merge with any existing consent data
        var existing = defaults.dictionary(forKey: dataKey) as? [String: Bool] ?? [:]
        for (k, v) in consent {
            existing[k] = v
        }
        
        // Persist
        defaults.set(existing, forKey: dataKey)
        defaults.set(newExpiry, forKey: expiryKey)
        defaults.set(version, forKey: versionKey)
    }
    
    /// Load saved consent only if not expired and version matches.
    /// - Parameter version: current SDK version
    /// - Returns: stored consent or nil if expired/mismatched/not present
    static func loadValid(currentVersion version: String) -> [String: Bool]? {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970 * 1_000
        
        // Verify expiry
        guard let expiry = defaults.value(forKey: expiryKey) as? Double,
              now < expiry else {
            clearAll()
            return nil
        }
        
        // Verify version
        guard let savedVersion = defaults.string(forKey: versionKey),
              savedVersion == version else {
            clearAll()
            return nil
        }
        
        // Return stored consent
        return defaults.dictionary(forKey: dataKey) as? [String: Bool]
    }
    
    /// Retrieve full consent dictionary or empty.
    static func getAll() -> [String: Bool] {
        return UserDefaults.standard.dictionary(forKey: dataKey) as? [String: Bool] ?? [:]
    }
    
    /// Retrieve consent for a single category.
    static func get(_ key: String) -> Bool {
        return getAll()[key] ?? false
    }
    
    /// Retrieve consent for multiple categories.
    static func get(_ keys: [String]) -> [String: Bool] {
        let all = getAll()
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, all[$0] ?? false) })
    }
    
    /// Clear all stored consent data (used on expiry or version change).
    private static func clearAll() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dataKey)
        defaults.removeObject(forKey: expiryKey)
        defaults.removeObject(forKey: versionKey)
    }
    
}
