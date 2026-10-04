//
//  PKCE.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-06-18.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import Foundation
import CryptoKit

/// PKCE (RFC 7636) parameters, plus the OAuth state (CSRF protection)
/// code_challenge uses S256 (SHA-256 plus base64url)
struct PKCECodes {
    let codeVerifier: String
    let codeChallenge: String
    let state: String

    init() {
        codeVerifier = Self.randomURLSafe(byteCount: 64)
        state = Self.randomURLSafe(byteCount: 32)
        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        codeChallenge = Self.base64URL(Data(digest))
    }

    /// Generate a URL safe random string (base64url, no padding)
    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        // If SecRandomCopyBytes fails (very rare) bytes stays all zeros, which makes
        // code_verifier and state predictable and the PKCE and CSRF protection worthless. Crashing beats silently using an unsafe value.
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return base64URL(Data(bytes))
    }

    /// base64url encoding (no padding)
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
