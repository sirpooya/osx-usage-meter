//
//  CodexOAuthConfig.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-06-18.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import Foundation

/// Codex (ChatGPT) OAuth configuration constants
///
/// Reuses OpenAI's official Codex CLI public OAuth client (PKCE, no client secret).
/// These constants come from the openai/codex source at `codex-rs/login` and are the official "Sign in with ChatGPT" flow,
/// which authenticates in the user's default browser and so is unaffected by WKWebView's block on Google's embedded login,
/// and by WebAuthn and passkeys not working in an embedded WebView.
enum CodexOAuthConfig {
    /// Authorization service issuer
    static let issuer = "https://auth.openai.com"
    /// Authorization endpoint
    static let authorizeURL = "\(issuer)/oauth/authorize"
    /// token / refresh endpoint (the code exchange and the refresh share it)
    static let tokenURL = "\(issuer)/oauth/token"

    /// Codex CLI's official public client id (PKCE, no client secret)
    /// Note: OpenAI registered only fixed localhost callbacks for this client, so redirect_uri has to use the ports below
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    /// OAuth scope (the same as the official Codex CLI)
    static let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"

    /// Local callback ports (the same as the official client; OpenAI registered only these two localhost callbacks for it)
    static let primaryPort: UInt16 = 1455
    static let fallbackPort: UInt16 = 1457
    /// Callback path
    static let callbackPath = "/auth/callback"

    /// The originator identifier (the same as the official Codex CLI, which lowers the odds the auth service flags it)
    static let originator = "codex_cli_rs"

    /// Build the local redirect_uri
    static func redirectURI(port: UInt16) -> String {
        "http://localhost:\(port)\(callbackPath)"
    }
}
