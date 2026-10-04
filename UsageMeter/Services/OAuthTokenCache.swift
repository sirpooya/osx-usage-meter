//
//  OAuthTokenCache.swift
//  UsageMeter
//
//  Audit report 4.2: caching plus single flight coalescing for the OAuth access_token, with an actor in place of a
//  hand written NSLock and waiter array. Actor methods serialize naturally: concurrent callers yield at the await
//  suspension point, and whoever arrives later finds refreshTask already there and reuses that same Task, so there is
//  no waiter list to maintain and no way to forget to wake one up.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// OAuth access_token cache plus single flight refresh, for one provider
actor OAuthTokenCache {
    /// The result of one refresh (providers return different response shapes, and callers normalize to this one inside the refresh closure)
    struct Tokens {
        let accessToken: String
        /// The refresh endpoint may not rotate the refresh_token (an empty string means keep the old value, which the caller handles in the closure)
        let refreshToken: String
        let expiresAt: Date
    }

    private var cachedAccessToken: String?
    private var cachedExpiry: Date?
    private var cachedForRefreshToken: String?

    private var refreshTask: Task<Tokens, Error>?
    private var refreshTaskToken: String?

    /// Get a valid access_token: a cache hit returns immediately, otherwise a refresh starts,
    /// and concurrent calls with the same refresh_token automatically share the one network request.
    /// - Parameters:
    ///   - refreshToken: the current refresh_token
    ///   - margin: early refresh margin, so a nearly expired token is not used (5 minutes by default)
    ///   - refresh: the closure that actually performs the network refresh, returning the new token triple
    func accessToken(
        refreshToken: String,
        margin: TimeInterval = 5 * 60,
        refresh: @escaping (String) async throws -> Tokens
    ) async throws -> String {
        if let cached = cachedAccessToken, !cached.isEmpty,
           let expiry = cachedExpiry,
           cachedForRefreshToken == refreshToken,
           expiry > Date().addingTimeInterval(margin) {
            return cached
        }

        // A refresh for this refresh_token is already running: reuse that Task's result
        if let task = refreshTask, refreshTaskToken == refreshToken {
            return try await task.value.accessToken
        }

        let task = Task<Tokens, Error> {
            try await refresh(refreshToken)
        }
        refreshTask = task
        refreshTaskToken = refreshToken

        defer {
            // Do not leave a finished Task (successful or not) in place, or the next call would read it as "still running"
            if refreshTaskToken == refreshToken {
                refreshTask = nil
                refreshTaskToken = nil
            }
        }

        let tokens = try await task.value
        cachedAccessToken = tokens.accessToken
        cachedExpiry = tokens.expiresAt
        cachedForRefreshToken = tokens.refreshToken
        return tokens.accessToken
    }

    /// Return the cached token while it has not expired (without triggering a refresh)
    /// The fallback for a failed refresh (a network blip or server hiccup): margin 0 by default, so
    /// a token already inside the early refresh window still carries one more round as long as it has not really expired.
    func validCachedToken(refreshToken: String, margin: TimeInterval = 0) -> String? {
        guard let cached = cachedAccessToken, !cached.isEmpty,
              let expiry = cachedExpiry,
              cachedForRefreshToken == refreshToken,
              expiry > Date().addingTimeInterval(margin) else { return nil }
        return cached
    }

    /// Clear the cache (called on an account switch or a 401, forcing the next call through a network refresh)
    func clear() {
        cachedAccessToken = nil
        cachedExpiry = nil
        cachedForRefreshToken = nil
    }
}
