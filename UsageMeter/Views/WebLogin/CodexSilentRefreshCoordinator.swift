//
//  CodexSilentRefreshCoordinator.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-06-05.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import WebKit
import OSLog

/// Codex hidden WebView silent renewal coordinator (the level 2 fallback)
///
/// How it works: WKWebsiteDataStore.default() (a process wide singleton) backs a hidden WKWebView that never joins
/// the view hierarchy and loads chatgpt.com. WebKit automatically sends every cookie the process already has (Cloudflare's
/// cf_clearance and __cf_bm included), the server performs the NextAuth OAuth refresh and issues the renewed
/// session-token through Set-Cookie, which WebKit stores in the shared data store.
/// Once loading finishes, the new session-token is read from the cookie store and written back to the Keychain silently.
///
/// When it applies: the fallback path after a failed level 1 SSR refresh. It is more reliable than the URLSession path,
/// because WebKit uses real browser level cookies and TLS fingerprints and gets past Cloudflare more often.
@MainActor
final class CodexSilentRefreshCoordinator: NSObject {

    static let shared = CodexSilentRefreshCoordinator()

    private(set) var isRefreshing = false

    private var webView: WKWebView?
    private var navigationDelegate: NavigationDelegate?
    private var timeoutTask: Task<Void, Never>?
    private var completion: ((Result<String, Error>) -> Void)?

    private let timeoutInterval: TimeInterval = 25
    private let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    private override init() {}

    // MARK: - Public

