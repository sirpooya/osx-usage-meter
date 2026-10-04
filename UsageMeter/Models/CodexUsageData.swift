//
//  CodexUsageData.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-04-24.
//  Copyright © 2025 f-is-h. All rights reserved.
//
//  Pure-data types + parsing for the Codex /backend-api/wham/usage response.
//  Lives here (not Helpers/) so it can be cherry-picked into a SwiftPM test
//  target — every symbol here must stay free of `L.*`/`Logger`/UI dependency.
//  The `L.*`-dependent display formatting lives in
//  `CodexUsageData+Formatting.swift`.
//

import Foundation

// MARK: - Internal data models

/// Codex usage data (the app's normalized structure)
struct CodexUsageData: Sendable {
    /// 5 hour window usage (primary)
    let primary: LimitData?
    /// 7 day window usage (secondary)
    let secondary: LimitData?
    /// Codex Extra Usage / credits data
    let extraUsage: CodexExtraUsageData?

    struct LimitData: Sendable {
        /// Current usage percentage (0-100)
        let percentage: Double
        /// Reset time, nil means usage has not started yet
        let resetsAt: Date?
    }
}

// MARK: - API response models

/// Codex /backend-api/wham/usage response model
nonisolated struct CodexUsageResponse: Codable, Sendable {
    let account_id: String?
    let email: String?
    let plan_type: String?
    let rate_limit: RateLimit?
    let credits: Credits?
    let spend_control: SpendControl?

    struct RateLimit: Codable, Sendable {
        let allowed: Bool?
        let limit_reached: Bool?
        let primary_window: Window?
        let secondary_window: Window?
    }

    struct Window: Codable, Sendable {
        /// Usage percentage (0-100)
        let used_percent: Double
        /// Window length (seconds): 18000 = 5 hours, 604800 = 7 days
        let limit_window_seconds: Int?
        /// Seconds left until the reset
        let reset_after_seconds: Int?
        /// Reset time (a Unix timestamp, unlike Claude's ISO 8601)
        let reset_at: Int?
    }

    struct Credits: Codable, Sendable {
        let has_credits: Bool?
        let unlimited: Bool?
        let overage_limit_reached: Bool?
        let balance: String?
        let approx_local_messages: [Int]?
        let approx_cloud_messages: [Int]?

        private enum CodingKeys: String, CodingKey {
            case has_credits
            case unlimited
            case overage_limit_reached
            case balance
            case approx_local_messages
            case approx_cloud_messages
        }

        init(
            has_credits: Bool?,
            unlimited: Bool?,
            overage_limit_reached: Bool?,
            balance: String?,
            approx_local_messages: [Int]?,
            approx_cloud_messages: [Int]?
        ) {
            self.has_credits = has_credits
            self.unlimited = unlimited
            self.overage_limit_reached = overage_limit_reached
            self.balance = balance
            self.approx_local_messages = approx_local_messages
            self.approx_cloud_messages = approx_cloud_messages
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            has_credits = try container.decodeIfPresent(Bool.self, forKey: .has_credits)
            unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited)
            overage_limit_reached = try container.decodeIfPresent(Bool.self, forKey: .overage_limit_reached)
            approx_local_messages = try container.decodeIfPresent([Int].self, forKey: .approx_local_messages)
            approx_cloud_messages = try container.decodeIfPresent([Int].self, forKey: .approx_cloud_messages)

            if let stringBalance = try? container.decodeIfPresent(String.self, forKey: .balance) {
                balance = stringBalance
            } else if let doubleBalance = try? container.decodeIfPresent(Double.self, forKey: .balance) {
                balance = String(doubleBalance)
            } else if let intBalance = try? container.decodeIfPresent(Int.self, forKey: .balance) {
                balance = String(intBalance)
            } else {
                balance = nil
            }
        }
    }

    struct SpendControl: Codable, Sendable {
        let reached: Bool?
    }

    /// Standard length of the 5 hour window (seconds)
    private static let fiveHourWindowSeconds = 18_000
    /// Standard length of the 7 day window (seconds)
    private static let sevenDayWindowSeconds = 604_800

    /// Decide whether a window belongs to the "5 hour" bucket, from the real limit_window_seconds
    /// rather than from the JSON field name (primary_window/secondary_window).
    /// Background: Codex once dropped the 5 hour limit temporarily, and the single remaining window still arrived in the primary_window slot
    /// while its limit_window_seconds was 604800 (7 days), so mapping by field position would have shown it as a "5 hour limit".
    /// A missing limit_window_seconds is treated conservatively as not 5 hour, so old data is not misclassified.
    private static func isFiveHourWindow(_ window: Window) -> Bool {
        guard let seconds = window.limit_window_seconds else { return false }
        return abs(seconds - fiveHourWindowSeconds) < abs(seconds - sevenDayWindowSeconds)
    }

    /// Convert the API response into the internal CodexUsageData
    func toCodexUsageData() -> CodexUsageData {
        let now = Date()

        func resolvedResetDate(for window: Window) -> Date? {
            if let resetAt = window.reset_at {
                return Date(timeIntervalSince1970: TimeInterval(resetAt))
            }
            if let resetAfterSeconds = window.reset_after_seconds {
                return now.addingTimeInterval(TimeInterval(resetAfterSeconds))
            }
            return nil
        }

        func buildLimitData(_ window: Window?) -> CodexUsageData.LimitData? {
            guard let w = window else { return nil }
            // Treat used_percent of 0 with no reset info as invalid data
            if w.used_percent == 0 && w.reset_at == nil && w.reset_after_seconds == nil { return nil }
            return .init(percentage: w.used_percent, resetsAt: resolvedResetDate(for: w))
        }

        // Classify by real duration rather than by JSON field position, see the isFiveHourWindow comment
        let windows = [rate_limit?.primary_window, rate_limit?.secondary_window].compactMap { $0 }
        let primary = buildLimitData(windows.first { Self.isFiveHourWindow($0) })
        let secondary = buildLimitData(windows.first { !Self.isFiveHourWindow($0) })

        let extraUsage = credits.map {
            CodexExtraUsageData(
                hasCredits: $0.has_credits ?? false,
                unlimited: $0.unlimited ?? false,
                overageLimitReached: $0.overage_limit_reached ?? false,
                spendControlReached: spend_control?.reached ?? false,
                balance: CodexExtraUsageData.parseBalance($0.balance),
                approxLocalMessages: $0.approx_local_messages,
                approxCloudMessages: $0.approx_cloud_messages
            )
        }

        return CodexUsageData(primary: primary, secondary: secondary, extraUsage: extraUsage)
    }
}

