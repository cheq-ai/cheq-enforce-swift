//
//  lz4.swift
//  CheqEnforce
//
//  Created by Connor Parfitt on 02/07/2025.
//

import Foundation
import Compression
import os

private let log = Logger(subsystem: "Cheq", category: "CheqEnforce")

enum LZ4Compression {
    static func compressToBase64url(_ jsonString: String) -> (encodedBody: String, rawLength: Int)? {
        guard let input = jsonString.data(using: .utf8) else { return nil }

        let upperBound = input.count + input.count/255 + 16

        var out = Data(count: upperBound)
        let dstCapacity = upperBound
        let srcCount    = input.count

        let compressedSize: Int = input.withUnsafeBytes { srcBuf in
            out.withUnsafeMutableBytes { dstBuf in
                guard
                    let src = srcBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    let dst = dstBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else { return 0 }

                return compression_encode_buffer(
                    dst, dstCapacity,
                    src, srcCount,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }

        guard compressedSize > 0 else { return nil }

        out.removeSubrange(compressedSize..<out.count)

        let b64 = out.base64EncodedString()
        return (encodedBody: b64, rawLength: input.count)
    }
}
