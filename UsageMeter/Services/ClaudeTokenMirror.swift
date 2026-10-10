//
//  ClaudeTokenMirror.swift
//  UsageMeter
//
//  Our own copy of the OAuth tokens, in a Keychain item this app creates and therefore owns.
//
//  Why this exists: reading Claude Code's "Claude Code-credentials" item needs an ACL grant, and
//  that grant does not survive. Claude Code rewrites its own item whenever it rotates a token, and
//  a rewrite resets the item's ACL, so the "Always Allow" the user clicked is gone and the next
//  poll raises the authorization prompt again. Polling every 60s meant asking again every hour or
//  two, for a menu bar percentage nobody was interacting with.
//
//  The fix is to stop reading their item on the hot path. We read it once, mirror the tokens into
//  an item of our own, and serve every subsequent poll from that. An item created by this app has
//  this app in its ACL from birth, so reading it never prompts, and no other process rewrites it.
//  Claude Code's item is then only consulted when our own refresh_token is dead (the user signed
//  out and back in on the CLI, say), which is rare and worth one prompt.
//
//  Deliberately NOT routed through KeychainManager: that class swaps in a plaintext UserDefaults
//  backend for DEBUG builds, which is fine for an org id but not for a live OAuth token. This
//  writes to the real Keychain in every configuration.
//

import Foundation
import OSLog
import Security

/// The mirrored copy of Claude Code's OAuth credentials, in this app's own Keychain item
enum ClaudeTokenMirror {

    /// Service name of our own item. Distinct from `ClaudeCodeKeychain.servicePrefix`, so this
    /// can never be confused with (or matched by) an enumeration of Claude Code's own entries.
    private static let service = "in.pooya.usagemeter.tokens"

    /// Single account name: the app mirrors one CLI account at a time.
    private static let account = "cliMirror"

    /// What we keep. A subset of `ClaudeCodeCredentials`: enough to serve a poll and to refresh,
    /// plus the origin service name so a write-back can find the item it came from.
    struct Mirrored: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date?
        var subscriptionType: String
        /// Optional so a mirror written before this field existed still decodes
        var rateLimitTier: String?
        /// The Claude Code service name these tokens were originally read from
        var originService: String
        /// The Claude Code account name these tokens were originally read from
        var originAccount: String

        /// Whether the access token is still usable, with the same 2 minute margin
        /// `ClaudeCodeCredentials` uses, so the two cannot disagree about expiry.
        var isAccessTokenUsable: Bool {
            guard !accessToken.isEmpty else { return false }
            guard let expiresAt else { return true }
            return expiresAt > Date().addingTimeInterval(2 * 60)
        }
    }

    // MARK: - Read

    /// Read the mirrored tokens, or nil when nothing has been mirrored yet.
    ///
    /// This is the call the poll path makes. It touches only our own item, so it raises no prompt.
    static func load() -> Mirrored? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                Logger.keychain.error("Token mirror: read failed, OSStatus \(status)")
            }
            return nil
        }

        guard let mirrored = try? JSONDecoder().decode(Mirrored.self, from: data) else {
            Logger.keychain.error("Token mirror: stored payload could not be decoded")
            return nil
        }
        return mirrored
    }

    // MARK: - Write

    /// Store (or replace) the mirrored tokens.
    ///
    /// `kSecAttrAccessibleAfterFirstUnlock` so a poll that fires before the user has interacted
    /// with the machine still works; the item is not needed while the Mac is locked at boot.
    @discardableResult
    static func save(_ mirrored: Mirrored) -> Bool {
        guard let data = try? JSONEncoder().encode(mirrored) else { return false }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Update in place when the item already exists, so its ACL (which already names this app)
        // is preserved. Delete-then-add would create a fresh item each time, and while that item
        // would still be ours, it needlessly churns the ACL this whole file exists to keep stable.
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else {
            Logger.keychain.error("Token mirror: update failed, OSStatus \(updateStatus)")
            return false
        }

        var addQuery = identity
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Logger.keychain.error("Token mirror: create failed, OSStatus \(addStatus)")
            return false
        }
        Logger.keychain.notice("Token mirror: created this app's own token item")
        return true
    }

    /// Mirror a set of Claude Code credentials as they were just read.
    @discardableResult
    static func save(from credentials: ClaudeCodeCredentials) -> Bool {
        save(Mirrored(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt,
            subscriptionType: credentials.subscriptionType,
            rateLimitTier: credentials.rateLimitTier,
            originService: credentials.serviceName,
            originAccount: credentials.accountName
        ))
    }

    /// Update just the token trio after a refresh, keeping the origin fields.
    @discardableResult
    static func updateTokens(accessToken: String, refreshToken: String, expiresAt: Date?) -> Bool {
        guard var mirrored = load() else { return false }
        mirrored.accessToken = accessToken
        mirrored.refreshToken = refreshToken
        mirrored.expiresAt = expiresAt
        return save(mirrored)
    }

    // MARK: - Delete

    /// Remove our mirrored item. Claude Code's own item is untouched.
    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
