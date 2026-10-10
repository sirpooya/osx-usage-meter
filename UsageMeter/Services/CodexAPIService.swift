//
//  CodexAPIService.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-04-24.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// Codex API service
/// The two step authentication flow:
///   1. GET /api/auth/session (with the session-token cookie) returns the accessToken
///   2. GET /backend-api/wham/usage (with the Bearer token) returns the usage data
class CodexAPIService {

    // MARK: - Properties

    private let baseURL = "https://chatgpt.com"
    private let settings = UserSettings.shared
    private let session: URLSession

    /// The tasks in flight (at most two: session and usage)
    /// - Note: append happens on the main thread (when the session request starts) and on the URLSession callback thread
    ///   (when the usage request starts, triggered by fetchAccessToken's completion), while cancelAllRequests clears it on the main thread,
    ///   so the concurrent access needs tasksLock (see trackTask and cancelAllRequests).
    private var activeTasks: [URLSessionDataTask] = []

    /// The lock protecting activeTasks
    private let tasksLock = NSLock()

    // MARK: - Access Token Cache

    /// Proactive refresh window: refetch once expiry is less than 20 minutes away
    /// Set to the longest refresh interval (15min) plus a 5min buffer, so any interval refreshes proactively rather than leaning on the three level chain
    private static let tokenRefreshMargin: TimeInterval = 20 * 60

    /// access_token caching plus single flight coalescing (an actor, see Services/OAuthTokenCache.swift; audit report 4.2).
    /// Shared by the cookie session path and the OAuth refresh path: the cache key is the account credential
    /// (a session-token, or an OAuth refresh_token with the "rt." prefix), so the two cannot cross talk.
    private let tokenCache = OAuthTokenCache()

    /// Record an in flight task in a thread safe way, so cancelAllRequests can cancel them all
    private func trackTask(_ task: URLSessionDataTask) {
        tasksLock.lock()
        activeTasks.append(task)
        tasksLock.unlock()
    }

    /// Clear the cache on an account switch, so the next fetch starts fresh
    /// - Note: takes effect asynchronously. The 401 path clears the cache inside fetchWhamUsage (guaranteeing it happens before the error propagates),
    ///   while an account switch relies on the cache being keyed by credential: the old account's cache cannot be matched by the new account's credential.
    func clearAccessTokenCache() {
        Task { await tokenCache.clear() }
    }

    /// Called by its own timer: renews proactively only when the cache is about to expire, without triggering a usage fetch.
    /// fetchAccessToken checks the cache first (with a 20 minute margin) and makes no network request while it is still fresh.
    func proactivelyRefreshIfNeeded() {
        guard settings.hasValidCodexCredentials else { return }
        fetchAccessToken(sessionToken: settings.codexSessionToken) { result in
            switch result {
            case .success:
                Logger.api.debug("Codex accessToken: proactive renewal check finished")
            case .failure(let error):
                Logger.api.warning("Codex accessToken: proactive renewal failed (\(error.localizedDescription)), will retry on the next usage fetch")
            }
        }
    }

    // MARK: - Initialization

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Public Methods

