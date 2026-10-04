//
//  CodexWebLoginCoordinator.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-04-24.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Combine
import Foundation
import WebKit
import os

/// Codex WebView management and cookie detection
/// Loads the chatgpt.com login page, watches the __Secure-next-auth.session-token cookie, validates it and creates the account
final class CodexWebLoginCoordinator: ObservableObject {

    // MARK: - Login State

    enum LoginState: Equatable {
        case loading
        case waitingForLogin
        case validating
        case success(accountName: String)
        case failed(message: String)
    }

    // MARK: - Published Properties

    @Published var loginState: LoginState = .loading
    @Published var loadProgress: Double = 0

    // MARK: - Properties

    private(set) var webView: WKWebView!
    private var cookieTimer: Timer?
    private var progressObservation: NSKeyValueObservation?
    private var onAccountCreated: ((Account) -> Void)?
    private var navigationDelegate: NavigationDelegate?
    private var uiDelegate: UIDelegate?

    private let apiService = CodexAPIService()

    /// The domains navigation is allowed to (ChatGPT's SSO domains included)
    private let allowedDomains: Set<String> = [
        "chatgpt.com",
        "openai.com",
        "auth.openai.com",
        "auth0.openai.com",
        "google.com",
        "youtube.com",
        "appleid.apple.com",
        "login.microsoftonline.com",
        "github.com",
        "google.co.jp",
        "google.com.hk",
        "challenges.cloudflare.com"
    ]

    private let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    // MARK: - Init

