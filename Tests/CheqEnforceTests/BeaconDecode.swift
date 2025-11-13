//
//  BeaconDecode.swift
//  CheqEnforce
//
//  Created by Connor Parfitt on 10/10/2025.
//

import Foundation
import Compression
import XCTest

enum BeaconDecode {
    static func extractQuery(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    static func base64urlToData(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t.append("=") }
        return Data(base64Encoded: t)
    }

    static func lz4RawDecompress(_ data: Data, expectedOutSize: Int? = nil) -> Data? {
        var dst = Data(count: expectedOutSize ?? max(512, data.count * 4))
        let dstCapacity = dst.count
        let decompressedSize: Int = dst.withUnsafeMutableBytes { dstBuf in
            data.withUnsafeBytes { srcBuf in
                guard let src = srcBuf.baseAddress, let out = dstBuf.baseAddress else { return 0 }
                return compression_decode_buffer(
                    out.assumingMemoryBound(to: UInt8.self),
                    dstCapacity,
                    src.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }
        guard decompressedSize > 0 else { return nil }
        dst.removeSubrange(decompressedSize..<dst.count)
        return dst
    }

    static func decodeJSONPayload(from url: URL) throws -> [String: Any] {
        guard let d = extractQuery(url, "d"),
              let compressed = base64urlToData(d),
              let raw = lz4RawDecompress(compressed),
              let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw NSError(domain: "BeaconDecode", code: 1)
        }
        return obj
    }
}