    /// Fetch Codex usage (two steps: session then usage)
    /// - Parameter completion: CodexUsageData on success, an Error on failure
    func fetchUsage(completion: @escaping (Result<CodexUsageData, Error>) -> Void) {
        #if DEBUG
        if settings.debugModeEnabled {
            let mockData = createMockData()
            DispatchQueue.main.async { completion(.success(mockData)) }
            return
        }
        #endif

        cancelAllRequests()

        guard settings.hasValidCodexCredentials else {
            completion(.failure(UsageError.noCredentials))
            return
        }

        let sessionToken = settings.codexSessionToken

        // fetchAccessToken's completion already guarantees a main thread callback
        fetchAccessToken(sessionToken: sessionToken) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                completion(.failure(error))

            case .success(let accessToken):
                self.fetchWhamUsage(accessToken: accessToken) { usageResult in
                    DispatchQueue.main.async { completion(usageResult) }
                }
            }
        }
    }

    // MARK: - Private: Step 1, credential to accessToken

    /// Decide whether an account credential is an OAuth refresh_token (the OpenAI format starts with "rt.")
    /// An older session-token is a next-auth encrypted string and never matches this prefix
    static func isOAuthRefreshToken(_ credential: String) -> Bool {
        credential.hasPrefix("rt.")
    }

    /// Step one: trade the account credential for an accessToken
    /// - cookie account: GET /api/auth/session (with the session-token cookie)
    /// - OAuth account (the "rt." prefix): exchange the refresh_token at auth.openai.com
    ///
    /// A valid cache (more than 20 minutes from expiry) skips the network request; concurrent calls with the same credential
    /// are coalesced by OAuthTokenCache into a single network request. The completion always fires on the main thread.
    private func fetchAccessToken(sessionToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let accessToken = try await tokenCache.accessToken(
                    refreshToken: sessionToken,
                    margin: Self.tokenRefreshMargin
                ) { [weak self] credential in
                    guard let self else { throw UsageError.networkError }
                    if Self.isOAuthRefreshToken(credential) {
                        return try await self.refreshOAuthTokens(refreshToken: credential)
                    }
                    return try await self.fetchSessionTokens(sessionToken: credential)
                }
                await MainActor.run { completion(.success(accessToken)) }
            } catch {
                // Fallback on a failed refresh: while the old token has not really expired (even inside the early refresh window) it carries one more round,
                // so a brief network blip or server hiccup does not break the usage fetch. Credential failures do not fall back:
                // a 401 has to propagate so the three level refresh chain or the sign in prompt fires.
                switch error {
                case UsageError.unauthorized, UsageError.sessionExpired:
                    break
                default:
                    if let fallback = await tokenCache.validCachedToken(refreshToken: sessionToken) {
                        Logger.api.warning("Codex token refresh failed (\(error.localizedDescription)), falling back to the unexpired cached token")
                        await MainActor.run { completion(.success(fallback)) }
                        return
                    }
                }
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// cookie account: call /api/auth/session for an accessToken, returning the shared Tokens triple.
    /// When the response rotates the session-token through Set-Cookie, write it back to the account store silently and return the new value
    /// as refreshToken, so the cache key follows the new credential and the next query with the new session-token hits it.
    private func fetchSessionTokens(sessionToken: String) async throws -> OAuthTokenCache.Tokens {
        guard let url = URL(string: "\(baseURL)/api/auth/session") else {
            throw UsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false
        CodexAPIHeaderBuilder.applySessionHeaders(to: &request, sessionToken: sessionToken)

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                let result: Result<OAuthTokenCache.Tokens, Error> = {
                    if let error {
                        Logger.api.debug("Codex session error: \(error.localizedDescription)")
                        return .failure(UsageError.networkError)
                    }
                    guard let data else { return .failure(UsageError.noData) }

                    Logger.api.debug("Codex session response received: \(data.count) bytes")
                    if let jsonString = String(data: data, encoding: .utf8),
                       jsonString.contains("<!DOCTYPE html>") || jsonString.contains("<html") {
                        return .failure(UsageError.cloudflareBlocked)
                    }

                    if let httpResponse = response as? HTTPURLResponse {
                        Logger.api.debug("Codex session HTTP status: \(httpResponse.statusCode)")
                        // Phase 0 diagnostics: check whether /api/auth/session issues a new session-token
                        let setCookieHeaders = httpResponse.allHeaderFields
                            .filter { ($0.key as? String)?.lowercased() == "set-cookie" }
                            .compactMap { $0.value as? String }
                        Logger.api.debug("Codex session Set-Cookie count=\(setCookieHeaders.count)")
                        for cookieStr in setCookieHeaders where cookieStr.contains("next-auth.session-token") {
                            Logger.api.info("Codex session Set-Cookie [SESSION-TOKEN] \(cookieStr.prefix(80))")
                        }

                        switch httpResponse.statusCode {
                        case 200...299: break
                        case 401: return .failure(UsageError.unauthorized)
                        case 403: return .failure(UsageError.cloudflareBlocked)
                        case 429: return .failure(UsageError.rateLimited)
                        default:
                            return .failure(UsageError.httpError(statusCode: httpResponse.statusCode))
                        }
                    }

                    // Check whether HTTPCookieStorage received a rotated session-token
                    // (compared against the captured sessionToken parameter, so no @Published property is read on a background thread)
                    var effectiveSessionToken = sessionToken
                    let chatgptURL = URL(string: "https://chatgpt.com")!
                    let storedCookies = HTTPCookieStorage.shared.cookies(for: chatgptURL) ?? []
                    if let newToken = CodexWebLoginCoordinator.extractSessionToken(from: storedCookies),
                       newToken != sessionToken {
                        Logger.api.notice("Codex session: new session-token detected, written back silently")
                        effectiveSessionToken = newToken
                        DispatchQueue.main.async {
                            UserSettings.shared.silentlyUpdateCurrentCodexSessionToken(newToken)
                        }
                    }

                    do {
                        let sessionResponse = try JSONDecoder().decode(CodexSessionResponse.self, from: data)
                        guard let accessToken = sessionResponse.accessToken, !accessToken.isEmpty else {
                            Logger.api.error("Codex session response missing accessToken")
                            return .failure(UsageError.sessionExpired)
                        }
                        let exp = jwtExpiry(from: accessToken)
                        if let exp {
                            Logger.api.info("Codex accessToken expires at \(exp) (in \(Int(exp.timeIntervalSinceNow / 60)) min)")
                        } else {
                            Logger.api.debug("Codex accessToken: exp is not parseable, caching for 30 minutes")
                        }
                        return .success(OAuthTokenCache.Tokens(
                            accessToken: accessToken,
                            refreshToken: effectiveSessionToken,
                            expiresAt: exp ?? Date().addingTimeInterval(30 * 60)
                        ))
                    } catch {
                        Logger.api.debug("Codex session decode error: \(error.localizedDescription)")
                        return .failure(UsageError.decodingError)
                    }
                }()
                continuation.resume(with: result)
            }

            trackTask(task)
            task.resume()
        }
    }

    /// OAuth account: exchange the refresh_token for an access_token at auth.openai.com.
    /// Called exactly once whenever OAuthTokenCache decides "a new refresh really is needed" (concurrent callers share the one result).
    /// A rotated refresh_token is written back to the account store silently and returned as refreshToken (so the cache key follows the new value).
    private func refreshOAuthTokens(refreshToken: String) async throws -> OAuthTokenCache.Tokens {
        let tokens = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CodexOAuthTokens, Error>) in
            CodexOAuthService.refresh(refreshToken: refreshToken) { result in
                continuation.resume(with: result)
            }
        }

        let newRefresh = tokens.refreshToken.isEmpty ? refreshToken : tokens.refreshToken
        if newRefresh != refreshToken {
            Logger.api.notice("Codex OAuth: refresh_token rotated, written back silently")
            await MainActor.run {
                UserSettings.shared.silentlyUpdateCurrentCodexSessionToken(newRefresh)
            }
        }

        return OAuthTokenCache.Tokens(
            accessToken: tokens.accessToken,
            refreshToken: newRefresh,
            expiresAt: jwtExpiry(from: tokens.accessToken) ?? Date().addingTimeInterval(30 * 60)
        )
    }

    /// Skip the session step and query usage with an accessToken already in hand (used for the retry after a refresh)
    func fetchUsageWithAccessToken(_ accessToken: String, completion: @escaping (Result<CodexUsageData, Error>) -> Void) {
        fetchWhamUsage(accessToken: accessToken) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Async wrappers

    /// async wrapper around `fetchUsage(completion:)` for structured concurrency callers.
    /// The outcome is a Result rather than a throw, to match the error semantics of the completion version.
    func fetchUsageResult() async -> Result<CodexUsageData, Error> {
        await withCheckedContinuation { continuation in
            fetchUsage { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Private: Step 2 — accessToken → usage

    /// Step two: query usage with the Bearer accessToken
    private func fetchWhamUsage(accessToken: String, completion: @escaping (Result<CodexUsageData, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/backend-api/wham/usage") else {
            completion(.failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false
        CodexAPIHeaderBuilder.applyUsageHeaders(to: &request, accessToken: accessToken)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.api.debug("Codex usage error: \(error.localizedDescription)")
                completion(.failure(UsageError.networkError))
                return
            }

            guard let data = data else {
                completion(.failure(UsageError.noData))
                return
            }

            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.api.debug("Codex usage response received: \(data.count) bytes")
                if jsonString.contains("<!DOCTYPE html>") || jsonString.contains("<html") {
                    completion(.failure(UsageError.cloudflareBlocked))
                    return
                }
            }

            if let httpResponse = response as? HTTPURLResponse {
                Logger.api.debug("Codex usage HTTP status: \(httpResponse.statusCode)")
                switch httpResponse.statusCode {
                case 200...299: break
                case 401:
                    // The cached accessToken is dead. Await the cache clear before propagating the error,
                    // so the retry a caller fires right after the unauthorized cannot hit the same broken token
                    Task { [weak self] in
                        await self?.tokenCache.clear()
                        completion(.failure(UsageError.unauthorized))
                    }
                    return
                case 403: completion(.failure(UsageError.cloudflareBlocked)); return
                case 429: completion(.failure(UsageError.rateLimited)); return
                default:
                    completion(.failure(UsageError.httpError(statusCode: httpResponse.statusCode)))
                    return
                }
            }

            let decoder = JSONDecoder()
            do {
                let usageResponse = try decoder.decode(CodexUsageResponse.self, from: data)
                let usageData = usageResponse.toCodexUsageData()
                // Plan for the popover title ("Codex Plus"), refreshed on every fetch so a plan
                // change shows up without a re-login
                if let plan = usageResponse.plan_type, !plan.isEmpty {
                    DispatchQueue.main.async { UserSettings.shared.codexPlanType = plan }
                    self.fetchPlanDisplayNameIfNeeded(accessToken: accessToken, planType: plan)
                }
                completion(.success(usageData))
            } catch {
                Logger.api.debug("Codex usage decode error: \(error.localizedDescription)")
                completion(.failure(UsageError.decodingError))
            }
        }

        trackTask(task)
        task.resume()
    }

    /// The plan_type the display name was last fetched for, so it is fetched once per launch and
    /// again only when the plan changes, not on every poll
    private var displayNameFetchedForPlan: String?

    /// The plan's own display name ("Business Premium"), which carries the seat type. wham/usage
    /// only has the raw `plan_type` ("self_serve_business_prolite"), which does not say Standard or
    /// Premium; `accounts/check` does, as `account.plan_display_name`.
    private func fetchPlanDisplayNameIfNeeded(accessToken: String, planType: String) {
        guard displayNameFetchedForPlan != planType,
              let url = URL(string: "\(baseURL)/backend-api/accounts/check/v4-2023-04-27") else { return }
        displayNameFetchedForPlan = planType

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false
        CodexAPIHeaderBuilder.applyUsageHeaders(to: &request, accessToken: accessToken)

        let task = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accounts = json["accounts"] as? [String: Any] else {
                self?.displayNameFetchedForPlan = nil   // try again on the next poll
                return
            }
            // Prefer the account whose plan matches the one wham/usage reported, else "default"
            let entries = accounts.values.compactMap { ($0 as? [String: Any])?["account"] as? [String: Any] }
            let match = entries.first { $0["plan_type"] as? String == planType }
                ?? ((accounts["default"] as? [String: Any])?["account"] as? [String: Any])
            guard let name = match?["plan_display_name"] as? String, !name.isEmpty else { return }
            DispatchQueue.main.async { UserSettings.shared.codexPlanDisplayName = name }
        }
        trackTask(task)
        task.resume()
    }

    // MARK: - Validation (used by WebLoginCoordinator)

    /// Validate a session token and return the account info (for the WebLogin flow)
    /// - Parameters:
    ///   - sessionToken: the __Secure-next-auth.session-token value
    ///   - completion: (email, displayName) on success, an Error on failure
    func validateSessionToken(_ sessionToken: String, cookieHeader: String, completion: @escaping (Result<(email: String, displayName: String), Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/auth/session") else {
            completion(.failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false
        CodexAPIHeaderBuilder.applySessionHeaders(to: &request, sessionToken: sessionToken)
        // Use the WebView's full Cookie header, so the Cloudflare cookies come along too
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let task = session.dataTask(with: request) { data, response, error in
            if error != nil {
                DispatchQueue.main.async { completion(.failure(UsageError.networkError)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(UsageError.noData)) }
                return
            }

            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.api.debug("Codex validate session response received: \(data.count) bytes")
                if jsonString.contains("<!DOCTYPE html>") || jsonString.contains("<html") {
                    DispatchQueue.main.async { completion(.failure(UsageError.cloudflareBlocked)) }
                    return
                }
            }

            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299: break
                case 401:
                    DispatchQueue.main.async { completion(.failure(UsageError.unauthorized)) }
                    return
                case 403:
                    DispatchQueue.main.async { completion(.failure(UsageError.cloudflareBlocked)) }
                    return
                default:
                    DispatchQueue.main.async {
                        completion(.failure(UsageError.httpError(statusCode: httpResponse.statusCode)))
                    }
                    return
                }
            }

            let decoder = JSONDecoder()
            do {
                let sessionResponse = try decoder.decode(CodexSessionResponse.self, from: data)
                guard let accessToken = sessionResponse.accessToken, !accessToken.isEmpty else {
                    DispatchQueue.main.async { completion(.failure(UsageError.sessionExpired)) }
                    return
                }
                // The session-token is a JWE and cannot be decrypted locally, but the accessToken inside it is a plain JWT
                // An expired accessToken means the OAuth refresh token is dead too, so reject this session
                if let exp = jwtExpiry(from: accessToken), exp < Date() {
                    Logger.api.warning("Codex validate: session stale (accessToken expired at \(exp)), rejecting login")
                    DispatchQueue.main.async { completion(.failure(UsageError.sessionExpired)) }
                    return
                }
                let email = sessionResponse.user?.email ?? ""
                let name = sessionResponse.user?.name ?? email
                let displayName = name.isEmpty ? "Codex" : name
                DispatchQueue.main.async { completion(.success((email: email, displayName: displayName))) }
            } catch {
                DispatchQueue.main.async { completion(.failure(UsageError.decodingError)) }
            }
        }

        trackTask(task)
        task.resume()
    }

    // MARK: - Debug Mock Data

    #if DEBUG
    private func createMockData() -> CodexUsageData {
        let primaryResetAt = Date().addingTimeInterval(3600 * 2.5)
        let secondaryResetAt = Date().addingTimeInterval(3600 * 24 * 3.2)
        let extraPercentage = Double(settings.debugCodexExtraUsagePercentage)
        let debugCreditLimit = Decimal(1000)
        let remainingRatio = max(0, (100 - extraPercentage) / 100.0)
        let balance = debugCreditLimit * Decimal(remainingRatio)
        let balanceValue = balance.doubleValue

        return CodexUsageData(
            primary: .init(percentage: Double(settings.debugCodexPrimaryPercentage), resetsAt: primaryResetAt),
            secondary: .init(percentage: Double(settings.debugCodexSecondaryPercentage), resetsAt: secondaryResetAt),
            extraUsage: CodexExtraUsageData(
                hasCredits: true,
                unlimited: false,
                overageLimitReached: extraPercentage >= 100,
                spendControlReached: false,
                balance: balance,
                approxLocalMessages: [Int(balanceValue / 14), Int(balanceValue / 2)],
                approxCloudMessages: [Int(balanceValue / 34), Int(balanceValue / 25)],
                visualPercentage: extraPercentage
            )
        )
    }
    #endif
}

private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

// MARK: - UsageProvider

extension CodexAPIService: UsageProvider {
    var providerType: ProviderType { .codex }

    func cancelAllRequests() {
        tasksLock.lock()
        let tasks = activeTasks
        activeTasks.removeAll()
        tasksLock.unlock()
        tasks.forEach { $0.cancel() }
        Logger.api.debug("Codex: cancelled all network requests")
    }
}