    /// Trigger the silent refresh. On success Result.success carries the latest session-token string.
    func refresh(completion: @escaping (Result<String, Error>) -> Void) {
        guard !isRefreshing else {
            Logger.settings.debug("CodexSilentRefresh: a refresh is already in progress, skipping")
            completion(.failure(UsageError.networkError))
            return
        }

        let sessionToken = UserSettings.shared.codexSessionToken
        guard !sessionToken.isEmpty else {
            completion(.failure(UsageError.noCredentials))
            return
        }

        isRefreshing = true
        self.completion = completion

        // Use the process wide shared data store, sharing cookies with the login window's WKWebView
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = safariUserAgent
        // Never joins any view hierarchy, it exists only to load in the background

        let delegate = NavigationDelegate(coordinator: self)
        wv.navigationDelegate = delegate
        self.navigationDelegate = delegate
        self.webView = wv

        // Timeout protection
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.timeoutInterval ?? 25) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self, self.isRefreshing else { return }
            Logger.settings.error("CodexSilentRefresh: timed out (\(self.timeoutInterval)s), giving up")
            self.finish(result: .failure(UsageError.networkError))
        }

        guard let url = URL(string: "https://chatgpt.com") else {
            finish(result: .failure(UsageError.invalidURL))
            return
        }

        // Reset the default() store's session-token before renewing:
        // 1. Delete every leftover (other accounts and old .0/.1 shards included)
        // 2. Inject the current account's full session-token
        // 3. Only load once all of that is done, so the server sees the right account's session
        let cookieStore = wv.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
            let toDelete = cookies.filter { c in
                (c.domain.contains("chatgpt.com") || c.domain.contains("openai.com")) &&
                c.name.contains("session-token")
            }
            Logger.settings.debug("CodexSilentRefresh: cleared \(toDelete.count) old session-token entries")

            let group = DispatchGroup()
            for cookie in toDelete {
                group.enter()
                cookieStore.delete(cookie) { group.leave() }
            }

            group.notify(queue: .main) {
                let baseName = "__Secure-next-auth.session-token"
                // WebKit caps a single cookie at about 4KB, and NextAuth shards past that into .0/.1/.2...
                // The injection shards the same way, matching how extractSessionToken reads it
                let chunkSize = 4000
                // originURL (HTTPS) is required for a __Secure- prefixed cookie to validate
                let origin = URL(string: "https://chatgpt.com")!

                let tokenChunks = stride(from: 0, to: sessionToken.count, by: chunkSize).map { start -> String in
                    let from = sessionToken.index(sessionToken.startIndex, offsetBy: start)
                    let to = sessionToken.index(from, offsetBy: min(chunkSize, sessionToken.count - start))
                    return String(sessionToken[from..<to])
                }

                let shards: [(name: String, value: String)]
                if tokenChunks.count == 1 {
                    shards = [(baseName, tokenChunks[0])]
                } else {
                    shards = tokenChunks.enumerated().map { ("\(baseName).\($0.offset)", $0.element) }
                    Logger.settings.debug("CodexSilentRefresh: token exceeds the size limit, injecting it in \(shards.count) shards")
                }

                let cookies = shards.compactMap { name, value in
                    HTTPCookie(properties: [
                        .name: name,
                        .value: value,
                        .originURL: origin,
                        .path: "/",
                        .secure: "TRUE"
                    ])
                }

                guard !cookies.isEmpty else {
                    Logger.settings.warning("CodexSilentRefresh: could not build the session-token cookie, loading directly")
                    wv.load(URLRequest(url: url))
                    return
                }

                let injectGroup = DispatchGroup()
                for cookie in cookies {
                    injectGroup.enter()
                    cookieStore.setCookie(cookie) { injectGroup.leave() }
                }
                injectGroup.notify(queue: .main) {
                    Logger.settings.info("CodexSilentRefresh: injected \(cookies.count) cookies, loading chatgpt.com")
                    wv.load(URLRequest(url: url))
                }
            }
        }
    }

    // MARK: - Navigation Callbacks (called by NavigationDelegate)

    fileprivate func didFinishNavigation() {
        webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }

            let chatgptCookies = cookies.filter { $0.domain.contains("chatgpt.com") }
            Logger.settings.debug("CodexSilentRefresh: load finished, chatgpt.com cookie count: \(chatgptCookies.count)")

            guard let newToken = CodexWebLoginCoordinator.extractSessionToken(from: chatgptCookies) else {
                Logger.settings.error("CodexSilentRefresh: no session-token found in the cookies, silent refresh failed")
                self.finish(result: .failure(UsageError.sessionExpired))
                return
            }

            let currentToken = UserSettings.shared.codexSessionToken
            if newToken != currentToken {
                Logger.settings.notice("CodexSilentRefresh: got a new session-token, written back to the keychain silently")
                UserSettings.shared.silentlyUpdateCurrentCodexSessionToken(newToken)
            } else {
                Logger.settings.info("CodexSilentRefresh: session-token unchanged (the server did not renew it)")
            }

            self.finish(result: .success(newToken))
        }
    }

    fileprivate func didDetectCloudflareChallenge() {
        Logger.settings.error("CodexSilentRefresh: hit a Cloudflare challenge, silent refresh cannot continue")
        finish(result: .failure(UsageError.cloudflareBlocked))
    }

    fileprivate func didFailNavigation(error: Error) {
        Logger.settings.error("CodexSilentRefresh: navigation failed - \(error.localizedDescription)")
        finish(result: .failure(error))
    }

    // MARK: - Private

    private func finish(result: Result<String, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        isRefreshing = false
        webView?.navigationDelegate = nil
        webView = nil
        navigationDelegate = nil
        let cb = completion
        completion = nil
        cb?(result)
    }
}

// MARK: - WKNavigationDelegate

extension CodexSilentRefreshCoordinator {

    final class NavigationDelegate: NSObject, WKNavigationDelegate {
        private weak var coordinator: CodexSilentRefreshCoordinator?

        init(coordinator: CodexSilentRefreshCoordinator) {
            self.coordinator = coordinator
            super.init()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Read the page title with JS, to detect a Cloudflare interactive challenge page
            webView.evaluateJavaScript("document.title") { [weak self] result, _ in
                let title = result as? String ?? ""
                if title.contains("Just a moment") || title.contains("Attention Required") || title.contains("cf-browser-verification") {
                    self?.coordinator?.didDetectCloudflareChallenge()
                } else {
                    self?.coordinator?.didFinishNavigation()
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            coordinator?.didFailNavigation(error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            coordinator?.didFailNavigation(error: error)
        }
    }
}
