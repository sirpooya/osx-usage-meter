//
//  GeneralSettingsDisplayOptionsSection.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// The "display options" card on the general settings page: the smart/custom display mode plus the custom type checkboxes
/// Split out of GeneralSettingsView to keep single file size manageable
struct GeneralSettingsDisplayOptionsSection: View {
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        SettingSection(
            icon: "rectangle.3.group",
            iconColor: .purple,
            title: L.DisplayOptions.title,
            hint: settings.displayMode == .smart ? L.DisplayOptions.smartDisplayDescription : L.DisplayOptions.customDisplayDescription
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // No "Display Mode:" label and no info glyph description row. The card's own
                // header already says Display Options, and the two radios name themselves, so both
                // only repeated what was on screen. The card's `hint` slot still carries the mode
                // description, which is where a per-card explanation belongs.
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $settings.displayMode) {
                        Text(L.DisplayOptions.smartDisplay).tag(DisplayMode.smart)
                        Text(L.DisplayOptions.customDisplay).tag(DisplayMode.custom)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .focusable(false)

                    // The checkbox list keeps its caption heading and sits indented under the
                    // radio that reveals it, the placement the recovered welcome screen design used
                    // (`48850a8^`, `reference/Usage4Claude/.../SetupStepView.swift`).
                    if settings.displayMode == .custom {
                        limitTypeGrid
                            .padding(.top, 4)
                        .padding(.leading, 20)
                    }
                }

                // The hints and the menu bar switch stay below, outside the mode column, so a
                // long hint can use the card's full width instead of the column's.
                if settings.displayMode == .custom {
                    VStack(alignment: .leading, spacing: 12) {

                        // Constraint hints
                        if hasOnlyOneCircularIcon {
                            Text(L.DisplayOptions.circularIconConstraint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 20)
                        }

                        // Theme availability hint
                        if !canUseColoredTheme {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text(L.DisplayOptions.coloredThemeUnavailable)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.leading, 20)
                        }

                        Divider()

                        // The "menu bar only" switch: when on, the popover uses the smart display.
                        // A SettingToggleRow like every other switch in these sections: it is a
                        // setting in its own right, not one of the limit type checkboxes above it,
                        // so it gets the 13pt medium title, the control on the trailing edge and a
                        // flush description rather than a checkbox with an indented caption.
                        SettingToggleRow(
                            title: L.DisplayOptions.menuBarOnlyToggle,
                            description: L.DisplayOptions.menuBarOnlyDescription,
                            isOn: $settings.customDisplayMenuBarOnly
                        )
                    }
                }
            }
        }
    }

    /// The limit type checkboxes, one per line.
    ///
    /// A wrapped grid was tried and reverted: three to a row put the checkbox of one column right
    /// next to the *label* of the one before it, so the boxes no longer formed a single scannable
    /// edge and the rows read as one run-on line. One per line keeps every box on the same x.
    ///
    /// Grouped by provider, Claude then Codex, each under its brand mark, the same grouping the
    /// Account tab's sidebar uses. The provider names are brand names, so not localized.
    ///
    /// The two providers sit side by side as two columns, each still one checkbox per line, so
    /// every box in a column shares one x. Columns split the width evenly so Codex always starts
    /// at the same place regardless of how long Claude's labels are.
    private var limitTypeGrid: some View {
        HStack(alignment: .top, spacing: 16) {
            limitGroup("Claude", icon: ImageHelper.createClaudeMark(size: 12), types: limitTypes(for: .claude))
                .frame(maxWidth: .infinity, alignment: .leading)
            limitGroup("Codex", icon: ImageHelper.createCodexMark(size: 12), types: limitTypes(for: .codex))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Extra Usage goes last in each column, after the windowed limits it is not one of. Sorted
    /// here rather than by reordering the enum, so the menu bar and popover order stay put.
    private func limitTypes(for provider: ProviderType) -> [LimitType] {
        let types = LimitType.allCases.filter { $0.provider == provider }
        let isExtra: (LimitType) -> Bool = { $0 == .extraUsage || $0 == .codexExtraUsage }
        return types.filter { !isExtra($0) } + types.filter(isExtra)
    }

    private func limitGroup(_ title: String, icon: NSImage?, types: [LimitType]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            ForEach(types, id: \.self) { limitType in
                LimitTypeCheckbox(
                    limitType: limitType,
                    isSelected: settings.customDisplayTypes.contains(limitType),
                    isDisabled: shouldDisableCheckbox(for: limitType)
                ) {
                    toggleLimitType(limitType)
                }
            }
        }
    }

    // MARK: - Display Options Helpers

    /// Decide whether only one circular icon is left
    private var hasOnlyOneCircularIcon: Bool {
        let circularTypes: Set<LimitType> = [.fiveHour, .sevenDay, .codexPrimary, .codexSecondary]
        let selectedCircular = settings.customDisplayTypes.intersection(circularTypes)
        return selectedCircular.count == 1
    }

    /// Decide whether a color theme can be used
    private var canUseColoredTheme: Bool {
        // Every limit type supports colored display now
        // A color theme works as long as some limit type is selected
        return !settings.customDisplayTypes.isEmpty
    }

    /// Decide whether a checkbox should be disabled
    private func shouldDisableCheckbox(for limitType: LimitType) -> Bool {
        #if DEBUG
        // In Debug mode, when "show every shape separately" is on, deselecting every limit is allowed
        if settings.debugShowAllShapesIndividually {
            return false
        }
        #endif

        let circularTypes: Set<LimitType> = [.fiveHour, .sevenDay, .codexPrimary, .codexSecondary]

        // Disable it when this is the last selected circular icon
        if circularTypes.contains(limitType) {
            let selectedCircular = settings.customDisplayTypes.intersection(circularTypes)
            return selectedCircular.count == 1 && selectedCircular.contains(limitType)
        }

        return false
    }

    /// Toggle a limit type's selection
    private func toggleLimitType(_ limitType: LimitType) {
        if settings.customDisplayTypes.contains(limitType) {
            // Check whether it can be deselected
            if !shouldDisableCheckbox(for: limitType) {
                settings.customDisplayTypes.remove(limitType)
            }
        } else {
            settings.customDisplayTypes.insert(limitType)
        }
    }
}