    init() {
        setupWebView()
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // nonPersistent: completely blank, no OAuth provider has an existing session, which keeps auto SSO from firing when adding multiple accounts
        config.websiteDataStore = .nonPersistent()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = safariUserAgent
        webView.allowsBackForwardNavigationGestures = true

        let delegate = NavigationDelegate(coordinator: self)
        webView.navigationDelegate = delegate
        self.navigationDelegate = delegate

        let ui = UIDelegate(coordinator: self)
        webView.uiDelegate = ui
        self.uiDelegate = ui

        progressObservation = webView.observe(\.estimatedProgress) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.loadProgress = webView.estimatedProgress
            }
        }

        self.webView = webView
    }

    // MARK: - Public Methods

    func loadLoginPage() {
        guard let url = URL(string: "https://chatgpt.com/auth/login") else { return }
        loginState = .loading
        webView.load(URLRequest(url: url))
    }

    func setOnAccountCreated(_ callback: @escaping (Account) -> Void) {
        self.onAccountCreated = callback
    }

    func cleanup() {
        cookieTimer?.invalidate()
        cookieTimer = nil
        progressObservation = nil
    }

    /// Copy the chatgpt.com and openai.com cookies from the login WebView (nonPersistent) into the default store
    /// Syncs the session after a successful login, for use by the Level 2 silent refresh
    private func transferCookiesToDefaultStore() {
        let sourceStore = webView.configuration.websiteDataStore.httpCookieStore
        let destStore = WKWebsiteDataStore.default().httpCookieStore
        sourceStore.getAllCookies { cookies in
            let relevant = cookies.filter { c in
                c.domain.contains("chatgpt.com") || c.domain.contains("openai.com")
            }
            for cookie in relevant { destStore.setCookie(cookie) { } }
            Logger.settings.info("CodexWebLogin: copied \(relevant.count) cookies into the default store")
        }
    }

    // MARK: - Cookie Monitoring

    fileprivate func startCookieMonitoring() {
        cookieTimer?.invalidate()
        cookieTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForSessionToken()
        }
    }

    private func checkForSessionToken() {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }

            let chatgptCookies = cookies.filter { $0.domain.contains("chatgpt.com") }
            guard let sessionToken = Self.extractSessionToken(from: chatgptCookies) else { return }

            let cookieHeader = chatgptCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            Logger.settings.info("CodexWebLogin: detected the session-token cookie")

            DispatchQueue.main.async {
                self.cookieTimer?.invalidate()
                self.cookieTimer = nil
                self.validateSessionToken(sessionToken, cookieHeader: cookieHeader)
            }
        }
    }

    /// Extract the session token value from the chatgpt.com cookie list
    /// Handles the standard name, the version without the __Secure- prefix, and next-auth's sharded cookies (.0/.1/...)
    static func extractSessionToken(from cookies: [HTTPCookie]) -> String? {
        let baseNames = ["__Secure-next-auth.session-token", "next-auth.session-token"]

        for baseName in baseNames {
            if let cookie = cookies.first(where: { $0.name == baseName }) {
                return cookie.value
            }
            let chunks = cookies
                .filter { cookie in
                    guard cookie.name.hasPrefix(baseName + ".") else { return false }
                    let suffix = cookie.name.dropFirst(baseName.count + 1)
                    return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
                }
                .sorted {
                    let ia = Int($0.name.dropFirst(baseName.count + 1)) ?? 0
                    let ib = Int($1.name.dropFirst(baseName.count + 1)) ?? 0
                    return ia < ib
                }
            if !chunks.isEmpty {
                return chunks.map(\.value).joined()
            }
        }
        return nil
    }

    // MARK: - Validation

    private func validateSessionToken(_ sessionToken: String, cookieHeader: String) {
        loginState = .validating

        apiService.validateSessionToken(sessionToken, cookieHeader: cookieHeader) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let info):
                let account = Account(
                    sessionKey: sessionToken,
                    organizationId: info.email,
                    organizationName: info.displayName,
                    alias: nil,
                    provider: .codex
                )

                let storedAccount = UserSettings.shared.addCodexAccount(account)
                UserSettings.shared.switchToCodexAccount(storedAccount)

                self.loginState = .success(accountName: storedAccount.displayName)
                self.onAccountCreated?(storedAccount)
                self.transferCookiesToDefaultStore()

                Logger.settings.notice("CodexWebLogin: account created - \(storedAccount.displayName)")

            case .failure(let error):
                self.loginState = .failed(message: error.localizedDescription)
                Logger.settings.error("CodexWebLogin: validation failed - \(error.localizedDescription)")

                // Start listening again after a failed validation
                self.startCookieMonitoring()
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension CodexWebLoginCoordinator {

    final class NavigationDelegate: NSObject, WKNavigationDelegate {
        private weak var coordinator: CodexWebLoginCoordinator?

        init(coordinator: CodexWebLoginCoordinator) {
            self.coordinator = coordinator
            super.init()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard let coordinator = coordinator else { return }
            if coordinator.loginState != .validating {
                coordinator.loginState = .loading
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let coordinator = coordinator else { return }
            if case .validating = coordinator.loginState { return }
            if case .success = coordinator.loginState { return }
            coordinator.loginState = .waitingForLogin

            // Only start polling for the cookie after a redirect to a non authentication page on chatgpt.com
            // which means the user finished the OAuth flow and was sent back to the home page
            // This avoids picking up a stale session-token a background WebView wrote while still on the auth/login page
            if let host = webView.url?.host, host.hasSuffix("chatgpt.com"),
               let path = webView.url?.path, !path.hasPrefix("/auth") {
                coordinator.startCookieMonitoring()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            coordinator?.loginState = .failed(message: error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let coordinator = coordinator,
                  let url = navigationAction.request.url,
                  let host = url.host?.lowercased() else {
                decisionHandler(.allow)
                return
            }

            let isAllowed = coordinator.allowedDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }

            if isAllowed {
                decisionHandler(.allow)
            } else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }
    }
}

// MARK: - WKUIDelegate

extension CodexWebLoginCoordinator {

    /// Handle popup windows the page opens through window.open()
    /// The classic Google OAuth flow authorizes in a popup, and without this delegate the login fails silently
    final class UIDelegate: NSObject, WKUIDelegate {
        private weak var coordinator: CodexWebLoginCoordinator?

        init(coordinator: CodexWebLoginCoordinator) {
            self.coordinator = coordinator
            super.init()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            webView.load(navigationAction.request)
            return nil
        }
    }
}
