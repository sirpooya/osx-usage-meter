//
//  ClaudeAPIService.swift
//  ClaudeUsage
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// Claude API service
/// Talks to the Claude.ai API and fetches the user's usage data
/// Covers request building, authentication, getting past Cloudflare and parsing the data
class ClaudeAPIService {
    // MARK: - Properties

    /// Shared instance reused by the one shot validation paths (the login page and settings page validating a sessionKey).
    /// Those call sites used to create a local `ClaudeAPIService()` each, whose URLSession was never
    /// `finishTasksAndInvalidate()`ed; and if the instance was released mid request, the single flight waiters
    /// suspended inside its `[weak self]` closures were lost with it. Reusing one long lived instance avoids both.
    static let shared = ClaudeAPIService()

    /// API base URL
    private let baseURL = "https://claude.ai/api/organizations"

    /// User settings instance, used to read the authentication data
    private let settings = UserSettings.shared

    /// Shared URLSession instance
    private let session: URLSession

    /// The network request currently in flight
    private var currentTask: URLSessionDataTask?

    // MARK: - Claude OAuth single flight and cache
    //
    // A Claude OAuth refresh_token rotates on every renewal (the old value dies immediately).
    // Several concurrent refresh calls can use the same refresh_token, so whichever arrives later gets a 401.
    // Single flight coalescing and the cache are both delegated to OAuthTokenCache (an actor, see Services/OAuthTokenCache.swift),
    // whose serialization naturally replaces a hand written NSLock plus waiter array.
    private let oauthTokenCache = OAuthTokenCache()

    // MARK: - Initialization

