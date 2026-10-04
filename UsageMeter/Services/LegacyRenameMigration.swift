//
//  LegacyRenameMigration.swift
//  UsageMeter
//
//  One time carry over from the app's previous identity, ClaudeUsage (bundle id
//  com.claudeusage.ClaudeUsage). A new bundle id means a new UserDefaults domain, a new Keychain
//  service and a new Application Support folder, so without this the renamed app would start
//  with no settings, no accounts and no history.
//
//  Non destructive: everything is copied (or, for the folder, moved only when the new one does
//  not exist yet), existing values in the new domain always win, and the old domain is left in
//  place. Runs once, gated by `doneKey`.
//
//  Must run before anything reads settings, which is why AppDelegate calls it from its first
//  stored property rather than from applicationDidFinishLaunching: `UserSettings.shared` is
//  already loaded by then.
//

import Foundation
import OSLog
import Security

enum LegacyRenameMigration {

    static let legacyBundleID = "com.claudeusage.ClaudeUsage"
    private static let legacyFolderName = "ClaudeUsage"
    private static let folderName = "UsageMeter"
    private static let doneKey = "legacyRename.migratedFromClaudeUsage"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        migrateDefaults(into: defaults)
        #if !DEBUG
        // DEBUG builds keep KeychainManager's values in UserDefaults (`DEBUG_*` keys), which the
        // defaults copy above already carried over.
        migrateKeychainItems()
        #endif
        migrateApplicationSupportFolder()

        defaults.set(true, forKey: doneKey)
    }

    // MARK: - UserDefaults

    private static func migrateDefaults(into defaults: UserDefaults) {
        guard let legacy = defaults.persistentDomain(forName: legacyBundleID), !legacy.isEmpty else { return }

        var copied = 0
        for (key, value) in legacy {
            // Window autosave names carried the old app name, e.g. "NSWindow Frame ClaudeUsage.SettingsWindow"
            let newKey = key.replacingOccurrences(of: "\(legacyFolderName).", with: "\(folderName).")
            guard defaults.object(forKey: newKey) == nil else { continue }
            defaults.set(value, forKey: newKey)
            copied += 1
        }
        Logger.settings.notice("Rename migration: copied \(copied) settings from \(legacyBundleID, privacy: .public)")
    }

    // MARK: - Keychain

    /// Copies KeychainManager's items from the old service to the new one. Each read may raise one
    /// authorization prompt, because the items' ACL names the old bundle id.
    private static func migrateKeychainItems() {
        guard let newService = Bundle.main.bundleIdentifier, newService != legacyBundleID else { return }

        // Attributes only: macOS refuses kSecReturnData together with kSecMatchLimitAll.
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyBundleID,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var listResult: CFTypeRef?
        guard SecItemCopyMatching(listQuery as CFDictionary, &listResult) == errSecSuccess,
              let items = listResult as? [[String: Any]] else { return }

        var copied = 0
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }

            let readQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyBundleID,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var dataResult: CFTypeRef?
            guard SecItemCopyMatching(readQuery as CFDictionary, &dataResult) == errSecSuccess,
                  let data = dataResult as? Data else { continue }

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: newService,
                kSecAttrAccount as String: account,
                kSecValueData as String: data
            ]
            // errSecDuplicateItem means the new app already wrote this one, which wins.
            if SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess {
                copied += 1
            }
        }
        Logger.keychain.notice("Rename migration: copied \(copied) Keychain items")
    }

    // MARK: - Application Support

    /// Moves usage history and logs. Only when the new folder does not exist yet, so a history the
    /// renamed app has already started is never overwritten.
    private static func migrateApplicationSupportFolder() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacy = base.appendingPathComponent(legacyFolderName, isDirectory: true)
        let current = base.appendingPathComponent(folderName, isDirectory: true)

        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: current.path) else { return }
        do {
            try fm.moveItem(at: legacy, to: current)
            Logger.settings.notice("Rename migration: moved Application Support folder")
        } catch {
            Logger.settings.error("Rename migration: folder move failed: \(error.localizedDescription)")
        }
    }
}
