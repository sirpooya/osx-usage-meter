//
//  Account.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-02-05.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Credential source
/// Decides where the token comes from on a refresh: manually pasted credentials and browser OAuth credentials live on the account,
/// while a CLI synced account re-reads Claude Code's Keychain entry on every poll (the CLI rotates it behind our back).
enum CredentialSource: String, Codable {
    /// A manually pasted sessionKey, or a refresh_token the app got through browser OAuth itself
    case manual
    /// Synced from Claude Code CLI's Keychain entry
    case claudeCodeCLI

    var isCLISynced: Bool { self == .claudeCodeCLI }
}

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var sessionKey: String
    var organizationId: String
    var organizationName: String
    var alias: String?
    let createdAt: Date
    var provider: ProviderType
    /// Credential source (absent in older data, which decodes as .manual)
    var credentialSource: CredentialSource
    /// Keychain service name for a CLI synced account (nil for every other source)
    var keychainService: String?

    var displayName: String {
        if let alias = alias, !alias.isEmpty {
            return alias
        }
        return organizationName
    }

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id, sessionKey, organizationId, organizationName, alias, createdAt, provider
        case credentialSource, keychainService
    }

    // MARK: - Codable

    // Custom decoding: older JSON has no provider field and defaults to .claude, so stored accounts need zero migration
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionKey = try container.decode(String.self, forKey: .sessionKey)
        organizationId = try container.decode(String.self, forKey: .organizationId)
        organizationName = try container.decode(String.self, forKey: .organizationName)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        provider = try container.decodeIfPresent(ProviderType.self, forKey: .provider) ?? .claude
        credentialSource = try container.decodeIfPresent(CredentialSource.self, forKey: .credentialSource) ?? .manual
        keychainService = try container.decodeIfPresent(String.self, forKey: .keychainService)
    }

    // MARK: - Initialization

    init(
        sessionKey: String,
        organizationId: String,
        organizationName: String,
        alias: String? = nil,
        provider: ProviderType = .claude,
        credentialSource: CredentialSource = .manual,
        keychainService: String? = nil
    ) {
        self.id = UUID()
        self.sessionKey = sessionKey
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.alias = alias
        self.createdAt = Date()
        self.provider = provider
        self.credentialSource = credentialSource
        self.keychainService = keychainService
    }

    init(
        id: UUID,
        sessionKey: String,
        organizationId: String,
        organizationName: String,
        alias: String?,
        createdAt: Date,
        provider: ProviderType = .claude,
        credentialSource: CredentialSource = .manual,
        keychainService: String? = nil
    ) {
        self.id = id
        self.sessionKey = sessionKey
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.alias = alias
        self.createdAt = createdAt
        self.provider = provider
        self.credentialSource = credentialSource
        self.keychainService = keychainService
    }

    // MARK: - Equatable

    static func == (lhs: Account, rhs: Account) -> Bool {
        return lhs.id == rhs.id
    }
}
