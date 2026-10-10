//
//  ClaudeCodeCredentials.swift
//  UsageMeter
//
//  Reads the OAuth credentials Claude Code CLI stores in the macOS Keychain,
//  so the user never has to paste a sessionKey or go through a browser login ("CLI Account Sync").
//
//  The Keychain entry looks like:
//    service = "Claude Code-credentials" (suffixed when CLAUDE_CONFIG_DIR is set,
//              "Claude Code-credentials-1100457a" for instance)
//    account = the macOS username
//    data    = {"claudeAiOauth":{"accessToken":…,"refreshToken":…,
//               "expiresAt":<milliseconds timestamp>,"scopes":[...],"subscriptionType":"team"}}
//
//  Note: reading a Keychain entry another app created requires that this app run with App Sandbox **off**
//  (inside the sandbox only entries in our own access group are reachable). See Config/UsageMeter.entitlements.
//

import Foundation
import OSLog
import Security

/// The OAuth credentials inside Claude Code's Keychain entry
struct ClaudeCodeCredentials: Equatable {
    /// Keychain service name ("Claude Code-credentials", or a variant with a config dir suffix)
    let serviceName: String
    /// Keychain account name (usually the macOS username)
    let accountName: String

    let accessToken: String
    let refreshToken: String
    /// access_token expiry; nil when the entry does not carry one
    let expiresAt: Date?
    let scopes: [String]
    /// Subscription type ("team" / "max" / "pro" and so on), an empty string when absent
    let subscriptionType: String
    /// Rate limit tier ("default_claude_max_5x" and so on), an empty string when absent
    let rateLimitTier: String

    /// Whether this access_token is still usable (with a 2 minute margin, to avoid the boundary)
    var isAccessTokenUsable: Bool {
        guard !accessToken.isEmpty else { return false }
        guard let expiresAt else { return true }  // With no expiry given, assume it is usable
        return expiresAt > Date().addingTimeInterval(2 * 60)
    }

    /// The masked token, for display only (first 12 characters plus the last 4, middle elided)
    /// The full token never touches disk and is never logged.
    var maskedAccessToken: String {
        Self.mask(accessToken)
    }

    static func mask(_ token: String) -> String {
        guard token.count > 20 else { return String(repeating: "•", count: max(token.count, 8)) }
        return "\(token.prefix(12))\(String(repeating: "•", count: 6))\(token.suffix(4))"
    }
}

/// Reading and writing Claude Code's Keychain entry
///
/// Secret data goes through `/usr/bin/security`, never `SecItemCopyMatching` / `SecItemUpdate` from this app.
/// Claude Code creates and rotates its entry with that tool, so `/usr/bin/security` sits in the entry's ACL and its
/// `apple-tool:` partition from birth, and reading through it never prompts. Reading in process made macOS check
/// this app against the entry instead: the "enter the login keychain password" prompt is the partition list check,
/// and clicking Always Allow did not stop it coming back. Enumerating attributes (`listEntries`) reads no secret,
/// so it stays on the Security framework.
enum ClaudeCodeKeychain {

    /// Service name prefix of Claude Code's Keychain entries (a suffixed variant means a non default CLAUDE_CONFIG_DIR)
    static let servicePrefix = "Claude Code-credentials"

    /// The default (unsuffixed) service name
    static let defaultService = "Claude Code-credentials"

    /// One usable Keychain entry (attributes only, no secret data)
    struct Entry: Identifiable, Hashable {
        var id: String { "\(service)\u{1F}\(account)" }
        let service: String
        let account: String

        /// Whether this is the entry of the default config dir
        var isDefault: Bool { service == ClaudeCodeKeychain.defaultService }

        /// For the picker: the default entry shows its service name, a suffixed one calls its suffix out
        var displayName: String {
            guard !isDefault else { return service }
            return service
        }
    }

    // MARK: - Enumerate entries (no secret data is read, so no Keychain authorization prompt appears)