// MARK: - Limit Type Checkbox Component

/// Limit type checkbox
struct LimitTypeCheckbox: View {
    let limitType: LimitType
    let isSelected: Bool
    let isDisabled: Bool
    let onToggle: () -> Void

    var body: some View {
        // A real Toggle, not a Button drawing SF Symbol squares. The hand rolled version drew
        // `checkmark.square.fill` / `square`, which is close enough to be recognisable but is not
        // an AppKit checkbox: wrong box size and corner radius, wrong blue, no focus ring, no
        // mixed state, and none of the system's own disabled or accent handling. Every other
        // checkbox on this page is a `Toggle(.checkbox)`, so this one was also the odd one out.
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in onToggle() }
        )) {
            HStack(spacing: 6) {
                // Limit type icon
                limitTypeIcon
                    .font(.caption)

                // Limit type name
                Text(limitType.groupedName)
                    .foregroundColor(isDisabled ? .secondary : .primary)
            }
        }
        .toggleStyle(.checkbox)
        .focusable(false)
        .disabled(isDisabled)
        .help(isDisabled ? L.DisplayOptions.circularIconConstraint : "")
        .fixedSize()
    }

    @ViewBuilder
    private var limitTypeIcon: some View {
        // Draw the icon on a Canvas, the same way the detail UI does
        Canvas { context, canvasSize in
            let lineWidth: CGFloat = 1.8
            let path = shapePath(for: limitType, in: CGRect(origin: .zero, size: canvasSize))

            // Draw the background border
            context.stroke(path, with: .color(Color.gray.opacity(0.3)), lineWidth: lineWidth)

            // Draw a full progress ring (100%)
            context.stroke(path, with: .color(iconColor(for: limitType)), lineWidth: lineWidth)
        }
        .frame(width: 14, height: 14)
    }

    private func shapePath(for type: LimitType, in rect: CGRect) -> Path {
        return IconShapePaths.pathForLimitType(type, in: rect)
    }

    private func iconColor(for type: LimitType) -> Color {
        switch type {
        case .fiveHour: return .green
        case .sevenDay: return .purple
        case .extraUsage: return .pink
        case .opusWeekly: return .orange
        case .sonnetWeekly: return .blue
        case .codexPrimary:  return Color(red: 45/255.0, green: 212/255.0, blue: 191/255.0)
        case .codexSecondary: return Color(red: 96/255.0, green: 165/255.0, blue: 250/255.0)
        case .codexExtraUsage: return Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0)
        }
    }
}
