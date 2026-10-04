//
//  SmartRefreshPolicy.swift
//  UsageMeter
//
//  Extracted from UserSettings.swift so the 4 level monitoring mode state machine can live as pure,
//  UI/UserDefaults-free logic — cherry-pickable into a SwiftPM test target.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// The 4 level monitoring mode state machine behind smart refresh
/// Rule: any provider whose usage changed switches straight back to active mode; only when nothing changed does the quiet count build up and slow the polling down step by step.
/// Pure logic, independent of Logger, UserDefaults and NotificationCenter. Side effects (logging, notifications) are the caller's job.
final class SmartRefreshPolicy {
    /// Current monitoring mode
    var currentMode: MonitoringMode = .active
    /// Number of consecutive unchanged polls
    var unchangedCount: Int = 0
    /// Keeps the old field's meaning, handy while debugging (same as claude, or the first provider)
    var lastUtilization: Double?

    private var lastUtilizationByProvider: [ProviderType: Double] = [:]

    /// Handle one round of usage detection
    /// - Parameter providerUtilizations: provider usage percentages fetched successfully this round
    /// - Returns: whether the mode changed (the caller uses this to decide whether to restart timers or post a notification)
    @discardableResult
    func update(providerUtilizations: [ProviderType: Double]) -> Bool {
        guard !providerUtilizations.isEmpty else { return false }

        let modeChanged: Bool
        if hasProviderUtilizationChanged(providerUtilizations) {
            modeChanged = switchToActiveMode()
        } else {
            modeChanged = handleNoChange()
        }

        for (provider, utilization) in providerUtilizations {
            lastUtilizationByProvider[provider] = utilization
        }
        lastUtilization = providerUtilizations[.claude] ?? providerUtilizations.values.first

        return modeChanged
    }

    /// Reset the state (called when switching to fixed mode, or on a manual refresh)
    func reset() {
        lastUtilization = nil
        lastUtilizationByProvider.removeAll()
        unchangedCount = 0
        currentMode = .active
    }

    private func hasProviderUtilizationChanged(_ current: [ProviderType: Double]) -> Bool {
        current.contains { provider, utilization in
            guard let last = lastUtilizationByProvider[provider] else { return false }
            return abs(utilization - last) > 0.01
        }
    }

    @discardableResult
    private func switchToActiveMode() -> Bool {
        guard currentMode != .active else { return false }
        currentMode = .active
        unchangedCount = 0
        return true
    }

    @discardableResult
    private func handleNoChange() -> Bool {
        unchangedCount += 1
        guard let newMode = calculateNewMode() else { return false }
        currentMode = newMode
        unchangedCount = 0
        return true
    }

    /// Compute the new mode from the current mode and the unchanged count
    /// - Returns: the new mode when a switch is needed, otherwise nil
    private func calculateNewMode() -> MonitoringMode? {
        switch currentMode {
        case .active:
            // Active mode: 3 rounds unchanged (3 minutes) -> short quiet
            return unchangedCount >= 3 ? .idleShort : nil
        case .idleShort:
            // Short quiet: 6 rounds unchanged (18 minutes) -> medium quiet
            return unchangedCount >= 6 ? .idleMedium : nil
        case .idleMedium:
            // Medium quiet: 12 rounds unchanged (60 minutes) -> long quiet
            return unchangedCount >= 12 ? .idleLong : nil
        case .idleLong:
            // Long quiet: stay in the current mode
            return nil
        }
    }
}
