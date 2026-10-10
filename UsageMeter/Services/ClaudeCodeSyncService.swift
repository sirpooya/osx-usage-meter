//
//  ClaudeCodeSyncService.swift
//  UsageMeter
//
//  "CLI Account Sync": adopt the account Claude Code CLI already signed in,
//  so the user pastes no sessionKey and goes through no browser OAuth.
//
//  How it relates to manual and browser login:
//  - The three paths do not interfere; configuring any one of them produces data (the same Claude.ai cookie / API Console / CLI split).
//  - A CLI synced account is marked credentialSource == .claudeCodeCLI, and re-reads the Keychain every time it needs a token,
//    because Claude Code rotates it behind our back.
//

import Combine
import Foundation
import OSLog

@MainActor
final class ClaudeCodeSyncService: ObservableObject {

    static let shared = ClaudeCodeSyncService()

    enum SyncState: Equatable {
        case notSynced
        case syncing
        case synced(at: Date)
        case failed(message: String)
    }

    // MARK: - Published

    @Published private(set) var state: SyncState = .notSynced
    /// The credentials currently read (the UI shows only the masked token, the subscription type and the scopes)
    @Published private(set) var credentials: ClaudeCodeCredentials?
    /// Every usable Claude Code Keychain entry on this machine
    @Published private(set) var availableEntries: [ClaudeCodeKeychain.Entry] = []

    /// The Keychain entry the user pinned under "credential source"; nil means automatic (the default entry wins)
    @Published var pinnedService: String? {
        didSet {
            guard pinnedService != oldValue else { return }
            if let pinnedService {
                UserDefaults.standard.set(pinnedService, forKey: Self.pinnedServiceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pinnedServiceKey)
            }
        }
    }

    private static let pinnedServiceKey = "cliSync.pinnedService"
    private static let lastSyncedAtKey = "cliSync.lastSyncedAt"

    /// When the last successful sync happened, kept across launches so the status card can
    /// show "1 hr, 35 min" rather than resetting to nothing every time the app restarts.
    @Published private(set) var lastSyncedAt: Date?

    /// Elapsed time since the last sync, in the compact form the status card shows
    var timeSinceSync: String? {
        guard let lastSyncedAt else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        let elapsed = max(0, Date().timeIntervalSince(lastSyncedAt))
        // Under a minute the seconds matter, above it they are noise
        if elapsed >= 60 { formatter.allowedUnits = [.hour, .minute] }
        return formatter.string(from: elapsed)
    }

    private init() {
        pinnedService = UserDefaults.standard.string(forKey: Self.pinnedServiceKey)
        availableEntries = ClaudeCodeKeychain.listEntries()
        let stored = UserDefaults.standard.double(forKey: Self.lastSyncedAtKey)
        lastSyncedAt = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    // MARK: - Queries

    /// Whether a Claude Code credential entry exists on this machine (only whether it exists, no secret data is read, so no prompt appears)
    var isAvailable: Bool { !availableEntries.isEmpty }

    /// The CLI account already synced (if any)
    var syncedAccount: Account? {
        UserSettings.shared.accounts.first { $0.credentialSource.isCLISynced }
    }

    var isSynced: Bool { syncedAccount != nil }

    /// Re-enumerate the Keychain entries (called by the Refresh button and when the settings page opens)
    func refreshEntries() {
        availableEntries = ClaudeCodeKeychain.listEntries()
    }

    // MARK: - Sync

    /// The silent sync at launch: adopts only when there is no CLI account yet and CLI credentials do exist on the machine,
    /// so on success the caller does not have to show the login window.
    /// - Returns: whether a usable account was established
    func syncOnLaunchIfNeeded() async -> Bool {
        refreshEntries()
        guard isAvailable else { return false }

        // A CLI account already exists: only realign its token to the latest Keychain value, do not rebuild the account
        if let existing = syncedAccount {
            realignStoredToken(for: existing)
            stampSynced()
            return true
        }

        // The user already configured a Claude account by hand, so do not replace their choice
        guard UserSettings.shared.accounts.isEmpty else { return false }

        return await sync()
    }

    /// Run one sync (first time setup, the Re-sync button, or a changed pinned entry)
    /// - Returns: whether it succeeded
    @discardableResult
    func sync() async -> Bool {
        state = .syncing
        refreshEntries()

        guard let credentials = readResolvedCredentials() else {
            self.credentials = nil
            state = .failed(message: L.CLISync.errorNoCredentials)
            Logger.settings.error("CLI sync: no readable Claude Code credentials found")
            return false
        }
        self.credentials = credentials

        guard !credentials.refreshToken.isEmpty else {
            // An entry with nothing but an access_token would not last an hour, so refuse to create an account and leave the user thinking they are set up
            state = .failed(message: L.CLISync.errorNoRefreshToken)
            Logger.settings.error("CLI sync: keychain item has no refresh_token, refusing to create an account")
            return false
        }

        let profile = await fetchProfile(credentials: credentials)
        upsertAccount(credentials: credentials, profile: profile)
        stampSynced()
        Logger.settings.notice("CLI sync: synced the Claude Code account from keychain service \(credentials.serviceName, privacy: .public)")
        return true
    }

    /// Unsync: delete the CLI synced account and clear this service's state.
    /// Only our own account list is touched, Claude Code's Keychain entry is never modified.
    func removeSync() {
        if let account = syncedAccount {
            UserSettings.shared.removeAccount(account)
        }
        credentials = nil
        state = .notSynced
        lastSyncedAt = nil
        UserDefaults.standard.removeObject(forKey: Self.lastSyncedAtKey)
        // Our own mirrored copy of the tokens has to go with the account, or it would keep serving
        // polls for an account the user just removed. Claude Code's own entry is still untouched.
        ClaudeTokenMirror.clear()
        Logger.settings.notice("CLI sync: removed the synced account (the Claude Code keychain item was left untouched)")
    }

    /// Record a successful sync, both in the published state and on disk
    private func stampSynced() {
        let now = Date()
        lastSyncedAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastSyncedAtKey)
        state = .synced(at: now)
    }

