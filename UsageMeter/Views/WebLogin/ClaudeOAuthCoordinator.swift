//
//  ClaudeOAuthCoordinator.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-06-19.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import AppKit
import Combine
import Foundation
import OSLog

/// Claude OAuth login coordinator
///
/// Orchestrates the "Sign in with Claude" flow: browser authorization, localhost callback, code for token exchange,
/// profile fetch, then the refresh_token into the account. It fully sidesteps embedded WKWebView's limits on Google
/// and passkey logins (Issue #49).
///
/// Credential convention: the refresh_token (sk-ant-ort01-...) goes into `Account.sessionKey`, and
/// `organizationId` holds the organization uuid (the same dedupe identity as older cookie accounts, which eases migration).
@MainActor
final class ClaudeOAuthCoordinator: ObservableObject {

    enum LoginState: Equatable {
        case starting
        case waitingForBrowser
        case exchanging
        case success(accountName: String)
        case failed(message: String)
    }

    @Published private(set) var loginState: LoginState = .starting

    private let server = OAuthCallbackServer()
    private var pkce: PKCECodes?
    private var redirectURI = ""
    private var authorizeURL: URL?
    private var onAccountCreated: ((Account) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    private let loginTimeout: TimeInterval = 5 * 60

    // MARK: - Public

    func start(onAccountCreated: ((Account) -> Void)? = nil) {
        self.onAccountCreated = onAccountCreated
        finished = false
        loginState = .starting

        let pkce = PKCECodes()
        self.pkce = pkce

        let ports = [ClaudeOAuthConfig.primaryPort, ClaudeOAuthConfig.fallbackPort]
        guard let port = server.start(ports: ports, onCallback: { [weak self] query in
            Task { @MainActor in self?.handleCallback(query) }
        }) else {
            fail(L.WebLogin.claudeOAuthPortBusy)
            return
        }
        redirectURI = ClaudeOAuthConfig.redirectURI(port: port)

        guard let url = buildAuthorizeURL(pkce: pkce, redirectURI: redirectURI) else {
            fail(L.WebLogin.codexOAuthFailed)
            return
        }
        authorizeURL = url
        NSWorkspace.shared.open(url)
        loginState = .waitingForBrowser
        Logger.settings.notice("ClaudeOAuth: opened the system browser and is waiting for authorization (callback port \(port))")

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.loginTimeout ?? 300) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.failIfPending(L.WebLogin.codexOAuthTimeout)
        }
    }

    func reopenBrowser() {
        guard let url = authorizeURL, !finished else { return }
        NSWorkspace.shared.open(url)
    }

    /// Manual fallback (Issue #68): takes the callback link the user pastes back from the browser address bar,
    /// parses the code and state out of it and follows exactly the same path as the automatic loopback callback
    /// (state validation included, exchanging the token with the same loopback redirect_uri, with no need to reopen the browser).
    /// For environments where the browser has already reached the localhost callback page but the local callback server never sees the request (some Chromium variants, for instance).
    /// - Returns: whether a code was parsed and the rest of the flow started; false means the pasted content held no usable code.
    @discardableResult
    func submitManualCallback(_ pasted: String) -> Bool {
        guard !finished else { return false }
        let query = Self.parseManualCallback(pasted)
        // handleCallback is called when there is a code or an error: the error case gives it an accurate failure reason,
        // and when there is neither (invalid pasted content) it returns false so the UI can inline a prompt to paste the full link again.
        guard query["code"] != nil || query["error"] != nil else {
            Logger.settings.error("ClaudeOAuth: no code could be parsed out of the pasted content")
            return false
        }
        Logger.settings.notice("ClaudeOAuth: completed sign in using the manually pasted callback link")
        handleCallback(query)
        return true
    }

    func cancel() {
        cleanup()
    }

    // MARK: - Private

    private func buildAuthorizeURL(pkce: PKCECodes, redirectURI: String) -> URL? {
        var comps = URLComponents(string: ClaudeOAuthConfig.authorizeURL)
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: ClaudeOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: ClaudeOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state)
        ]
        return comps?.url
    }

    /// Parse the OAuth callback parameters (code and state) out of what the user pasted.
    /// Three shapes are accepted: a full callback URL (with ?code=...&state=...), `code#state`, and a bare code.
    static func parseManualCallback(_ raw: String) -> [String: String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [:] }

        // 1) A URL with a query: always parse the query (code / state / error, with queryItems already percent decoded),
        //    so the whole URL is not mistaken for the code (when consent is denied, for instance, the callback carries an error and no code).
        if let items = URLComponents(string: text)?.queryItems, !items.isEmpty {
            var result: [String: String] = [:]
            for key in ["code", "state", "error"] {
                if let value = items.first(where: { $0.name == key })?.value, !value.isEmpty {
                    result[key] = value
                }
            }
            return result
        }

        // 2) The `code#state` shape
        if text.contains("#"), !text.contains("?"), !text.contains("/") {
            let parts = text.split(separator: "#", maxSplits: 1).map(String.init)
            var result = ["code": parts[0]]
            if parts.count > 1, !parts[1].isEmpty { result["state"] = parts[1] }
            return result
        }

        // 3) A bare code (no state; handleCallback's state validation catches it and prompts for the full link)
        return ["code": text]
    }

    private func handleCallback(_ query: [String: String]) {
        guard !finished else { return }

        guard let returnedState = query["state"], returnedState == pkce?.state else {
            Logger.settings.error("ClaudeOAuth: state validation failed")
            fail(L.WebLogin.codexOAuthFailed)
            return
        }
        if let error = query["error"] {
            Logger.settings.error("ClaudeOAuth: the authorization server returned an error \(error)")
            fail(L.WebLogin.codexOAuthFailed)
            return
        }
        guard let code = query["code"], let pkce = pkce else {
            fail(L.WebLogin.codexOAuthFailed)
            return
        }

        loginState = .exchanging
        ClaudeOAuthService.exchangeCode(
            code: code,
            state: returnedState,
            codeVerifier: pkce.codeVerifier,
            redirectURI: redirectURI
        ) { [weak self] result in
            Task { @MainActor in self?.handleTokens(result) }
        }
    }

    private func handleTokens(_ result: Result<ClaudeOAuthTokens, Error>) {
        guard !finished else { return }

        switch result {
        case .failure(let error):
            Logger.settings.error("ClaudeOAuth: token exchange failed \(error.localizedDescription)")
            fail(L.WebLogin.codexOAuthFailed)

        case .success(let tokens):
            guard !tokens.refreshToken.isEmpty else {
                Logger.settings.error("ClaudeOAuth: response is missing refresh_token")
                fail(L.WebLogin.codexOAuthFailed)
                return
            }
            // Fetch the profile to complete the account info (email, organization uuid); a failure does not block the login
            ClaudeOAuthService.fetchProfile(accessToken: tokens.accessToken) { [weak self] profile in
                Task { @MainActor in self?.createAccount(tokens: tokens, profile: profile) }
            }
        }
    }

    private func createAccount(tokens: ClaudeOAuthTokens, profile: Result<(email: String, orgId: String, orgName: String, tier: String, rateLimitTier: String), Error>) {
        guard !finished else { return }

        var email = ""
        var orgId = ""
        if case .success(let p) = profile {
            email = p.email
            orgId = p.orgId
            // Tier for the popover title; a browser login has no Keychain entry to fall back on
            if !p.tier.isEmpty {
                UserSettings.shared.claudeSubscriptionTier = p.tier
            }
            if !p.rateLimitTier.isEmpty {
                UserSettings.shared.claudeRateLimitTier = p.rateLimitTier
            }
        }
        let displayName = email.isEmpty ? "Claude" : email
        // organizationId holds the organization uuid (falling back to the email), the same dedupe identity as older cookie accounts
        let stableOrgId = orgId.isEmpty ? email : orgId

        // Migration: addAccount skips an organizationId that already exists, so remove the old account with the same identity before adding
        if !stableOrgId.isEmpty,
           let existing = UserSettings.shared.accounts.first(where: { $0.organizationId == stableOrgId }) {
            UserSettings.shared.removeAccount(existing)
        }

        let account = Account(
            sessionKey: tokens.refreshToken,
            organizationId: stableOrgId,
            organizationName: displayName,
            alias: nil,
            provider: .claude
        )
        UserSettings.shared.addAccount(account)
        UserSettings.shared.switchToAccount(account)

        loginState = .success(accountName: account.displayName)
        onAccountCreated?(account)
        Logger.settings.notice("ClaudeOAuth: account created - \(account.displayName)")
        finishCleanup()
    }

    private func fail(_ message: String) {
        loginState = .failed(message: message)
        finishCleanup()
    }

    private func failIfPending(_ message: String) {
        guard !finished else { return }
        fail(message)
    }

    private func finishCleanup() {
        finished = true
        cleanup()
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        server.stop()
    }
}
