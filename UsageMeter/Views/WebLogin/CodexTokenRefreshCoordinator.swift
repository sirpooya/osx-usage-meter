//
//  CodexTokenRefreshCoordinator.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-05-13.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// Codex session token silent refresh coordinator
/// GETs chatgpt.com through URLSession to trigger the server side SSR OAuth refresh,
/// then reads the freshly generated accessToken out of the client-bootstrap JSON.
///
/// Why SSR rather than /api/auth/session:
///   - GET /api/auth/session only returns the accessToken cached in the JWE, it triggers no OAuth refresh
///   - during SSR the server middleware checks whether the accessToken expired and refreshes it with the refresh token inside the JWE
///   - success condition: the OAuth refresh token inside the JWE has not expired yet (it normally outlives the accessToken)
@MainActor
final class CodexTokenRefreshCoordinator: NSObject {

    static let shared = CodexTokenRefreshCoordinator()

    private(set) var isRefreshing = false

    private var dataTask: URLSessionDataTask?
    private var urlSession: URLSession?
    private var completion: ((Result<String, Error>) -> Void)?

    private override init() {}

    // MARK: - Public

    /// Refresh the accessToken. On success Result.success carries the fresh accessToken string.
    func refresh(completion: @escaping (Result<String, Error>) -> Void) {
        guard !isRefreshing else {
            Logger.settings.debug("CodexTokenRefresh: a refresh is already in progress, skipping")
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

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: config)

        guard let url = URL(string: "https://chatgpt.com") else {
            finish(result: .failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false
        // Use the same headers as the /api/auth/session endpoint (proven to get past Cloudflare)
        let sessionHeaders = CodexAPIHeaderBuilder.buildSessionHeaders(sessionToken: sessionToken)
        for (key, value) in sessionHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // Override the fetch mode fields for an HTML page
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "accept")
        request.setValue("navigate", forHTTPHeaderField: "sec-fetch-mode")
        request.setValue("document", forHTTPHeaderField: "sec-fetch-dest")

        Logger.settings.info("CodexTokenRefresh: URLSession GET chatgpt.com to trigger the SSR OAuth refresh")

        let task = urlSession?.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error = error {
                Logger.settings.error("CodexTokenRefresh: request failed - \(error.localizedDescription)")
                DispatchQueue.main.async { self.finish(result: .failure(error)) }
                return
            }

            if let http = response as? HTTPURLResponse {
                Logger.settings.debug("CodexTokenRefresh: HTTP \(http.statusCode)")
                // Phase 0 diagnostics: log the Set-Cookie response header, to confirm whether the server renewed the session-token
                let setCookieHeaders = http.allHeaderFields
                    .filter { ($0.key as? String)?.lowercased() == "set-cookie" }
                    .compactMap { $0.value as? String }
                Logger.settings.debug("CodexTokenRefresh: Set-Cookie response header count=\(setCookieHeaders.count)")
                for cookieStr in setCookieHeaders {
                    let isSessionToken = cookieStr.contains("next-auth.session-token")
                    Logger.settings.info("CodexTokenRefresh: Set-Cookie [\(isSessionToken ? "SESSION-TOKEN" : "other")] \(cookieStr.prefix(80))")
                }

                guard (200...299).contains(http.statusCode) else {
                    let err: Error = http.statusCode == 403
                        ? UsageError.cloudflareBlocked
                        : UsageError.httpError(statusCode: http.statusCode)
                    DispatchQueue.main.async { self.finish(result: .failure(err)) }
                    return
                }
            }

            // Level 1: check whether HTTPCookieStorage received a new session-token
            let chatgptURL = URL(string: "https://chatgpt.com")!
            let storedCookies = HTTPCookieStorage.shared.cookies(for: chatgptURL) ?? []
            if let newToken = CodexWebLoginCoordinator.extractSessionToken(from: storedCookies) {
                let currentToken = UserSettings.shared.codexSessionToken
                if newToken != currentToken {
                    Logger.settings.notice("CodexTokenRefresh: URLSession detected a new session-token, written back silently")
                    DispatchQueue.main.async {
                        UserSettings.shared.silentlyUpdateCurrentCodexSessionToken(newToken)
                    }
                } else {
                    Logger.settings.debug("CodexTokenRefresh: session-token unchanged")
                }
            }

            guard let data,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                Logger.settings.error("CodexTokenRefresh: the response could not be decoded")
                DispatchQueue.main.async { self.finish(result: .failure(UsageError.noData)) }
                return
            }

            Logger.settings.debug("CodexTokenRefresh: received an HTML response of \(html.count) bytes")

            if html.contains("Just a moment") || html.contains("cf-browser-verification") {
                Logger.settings.error("CodexTokenRefresh: Cloudflare challenge page")
                DispatchQueue.main.async { self.finish(result: .failure(UsageError.cloudflareBlocked)) }
                return
            }

            let result = Self.extractBootstrapAccessToken(from: html)
            DispatchQueue.main.async { self.finish(result: result) }
        }
        dataTask = task
        task?.resume()
    }

    // MARK: - Private

    private static func extractBootstrapAccessToken(from html: String) -> Result<String, Error> {
        guard let idRange = html.range(of: "id=\"client-bootstrap\"") else {
            Logger.settings.error("CodexTokenRefresh: no client-bootstrap element found in the HTML")
            return .failure(UsageError.sessionExpired)
        }

        guard let gtRange = html.range(of: ">", range: idRange.upperBound..<html.endIndex),
              let jsonStart = html.range(of: "{", range: gtRange.upperBound..<html.endIndex) else {
            Logger.settings.error("CodexTokenRefresh: could not locate the start of the client-bootstrap JSON")
            return .failure(UsageError.sessionExpired)
        }

        guard let scriptEnd = html.range(of: "</script>", range: jsonStart.lowerBound..<html.endIndex) else {
            Logger.settings.error("CodexTokenRefresh: could not locate the client-bootstrap closing tag")
            return .failure(UsageError.sessionExpired)
        }

        let jsonString = String(html[jsonStart.lowerBound..<scriptEnd.lowerBound])

        guard let jsonData = jsonString.data(using: .utf8),
              let bootstrap = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            Logger.settings.error("CodexTokenRefresh: client-bootstrap JSON parse failed")
            return .failure(UsageError.decodingError)
        }

        let authStatus = bootstrap["authStatus"] as? String ?? "unknown"
        guard let session = bootstrap["session"] as? [String: Any],
              let accessToken = session["accessToken"] as? String,
              !accessToken.isEmpty else {
            Logger.settings.error("CodexTokenRefresh: bootstrap has no accessToken (authStatus=\(authStatus))")
            return .failure(UsageError.sessionExpired)
        }

        if let exp = jwtExpiry(from: accessToken), exp < Date() {
            Logger.settings.error("CodexTokenRefresh: bootstrap accessToken is still expired exp=\(exp)")
            return .failure(UsageError.sessionExpired)
        }

        Logger.settings.info("CodexTokenRefresh: SSR returned a fresh accessToken (authStatus=\(authStatus))")
        return .success(accessToken)
    }

    private func finish(result: Result<String, Error>) {
        isRefreshing = false
        dataTask = nil
        urlSession = nil
        let cb = completion
        completion = nil
        cb?(result)
    }
}
