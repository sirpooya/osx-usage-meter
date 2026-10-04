//
//  SensitiveDataRedactor.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Sensitive data redactor
/// One place for redacting sensitive data, used by logging and diagnostic reports
/// Handles Organization IDs, session keys and sensitive data embedded in text
class SensitiveDataRedactor {
    // MARK: - Public Methods

    /// Redact an Organization ID
    /// - Parameter id: the raw Organization ID
    /// - Returns: the redacted string
    /// - Note: an ID shorter than 8 characters is replaced entirely with asterisks; otherwise the first and last 4 characters are kept
    /// - Example: "12345678-1234-1234-1234-123456789012" -> "1234...9012"
    static func redactOrganizationId(_ id: String) -> String {
        guard id.count > 8 else {
            return String(repeating: "*", count: id.count)
        }
        let prefix = id.prefix(4)
        let suffix = id.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    /// Redact a session key
    /// - Parameter key: the raw session key
    /// - Returns: the redacted string
    /// - Note: a key starting with sk-ant- keeps the prefix and shows the length; anything else returns "***"
    /// - Example: "sk-ant-sid...XXXXX" -> "sk-ant-***...*** (128 chars)"
    static func redactSessionKey(_ key: String) -> String {
        guard key.count > 20 else {
            return "***"
        }

        // Keep the "sk-ant-" prefix
        if key.hasPrefix("sk-ant-") {
            return "sk-ant-***...*** (\(key.count) chars)"
        }

        // Keys in any other format
        return "***...*** (\(key.count) chars)"
    }

    /// Redact a Codex session token (a long JWE string)
    /// - Parameter token: the value of __Secure-next-auth.session-token
    /// - Returns: the redacted string, keeping the first 8 and last 4 characters
    static func redactCodexSessionToken(_ token: String) -> String {
        guard token.count > 12 else {
            return String(repeating: "*", count: token.count)
        }
        return "\(token.prefix(8))...\(token.suffix(4)) (\(token.count) chars)"
    }

    /// Redact a JWT access token (the three part header.payload.signature form)
    /// - Parameter token: the Bearer accessToken string
    /// - Returns: the redacted string, keeping only the first 6 characters of each part
    static func redactAccessToken(_ token: String) -> String {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            guard token.count > 12 else { return "***" }
            return "\(token.prefix(8))...\(token.suffix(4)) (\(token.count) chars)"
        }
        let h = String(parts[0].prefix(6))
        let p = String(parts[1].prefix(6))
        let s = String(parts[2].prefix(6))
        return "\(h)...\(p)...\(s)... (\(token.count) chars)"
    }

    /// Redact sensitive data inside text
    /// Finds and replaces Organization IDs and session keys in text with regular expressions
    /// - Parameter text: the raw text containing sensitive data
    /// - Returns: the redacted text
    /// - Note: used for log and diagnostic output, it recognizes and redacts the common formats automatically
    static func redactText(_ text: String) -> String {
        var sanitized = text

        // Redact session keys (keeping the first and last 4 characters)
        // Patterns: sessionKey=xxx and sessionKey: xxx
        let sessionKeyPattern = "sessionKey[=:]\\s*[\"']?([a-zA-Z0-9-]{20,})[\"']?"
        if let regex = try? NSRegularExpression(pattern: sessionKeyPattern, options: .caseInsensitive) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "sessionKey=***REDACTED***"
            )
        }

        // Redact Organization IDs (UUID format)
        // Pattern: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        let orgIdPattern = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
        if let regex = try? NSRegularExpression(pattern: orgIdPattern, options: .caseInsensitive) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "********-****-****-****-************"
            )
        }

        // Redact the sessionKey inside a Cookie
        // Pattern: Cookie: sessionKey=xxx
        let cookiePattern = "Cookie:\\s*sessionKey=([a-zA-Z0-9-]{20,})"
        if let regex = try? NSRegularExpression(pattern: cookiePattern, options: .caseInsensitive) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "Cookie: sessionKey=***REDACTED***"
            )
        }

        // Redact bare tokens.
        //
        // Every pattern above needs a sessionKey= or Cookie: style label in front of the token,
        // but the most common shape in a log is the bare string with no label: an exception reason, a URL or an error
        // description carrying an sk-ant-... straight through. Without this pattern the "never log a token"
        // rule actually leaks.
        let bareTokenPatterns = [
            // Anthropic key / OAuth token: sk-ant-*
            "sk-ant-[A-Za-z0-9_-]{8,}",
            // Authorization: Bearer <any long string>
            "(?i)(bearer)\\s+[A-Za-z0-9._~+/=-]{12,}",
            // The three part JWT, which is the shape of a Codex session token
            "eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{4,}",
            // OAuth refresh / access token fields
            "(?i)(access_token|refresh_token|accessToken|refreshToken)[\"']?\\s*[=:]\\s*[\"']?[A-Za-z0-9._~+/=-]{12,}",
        ]
        for pattern in bareTokenPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            // $1 keeps the label (Bearer / access_token) and eats only the value that follows,
            // so the log still shows which kind of credential went wrong.
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "$1***REDACTED***"
            )
        }

        return sanitized
    }
}
