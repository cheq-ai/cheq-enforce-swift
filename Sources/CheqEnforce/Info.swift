import Foundation
import UIKit

enum Info {
    static let library = "cheq-enforce-swift"
    static let version = "0.1.3"
    static let platform = "ios"

    /// utm query items identifying the SDK, appended to every outgoing
    /// Cheq request (beacons, environment.json, error pings).
    static var utmQueryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "utm_platform", value: platform),
            URLQueryItem(name: "utm_sdk_version", value: version)
        ]
    }

    /// Beacon `gateway` field: (gateway-version)-(sdk-platform)-(sdk-version),
    /// e.g. "3-ios-0.1.2".
    static func gateway(_ gatewayVersion: String) -> String {
        "\(gatewayVersion)-\(platform)-\(version)"
    }
}
