//
//  JWT.swift
//  UsageMeter
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Read the `exp` field out of a JWT payload
/// - Note: a JWT payload is base64url encoded (its alphabet includes `-` and `_`, with no padding),
///   so it has to be mapped to the standard base64 alphabet before decoding, otherwise any payload containing `-` or `_` fails.
func jwtExpiry(from token: String) -> Date? {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var base64 = String(parts[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
    guard let data = Data(base64Encoded: base64),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let exp = json["exp"] as? TimeInterval else { return nil }
    return Date(timeIntervalSince1970: exp)
}
