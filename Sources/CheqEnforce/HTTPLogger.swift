//
//  HTTPLogger.swift
//  CheqEnforce
//
//  Created by Connor Parfitt on 30/09/2025.
//

import Foundation
import os

private let httpLog = Logger(subsystem: "Cheq", category: "CheqEnforce.Net")

enum HTTPLogger {
    static func logRequest(_ request: URLRequest, enabled: Bool) {
        guard enabled else { return }
        httpLog.debug("--- REQUEST ---")
        httpLog.debug("\tURL: \(request.url?.absoluteString ?? "N/A", privacy: .public)")
        httpLog.debug("\tMethod: \(request.httpMethod ?? "N/A", privacy: .public)")
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            httpLog.debug("Request Headers:")
            headers.forEach { k, v in
                httpLog.debug("\t\(k, privacy: .public): \(v, privacy: .public)")
            }
        }
        if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8), !bodyStr.isEmpty {
            httpLog.debug("Request Body:")
            httpLog.debug("\t\(bodyStr, privacy: .public)")
        }
    }

    static func logResponse(_ response: HTTPURLResponse, data: Data?, enabled: Bool) {
        guard enabled else { return }
        httpLog.debug("--- RESPONSE ---")
        httpLog.debug("\tStatus Code: \(response.statusCode, privacy: .public)")
        if !response.allHeaderFields.isEmpty {
            httpLog.debug("Response Headers:")
            response.allHeaderFields.forEach { k, v in
                httpLog.debug("\t\(String(describing: k), privacy: .public): \(String(describing: v), privacy: .public)")
            }
        }
        // Skip body for 204s
        if response.statusCode != 204,
           let data, let bodyStr = String(data: data, encoding: .utf8), !bodyStr.isEmpty {
            httpLog.debug("Response Body:")
            httpLog.debug("\t\(bodyStr, privacy: .public)")
        }
    }
}