    /// List every Claude Code credential entry, with the default one first
    static func listEntries() -> [Entry] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status != errSecItemNotFound {
                Logger.settings.error("CLI sync: keychain enumeration failed, OSStatus \(status)")
            }
            return []
        }

        let entries: [Entry] = items.compactMap { item in
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(servicePrefix) else { return nil }
            let account = item[kSecAttrAccount as String] as? String ?? ""
            return Entry(service: service, account: account)
        }

        return entries.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.service < rhs.service
        }
    }

    // MARK: - Read the credentials

    /// Read the credentials of one entry. When `service` is nil, take the first usable entry in listEntries order.
    /// - Note: this step reads secret data, so without prior authorization macOS raises one Keychain prompt (which stops appearing once the user clicks "Always Allow").
    static func readCredentials(service: String? = nil) -> ClaudeCodeCredentials? {
        let candidates: [Entry]
        if let service {
            candidates = listEntries().filter { $0.service == service }
        } else {
            candidates = listEntries()
        }

        for entry in candidates {
            if let credentials = readCredentials(entry: entry) {
                return credentials
            }
        }
        return nil
    }

    /// Read one specific entry
    static func readCredentials(entry: Entry) -> ClaudeCodeCredentials? {
        guard let data = readData(service: entry.service, account: entry.account) else { return nil }
        return parse(data: data, service: entry.service, account: entry.account)
    }

    /// Parse the JSON inside a Keychain entry
    static func parse(data: Data, service: String, account: String) -> ClaudeCodeCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any] else {
            Logger.settings.error("CLI sync: keychain payload is not in the expected claudeAiOauth shape")
            return nil
        }

        let accessToken = oauth["accessToken"] as? String ?? ""
        let refreshToken = oauth["refreshToken"] as? String ?? ""
        guard !accessToken.isEmpty || !refreshToken.isEmpty else {
            Logger.settings.error("CLI sync: keychain payload carries neither accessToken nor refreshToken")
            return nil
        }

        return ClaudeCodeCredentials(
            serviceName: service,
            accountName: account,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiryDate(from: oauth["expiresAt"]),
            scopes: oauth["scopes"] as? [String] ?? [],
            subscriptionType: oauth["subscriptionType"] as? String ?? "",
            rateLimitTier: oauth["rateLimitTier"] as? String ?? ""
        )
    }

    /// Claude Code writes expiresAt as a milliseconds timestamp; both seconds and milliseconds are accepted here
    /// (the 1e11 second threshold is about the year 5138, so every real seconds timestamp falls below it)
    private static func expiryDate(from raw: Any?) -> Date? {
        guard let number = raw as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 1e11 ? value / 1000 : value)
    }

    // MARK: - Write the rotated token back

    /// Write the refreshed token back into Claude Code's Keychain entry.
    ///
    /// Why this is mandatory: a refresh_token is **single use** on the server. Once we trade it for a new pair,
    /// the copy Claude Code holds is dead; skip the write back and the user's CLI gets logged out on its next refresh.
    /// The write preserves the entry's other fields, so keys Claude Code adds later are not wiped.
    /// - Returns: whether the write succeeded (a failure is not fatal, the caller only logs it)
    @discardableResult
    static func writeBack(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date?,
        to credentials: ClaudeCodeCredentials
    ) -> Bool {
        writeBackByService(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            service: credentials.serviceName,
            account: credentials.accountName
        )
    }

    /// The same write-back, addressed by service and account rather than by a credentials struct.
    ///
    /// The mirrored path (`ClaudeTokenMirror`) refreshes without ever reading Claude Code's item,
    /// so it holds only the origin service and account names, not a full `ClaudeCodeCredentials`.
    /// - Returns: whether the write succeeded (a failure is not fatal, the caller only logs it)
    @discardableResult
    static func writeBackByService(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date?,
        service: String,
        account: String
    ) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        if !account.isEmpty {
            query[kSecAttrAccount as String] = account
        }

        // Read the current content first, keeping the other fields inside and outside claudeAiOauth
        var result: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &result)
        guard readStatus == errSecSuccess, let data = result as? Data,
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else {
            Logger.settings.error("CLI sync: could not re-read the keychain item before write-back, OSStatus \(readStatus)")
            return false
        }

        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        if let expiresAt {
            // Claude Code uses a milliseconds timestamp, so the write back keeps the same unit
            oauth["expiresAt"] = Int(expiresAt.timeIntervalSince1970 * 1000)
        }
        root["claudeAiOauth"] = oauth

        guard let newData = try? JSONSerialization.data(withJSONObject: root) else { return false }

        // `-U` updates the existing item in place, which is how Claude Code rotates it too, so the
        // entry's ACL and partition list are untouched. The payload goes in as hex (`-X`) because
        // `security -i` cuts stdin lines off at about 4 KB and this JSON is already over 2 KB.
        // That leaves it visible to `ps` for the life of the call, which adds nothing: any process
        // running as this user can already read the entry silently through `security`.
        let hex = newData.map { String(format: "%02x", $0) }.joined()
        var arguments = ["add-generic-password", "-U", "-s", service]
        if !account.isEmpty {
            arguments += ["-a", account]
        }
        arguments += ["-X", hex]

        guard let result = runSecurity(arguments), result.status == 0 else {
            Logger.settings.error("CLI sync: keychain write-back through security failed")
            return false
        }

        Logger.settings.notice("CLI sync: rotated tokens written back to the Claude Code keychain item")
        return true
    }

    // MARK: - security(1)

    /// A `security` run is bounded: the tool has been seen to hang on some macOS 26 builds, and a
    /// hung read must not stall a poll (or, from the sync service, the main thread) indefinitely.
    private static let securityTimeout: TimeInterval = 5

    /// Read an entry's secret data through `security find-generic-password -w`.
    private static func readData(service: String, account: String) -> Data? {
        var arguments = ["find-generic-password", "-s", service]
        if !account.isEmpty {
            arguments += ["-a", account]
        }
        arguments.append("-w")

        guard let result = runSecurity(arguments) else { return nil }
        guard result.status == 0 else {
            // Exit 44 is "item not found"
            Logger.settings.error("CLI sync: security could not read the keychain item, exit \(result.status)")
            return nil
        }

        // -w prints the secret and a newline, and prints it hex encoded if it is not printable text
        let text = String(decoding: result.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.hasPrefix("{"), let decoded = hexDecoded(text) {
            return decoded
        }
        return Data(text.utf8)
    }

    /// Run `/usr/bin/security`, returning its exit status and stdout, or nil if it could not be
    /// launched or ran past `securityTimeout`.
    private static func runSecurity(_ arguments: [String]) -> (status: Int32, output: Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            Logger.settings.error("CLI sync: could not launch security, \(error.localizedDescription)")
            return nil
        }

        guard exited.wait(timeout: .now() + securityTimeout) == .success else {
            process.terminate()
            Logger.settings.error("CLI sync: security did not finish within \(securityTimeout)s")
            return nil
        }

        // A few KB of output, far under the pipe buffer, so reading after exit cannot deadlock
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, output)
    }

    private static func hexDecoded(_ text: String) -> Data? {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: bytes.count / 2)
        var index = 0
        while index < bytes.count {
            guard let byte = UInt8(String(decoding: bytes[index..<index + 2], as: UTF8.self), radix: 16) else {
                return nil
            }
            data.append(byte)
            index += 2
        }
        return data
    }
}
