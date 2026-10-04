//
//  ClaudeAPIHeaderBuilder.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Claude API HTTP header builder
/// One place to build request headers, used to get past Cloudflare
/// Carries a full browser impersonation header set
class ClaudeAPIHeaderBuilder {
    // MARK: - Constants

    /// The browser version the headers impersonate (Chrome on macOS).
    /// Worth bumping by hand every six months or so, since sitting on a very old version raises the odds Cloudflare flags it.
    private static let simulatedChromeVersion = "131.0.0.0"

    // MARK: - Public Methods

    /// Build the standard HTTP headers for a Claude API request
    /// - Parameters:
    ///   - organizationId: organization ID (optional, some APIs do not need it)
    ///   - sessionKey: session key
    /// - Returns: the HTTP header dictionary
    /// - Note: these headers are what gets past Cloudflare's bot detection
    /// - Important: the headers have to match a real browser request, otherwise a Cloudflare challenge fires
    static func buildHeaders(
        organizationId: String?,
        sessionKey: String
    ) -> [String: String] {
        return [
            // Base headers
            "accept": "*/*",
            "accept-language": acceptLanguageHeader(),
            "content-type": "application/json",

            // Anthropic platform identifiers
            "anthropic-client-platform": "web_claude_ai",
            "anthropic-client-version": "1.0.0",

            // Browser identifiers (Chrome on macOS)
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(simulatedChromeVersion) Safari/537.36",

            // Origin and referrer
            "origin": "https://claude.ai",
            "referer": "https://claude.ai/settings/usage",

            // Fetch API fields (important: Cloudflare checks these)
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",

            // Authentication cookie
            "Cookie": "sessionKey=\(sessionKey)"
        ]
    }

    /// Build accept-language from the system language preference rather than hardcoding zh-CN
    /// (a fixed value made requests from non Chinese users look less like a real browser to Cloudflare, see Issue #58)
    private static func acceptLanguageHeader() -> String {
        let languages = Locale.preferredLanguages.prefix(5)
        guard !languages.isEmpty else { return "en-US,en;q=0.9" }
        return languages.enumerated().map { index, language -> String in
            guard index > 0 else { return language }
            let q = max(0.1, 1.0 - Double(index) * 0.1)
            return "\(language);q=\(String(format: "%.1f", q))"
        }.joined(separator: ",")
    }

    /// Apply the standard headers to a URLRequest
    /// - Parameters:
    ///   - request: the URLRequest to set headers on (inout)
    ///   - organizationId: organization ID (optional, some APIs do not need it)
    ///   - sessionKey: session key
    /// - Note: modifies the request that was passed in
    static func applyHeaders(
        to request: inout URLRequest,
        organizationId: String?,
        sessionKey: String
    ) {
        let headers = buildHeaders(organizationId: organizationId, sessionKey: sessionKey)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
