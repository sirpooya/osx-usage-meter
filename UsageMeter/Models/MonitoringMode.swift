//
//  MonitoringMode.swift
//  UsageMeter
//
//  Extracted from UserSettings.swift so SmartRefreshPolicy (and its tests) don't
//  need to pull in UserSettings' full AppKit/Keychain dependency footprint.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Monitoring mode (internal, the 4 levels under smart refresh)
enum MonitoringMode: String, Codable {
    /// Active mode, refresh every minute
    case active = "active"
    /// Short quiet, refresh every 3 minutes
    case idleShort = "idle_short"
    /// Medium quiet, refresh every 5 minutes
    case idleMedium = "idle_medium"
    /// Long quiet, refresh every 10 minutes
    case idleLong = "idle_long"

    /// The matching refresh interval (seconds)
    var interval: Int {
        switch self {
        case .active:
            return 60      // 1 minute
        case .idleShort:
            return 180     // 3 minutes
        case .idleMedium:
            return 300     // 5 minutes
        case .idleLong:
            return 600     // 10 minutes
        }
    }
}
