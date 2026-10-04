//
//  SettingsView.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Settings view
/// A toolbar style layout with four tabs: general settings, authentication, history and about
struct SettingsView: View {
    /// Single source of truth for the window size, used by both this view's `.frame` and the
    /// window that hosts it. The window carries a frame autosave name, and the restore happens
    /// after creation, so a previously saved width would otherwise win over a change made here.
    /// MenuBarManager re-applies this as the content size for that reason. If the two disagree,
    /// the window opens at the stale saved width.
    static let contentSize = NSSize(width: 556, height: 600)

    @ObservedObject private var settings = UserSettings.shared
    @State private var selectedTab: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager.shared

    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preferences-style icon toolbar: items hug their intrinsic width and the group
            // sits centred, matching osx-download-manager / osx-launchpad.
            HStack(spacing: 2) {
                ToolbarButton(
                    icon: "gearshape.fill",
                    title: L.SettingsTab.general,
                    isSelected: selectedTab == 0
                ) {
                    selectedTab = 0
                }

                ToolbarButton(
                    icon: "key.horizontal.fill",
                    title: L.SettingsTab.auth,
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }

                ToolbarButton(
                    icon: "chart.bar.xaxis",
                    title: L.SettingsTab.history,
                    isSelected: selectedTab == 2
                ) {
                    selectedTab = 2
                }

                ToolbarButton(
                    icon: "info.circle.fill",
                    title: L.SettingsTab.about,
                    isSelected: selectedTab == 3
                ) {
                    selectedTab = 3
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.top, 3)
            .padding(.bottom, 4)
            .background(Color(NSColor.windowBackgroundColor))

            // Softened: a full-strength separator reads as a hard rule cutting the window in two.
            Divider().overlay(Color.primary.opacity(0.03))

            // Content area
            Group {
                switch selectedTab {
                case 0:
                    GeneralSettingsView()
                case 1:
                    AuthSettingsView()
                case 2:
                    HistorySettingsView()
                case 3:
                    AboutView()
                default:
                    GeneralSettingsView()
                }
            }
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .id(localization.updateTrigger)  // Rebuild the view when the language changes
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
