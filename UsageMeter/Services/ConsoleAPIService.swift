//
//  ConsoleAPIService.swift
//  UsageMeter
//
//  API Console credentials (console.anthropic.com): pay as you go spend, prepaid credits
//  and month to date usage cost. This is the third login method, next to the Claude.ai
//  session cookie and CLI Account Sync, and it answers a different question: what the API
//  is costing, rather than how much of a subscription limit is left.
//
//  Auth is the console's own sessionKey cookie (sk-ant-api03-…), pasted by the user or
//  captured from a console sign in. It is stored in our Keychain item, never on disk.
//

import Combine
import Foundation
import OSLog

// MARK: - Response models

/// Pay as you go spend for the current billing period. `amount` is in cents.
struct ConsoleCurrentSpend: Codable, Equatable {
    let amount: Int
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case resetsAt = "resets_at"
    }

    /// Spend in whole currency units
    var dollars: Double { Double(amount) / 100.0 }
}

/// Prepaid credit balance. `amount` is in cents.
struct ConsolePrepaidCredits: Codable, Equatable {
    let amount: Int
    let currency: String?

    var dollars: Double { Double(amount) / 100.0 }
}

/// One organization visible to the console session
struct ConsoleOrganization: Codable, Equatable, Identifiable {
    let uuid: String
    let name: String

    var id: String { uuid }
}

// MARK: - Credentials store

/// The API Console credentials, persisted in our own Keychain item
struct ConsoleCredentials: Equatable {
    var sessionKey: String
    var organizationId: String
    var organizationName: String

    var isConfigured: Bool { !sessionKey.isEmpty && !organizationId.isEmpty }

    /// Masked key for display. The full value is never shown or copied.
    var maskedSessionKey: String {
        guard sessionKey.count > 20 else { return String(repeating: "•", count: max(sessionKey.count, 8)) }
        return "\(sessionKey.prefix(14))\(String(repeating: "•", count: 6))\(sessionKey.suffix(4))"
    }
}

// MARK: - Service

@MainActor
final class ConsoleAPIService: ObservableObject {

    static let shared = ConsoleAPIService()

    private static let baseURL = "https://console.anthropic.com/api"
    private static let keychainKeySession = "consoleSessionKey"
    private static let keychainKeyOrgId = "consoleOrganizationId"
    private static let keychainKeyOrgName = "consoleOrganizationName"

    @Published private(set) var credentials: ConsoleCredentials
    @Published private(set) var currentSpend: ConsoleCurrentSpend?
    @Published private(set) var prepaidCredits: ConsolePrepaidCredits?
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy = false

    private let keychain = KeychainManager.shared

    private init() {
        credentials = ConsoleCredentials(
            sessionKey: KeychainManager.shared.loadConsoleValue(forKey: Self.keychainKeySession) ?? "",
            organizationId: KeychainManager.shared.loadConsoleValue(forKey: Self.keychainKeyOrgId) ?? "",
            organizationName: KeychainManager.shared.loadConsoleValue(forKey: Self.keychainKeyOrgName) ?? ""
        )
    }

    var isConfigured: Bool { credentials.isConfigured }

    // MARK: - Credential lifecycle

    /// Validate a pasted console session key by listing the organizations it can see
    func fetchOrganizations(sessionKey: String) async throws -> [ConsoleOrganization] {
        try await get([ConsoleOrganization].self, path: "/organizations", sessionKey: sessionKey)
    }

    /// Persist the chosen organization and pull a first set of figures
    func save(sessionKey: String, organization: ConsoleOrganization) async {
        credentials = ConsoleCredentials(
            sessionKey: sessionKey,
            organizationId: organization.uuid,
            organizationName: organization.name
        )
        _ = keychain.saveConsoleValue(sessionKey, forKey: Self.keychainKeySession)
        _ = keychain.saveConsoleValue(organization.uuid, forKey: Self.keychainKeyOrgId)
        _ = keychain.saveConsoleValue(organization.name, forKey: Self.keychainKeyOrgName)
        Logger.settings.notice("API Console: credentials saved for an organization")
        await refresh()
    }

    /// Forget the console credentials. Nothing is revoked server side, we just drop our copy.
    func remove() {
        credentials = ConsoleCredentials(sessionKey: "", organizationId: "", organizationName: "")
        currentSpend = nil
        prepaidCredits = nil
        lastError = nil
        _ = keychain.deleteConsoleValue(forKey: Self.keychainKeySession)
        _ = keychain.deleteConsoleValue(forKey: Self.keychainKeyOrgId)
        _ = keychain.deleteConsoleValue(forKey: Self.keychainKeyOrgName)
        Logger.settings.notice("API Console: credentials removed")
    }

    // MARK: - Figures

    /// Refresh spend and credits. Either call failing leaves the other one intact.
    func refresh() async {
        guard credentials.isConfigured else { return }
        isBusy = true
        defer { isBusy = false }

        let orgId = credentials.organizationId
        let key = credentials.sessionKey

        do {
            currentSpend = try await get(
                ConsoleCurrentSpend.self,
                path: "/organizations/\(orgId)/current_spend",
                sessionKey: key
            )
            lastError = nil
            if let spend = currentSpend {
                UsageHistoryStore.shared.recordBilling(
                    spendCents: spend.amount,
                    currency: prepaidCredits?.currency ?? "USD"
                )
            }
        } catch {
            Logger.api.error("API Console: current_spend failed \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        do {
            prepaidCredits = try await get(
                ConsolePrepaidCredits.self,
                path: "/organizations/\(orgId)/prepaid/credits",
                sessionKey: key
            )
        } catch {
            // Not every account has prepaid credits, so a failure here is not worth surfacing
            Logger.api.debug("API Console: prepaid credits unavailable")
            prepaidCredits = nil
        }
    }

    // MARK: - Private

    private func get<T: Decodable>(_ type: T.Type, path: String, sessionKey: String) async throws -> T {
        guard let url = URL(string: Self.baseURL + path) else { throw UsageError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.networkError }

        switch http.statusCode {
        case 200...299:
            return try JSONDecoder().decode(T.self, from: data)
        case 401, 403:
            throw UsageError.unauthorized
        case 429:
            throw UsageError.rateLimited
        default:
            throw UsageError.httpError(statusCode: http.statusCode)
        }
    }
}
