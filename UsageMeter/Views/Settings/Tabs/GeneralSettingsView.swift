//
//  GeneralSettingsView.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import ServiceManagement

/// General settings page
/// A card layout covering launch at login, display settings, refresh settings and language
/// Each card's content is split by topic into GeneralSettings*Section.swift, to keep this file manageable
struct GeneralSettingsView: View {
    @ObservedObject private var settings = UserSettings.shared
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GeneralSettingsDisplaySection()
                GeneralSettingsDisplayOptionsSection()

                // Refresh settings card
                SettingSection(
                    icon: "clock.arrow.trianglehead.2.counterclockwise.rotate.90",
                    iconColor: .green,
                    title: L.SettingsGeneral.refreshSection
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Refresh mode picker
                        Picker("", selection: $settings.refreshMode) {
                            ForEach(RefreshMode.allCases, id: \.self) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        .focusable(false)

                        // Fixed interval picker (shown in fixed mode only)
                        if settings.refreshMode == .fixed {
                            HStack {
                                Text(L.SettingsGeneral.refreshInterval)
                                    .foregroundColor(.secondary)

                                Picker("", selection: $settings.refreshInterval) {
                                    ForEach(RefreshInterval.allCases, id: \.rawValue) { interval in
                                        Text(interval.localizedName).tag(interval.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                            .padding(.leading, 20)
                        }
                    }
                }

                // Notification settings card. The card hint used to repeat what the row
                // description already said ("Get notified when usage reaches threshold or
                // resets" over "Receive a notification when any limit reaches 90%..."), so the
                // specific line is now the only one and `notification.hint` is unused.
                SettingSection(
                    icon: "bell.badge",
                    iconColor: .red,
                    title: L.SettingsNotification.section
                ) {
                    SettingToggleRow(
                        title: L.SettingsNotification.enable,
                        isOn: $settings.notificationsEnabled
                    )
                }

                // Launch at login settings card
                SettingSection(
                    icon: "power",
                    iconColor: .orange,
                    title: L.SettingsGeneral.launchSection
                ) {
                    SettingRow(title: L.SettingsGeneral.launchAtLogin) {
                        // The status badge only earns its place when the user has to do
                        // something about it. "Not Found" and "Not Enabled" are SMAppService
                        // registration states the switch itself already conveys, and they read
                        // as errors next to an off switch.
                        if settings.launchAtLoginStatus == .requiresApproval {
                            HStack(spacing: 4) {
                                Image(systemName: statusIcon)
                                    .foregroundColor(statusColor)
                                    .font(.caption)
                                Text(statusText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Toggle("", isOn: $settings.launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .focusable(false)
                            .labelsHidden()
                    }
                }

                // Language settings card
                SettingSection(
                    icon: "globe",
                    iconColor: .orange,
                    title: L.SettingsGeneral.languageSection
                ) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.localizedName).tag(lang)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .focusable(false)
                }

            }
            .padding()
        }
        .onAppear {
            // Sync the state when the settings page opens
            settings.syncLaunchAtLoginStatus()

            // Listen for the error notification
            NotificationCenter.default.addObserver(
                forName: .launchAtLoginError,
                object: nil,
                queue: .main
            ) { notification in
                handleLaunchError(notification)
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text(L.LaunchAtLogin.errorTitle),
                message: Text(errorMessage),
                dismissButton: .default(Text(L.Update.okButton))
            )
        }
    }

    // MARK: - Computed Properties

    /// Status icon
    private var statusIcon: String {
        switch settings.launchAtLoginStatus {
        case .enabled:
            return "checkmark.circle.fill"
        case .requiresApproval:
            return "exclamationmark.circle.fill"
        case .notRegistered:
            return "circle"
        case .notFound:
            return "xmark.circle.fill"
        @unknown default:
            // An unknown state is treated as not enabled, and the real state is synced in onAppear
            return "circle"
        }
    }

    /// Status color
    private var statusColor: Color {
        switch settings.launchAtLoginStatus {
        case .enabled:
            return .green
        case .requiresApproval:
            return .orange
        case .notRegistered:
            return .secondary
        case .notFound:
            return .red
        @unknown default:
            // Treat an unknown state as not enabled
            return .secondary
        }
    }

    /// Status text
    private var statusText: String {
        switch settings.launchAtLoginStatus {
        case .enabled:
            return L.LaunchAtLogin.statusEnabled
        case .requiresApproval:
            return L.LaunchAtLogin.statusRequiresApproval
        case .notRegistered:
            return L.LaunchAtLogin.statusDisabled
        case .notFound:
            return L.LaunchAtLogin.statusNotFound
        @unknown default:
            // Treat an unknown state as not enabled
            return L.LaunchAtLogin.statusDisabled
        }
    }

    // MARK: - Error Handling

    /// Handle a launch at login error
    private func handleLaunchError(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let error = userInfo["error"] as? Error,
              let operation = userInfo["operation"] as? String else {
            return
        }

        let operationType = operation == "enable" ? L.LaunchAtLogin.errorEnable : L.LaunchAtLogin.errorDisable
        errorMessage = "\(operationType)\n\n\(error.localizedDescription)"
        showErrorAlert = true
    }
}
