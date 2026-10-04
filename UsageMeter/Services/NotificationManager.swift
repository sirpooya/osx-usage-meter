//
//  NotificationManager.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-02-17.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import UserNotifications
import OSLog

/// Usage notification manager
/// Posts macOS notifications when usage crosses a threshold or resets
/// Subclassing NSObject is required by the UNUserNotificationCenterDelegate protocol
final class NotificationManager: NSObject {
    // MARK: - Singleton

    static let shared = NotificationManager()

    // MARK: - State

    /// UserDefaults key for the persisted notification record
    private static let notifiedWarningsKey = "notifiedWarnings"

    /// The notification record (keeps one account from being notified twice in the same window)
    /// key = provider + accountId + limitType, value = the resetsAt epoch of the window the warning was sent in (0 when unknown)
    /// Persisted to UserDefaults: otherwise a restart would resend the 90% and 75% warnings already sent in this window.
    /// The value records the window rather than a Bool: a reset while the app was not running cannot be caught by isReset's in memory comparison,
    /// and without a window identity an old flag would suppress the new window's warning forever (see the stale flag cleanup in checkLimit).
    private var notifiedWarnings: [String: Double] = [:] {
        didSet {
            UserDefaults.standard.set(notifiedWarnings, forKey: Self.notifiedWarningsKey)
        }
    }