    // MARK: - For the API layer

    /// Read the CLI credentials to use right now (re-read on every poll, the token is never cached)
    nonisolated static func currentCredentials(preferredService: String?) -> ClaudeCodeCredentials? {
        if let preferredService,
           let credentials = ClaudeCodeKeychain.readCredentials(service: preferredService) {
            return credentials
        }
        return ClaudeCodeKeychain.readCredentials()
    }

    // MARK: - Private

    /// Resolve which entry to read from the pinned setting
    private func readResolvedCredentials() -> ClaudeCodeCredentials? {
        Self.currentCredentials(preferredService: pinnedService)
    }

    /// Once Claude Code rotates the token, realign the copy stored on the account,
    /// so we do not try to refresh with a long dead refresh_token.
    private func realignStoredToken(for account: Account) {
        guard let credentials = Self.currentCredentials(preferredService: account.keychainService ?? pinnedService) else { return }
        self.credentials = credentials
        guard !credentials.refreshToken.isEmpty, credentials.refreshToken != account.sessionKey else { return }
        UserSettings.shared.silentlyUpdateCurrentClaudeSessionToken(credentials.refreshToken)
    }

    /// Fetch the profile to fill in the account display name, a failure does not abort the sync
    private func fetchProfile(credentials: ClaudeCodeCredentials) async -> (email: String, orgId: String, orgName: String, tier: String, rateLimitTier: String)? {
        guard credentials.isAccessTokenUsable else { return nil }
        return await withCheckedContinuation { continuation in
            ClaudeOAuthService.fetchProfile(accessToken: credentials.accessToken) { result in
                switch result {
                case .success(let profile): continuation.resume(returning: profile)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Create or update the CLI synced account
    private func upsertAccount(
        credentials: ClaudeCodeCredentials,
        profile: (email: String, orgId: String, orgName: String, tier: String, rateLimitTier: String)?
    ) {
        let settings = UserSettings.shared
        let email = profile?.email ?? ""
        let orgId = profile?.orgId ?? ""

        // Tier for the popover title. The profile is the richer source ("claude_team"), but the Keychain
        // entry carries one too ("team") and is readable even when the access token has already expired.
        let profileTier = profile?.tier ?? ""
        let tier = profileTier.isEmpty ? credentials.subscriptionType : profileTier
        if !tier.isEmpty {
            settings.claudeSubscriptionTier = tier
        }
        let profileRateTier = profile?.rateLimitTier ?? ""
        let rateLimitTier = profileRateTier.isEmpty ? credentials.rateLimitTier : profileRateTier
        if !rateLimitTier.isEmpty {
            settings.claudeRateLimitTier = rateLimitTier
        }
        let displayName = email.isEmpty ? L.CLISync.defaultAccountName : email
        // Same dedupe identity as browser OAuth login: the organization uuid, falling back to the email,
        // and to the Keychain service name when neither exists (so one entry cannot create two accounts)
        let stableOrgId = !orgId.isEmpty ? orgId : (!email.isEmpty ? email : credentials.serviceName)

        // Remove an older account with the same identity first (addAccount skips an organizationId that already exists)
        if let existing = settings.accounts.first(where: {
            $0.organizationId == stableOrgId || $0.credentialSource.isCLISynced
        }) {
            settings.removeAccount(existing)
        }

        let account = Account(
            sessionKey: credentials.refreshToken,
            organizationId: stableOrgId,
            organizationName: displayName,
            alias: nil,
            provider: .claude,
            credentialSource: .claudeCodeCLI,
            keychainService: credentials.serviceName
        )
        settings.addAccount(account)
        settings.switchToAccount(account)
    }
}
