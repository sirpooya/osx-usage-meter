//
//  CodexAPIHeaderBuilder.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-04-24.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Codex API HTTP header builder
/// Two header sets:
///   - the session endpoint (/api/auth/session): a session-token cookie
///   - the usage endpoint (/backend-api/wham/usage): a Bearer accessToken
class CodexAPIHeaderBuilder {

    // MARK: - Session endpoint headers (cookie authentication)

    /// Build the headers for an /api/auth/session request
    /// - Parameter sessionToken: the __Secure-next-auth.session-token cookie value
    static func buildSessionHeaders(sessionToken: String) -> [String: String] {
        return [
            "accept": "*/*",
            "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "origin": "https://chatgpt.com",
            "referer": "https://chatgpt.com/",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",
            "Cookie": "__Secure-next-auth.session-token=\(sessionToken)"
        ]
    }

    /// Apply the session endpoint headers to a URLRequest
    static func applySessionHeaders(to request: inout URLRequest, sessionToken: String) {
        let headers = buildSessionHeaders(sessionToken: sessionToken)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    // MARK: - Usage endpoint headers (Bearer token authentication)

    /// Build the headers for a /backend-api/wham/usage request
    /// - Parameter accessToken: the Bearer token obtained from /api/auth/session
    static func buildUsageHeaders(accessToken: String) -> [String: String] {
        return [
            "accept": "*/*",
            "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
            "content-type": "application/json",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "authorization": "Bearer \(accessToken)",
            "origin": "https://chatgpt.com",
            "referer": "https://chatgpt.com/",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin"
        ]
    }

    /// Apply the usage endpoint headers to a URLRequest
    static func applyUsageHeaders(to request: inout URLRequest, accessToken: String) {
        let headers = buildUsageHeaders(accessToken: accessToken)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