    private override init() {
        super.init()
        if let saved = UserDefaults.standard.dictionary(forKey: Self.notifiedWarningsKey) {
            // Accept the old [String: Bool] format: a Bool becomes 1.0, which differs from any real resetsAt and so
            // is cleaned up as a stale flag on the first check, behaving as if the record started over
            notifiedWarnings = saved.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
        // Without a delegate, macOS silently drops notifications from a foreground app (add succeeds and reports nothing).
        // This app is foreground and active exactly while its settings window or popover is open, which is when usage warnings most often fire.
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    /// Request notification permission
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                Logger.menuBar.error("Failed to request notification permission: \(error.localizedDescription)")
            }
            Logger.menuBar.info("Notification permission: \(granted ? "granted" : "denied")")
        }
    }

    // MARK: - Check & Notify

    /// Check the usage data and post notifications when needed
    /// - Parameters:
    ///   - usageData: the latest usage data
    ///   - previousData: the previous usage data (used to spot changes)
    func checkAndNotify(usageData: UsageData, previousData: UsageData?) {
        // Check each limit type in turn
        checkLimit(
            type: .fiveHour,
            current: usageData.fiveHour?.percentage,
            previous: previousData?.fiveHour?.percentage,
            currentResetsAt: usageData.fiveHour?.resetsAt,
            previousResetsAt: previousData?.fiveHour?.resetsAt
        )
        checkLimit(
            type: .sevenDay,
            current: usageData.sevenDay?.percentage,
            previous: previousData?.sevenDay?.percentage,
            currentResetsAt: usageData.sevenDay?.resetsAt,
            previousResetsAt: previousData?.sevenDay?.resetsAt
        )
        checkLimit(
            type: .opusWeekly,
            current: usageData.opus?.percentage,
            previous: previousData?.opus?.percentage,
            currentResetsAt: usageData.opus?.resetsAt,
            previousResetsAt: previousData?.opus?.resetsAt
        )
        checkLimit(
            type: .sonnetWeekly,
            current: usageData.sonnet?.percentage,
            previous: previousData?.sonnet?.percentage,
            currentResetsAt: usageData.sonnet?.resetsAt,
            previousResetsAt: previousData?.sonnet?.resetsAt
        )

        // Extra Usage is handled separately
        checkLimit(
            type: .extraUsage,
            current: usageData.extraUsage?.percentage,
            previous: previousData?.extraUsage?.percentage,
            currentResetsAt: nil,
            previousResetsAt: nil
        )
    }

    /// Check the Codex usage data and post notifications when needed
    /// - Parameters:
    ///   - codexUsageData: the latest Codex usage data
    ///   - previousData: the previous Codex usage data (used to spot changes)
    func checkAndNotify(codexUsageData: CodexUsageData, previousData: CodexUsageData?) {
        checkLimit(
            type: .codexPrimary,
            current: codexUsageData.primary?.percentage,
            previous: previousData?.primary?.percentage,
            currentResetsAt: codexUsageData.primary?.resetsAt,
            previousResetsAt: previousData?.primary?.resetsAt
        )
        checkLimit(
            type: .codexSecondary,
            current: codexUsageData.secondary?.percentage,
            previous: previousData?.secondary?.percentage,
            currentResetsAt: codexUsageData.secondary?.resetsAt,
            previousResetsAt: previousData?.secondary?.resetsAt
        )
        checkLimit(
            type: .codexExtraUsage,
            current: codexUsageData.extraUsage?.percentage,
            previous: previousData?.extraUsage?.percentage,
            currentResetsAt: nil,
            previousResetsAt: nil
        )
    }

    // MARK: - Private Methods

    /// Check how one limit type's usage changed
    /// The state logic lives in the pure `NotificationDecisionEngine.evaluate` (see that file),
    /// and this only assembles the keys and turns the returned actions into real system notifications
    private func checkLimit(
        type: LimitType,
        current: Double?,
        previous: Double?,
        currentResetsAt: Date?,
        previousResetsAt: Date?
    ) {
        let warningKey = notificationKey(for: type)
        // The 7 day limit also checks the 75% threshold; no other type gets an early warning
        let earlyWarningKey = (type == .sevenDay || type == .codexSecondary)
            ? notificationKey(for: type, suffix: "75")
            : nil

        let (actions, updatedWarnings) = NotificationDecisionEngine.evaluate(
            current: current,
            previous: previous,
            currentResetsAt: currentResetsAt,
            previousResetsAt: previousResetsAt,
            warningKey: warningKey,
            earlyWarningKey: earlyWarningKey,
            notifiedWarnings: notifiedWarnings
        )
        // Assign only on a real change: notifiedWarnings' didSet writes UserDefaults,
        // so an unconditional assignment would mean a disk write on every checkLimit call
        if updatedWarnings != notifiedWarnings {
            notifiedWarnings = updatedWarnings
        }

        for action in actions {
            switch action {
            case .reset:
                sendResetNotification(limitType: type)
            case .warning(let percentage):
                sendUsageWarning(limitType: type, percentage: percentage)
            }
        }
    }

    private func notificationKey(for type: LimitType, suffix: String? = nil) -> String {
        let accountId: UUID?
        switch type.provider {
        case .claude:
            accountId = UserSettings.shared.currentAccountId
        case .codex:
            accountId = UserSettings.shared.currentCodexAccountId
        }
        return Self.makeNotificationKey(
            provider: type.provider,
            accountId: accountId,
            limitType: type,
            suffix: suffix
        )
    }

    static func makeNotificationKey(
        provider: ProviderType,
        accountId: UUID?,
        limitType: LimitType,
        suffix: String? = nil
    ) -> String {
        var key = "\(provider.rawValue):\(accountId?.uuidString ?? "none"):\(limitType.rawValue)"
        if let suffix {
            key += ":\(suffix)"
        }
        return key
    }

    static func makeAccountNotificationKeyPrefix(provider: ProviderType, accountId: UUID?) -> String {
        "\(provider.rawValue):\(accountId?.uuidString ?? "none"):"
    }

    /// Post the usage warning notification
    private func sendUsageWarning(limitType: LimitType, percentage: Double) {
        let content = UNMutableNotificationContent()
        content.title = L.UsageNotification.warningTitle
        content.body = L.UsageNotification.warningBody(limitType.displayName, Int(percentage))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage_warning_\(limitType.rawValue)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.menuBar.error("Failed to send the usage warning notification: \(error.localizedDescription)")
            }
        }

        Logger.menuBar.info("Sent usage warning: \(limitType.displayName) \(Int(percentage))%")
    }

    /// Post the usage reset notification
    private func sendResetNotification(limitType: LimitType) {
        let content = UNMutableNotificationContent()
        content.title = L.UsageNotification.resetTitle
        content.body = L.UsageNotification.resetBody(limitType.displayName)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage_reset_\(limitType.rawValue)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.menuBar.error("Failed to send the reset notification: \(error.localizedDescription)")
            }
        }

        Logger.menuBar.info("Sent reset notification: \(limitType.displayName)")
    }

    /// Post the "Codex login expired" system notification (once only, so it does not nag)
    /// The caller owns the deduplication (DataRefreshManager.codexSessionExpiredNotified)
    func sendCodexSessionExpiredNotification() {
        let content = UNMutableNotificationContent()
        content.title = L.UsageNotification.codexSessionExpiredTitle
        content.body = L.UsageNotification.codexSessionExpiredBody
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codex_session_expired",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.menuBar.error("Failed to send the Codex expiry notification: \(error.localizedDescription)")
            }
        }

        Logger.menuBar.info("Sent the Codex sign in expiry notification")
    }

    /// Reset the entire notification record
    func resetAllNotificationStates() {
        notifiedWarnings.removeAll()
    }

    /// Reset the notification record for one account
    func resetNotificationStates(for provider: ProviderType, accountId: UUID?) {
        let prefix = Self.makeAccountNotificationKeyPrefix(provider: provider, accountId: accountId)
        notifiedWarnings = notifiedWarnings.filter { key, _ in
            !key.hasPrefix(prefix)
        }
    }

}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show the banner and play the sound even while the app is in the foreground
    /// (the system default is to drop it silently, and a menu bar app is foreground whenever its settings window or popover is open)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
