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
    /// Active mode, refresh every 3 minutes
    case active = "active"
    /// Short quiet, refresh every 5 minutes
    case idleShort = "idle_short"
    /// Medium quiet, refresh every 10 minutes
    case idleMedium = "idle_medium"
    /// Long quiet, refresh every 15 minutes
    case idleLong = "idle_long"

    /// The matching refresh interval (seconds)
    /// The usage endpoint rate limits per access token, and that token is shared with Claude Code,
    /// which polls the same endpoint from every open session. 60s active polling drew 429s.
    var interval: Int {
        switch self {
        case .active:
            return 180     // 3 minutes
        case .idleShort:
            return 300     // 5 minutes
        case .idleMedium:
            return 600     // 10 minutes
        case .idleLong:
            return 900     // 15 minutes
        }
    }
}
