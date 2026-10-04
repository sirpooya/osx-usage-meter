//
//  AccountStore.swift
//  UsageMeter
//
//  Extracted from UserSettings.swift (audit report 4.1): account CRUD, Keychain persistence,
//  the current account ID, silentlyUpdate*Token and the rest of the multi account logic became one composable ObservableObject.
//  UserSettings holds it through its accountStore property and forwards to it, so the public API is unchanged.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine
import OSLog

/// Multi account (Claude + Codex) storage, persistence and switching
final class AccountStore: ObservableObject {

    private let defaults = UserDefaults.standard
    private let keychain = KeychainManager.shared

    // MARK: - Claude accounts

    /// Account list (stored in the Keychain)
    @Published var accounts: [Account] {
        didSet {
            saveAccounts()
        }
    }

    /// ID of the active account (stored in UserDefaults)
    @Published var currentAccountId: UUID? {
        didSet {
            #if DEBUG
            let key = "DEBUG_currentAccountId"
            #else
            let key = "currentAccountId"
            #endif
            if let id = currentAccountId {
                defaults.set(id.uuidString, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// The active account
    var currentAccount: Account? {
        guard let id = currentAccountId else { return accounts.first }
        return accounts.first { $0.id == id } ?? accounts.first
    }

    /// Claude session key (computed, points at the current account)
    var sessionKey: String {
        get { currentAccount?.sessionKey ?? "" }
        set {
            guard let id = currentAccountId,
                  let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index].sessionKey = newValue
        }
    }

    /// Claude organization ID (computed, points at the current account)
    var organizationId: String {
        get { currentAccount?.organizationId ?? "" }
        set {
            guard let id = currentAccountId,
                  let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index].organizationId = newValue
        }
    }

    /// Semantic alias for the Claude account list (same as accounts, keeps provider aware code symmetric)
    var claudeAccounts: [Account] { accounts }

    /// Account list used for display
    var displayAccounts: [Account] { accounts }

    /// Display name of the current account
    var currentAccountName: String? { currentAccount?.displayName }

    // MARK: - Codex accounts

    /// Codex account list (stored under its own Keychain key "accounts_codex", so Claude data is untouched)
    @Published var codexAccounts: [Account] {
        didSet {
            saveCodexAccounts()
        }
    }

    /// ID of the active Codex account (stored in UserDefaults)
    @Published var currentCodexAccountId: UUID? {
        didSet {
            #if DEBUG
            let key = "DEBUG_currentCodexAccountId"
            #else
            let key = "currentCodexAccountId"
            #endif
            if let id = currentCodexAccountId {
                defaults.set(id.uuidString, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// The active Codex account
    var currentCodexAccount: Account? {
        guard let id = currentCodexAccountId else { return codexAccounts.first }
        return codexAccounts.first { $0.id == id } ?? codexAccounts.first
    }

    /// Codex session token (computed, points at the current Codex account's sessionKey field)
    var codexSessionToken: String {
        currentCodexAccount?.sessionKey ?? ""
    }

    /// Whether Codex authentication is configured
    var hasValidCodexCredentials: Bool {
        !codexSessionToken.isEmpty
    }

    // MARK: - Initialization

    init() {
        // MARK: - Load multi account data (v2.1.0)

        // Load the account list from the Keychain (into a local, to avoid initialization order problems)
        var loadedAccounts = keychain.loadAccounts() ?? []
        var loadedCurrentAccountId: UUID? = nil

        // Load the current account ID
        #if DEBUG
        let currentAccountIdKey = "DEBUG_currentAccountId"
        #else
        let currentAccountIdKey = "currentAccountId"
        #endif
        if let idString = defaults.string(forKey: currentAccountIdKey),
           let id = UUID(uuidString: idString) {
            loadedCurrentAccountId = id
        } else if let firstAccount = loadedAccounts.first {
            // With no saved current account ID, default to the first account
            loadedCurrentAccountId = firstAccount.id
        }

        // MARK: - Data migration (v2.0.x to v2.1.0 multi account)

        // Check whether a single account needs migrating to multi account
        if loadedAccounts.isEmpty && !defaults.bool(forKey: "multiAccountMigrated") {
            // Try migrating from the old single account data
            let oldSessionKey = keychain.loadSessionKey() ?? ""
            let oldOrgId = defaults.string(forKey: "organizationId") ?? ""

            if !oldSessionKey.isEmpty && !oldOrgId.isEmpty {
                Logger.settings.notice("[Migration] Migrating single account to multi-account system")

                // Get the organization name (if it is cached)
                let cachedOrgs = Self.loadOrganizations(from: defaults)
                let orgName = cachedOrgs.first { $0.uuid == oldOrgId }?.name ?? "Account 1"

                // Create the first account
                let migratedAccount = Account(
                    sessionKey: oldSessionKey,
                    organizationId: oldOrgId,
                    organizationName: orgName
                )
                loadedAccounts = [migratedAccount]
                loadedCurrentAccountId = migratedAccount.id

                // Clean up the old single account data
                keychain.deleteSessionKey()
                defaults.removeObject(forKey: "organizationId")

                Logger.settings.notice("[Migration] Multi-account migration completed")
            }

            defaults.set(true, forKey: "multiAccountMigrated")
        }

        // Set accounts and currentAccountId
        self.accounts = loadedAccounts
        self.currentAccountId = loadedCurrentAccountId

        // MARK: - Load Codex account data

        let loadedCodexAccounts = keychain.loadCodexAccounts() ?? []
        self.codexAccounts = loadedCodexAccounts

        #if DEBUG
        let codexCurrentAccountIdKey = "DEBUG_currentCodexAccountId"
        #else
        let codexCurrentAccountIdKey = "currentCodexAccountId"
        #endif
        if let idString = defaults.string(forKey: codexCurrentAccountIdKey),
           let id = UUID(uuidString: idString) {
            self.currentCodexAccountId = id
        } else {
            self.currentCodexAccountId = loadedCodexAccounts.first?.id
        }

        // MARK: - Legacy migration (v1.x to v2.0.0, kept for backward compatibility)

        // Migrate the organization ID from the Keychain to UserDefaults (legacy migration, now covered by the multi account migration above)
        if !defaults.bool(forKey: "organizationIdMigrated") {
            if let oldOrgId = keychain.loadOrganizationId(), !oldOrgId.isEmpty {
                Logger.settings.notice("[Migration] Found Organization ID in old Keychain location")
                keychain.deleteOrganizationId()
            }
            defaults.set(true, forKey: "organizationIdMigrated")
        }
    }

    // MARK: - Claude Account Management

    /// Save the account list to the Keychain
    private func saveAccounts() {
        // Snapshot on the calling thread (the main thread) so background queues never read the mutable array the main thread owns, which would be a data race
        let snapshot = accounts
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.keychain.saveAccounts(snapshot)
        }
    }

    /// Add a new account
    /// - Parameter account: the account to add
    /// - Returns: whether this is the first Claude account (callers use it to run one time setup)
    @discardableResult
    func addAccount(_ account: Account) -> Bool {
        // Check for an existing account with the same organizationId
        if accounts.contains(where: { $0.organizationId == account.organizationId }) {
            Logger.settings.notice("Account already exists, skipping: \(account.displayName)")
            return false
        }
        let wasFirstClaudeAccount = accounts.isEmpty
        accounts.append(account)
        // Make the first account the current one automatically
        if accounts.count == 1 {
            currentAccountId = account.id
        }
        Logger.settings.notice("Added account: \(account.displayName)")

        if wasFirstClaudeAccount {
            postAccountChanged(provider: .claude)
        }
        return wasFirstClaudeAccount
    }

    /// Delete an account
    /// - Parameter account: the account to delete
    func removeAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }

        let wasCurrentAccount = (currentAccountId == account.id)
        accounts.remove(at: index)
        NotificationManager.shared.resetNotificationStates(for: .claude, accountId: account.id)

        // When the deleted account was the current one, switch to the first account
        if wasCurrentAccount {
            currentAccountId = accounts.first?.id
            // Post the account changed notification
            postAccountChanged(provider: .claude)
        }

        Logger.settings.notice("Removed account: \(account.displayName)")
    }

    /// Switch to the given account
    /// - Parameter account: the account to switch to
    func switchToAccount(_ account: Account) {
        guard account.id != currentAccountId else { return }
        guard accounts.contains(where: { $0.id == account.id }) else { return }

        currentAccountId = account.id
        Logger.settings.notice("Switched to account: \(account.displayName)")

        // Post the account changed notification
        postAccountChanged(provider: .claude)
    }

    /// Update account information
    /// - Parameters:
    ///   - account: the account to update
    ///   - alias: new alias (optional)
    func updateAccount(_ account: Account, alias: String?) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].alias = alias
        let displayName = accounts[index].displayName
        Logger.settings.notice("Updated account alias: \(displayName)")
    }

    /// Silently update the current Claude account's session token (does not post accountChanged)
    /// For the OAuth refresh_token rotation case: only the persisted data changes, no refetch loop is triggered
    func silentlyUpdateCurrentClaudeSessionToken(_ token: String) {
        guard let id = currentAccountId,
              let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        guard accounts[index].sessionKey != token else { return }
        // Account is a struct, so a subscript assignment triggers accounts.didSet and saveAccounts(), persisting automatically
        accounts[index].sessionKey = token
        Logger.settings.notice("Claude session-token updated silently (auto renewal)")
    }

    // MARK: - Codex Account Management

    private func saveCodexAccounts() {
        // Snapshot on the calling thread (the main thread) so background queues never read the mutable array the main thread owns, which would be a data race
        let snapshot = codexAccounts
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.keychain.saveCodexAccounts(snapshot)
        }
    }