/// Codex Extra Usage / credits data
/// Codex returns the available balance and a rough message count, not the used/limit shape of Claude's Extra Usage.
nonisolated struct CodexExtraUsageData: Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let overageLimitReached: Bool
    let spendControlReached: Bool
    let balance: Decimal?
    let approxLocalMessages: [Int]?
    let approxCloudMessages: [Int]?
    let visualPercentage: Double?

    init(
        hasCredits: Bool,
        unlimited: Bool,
        overageLimitReached: Bool,
        spendControlReached: Bool,
        balance: Decimal?,
        approxLocalMessages: [Int]?,
        approxCloudMessages: [Int]?,
        visualPercentage: Double? = nil
    ) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.overageLimitReached = overageLimitReached
        self.spendControlReached = spendControlReached
        self.balance = balance
        self.approxLocalMessages = approxLocalMessages
        self.approxCloudMessages = approxCloudMessages
        self.visualPercentage = visualPercentage
    }

    var enabled: Bool {
        if hasCredits || unlimited || overageLimitReached || spendControlReached {
            return true
        }
        return (balanceValue ?? 0) > 0
    }

    var percentage: Double? {
        if let visualPercentage {
            return visualPercentage
        }
        if overageLimitReached || spendControlReached {
            return 100
        }
        if hasCredits || unlimited || (balanceValue ?? 0) > 0 {
            return 0
        }
        return nil
    }

    /// Reused by the `L.*` formatting properties in `CodexUsageData+Formatting.swift`,
    /// so it cannot be `private` (an extension in another file could not reach it)
    var balanceValue: Double? {
        guard let balance else { return nil }
        return NSDecimalNumber(decimal: balance).doubleValue
    }

    static func parseBalance(_ value: String?) -> Decimal? {
        guard let value, !value.isEmpty else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - Formatting bridge

extension CodexUsageData.LimitData {
    /// Convert to UsageData.LimitData, reusing all of its formatting (countdown, reset time and so on)
    func asUsageLimitData() -> UsageData.LimitData {
        return UsageData.LimitData(percentage: percentage, resetsAt: resetsAt)
    }
}

// MARK: - Session response models

/// Codex /api/auth/session response model
/// Used to obtain the Bearer accessToken
nonisolated struct CodexSessionResponse: Codable, Sendable {
    let accessToken: String?
    let user: User?

    struct User: Codable, Sendable {
        let name: String?
        let email: String?
    }
}
