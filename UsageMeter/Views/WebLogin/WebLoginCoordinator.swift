//
//  WebLoginCoordinator.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-02-06.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import Combine
import Foundation
import WebKit
import os

/// WKWebView management and cookie detection
/// Loads the claude.ai login page, watches the sessionKey cookie, validates it and creates the account
final class WebLoginCoordinator: ObservableObject {

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

    /// The domains navigation is allowed to
    private let allowedDomains: Set<String> = [
        "claude.ai",
        "google.com",
        "youtube.com",
        "appleid.apple.com",
        "login.microsoftonline.com",
        "github.com",
        "google.co.jp",
        "google.com.hk",
        "challenges.cloudflare.com"
    ]

    /// Safari 17.6 macOS User-Agent
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

        // Watch the loading progress
        progressObservation = webView.observe(\.estimatedProgress) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.loadProgress = webView.estimatedProgress
            }
        }

        self.webView = webView
    }

    // MARK: - Public Methods

    /// Load the login page
    func loadLoginPage() {
        guard let url = URL(string: "https://claude.ai/login") else { return }
        loginState = .loading
        webView.load(URLRequest(url: url))
    }

    /// Set the account creation callback
    func setOnAccountCreated(_ callback: @escaping (Account) -> Void) {
        self.onAccountCreated = callback
    }

    func cleanup() {
        cookieTimer?.invalidate()
        cookieTimer = nil
        progressObservation = nil
    }

    /// Copy the cookies of the given domain from the login WebView (nonPersistent) into the default store
    /// Syncs the session after a successful login, for use by the Level 2 silent refresh
    private func transferCookiesToDefaultStore(domains: [String]) {
        let sourceStore = webView.configuration.websiteDataStore.httpCookieStore
        let destStore = WKWebsiteDataStore.default().httpCookieStore
        sourceStore.getAllCookies { cookies in
            let relevant = cookies.filter { c in domains.contains { c.domain.contains($0) } }
            for cookie in relevant { destStore.setCookie(cookie) { } }
            Logger.settings.info("WebLogin: copied \(relevant.count) Claude cookies into the default store")
        }
    }

    // MARK: - Cookie Monitoring

    /// Start the cookie polling timer
    fileprivate func startCookieMonitoring() {
        cookieTimer?.invalidate()
        cookieTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForSessionKey()
        }
    }

    /// Check whether the cookies contain a sessionKey
    private func checkForSessionKey() {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }

            let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
            guard let sessionCookie = claudeCookies.first(where: { $0.name == "sessionKey" }) else { return }

            let sessionKey = sessionCookie.value
            // Assemble the WebView's full cookie set (cf_clearance and __cf_bm included) into a header,
            // so the validation request is not blocked for lack of the Cloudflare pass
            let cookieHeader = claudeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            Logger.settings.info("WebLogin: detected the sessionKey cookie")

            DispatchQueue.main.async {
                self.cookieTimer?.invalidate()
                self.cookieTimer = nil
                self.validateSessionKey(sessionKey, cookieHeader: cookieHeader)
            }
        }
    }

    // MARK: - Validation

    /// Validate the sessionKey and fetch the organization info
    private func validateSessionKey(_ sessionKey: String, cookieHeader: String) {
        loginState = .validating

        let apiService = ClaudeAPIService.shared
        apiService.fetchOrganizations(sessionKey: sessionKey, cookieHeader: cookieHeader) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success(let organizations):
                    if let firstOrg = organizations.first {
                        let account = Account(
                            sessionKey: sessionKey,
                            organizationId: firstOrg.uuid,
                            organizationName: firstOrg.name,
                            alias: nil
                        )

                        // Add the new account and switch to it
                        UserSettings.shared.addAccount(account)
                        UserSettings.shared.switchToAccount(account)

                        self.loginState = .success(accountName: account.displayName)
                        self.onAccountCreated?(account)
                        self.transferCookiesToDefaultStore(domains: ["claude.ai"])

                        Logger.settings.notice("WebLogin: account created - \(account.displayName)")
                    } else {
                        self.loginState = .failed(message: L.Error.noOrganizationsFound)
                    }

                case .failure(let error):
                    let message: String
                    if let usageError = error as? UsageError {
                        message = usageError.localizedDescription
                    } else {
                        message = error.localizedDescription
                    }
                    self.loginState = .failed(message: message)
                    Logger.settings.error("WebLogin: validation failed - \(message)")

                    // Start listening again after a failed validation
                    self.startCookieMonitoring()
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebLoginCoordinator {

    /// A separate NavigationDelegate class, to avoid the NSObject plus ObservableObject conflict
    final class NavigationDelegate: NSObject, WKNavigationDelegate {
        private weak var coordinator: WebLoginCoordinator?

        init(coordinator: WebLoginCoordinator) {
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
            // Once the page has loaded, start watching the cookies unless validation is already running
            if case .validating = coordinator.loginState { return }
            if case .success = coordinator.loginState { return }
            coordinator.loginState = .waitingForLogin
            coordinator.startCookieMonitoring()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Ignore a cancelled navigation
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

            // Check whether the domain is on the allow list
            let isAllowed = coordinator.allowedDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }

            if isAllowed {
                decisionHandler(.allow)
            } else {
                // Open a domain that is not allowed in the system browser
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }
    }
}

// MARK: - WKUIDelegate

extension WebLoginCoordinator {

    /// Handle popup windows the page opens through window.open()
    /// The classic Google OAuth flow authorizes in a popup, and without this delegate the login fails silently
    final class UIDelegate: NSObject, WKUIDelegate {
        private weak var coordinator: WebLoginCoordinator?

        init(coordinator: WebLoginCoordinator) {
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