    /// Add or update a Codex account
    /// - Returns: (the stored account, whether this is the first Codex account added)
    ///   The second value lets callers decide whether to run the one time "first Codex account" setup
    @discardableResult
    func addCodexAccount(_ account: Account) -> (account: Account, wasFirstCodexAccount: Bool) {
        let stableId = account.organizationId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existingIndex = codexAccounts.firstIndex { existing in
            if !stableId.isEmpty {
                let existingStableId = existing.organizationId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return existingStableId == stableId || existing.sessionKey == account.sessionKey
            }
            return existing.sessionKey == account.sessionKey
        }

        if let index = existingIndex {
            codexAccounts[index].sessionKey = account.sessionKey
            codexAccounts[index].organizationId = account.organizationId
            codexAccounts[index].organizationName = account.organizationName
            codexAccounts[index].provider = .codex
            if currentCodexAccountId == nil {
                currentCodexAccountId = codexAccounts[index].id
            }
            Logger.settings.notice("Updated the existing Codex account: \(self.codexAccounts[index].displayName)")
            postAccountChanged(provider: .codex)
            return (codexAccounts[index], false)
        }

        let wasFirstCodexAccount = codexAccounts.isEmpty
        var storedAccount = account
        storedAccount.provider = .codex
        codexAccounts.append(storedAccount)
        if codexAccounts.count == 1 {
            currentCodexAccountId = storedAccount.id
        }
        Logger.settings.notice("Added Codex account: \(storedAccount.displayName)")
        postAccountChanged(provider: .codex)
        return (storedAccount, wasFirstCodexAccount)
    }

