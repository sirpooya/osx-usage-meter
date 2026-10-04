//
//  CodexOAuthCoordinator.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-06-18.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import AppKit
import Combine
import Foundation
import OSLog

/// Codex OAuth login coordinator
///
/// Orchestrates the whole "Sign in with ChatGPT" flow:
///   1. Generate PKCE plus state
///   2. Start the local callback server (localhost:1455/1457)
///   3. Open the authorization page in the default browser (Google, Microsoft, enterprise SSO and passkeys all work in a real browser)
///   4. Receive the callback, validate state, exchange the code for a token
///   5. Parse the account info and store the refresh_token in the account system
///
/// Credential storage convention: the refresh_token goes into `Account.sessionKey` and `organizationId` holds the email
/// (sharing the same multi account system as older session-token accounts, with no structural change).
@MainActor
final class CodexOAuthCoordinator: ObservableObject {

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

    /// The overall timeout while the user has not finished signing in
    private let loginTimeout: TimeInterval = 5 * 60

    // MARK: - Public

    func start(onAccountCreated: ((Account) -> Void)? = nil) {
        self.onAccountCreated = onAccountCreated
        finished = false
        loginState = .starting

        let pkce = PKCECodes()
        self.pkce = pkce

        // Start the local callback server (trying 1455 then 1457)
        let ports = [CodexOAuthConfig.primaryPort, CodexOAuthConfig.fallbackPort]
        guard let port = server.start(ports: ports, onCallback: { [weak self] query in
            Task { @MainActor in self?.handleCallback(query) }
        }) else {
            fail(L.WebLogin.codexOAuthPortBusy)
            return
        }
        redirectURI = CodexOAuthConfig.redirectURI(port: port)

        guard let url = buildAuthorizeURL(pkce: pkce, redirectURI: redirectURI) else {
            fail(L.WebLogin.codexOAuthFailed)
            return
        }
        authorizeURL = url
        NSWorkspace.shared.open(url)
        loginState = .waitingForBrowser
        Logger.settings.notice("CodexOAuth: opened the system browser and is waiting for authorization (callback port \(port))")

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.loginTimeout ?? 300) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.failIfPending(L.WebLogin.codexOAuthTimeout)
        }
    }

    /// Reopen the authorization page when the user closes the browser tab by accident
    func reopenBrowser() {
        guard let url = authorizeURL, !finished else { return }
        NSWorkspace.shared.open(url)
    }

    func cancel() {
        cleanup()
    }

    // MARK: - Private

    private func buildAuthorizeURL(pkce: PKCECodes, redirectURI: String) -> URL? {
        var comps = URLComponents(string: CodexOAuthConfig.authorizeURL)
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: CodexOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: CodexOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "originator", value: CodexOAuthConfig.originator),
            URLQueryItem(name: "state", value: pkce.state)
        ]
        return comps?.url
    }

    private func handleCallback(_ query: [String: String]) {
        guard !finished else { return }

        // Validate state, for CSRF protection
        guard let returnedState = query["state"], returnedState == pkce?.state else {
            Logger.settings.error("CodexOAuth: state validation failed")
            fail(L.WebLogin.codexOAuthFailed)
            return
        }
        if let error = query["error"] {
            Logger.settings.error("CodexOAuth: the authorization server returned an error \(error)")
            fail(L.WebLogin.codexOAuthFailed)
            return
        }
        guard let code = query["code"], let verifier = pkce?.codeVerifier else {
            fail(L.WebLogin.codexOAuthFailed)
            return
        }

        loginState = .exchanging
        CodexOAuthService.exchangeCode(code: code, codeVerifier: verifier, redirectURI: redirectURI) { [weak self] result in
            Task { @MainActor in self?.handleTokens(result) }
        }
    }

    private func handleTokens(_ result: Result<CodexOAuthTokens, Error>) {
        guard !finished else { return }

        switch result {
        case .failure(let error):
            Logger.settings.error("CodexOAuth: token exchange failed \(error.localizedDescription)")
            fail(L.WebLogin.codexOAuthFailed)

        case .success(let tokens):
            guard !tokens.refreshToken.isEmpty else {
                Logger.settings.error("CodexOAuth: response is missing refresh_token")
                fail(L.WebLogin.codexOAuthFailed)
                return
            }
            let email = CodexOAuthService.email(fromIDToken: tokens.idToken) ?? ""
            let displayName = email.isEmpty ? "Codex" : email
            // organizationId uses the email as a stable dedupe identity (falling back to account_id when the email is missing)
            let account = Account(
                sessionKey: tokens.refreshToken,
                organizationId: email.isEmpty ? (tokens.accountId ?? "") : email,
                organizationName: displayName,
                alias: nil,
                provider: .codex
            )
            let stored = UserSettings.shared.addCodexAccount(account)
            UserSettings.shared.switchToCodexAccount(stored)

            loginState = .success(accountName: stored.displayName)
            onAccountCreated?(stored)
            Logger.settings.notice("CodexOAuth: account created - \(stored.displayName)")
            finishCleanup()
        }
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