    init() {
        // Configure the URLSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30  // Request timeout: 30 seconds
        configuration.timeoutIntervalForResource = 60 // Resource timeout: 60 seconds
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData  // No caching

        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Claude OAuth Support

    /// Decide whether a credential is a Claude OAuth refresh_token (it starts with "sk-ant-ort01-")
    static func isOAuthRefreshToken(_ credential: String) -> Bool {
        credential.hasPrefix("sk-ant-ort01-")
    }

    /// Clear the OAuth access_token cache (called on an account switch; the 401 retry path is in fetchClaudeOAuthUsageData,
    /// which has to await the clear before retrying and so uses the awaitable oauthTokenCache.clear())
    func clearOAuthTokenCache() {
        Task { await oauthTokenCache.clear() }
    }
    
    // MARK: - Public Methods
    
    /// Fetch the user's Claude usage (main usage and Extra Usage in parallel)
    /// - Parameter completion: called with the UsageData on success or an Error on failure
    /// - Note: the request adds the headers needed to get past Cloudflare automatically
    /// - Important: make sure valid authentication is configured before calling
    /// - Note: the main usage API and the Extra Usage API are called in parallel, and an Extra Usage failure does not affect the main feature
    func fetchUsage(completion: @escaping (Result<UsageData, Error>) -> Void) {
        #if DEBUG
        // Debug mode: return mock data (immediately, with no delay)
        if settings.debugModeEnabled {
            let mockData = createMockData()
            DispatchQueue.main.async {
                completion(.success(mockData))
            }
            return
        }
        #endif

        // Cancel the previous request (if there is one)
        currentTask?.cancel()

        // Check the authentication info
        guard settings.hasValidCredentials else {
            DispatchQueue.main.async { completion(.failure(UsageError.noCredentials)) }
            return
        }

        // OAuth account: the credential is a refresh_token, so take the /api/oauth/usage path and skip the Cloudflare cookie flow
        if Self.isOAuthRefreshToken(settings.sessionKey) {
            fetchOAuthUsage(completion: completion)
            return
        }

        // Use a DispatchGroup to request both APIs in parallel
        let dispatchGroup = DispatchGroup()
        var mainUsageData: UsageData?
        var extraUsageData: ExtraUsageData?
        var mainError: Error?

        // ========== Request 1: the main usage API ==========
        dispatchGroup.enter()
        fetchMainUsage { result in
            switch result {
            case .success(let data):
                mainUsageData = data
            case .failure(let error):
                mainError = error
            }
            dispatchGroup.leave()
        }

        // ========== Request 2: the Extra Usage API (optional) ==========
        dispatchGroup.enter()
        fetchExtraUsage { result in
            switch result {
            case .success(let data):
                extraUsageData = data  // May be nil (the feature is off, or the request failed)
            case .failure:
                // An Extra Usage failure does not affect the main feature, extraUsageData just stays nil
                Logger.api.info("Extra Usage API failed, continuing with main usage data only")
            }
            dispatchGroup.leave()
        }

        // ========== Wait for both requests, then merge the results ==========
        dispatchGroup.notify(queue: .main) {
            // A failure of the main API fails the whole thing
            if let error = mainError {
                completion(.failure(error))
                return
            }

            // The main API succeeded, merge in the Extra Usage data
            guard var finalData = mainUsageData else {
                completion(.failure(UsageError.decodingError))
                return
            }

            // Build the full data including Extra Usage (keeping every model slot, Fable / Opus / Sonnet and so on)
            finalData = UsageData(
                fiveHour: finalData.fiveHour,
                sevenDay: finalData.sevenDay,
                weeklyModels: finalData.weeklyModels,
                extraUsage: extraUsageData  // May be nil
            )

            completion(.success(finalData))
        }
    }

    /// Fetch the main usage API data (internal)
    /// - Parameter completion: the completion callback
    private func fetchMainUsage(completion: @escaping (Result<UsageData, Error>) -> Void) {
        // Service layer convention: every completion is called back on the main thread, so callers never need to wrap it in another DispatchQueue.main.async
        let complete: (Result<UsageData, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        let urlString = "\(baseURL)/\(settings.organizationId)/usage"

        guard let url = URL(string: urlString) else {
            complete(.failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false

        // Use the shared header builder to add the full browser headers, getting past Cloudflare
        ClaudeAPIHeaderBuilder.applyHeaders(
            to: &request,
            organizationId: settings.organizationId,
            sessionKey: settings.sessionKey
        )

        // Create the task and keep a reference
        currentTask = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.api.debug("Network error: \(error.localizedDescription)")
                complete(.failure(UsageError.networkError))
                return
            }

            guard let data = data else {
                complete(.failure(UsageError.noData))
                return
            }

            // Print the raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.api.debug("Main Usage API Response: \(jsonString)")

                // Check for an HTML response (a Cloudflare block)
                if jsonString.contains("<!DOCTYPE html>") || jsonString.contains("<html") {
                    Logger.api.debug("⚠️ Received HTML response, possibly intercepted by Cloudflare.")
                    complete(.failure(UsageError.cloudflareBlocked))
                    return
                }
            }

            // Check the HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                Logger.api.debug("Main Usage HTTP Status: \(httpResponse.statusCode)")

                // Handle the various HTTP error status codes
                switch httpResponse.statusCode {
                case 200...299:
                    // Successful response, keep going
                    break
                case 401:
                    // Unauthorized, usually invalid authentication
                    complete(.failure(UsageError.unauthorized))
                    return
                case 403:
                    // HTML already returned cloudflareBlocked above, so a 403 here is always a JSON auth failure
                    complete(.failure(UsageError.unauthorized))
                    return
                case 429:
                    // Too many requests
                    complete(.failure(UsageError.rateLimited))
                    return
                default:
                    // Other HTTP errors
                    Logger.api.error("HTTP error: \(httpResponse.statusCode)")
                    complete(.failure(UsageError.httpError(statusCode: httpResponse.statusCode)))
                    return
                }
            }

            // Decode the JSON response
            let decoder = JSONDecoder()

            // Check for an error response
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data),
               errorResponse.error.type == "permission_error" {
                complete(.failure(UsageError.sessionExpired))
                return
            }

            // Parse a successful response
            do {
                let response = try decoder.decode(UsageResponse.self, from: data)
                let usageData = response.toUsageData()
                complete(.success(usageData))
            } catch {
                Logger.api.debug("Decoding error: \(error.localizedDescription)")
                complete(.failure(UsageError.decodingError))
            }
        }

