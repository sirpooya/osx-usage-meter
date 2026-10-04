//
//  ClaudeOAuthConfig.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-06-19.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import Foundation

/// Claude (claude.ai) OAuth configuration constants
///
/// Reuses Anthropic's official Claude Code public OAuth client (PKCE, no client secret).
/// Authentication happens in the user's default browser, which sidesteps WKWebView's block on Google's embedded login
/// and the fact that passkeys and WebAuthn do not work in an embedded WebView (see Issue #49).
enum ClaudeOAuthConfig {
    /// Authorization endpoint (login and consent happen on claude.ai)
    static let authorizeURL = "https://claude.ai/oauth/authorize"
    /// token / refresh endpoint
    static let tokenURL = "https://console.anthropic.com/v1/oauth/token"

    /// Claude Code's official public client id (PKCE, no client secret)
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// OAuth scope: read only usage needs user:profile alone (user:inference is not requested, to avoid over broad permissions)
    static let scope = "user:profile"

    // MARK: - Usage and account endpoints (Bearer access_token)

    /// Subscription usage: returns the five_hour / seven_day utilizations, their reset times and extra_usage
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    /// Account info: returns account (email and so on) plus organization
    static let profileURL = "https://api.anthropic.com/api/oauth/profile"
    /// The beta header the OAuth endpoints require
    static let betaHeader = "oauth-2025-04-20"
    /// The User-Agent the OAuth usage and account endpoints require.
    /// This header is a hard requirement, not a courtesy: without it the endpoint returns an instant and
    /// persistent 429 rate_limit_error even with a perfectly valid access_token (see anthropics/claude-code#31021).
    static let userAgent = "claude-cli/2.0.0 (external, cli)"

    // MARK: - Local callback (preferred) / manual paste (fallback)

    /// Local callback port (loopback auto callback, tried first)
    ///
    /// It has to avoid macOS's ephemeral port range (49152-65535), otherwise a system outbound connection
    /// can claim the port dynamically and the login callback server fails to bind (especially after a restart, when system network activity is heavy).
    /// A fixed port from the registered range was chosen, kept clear of Codex's 1455/1457.
    static let primaryPort: UInt16 = 1456
    static let fallbackPort: UInt16 = 1458
    static let callbackPath = "/callback"

    /// Claude Code's official manual paste redirect (the fallback when the client does not accept localhost)
    static let manualRedirectURI = "https://console.anthropic.com/oauth/code/callback"

    /// Build the local redirect_uri
    static func redirectURI(port: UInt16) -> String {
        "http://localhost:\(port)\(callbackPath)"
    }
}
