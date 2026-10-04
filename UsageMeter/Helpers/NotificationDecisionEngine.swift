//
//  NotificationDecisionEngine.swift
//  UsageMeter
//
//  Copyright © 2025 f-is-h. All rights reserved.
//
//  Pure threshold logic for usage notifications: it depends on neither UserNotifications nor UserSettings,
//  and only answers "given the current state and what has already been notified, which notifications go out
//  and how does the record change". It lives in its own file so it fits in the SwiftPM test target: duplicate
//  and missed notifications almost always come from this state logic (stale flag cleanup, threshold crossing, reset detection) rather than from sending itself.
//

import Foundation

/// Actions the threshold logic asks for
enum NotificationDecisionAction: Equatable {
    /// Send the "reset" notification
    case reset
    /// Send the "threshold reached" notification, with the percentage that triggered it
    case warning(percentage: Double)
}

enum NotificationThresholds {
    /// Usage warning threshold (90%)
    static let warning: Double = 90.0
    /// Early warning threshold for the 7 day limit (75%)
    static let sevenDayEarlyWarning: Double = 75.0
    /// Reset detection threshold: a percentage drop larger than this counts as a reset
    static let resetDrop: Double = 30.0
}

enum NotificationDecisionEngine {

    /// Decide whether a reset happened
    static func isReset(
        currentPct: Double,
        previousPct: Double,
        currentResetsAt: Date?,
        previousResetsAt: Date?
    ) -> Bool {
        // Sharp percentage drop (from a higher value to a lower one)
        if previousPct >= NotificationThresholds.warning && (previousPct - currentPct) > NotificationThresholds.resetDrop {
            return true
        }

        // resetsAt changed (a new reset window) and the percentage dropped too, so this is a reset
        if let current = currentResetsAt, let previous = previousResetsAt,
           abs(current.timeIntervalSince(previous)) > 1.0,
           currentPct < previousPct {
            return true
        }

        return false
    }

    /// Notification logic for a single limit type
    /// - Parameters:
    ///   - current: latest percentage, nil means there is no data yet (the caller should skip)
    ///   - previous: the previous percentage
    ///   - currentResetsAt/previousResetsAt: used for reset detection
    ///   - warningKey: record key for the 90% threshold
    ///   - earlyWarningKey: record key for the 75% threshold; nil means this type gets no early warning
    ///   - notifiedWarnings: the current record (key -> resetsAt epoch of its window, 0 when there is no window info)
    /// - Returns: the actions to run (in the suggested send order) and the updated record
    static func evaluate(
        current: Double?,
        previous: Double?,
        currentResetsAt: Date?,
        previousResetsAt: Date?,
        warningKey: String,
        earlyWarningKey: String?,
        notifiedWarnings: [String: Double]
    ) -> (actions: [NotificationDecisionAction], updatedWarnings: [String: Double]) {
        guard let currentPct = current else { return ([], notifiedWarnings) }
        var warnings = notifiedWarnings

        if let previousPct = previous, isReset(
            currentPct: currentPct,
            previousPct: previousPct,
            currentResetsAt: currentResetsAt,
            previousResetsAt: previousResetsAt
        ) {
            warnings.removeValue(forKey: warningKey)
            if let earlyWarningKey {
                warnings.removeValue(forKey: earlyWarningKey)
            }
            return ([.reset], warnings)
        }

        let previousPct = previous ?? 0
        var actions: [NotificationDecisionAction] = []
        let currentCycle = currentResetsAt?.timeIntervalSince1970 ?? 0

        // Stale flag cleanup: a persisted flag belonging to an old window (resetsAt has changed) is dropped.
        // This covers "the quota reset while the app was not running", a reset that never reaches the isReset branch above.
        func clearIfStale(_ key: String) {
            guard currentCycle != 0,
                  let firedCycle = warnings[key], firedCycle != 0,
                  abs(firedCycle - currentCycle) > 1 else { return }
            warnings.removeValue(forKey: key)
        }

        if let earlyWarningKey {
            clearIfStale(earlyWarningKey)
            let alreadyNotifiedEarly = warnings[earlyWarningKey] != nil
            if !alreadyNotifiedEarly
                && previousPct < NotificationThresholds.sevenDayEarlyWarning
                && currentPct >= NotificationThresholds.sevenDayEarlyWarning {
                actions.append(.warning(percentage: currentPct))
                warnings[earlyWarningKey] = currentCycle
            }
        }

        clearIfStale(warningKey)
        let alreadyNotified = warnings[warningKey] != nil
        if !alreadyNotified
            && previousPct < NotificationThresholds.warning
            && currentPct >= NotificationThresholds.warning {
            actions.append(.warning(percentage: currentPct))
            warnings[warningKey] = currentCycle
        }

        return (actions, warnings)
    }
}