        // Start the task
        currentTask?.resume()
    }

    /// Fetch the user's organization list
    /// - Parameters:
    ///   - sessionKey: optional sessionKey, settings.sessionKey is used when it is not provided
    ///   - cookieHeader: optional full Cookie header string (supplied by the WebView login flow, carrying cf_clearance and __cf_bm)
    ///   - completion: called with the organization array on success or an Error on failure
    /// - Note: used to fetch the organization ID automatically, which simplifies setup
    func fetchOrganizations(sessionKey: String? = nil, cookieHeader: String? = nil, completion: @escaping (Result<[Organization], Error>) -> Void) {
        // Service layer convention: every completion is called back on the main thread, so callers never need to wrap it in another DispatchQueue.main.async
        let complete: (Result<[Organization], Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        let urlString = "\(baseURL.replacingOccurrences(of: "/organizations", with: ""))/organizations"

        guard let url = URL(string: urlString) else {
            complete(.failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false

        // Use the shared header builder, only the sessionKey is needed
        // Use the sessionKey parameter when it is given, otherwise settings.sessionKey
        let actualSessionKey = sessionKey ?? settings.sessionKey
        ClaudeAPIHeaderBuilder.applyHeaders(
            to: &request,
            organizationId: nil,  // Fetching the organization list does not need an organizationId
            sessionKey: actualSessionKey
        )
        // When a full Cookie header from the WebView is provided (carrying cf_clearance and __cf_bm),
        // override the sessionKey only Cookie field applyHeaders set, so the Cloudflare pass comes along too
        if let cookieHeader = cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.api.debug("Network error: \(error.localizedDescription)")
                complete(.failure(UsageError.networkError))
                return
            }

            guard let data = data else {
                complete(.failure(UsageError.noData))
                return
            }

            // Print the raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.api.debug("Organizations API Response: \(jsonString)")
            }

            // Check the HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                Logger.api.debug("HTTP Status Code: \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200...299:
                    // Successful response, keep going
                    break
                case 401:
                    complete(.failure(UsageError.unauthorized))
                    return
                case 403:
                    // A Cloudflare block returns HTML; an API auth failure returns JSON
                    let isHTML = String(data: data, encoding: .utf8).map {
                        $0.contains("<!DOCTYPE html>") || $0.contains("<html")
                    } ?? false
                    complete(.failure(isHTML ? UsageError.cloudflareBlocked : UsageError.unauthorized))
                    return
                default:
                    Logger.api.error("HTTP error: \(httpResponse.statusCode)")
                    complete(.failure(UsageError.httpError(statusCode: httpResponse.statusCode)))
                    return
                }
            }

            // Decode the JSON response
            let decoder = JSONDecoder()
            do {
                let organizations = try decoder.decode([Organization].self, from: data)
                complete(.success(organizations))
            } catch {
                Logger.api.debug("Decoding error: \(error.localizedDescription)")
                complete(.failure(UsageError.decodingError))
            }
        }

        task.resume()
    }

    /// Fetch the Extra Usage data
    /// - Parameter completion: called with the ExtraUsageData on success or an Error on failure
    /// - Note: this call is optional, a failure should not affect the main feature
    func fetchExtraUsage(completion: @escaping (Result<ExtraUsageData?, Error>) -> Void) {
        // Service layer convention: every completion is called back on the main thread, so callers never need to wrap it in another DispatchQueue.main.async
        let complete: (Result<ExtraUsageData?, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        // Check the authentication info
        guard settings.hasValidCredentials else {
            complete(.failure(UsageError.noCredentials))
            return
        }

        let urlString = "\(baseURL)/\(settings.organizationId)/overage_spend_limit"

        guard let url = URL(string: urlString) else {
            complete(.failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false

        // Use the shared header builder to add the full browser headers
        ClaudeAPIHeaderBuilder.applyHeaders(
            to: &request,
            organizationId: settings.organizationId,
            sessionKey: settings.sessionKey
        )

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.api.debug("Extra Usage API network error: \(error.localizedDescription)")
                complete(.failure(UsageError.networkError))
                return
            }

            guard let data = data else {
                complete(.failure(UsageError.noData))
                return
            }

            // Print the raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.api.debug("Extra Usage API Response: \(jsonString)")
            }

            // Check the HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                Logger.api.debug("Extra Usage HTTP Status: \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200...299:
                    // Successful response, keep going
                    break
                case 403, 404:
                    // Extra Usage is off or not permitted, so nil means the feature is unavailable
                    Logger.api.info("Extra Usage not available (HTTP \(httpResponse.statusCode))")
                    complete(.success(nil))
                    return
                case 401:
                    complete(.failure(UsageError.unauthorized))
                    return
                default:
                    Logger.api.warning("Extra Usage HTTP error: \(httpResponse.statusCode)")
                    complete(.success(nil))  // Graceful degradation
                    return
                }
            }

            // Decode the JSON response
            let decoder = JSONDecoder()
            do {
                let extraUsageResponse = try decoder.decode(ExtraUsageResponse.self, from: data)
                let extraUsageData = extraUsageResponse.toExtraUsageData()
                complete(.success(extraUsageData))
            } catch {
                Logger.api.debug("Extra Usage decoding error: \(error.localizedDescription)")
                complete(.success(nil))  // Graceful degradation
            }
        }

        task.resume()
    }

    // MARK: - OAuth Usage Path

    /// OAuth accounts only: trade the refresh_token for an access_token, then call /api/oauth/usage
    /// - Parameter retryOnUnauthorized: on a 401, whether to clear the cache and retry once immediately (forcing a fresh access_token).
    ///   Follows the existing pattern of `DataRefreshManager.fetchCodexOnly(retryOnUnauthorized:)` on the Codex side,
    ///   so the user does not stare at an error state until the next refresh cycle.
    private func fetchOAuthUsage(retryOnUnauthorized: Bool = true, completion: @escaping (Result<UsageData, Error>) -> Void) {
        // CLI synced accounts take their own path: the token belongs to Claude Code, not to us
        if settings.currentAccount?.credentialSource.isCLISynced == true {
            fetchCLISyncedUsage(retryOnUnauthorized: retryOnUnauthorized, completion: completion)
            return
        }

        let refreshToken = settings.sessionKey
        fetchOAuthAccessToken(refreshToken: refreshToken) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let accessToken):
                self.fetchClaudeOAuthUsageData(accessToken: accessToken, retryOnUnauthorized: retryOnUnauthorized, completion: completion)
            }
        }
    }

    // MARK: - CLI Account Sync

    /// The fetch path for CLI synced accounts.
    ///
    /// The key difference from a browser OAuth account: the refresh_token belongs to Claude Code CLI,
    /// and the server kills the old value the moment it issues a new one. So the order here is
    ///   1. Re-read the Keychain every time (the CLI may already have rotated the token behind our back)
    ///   2. Use the access_token directly while it is still valid, which costs no extra request and leaves the CLI alone
    ///   3. Only refresh ourselves once it has really expired, and write the rotated values **back into the Keychain**,
    ///      otherwise the user's Claude Code gets logged out on its next refresh
    private func fetchCLISyncedUsage(retryOnUnauthorized: Bool, completion: @escaping (Result<UsageData, Error>) -> Void) {
        let preferredService = settings.currentAccount?.keychainService

        // Reading the Keychain can raise a system authorization prompt, so it must not hold the main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Prefer our own mirrored item, which never prompts because this app created it.
            // Claude Code's item is only read when we have no mirror yet, or when the mirror's
            // refresh_token has stopped working. See ClaudeTokenMirror for why.
            if let mirrored = ClaudeTokenMirror.load() {
                self.publishTier(mirrored.subscriptionType)

                if mirrored.isAccessTokenUsable {
                    self.fetchClaudeOAuthUsageData(
                        accessToken: mirrored.accessToken,
                        retryOnUnauthorized: retryOnUnauthorized,
                        completion: completion
                    )
                    return
                }

                // Expired: refresh from the mirror's own refresh_token, still without reading
                // Claude Code's item. Only a refresh failure sends us back to the CLI entry,
                // because that means our copy is genuinely dead rather than merely stale.
                self.refreshMirroredToken(mirrored) { result in
                    switch result {
                    case .success(let accessToken):
                        self.fetchClaudeOAuthUsageData(
                            accessToken: accessToken,
                            retryOnUnauthorized: retryOnUnauthorized,
                            completion: completion
                        )
                    case .failure:
                        Logger.api.notice("Token mirror: refresh failed, falling back to the Claude Code keychain item")
                        self.fetchUsingCLIKeychain(
                            preferredService: preferredService,
                            retryOnUnauthorized: retryOnUnauthorized,
                            completion: completion
                        )
                    }
                }
                return
            }

            self.fetchUsingCLIKeychain(
                preferredService: preferredService,
                retryOnUnauthorized: retryOnUnauthorized,
                completion: completion
            )
        }
    }

    /// Push the subscription type to the popover title ("Claude Team"), on the main thread.
    private func publishTier(_ tier: String) {
        guard !tier.isEmpty else { return }
        DispatchQueue.main.async {
            UserSettings.shared.claudeSubscriptionTier = tier
        }
    }

    /// The original path: read Claude Code's own Keychain item, and mirror whatever comes back.
    ///
    /// This is the call that can raise the authorization prompt, so it is now reached only on a
    /// cold start or after our mirrored refresh_token has died, rather than on every poll.
    private func fetchUsingCLIKeychain(
        preferredService: String?,
        retryOnUnauthorized: Bool,
        completion: @escaping (Result<UsageData, Error>) -> Void
    ) {
        guard let credentials = ClaudeCodeSyncService.currentCredentials(preferredService: preferredService) else {
            Logger.api.error("CLI sync: keychain credentials are no longer readable")
            DispatchQueue.main.async { completion(.failure(UsageError.noCredentials)) }
            return
        }

        // The entry carries the subscription type, so the popover title can read "Claude Team".
        // Refreshed here rather than only at sync time, so an account that synced before this
        // existed, or one whose plan changed, still ends up with the right tier.
        publishTier(credentials.subscriptionType)

        // Mirror straight away, so the next poll does not have to come back here.
        ClaudeTokenMirror.save(from: credentials)

        // The access_token is still valid: use it and leave the refresh_token alone
        if credentials.isAccessTokenUsable {
            fetchClaudeOAuthUsageData(
                accessToken: credentials.accessToken,
                retryOnUnauthorized: retryOnUnauthorized,
                completion: completion
            )
            return
        }

        refreshCLISyncedToken(credentials: credentials) { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let accessToken):
                self.fetchClaudeOAuthUsageData(
                    accessToken: accessToken,
                    retryOnUnauthorized: retryOnUnauthorized,
                    completion: completion
                )
            }
        }
    }

    /// Refresh using the mirrored refresh_token, updating both our item and Claude Code's.
    ///
    /// The write-back to Claude Code's item matters for the same reason it always did: a
    /// refresh_token is single use, so once we spend it the CLI's copy is dead and the user would
    /// be logged out of their own terminal. That write does not prompt (writing is not reading).
    private func refreshMirroredToken(
        _ mirrored: ClaudeTokenMirror.Mirrored,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !mirrored.refreshToken.isEmpty else {
            completion(.failure(UsageError.unauthorized))
            return
        }

        ClaudeOAuthService.refresh(refreshToken: mirrored.refreshToken) { result in
            switch result {
            case .failure(let error):
                Logger.api.error("Token mirror: refresh failed \(error.localizedDescription)")
                completion(.failure(error))
            case .success(let tokens):
                let rotated = tokens.refreshToken.isEmpty ? mirrored.refreshToken : tokens.refreshToken
                ClaudeTokenMirror.updateTokens(
                    accessToken: tokens.accessToken,
                    refreshToken: rotated,
                    expiresAt: tokens.expiresAt
                )
                ClaudeCodeKeychain.writeBackByService(
                    accessToken: tokens.accessToken,
                    refreshToken: rotated,
                    expiresAt: tokens.expiresAt,
                    service: mirrored.originService,
                    account: mirrored.originAccount
                )
                if rotated != mirrored.refreshToken {
                    DispatchQueue.main.async {
                        UserSettings.shared.silentlyUpdateCurrentClaudeSessionToken(rotated)
                    }
                }
                completion(.success(tokens.accessToken))
            }
        }
    }

    /// Trade the Keychain's refresh_token for a new access_token, writing the rotated pair back into the Keychain entry.
    /// A failed write back does not abort this fetch (the new token in hand still works for this round), but it is logged:
    /// it means the CLI is holding a dead value and the next sync has to realign.
    private func refreshCLISyncedToken(
        credentials: ClaudeCodeCredentials,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !credentials.refreshToken.isEmpty else {
            completion(.failure(UsageError.unauthorized))
            return
        }

        ClaudeOAuthService.refresh(refreshToken: credentials.refreshToken) { result in
            switch result {
            case .failure(let error):
                Logger.api.error("CLI sync: token refresh failed \(error.localizedDescription)")
                completion(.failure(error))
            case .success(let tokens):
                let rotated = tokens.refreshToken.isEmpty ? credentials.refreshToken : tokens.refreshToken
                ClaudeCodeKeychain.writeBack(
                    accessToken: tokens.accessToken,
                    refreshToken: rotated,
                    expiresAt: tokens.expiresAt,
                    to: credentials
                )
                if rotated != credentials.refreshToken {
                    DispatchQueue.main.async {
                        UserSettings.shared.silentlyUpdateCurrentClaudeSessionToken(rotated)
                    }
                }
                completion(.success(tokens.accessToken))
            }
        }
    }

    /// Trade the refresh_token for an access_token, with caching and single flight coalescing (delegated to the OAuthTokenCache actor)
    private func fetchOAuthAccessToken(refreshToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let accessToken = try await oauthTokenCache.accessToken(refreshToken: refreshToken) { [weak self] token in
                    guard let self else { throw UsageError.decodingError }
                    return try await self.refreshClaudeOAuthTokens(refreshToken: token)
                }
                await MainActor.run { completion(.success(accessToken)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// Actually calls the Claude OAuth endpoint for a new token, and silently writes back a rotated refresh_token.
    /// Called exactly once whenever OAuthTokenCache decides "a new refresh really is needed" (concurrent callers share the one result).
    private func refreshClaudeOAuthTokens(refreshToken: String) async throws -> OAuthTokenCache.Tokens {
        do {
            let tokens = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ClaudeOAuthTokens, Error>) in
                ClaudeOAuthService.refresh(refreshToken: refreshToken) { result in
                    continuation.resume(with: result)
                }
            }

            // refresh_token rotation: when the response carries a new value, write it back to the account silently
            let newRefresh = tokens.refreshToken.isEmpty ? refreshToken : tokens.refreshToken
            if newRefresh != refreshToken {
                Logger.api.notice("Claude OAuth: refresh_token rotated, written back silently")
                await MainActor.run {
                    UserSettings.shared.silentlyUpdateCurrentClaudeSessionToken(newRefresh)
                }
            }

            // expires_in is usually 3600 seconds; when it is missing, assume a conservative 30 minutes
            let expiry = tokens.expiresAt ?? Date().addingTimeInterval(30 * 60)
            return OAuthTokenCache.Tokens(accessToken: tokens.accessToken, refreshToken: newRefresh, expiresAt: expiry)
        } catch {
            Logger.api.error("Claude OAuth refresh failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Call /api/oauth/usage with the access_token and parse it into UsageData
    private func fetchClaudeOAuthUsageData(accessToken: String, retryOnUnauthorized: Bool, completion: @escaping (Result<UsageData, Error>) -> Void) {
        // Service layer convention: every completion is called back on the main thread, so callers never need to wrap it in another DispatchQueue.main.async
        let complete: (Result<UsageData, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        guard let url = URL(string: ClaudeOAuthConfig.usageURL) else {
            complete(.failure(UsageError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(ClaudeOAuthConfig.betaHeader, forHTTPHeaderField: "anthropic-beta")
        // The User-Agent is a hard requirement of this endpoint: without it, even a perfectly valid token gets an
        // instant and persistent 429 rate_limit_error (the trap anthropics/claude-code#31021 hit)
        request.setValue(ClaudeOAuthConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                Logger.api.error("Claude OAuth usage network error: \(error.localizedDescription)")
                complete(.failure(UsageError.networkError))
                return
            }
            guard let data = data else {
                complete(.failure(UsageError.noData))
                return
            }
            if let http = response as? HTTPURLResponse {
                Logger.api.debug("Claude OAuth usage HTTP \(http.statusCode)")
                switch http.statusCode {
                case 200...299: break
                case 401:
                    // The access_token is dead, so clear the cache to force a fresh exchange with the refresh_token next time,
                    // rather than reusing a broken token for the 5 minute cache window and getting 401 after 401.
                    // Use a Task to await the clear before retrying, so the clear and the retry's cache read cannot race
                    // (both enter the actor, and separate Tasks could not guarantee the clear runs first).
                    if retryOnUnauthorized {
                        Logger.api.info("Claude OAuth usage 401. Cleared the cache and retrying once with a new access_token from refresh_token")
                        Task {
                            await self?.oauthTokenCache.clear()
                            self?.fetchOAuthUsage(retryOnUnauthorized: false, completion: completion)
                        }
                    } else {
                        Task { await self?.oauthTokenCache.clear() }
                        complete(.failure(UsageError.unauthorized))
                    }
                    return
                case 429:
                    complete(.failure(UsageError.rateLimited))
                    return
                default:
                    complete(.failure(UsageError.httpError(statusCode: http.statusCode)))
                    return
                }
            }
            if let raw = String(data: data, encoding: .utf8) {
                Logger.api.debug("Claude OAuth usage response: \(raw.prefix(500))")
            }

            let decoder = JSONDecoder()
            do {
                // Reuse the existing UsageResponse decoder (the five_hour/seven_day/opus/sonnet field names match)
                let baseResponse = try decoder.decode(UsageResponse.self, from: data)
                var usageData = baseResponse.toUsageData()

                // Try decoding the extra_usage field as well
                // Issue #64: four nested try? used to swallow the reason silently, so there was no telling whether
                // the field was absent, named differently or shaped differently. Now each case is explicit and logged.
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let extraJson = json["extra_usage"] as? [String: Any] {
                        // Diagnostics: log the keys even on a successful decode, because every ExtraUsageResponse field is optional,
                        // so mismatched names throw nothing and silently produce an all nil "disabled" result.
                        Logger.api.debug("Claude OAuth usage extra_usage keys=\(Array(extraJson.keys).sorted())")
                        if let extraData = try? JSONSerialization.data(withJSONObject: extraJson) {
                            do {
                                let extraResponse = try decoder.decode(ExtraUsageResponse.self, from: extraData)
                                let extraUsageData = extraResponse.toExtraUsageData()
                                Logger.api.debug("Claude OAuth usage extra_usage parse result: enabled=\(extraUsageData?.enabled ?? false)")
                                usageData = UsageData(
                                    fiveHour: usageData.fiveHour,
                                    sevenDay: usageData.sevenDay,
                                    weeklyModels: usageData.weeklyModels,
                                    extraUsage: extraUsageData
                                )
                            } catch {
                                Logger.api.error("Claude OAuth usage extra_usage decode failed: \(error.localizedDescription), keys=\(Array(extraJson.keys))")
                            }
                        } else {
                            Logger.api.error("Claude OAuth usage extra_usage field could not be re-serialized to JSON, keys=\(Array(extraJson.keys))")
                        }
                    } else {
                        Logger.api.info("Claude OAuth usage has no extra_usage field, top level keys=\(Array(json.keys))")
                    }
                }

                complete(.success(usageData))
            } catch {
                Logger.api.error("Claude OAuth usage parse failed: \(error.localizedDescription)")
                complete(.failure(UsageError.decodingError))
            }
        }.resume()
    }

    /// Cancel every in flight network request
    /// Called when the app quits, or when requests have to be interrupted
    func cancelAllRequests() {
        currentTask?.cancel()
        currentTask = nil
        Logger.api.debug("Cancelled all network requests")
    }

    // MARK: - Async wrappers

    /// async wrapper around `fetchUsage(completion:)` for structured concurrency callers.
    /// The outcome is a Result rather than a throw, to match the error semantics of the completion version.
    func fetchUsageResult() async -> Result<UsageData, Error> {
        await withCheckedContinuation { continuation in
            fetchUsage { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Debug Mock Data

    #if DEBUG
    /// Build a future time whose minute is 00
    /// - Parameter hoursFromNow: hours from now
    /// - Returns: a future date whose minute is 00
    private func createResetTime(hoursFromNow: Double) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let targetDate = now.addingTimeInterval(3600 * hoursFromNow)
        
        // Get the components of the target date
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: targetDate)
        components.minute = 0
        components.second = 0
        
        // Return the time with minute set to 00
        return calendar.date(from: components) ?? targetDate
    }
    
    /// Build mock data for debugging
    /// - Returns: a mock UsageData built from the percentage sliders
    private func createMockData() -> UsageData {
        // Build the limit data from each slider value
        let extraUsageData: ExtraUsageData? = {
            guard settings.debugExtraUsageEnabled else {
                return ExtraUsageData(enabled: false, used: nil, limit: nil, currency: "USD")
            }
            // Debug data is stored in cents, matching the real API, so divide by 100 for dollars
            return ExtraUsageData(
                enabled: true,
                used: settings.debugExtraUsageUsed / 100.0,
                limit: Double(settings.debugExtraUsageLimit) / 100.0,
                currency: "USD"
            )
        }()

        return UsageData(
            fiveHour: UsageData.LimitData(
                percentage: settings.debugFiveHourPercentage,
                resetsAt: createResetTime(hoursFromNow: 1.8)  // Resets in 1.8 hours
            ),
            sevenDay: UsageData.LimitData(
                percentage: settings.debugSevenDayPercentage,
                resetsAt: createResetTime(hoursFromNow: 24 * 2.3)  // Resets in 2.3 days
            ),
            opus: UsageData.LimitData(
                percentage: settings.debugOpusPercentage,
                resetsAt: createResetTime(hoursFromNow: 24 * 4.5)  // Resets in 4.5 days
            ),
            sonnet: UsageData.LimitData(
                percentage: settings.debugSonnetPercentage,
                resetsAt: createResetTime(hoursFromNow: 24 * 5.2)  // Resets in 5.2 days
            ),
            extraUsage: extraUsageData
        )
    }
    #endif
}


/// Errors from a usage query
enum UsageError: LocalizedError {
    case invalidURL
    case noData
    case sessionExpired
    case cloudflareBlocked
    case noCredentials
    case networkError
    case decodingError
    case unauthorized              // 401 unauthorized
    case rateLimited               // 429 too many requests
    case httpError(statusCode: Int)  // Other HTTP errors

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L.Error.invalidUrl
        case .noData:
            return L.Error.noData
        case .sessionExpired:
            return L.Error.sessionExpired
        case .cloudflareBlocked:
            return L.Error.cloudflareBlocked
        case .noCredentials:
            return L.Error.noCredentials
        case .networkError:
            return L.Error.networkFailed
        case .decodingError:
            return L.Error.decodingFailed
        case .unauthorized:
            return L.Error.unauthorized
        case .rateLimited:
            return L.Error.rateLimited
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        }
    }
}

// MARK: - UsageProvider

extension ClaudeAPIService: UsageProvider {
    var providerType: ProviderType { .claude }
}
