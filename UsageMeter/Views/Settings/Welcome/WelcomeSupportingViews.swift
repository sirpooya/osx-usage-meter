//
//  WelcomeSupportingViews.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//
//  Small reusable components, split out of WelcomeView.swift to keep single file size manageable:
//  HorizontalRadioGroup / MenuBarIconPreview / NavigationButtons

import SwiftUI

// MARK: - Horizontal Radio Group Component

/// Horizontal radio button group
struct HorizontalRadioGroup<T: Hashable>: View {
    let selection: Binding<T>
    let options: [(value: T, label: String)]
    let spacing: CGFloat

    init(selection: Binding<T>, options: [(value: T, label: String)], spacing: CGFloat = 16) {
        self.selection = selection
        self.options = options
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button(action: {
                    selection.wrappedValue = option.value
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: selection.wrappedValue == option.value ? "largecircle.fill.circle" : "circle")
                            .font(.body)
                            .foregroundColor(selection.wrappedValue == option.value ? .accentColor : .secondary)
                        Text(option.label)
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)  // Disable keyboard focus
            }
        }
    }
}

// MARK: - Menu Bar Icon Preview

/// Menu bar icon preview
/// Uses fake data to show what the real menu bar icon looks like
struct MenuBarIconPreview: View {
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        // Simulated menu bar background
        HStack(spacing: 3) {
            Image(nsImage: getPreviewIcon())
                .resizable()
                .scaledToFit()
                .frame(height: 18)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(previewBackgroundColor)
        .cornerRadius(4)
    }

    /// Get the preview icon (through createIcon)
    private func getPreviewIcon() -> NSImage {
        let renderer = MenuBarIconRenderer(settings: settings)
        let mockData = createMockUsageData()

        // Go through createIcon, so it responds to iconDisplayMode correctly
        return renderer.createIcon(usageData: mockData, hasUpdate: false, button: nil)
    }

    /// Build mock usage data (66% used)
    private func createMockUsageData() -> UsageData {
        let mockPercentage = 66.0

        return UsageData(
            fiveHour: UsageData.LimitData(
                percentage: mockPercentage,
                resetsAt: Date().addingTimeInterval(3600)
            ),
            sevenDay: UsageData.LimitData(
                percentage: mockPercentage,
                resetsAt: Date().addingTimeInterval(86400 * 3)
            ),
            opus: UsageData.LimitData(
                percentage: mockPercentage,
                resetsAt: Date().addingTimeInterval(86400 * 5)
            ),
            sonnet: UsageData.LimitData(
                percentage: mockPercentage,
                resetsAt: Date().addingTimeInterval(86400 * 5)
            ),
            extraUsage: ExtraUsageData(
                enabled: true,
                used: mockPercentage,
                limit: 100.0,
                currency: "USD"
            )
        )
    }

    /// Preview background color (simulating the menu bar)
    private var previewBackgroundColor: Color {
        // Return the menu bar color for the system appearance
        if UsageColorScheme.isDarkMode {
            return Color(white: 0.2)  // Dark mode menu bar
        } else {
            return Color(white: 0.95)  // Light mode menu bar
        }
    }
}

// MARK: - Navigation Buttons

/// The bottom done button.
/// A successful login wraps up on its own, and this button doubles as the "later" exit, so it is always clickable.
struct NavigationButtons: View {
    let onComplete: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(L.Welcome.finish, action: onComplete)
                .buttonStyle(.bordered)
        }
    }
}
