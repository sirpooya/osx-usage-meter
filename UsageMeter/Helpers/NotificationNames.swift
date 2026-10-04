//
//  NotificationNames.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Notification name extensions
/// Type safe notification name constants, so hardcoded strings cannot be misspelled
/// Every in app notification should use these constants rather than a raw string
extension Notification.Name {
    // MARK: - Settings Related

    /// Settings changed notification
    /// Posted whenever the user changes any setting
    static let settingsChanged = Notification.Name("settingsChanged")

    /// Refresh interval changed notification
    /// Posted when the user changes the refresh interval or the refresh mode
    static let refreshIntervalChanged = Notification.Name("refreshIntervalChanged")

    /// Language changed notification
    /// Posted when the user switches the app language, triggering a UI re-render
    static let languageChanged = Notification.Name("languageChanged")

    /// Account changed notification (v2.1.0)
    /// Posted when the user switches account, triggering a data refresh
    static let accountChanged = Notification.Name("accountChanged")

    // MARK: - Window Related

    /// Open settings window notification
    /// Post this to open the settings window
    static let openSettings = Notification.Name("openSettings")

    /// Open the settings window on a specific tab
    /// userInfo carries a "tab" key holding the tab index (Int)
    /// - Example: NotificationCenter.default.post(name: .openSettingsWithTab, object: nil, userInfo: ["tab": 1])
    static let openSettingsWithTab = Notification.Name("openSettingsWithTab")

    // MARK: - Error Related

    /// Launch at login error notification
    /// Posted when enabling launch at login fails
    static let launchAtLoginError = Notification.Name("launchAtLoginError")
}

// MARK: - UserInfo Keys

/// Key constants for notification userInfo dictionaries
/// Type safe access to userInfo keys
extension Notification {
    /// UserInfo key names
    enum UserInfoKey {
        /// Tab index key
        /// Used by the openSettingsWithTab notification, value type Int
        static let tab = "tab"

        /// Provider key for an account change
        /// Used by the accountChanged notification, value type ProviderType.rawValue
        static let provider = "provider"
    }
}
