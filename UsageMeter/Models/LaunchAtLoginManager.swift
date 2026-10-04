//
//  LaunchAtLoginManager.swift
//  UsageMeter
//
//  Extracted from UserSettings.swift (audit report 4.1). The original used a stored Bool plus an
//  isSyncingLaunchStatus flag to keep didSet from recursively registering and unregistering, and on failure it
//  wrote the old value back through DispatchQueue.main.async, which is racy on its own (toggle again before the
//  write back runs and the flag state is nonsense). SMAppService.mainApp.status is the real source of truth, and
//  the existing code already overwrote the stored value with it at launch and on didBecomeActive, so isEnabled is
//  now a computed property derived straight from status. That kills the flag and the race at the root: the Toggle binds to
//  isEnabled, a failure leaves status unchanged via refreshStatus(), and SwiftUI snaps the Toggle back on its own.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine
import ServiceManagement
import OSLog

/// Registering, unregistering and status syncing for launch at login
final class LaunchAtLoginManager: ObservableObject {
    private let defaults = UserDefaults.standard

    /// The single source of truth: the system's actual registration status
    @Published private(set) var status: SMAppService.Status

    init() {
        status = SMAppService.mainApp.status
    }

    /// For two way Toggle binding; the setter calls enable()/disable() directly rather than going through any stored property's didSet,
    /// so there is nothing to trigger recursively and no need for a flag like isSyncingLaunchStatus.
    var isEnabled: Bool {
        get { status == .enabled }
        set { newValue ? enable() : disable() }
    }

    /// Enable launch at login
    func enable() {
        do {
            try SMAppService.mainApp.register()
            Logger.settings.notice("Launch at login enabled")
        } catch {
            Logger.settings.error("Failed to enable launch at login: \(error.localizedDescription)")
            NotificationCenter.default.post(
                name: .launchAtLoginError,
                object: nil,
                userInfo: ["error": error, "operation": "enable"]
            )
        }
        // Success or failure, the system status decides; on failure status is unchanged and the Toggle snaps back on its own
        refreshStatus()
    }

    /// Disable launch at login
    func disable() {
        let currentStatus = SMAppService.mainApp.status

        // When the service is not registered or not found, just sync the status without calling unregister
        guard currentStatus != .notRegistered && currentStatus != .notFound else {
            Logger.settings.notice("Launch at login service is not registered, settings updated")
            refreshStatus()
            return
        }

        do {
            try SMAppService.mainApp.unregister()
            Logger.settings.notice("Launch at login disabled")
        } catch {
            Logger.settings.error("Failed to disable launch at login: \(error.localizedDescription)")
            NotificationCenter.default.post(
                name: .launchAtLoginError,
                object: nil,
                userInfo: ["error": error, "operation": "disable"]
            )
        }
        refreshStatus()
    }

    /// Read the real status from the system and update
    /// Replaces the old syncLaunchAtLoginStatus, called at launch and on didBecomeActive
    func refreshStatus() {
        let newStatus = SMAppService.mainApp.status
        DispatchQueue.main.async {
            // Assigning to @Published triggers objectWillChange even when the value is unchanged,
            // which makes the Toggle re-read isEnabled and snap back on the failure path too
            self.status = newStatus
            // Mirror it into UserDefaults, for any older logic still reading that key (there is none right now)
            self.defaults.set(newStatus == .enabled, forKey: "launchAtLogin")
        }
        Logger.settings.debug("Launch at login status: \(String(describing: newStatus))")
    }
}
