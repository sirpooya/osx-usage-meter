//
//  ClaudeOAuthService.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-06-19.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// The credentials the Claude OAuth token endpoint returns
struct ClaudeOAuthTokens {
    let accessToken: String
    /// May be an empty string when the refresh endpoint does not rotate it, callers should keep the old value
    let refreshToken: String
    let expiresAt: Date?
}

/// Talking to the Claude OAuth token endpoint
///
/// Both the code exchange and the refresh POST a **JSON** body to `console.anthropic.com/v1/oauth/token`
/// (the same as the official Claude Code).
enum ClaudeOAuthService {

    // MARK: - Exchange the authorization code for a token

    static func exchangeCode(
        code: String,
        state: String,
        codeVerifier: String,
        redirectURI: String,
        completion: @escaping (Result<ClaudeOAuthTokens, Error>) -> Void
    ) {
        post(payload: [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "redirect_uri": redirectURI,
            "client_id": ClaudeOAuthConfig.clientID,
            "code_verifier": codeVerifier
        ], completion: completion)
    }

    // MARK: - refresh_token renewal

    static func refresh(
        refreshToken: String,
        completion: @escaping (Result<ClaudeOAuthTokens, Error>) -> Void
    ) {
        post(payload: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": ClaudeOAuthConfig.clientID
        ], completion: completion)
    }

    // MARK: - Account info (for the account display name)

    /// Fetch the profile, returning (email, organization uuid, organization name, subscription tier)
    /// The organization uuid is used as the account's organizationId (the same dedupe identity as older cookie accounts, which eases migration)
    static func fetchProfile(
        accessToken: String,
        completion: @escaping (Result<(email: String, orgId: String, orgName: String, tier: String), Error>) -> Void
    ) {
        guard let url = URL(string: ClaudeOAuthConfig.profileURL) else {
            completion(.failure(UsageError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(ClaudeOAuthConfig.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(ClaudeOAuthConfig.userAgent, forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["account"] as? [String: Any] else {
                completion(.failure(UsageError.decodingError))
                return
            }
            let email = account["email"] as? String ?? ""
            let org = json["organization"] as? [String: Any]
            let orgId = org?["uuid"] as? String ?? ""
            let orgName = org?["name"] as? String ?? email
            // Tier for the popover title. `organization_type` ("claude_team") is the reliable one on a
            // team or enterprise seat; a personal account carries it on the account block instead.
            var tier = org?["organization_type"] as? String ?? ""
            if tier.isEmpty {
                if account["has_claude_max"] as? Bool == true {
                    tier = "max"
                } else if account["has_claude_pro"] as? Bool == true {
                    tier = "pro"
                }
            }
            completion(.success((email: email, orgId: orgId, orgName: orgName, tier: tier)))
        }.resume()
    }

    // MARK: - Private

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static func post(payload: [String: String], completion: @escaping (Result<ClaudeOAuthTokens, Error>) -> Void) {
        guard let url = URL(string: ClaudeOAuthConfig.tokenURL),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(UsageError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The token endpoint needs the User-Agent just as much as the usage endpoint does:
        // without it a perfectly valid refresh_token comes back 429 rate_limit_error, and since
        // every usage fetch goes through here once the access_token expires (~60 min), the whole
        // app looked rate limited. Same trap as anthropics/claude-code#31021.
        request.setValue(ClaudeOAuthConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.api.error("Claude OAuth token request failed: \(error.localizedDescription)")
                completion(.failure(UsageError.networkError))
                return
            }
            guard let data = data else {
                completion(.failure(UsageError.noData))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                Logger.api.error("Claude OAuth token HTTP \(http.statusCode): \(bodyText.prefix(200))")
                completion(.failure(http.statusCode == 401 ? UsageError.unauthorized
                                    : UsageError.httpError(statusCode: http.statusCode)))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
                completion(.failure(UsageError.decodingError))
                return
            }
            let refreshToken = json["refresh_token"] as? String ?? ""
            var expiresAt: Date?
            if let expiresIn = json["expires_in"] as? TimeInterval {
                expiresAt = Date().addingTimeInterval(expiresIn)
            }
            completion(.success(ClaudeOAuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt
            )))
        }.resume()
    }
}