    func removeCodexAccount(_ account: Account) {
        guard let index = codexAccounts.firstIndex(where: { $0.id == account.id }) else { return }
        let wasCurrent = (currentCodexAccountId == account.id)
        codexAccounts.remove(at: index)
        NotificationManager.shared.resetNotificationStates(for: .codex, accountId: account.id)
        if wasCurrent {
            currentCodexAccountId = codexAccounts.first?.id
            postAccountChanged(provider: .codex)
        }
        Logger.settings.notice("Removed Codex account: \(account.displayName)")
    }

    func switchToCodexAccount(_ account: Account) {
        guard account.id != currentCodexAccountId else { return }
        guard codexAccounts.contains(where: { $0.id == account.id }) else { return }
        currentCodexAccountId = account.id
        Logger.settings.notice("Switched to Codex account: \(account.displayName)")
        postAccountChanged(provider: .codex)
    }

    func updateCodexAccount(_ account: Account, alias: String?) {
        guard let index = codexAccounts.firstIndex(where: { $0.id == account.id }) else { return }
        codexAccounts[index].alias = alias
        Logger.settings.notice("Updated Codex account alias: \(self.codexAccounts[index].displayName)")
    }

    /// Silently update the current Codex account's session token (does not post accountChanged)
    /// For the auto renewal case: only the persisted data changes, no refetch loop is triggered
    func silentlyUpdateCurrentCodexSessionToken(_ token: String) {
        guard let id = currentCodexAccountId,
              let index = codexAccounts.firstIndex(where: { $0.id == id }) else { return }
        guard codexAccounts[index].sessionKey != token else { return }
        // Account is a struct, so a subscript assignment triggers codexAccounts.didSet and saveCodexAccounts(), persisting automatically
        codexAccounts[index].sessionKey = token
        Logger.settings.notice("Codex session-token updated silently (auto renewal)")
    }

    // MARK: - Shared Helpers

    private func postAccountChanged(provider: ProviderType) {
        NotificationCenter.default.post(
            name: .accountChanged,
            object: nil,
            userInfo: [Notification.UserInfoKey.provider: provider.rawValue]
        )
    }

    /// Load the organization list from UserDefaults (used to look up organization names during the v2.0.x to v2.1.0 migration)
    /// - Parameter defaults: the UserDefaults instance
    /// - Returns: the organization list, or an empty array when loading fails
    private static func loadOrganizations(from defaults: UserDefaults) -> [Organization] {
        guard let data = defaults.data(forKey: "cachedOrganizations") else {
            return []
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode([Organization].self, from: data)) ?? []
    }
}
