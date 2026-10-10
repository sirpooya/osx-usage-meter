//
//  GeneralSettingsDisplaySection.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// The "display settings" card on the general settings page: the menu bar icon style plus the icon/percentage switches
/// Split out of GeneralSettingsView to keep single file size manageable
struct GeneralSettingsDisplaySection: View {
    @ObservedObject private var settings = UserSettings.shared

    /// Which of the three colour sources a bar or icon uses. Derived from the two stored settings
    /// rather than stored itself, so nothing had to migrate: Monochrome already won over pace in
    /// every renderer, which is exactly the precedence this enum encodes.
    private enum ColorMode: Int, CaseIterable, Identifiable {
        case limitType   // each limit keeps its own hue, escalating with the percentage
        case usage       // blue / orange / red on the projected pace
        case monochrome  // one adaptive colour that matches the menu bar

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .limitType:  return L.Display.colorModeType
            case .usage:      return L.Display.colorModeUsage
            case .monochrome: return L.Display.colorModeMonochrome
            }
        }

        var description: String {
            switch self {
            case .limitType:  return L.Display.colorModeTypeDesc
            case .usage:      return L.Display.colorModeUsageDesc
            case .monochrome: return L.Display.colorModeMonochromeDesc
            }
        }
    }

    private var colorMode: Binding<ColorMode> {
        Binding(
            get: {
                if settings.iconStyleMode == .monochrome { return .monochrome }
                return settings.paceAwareBarColors ? .usage : .limitType
            },
            set: { mode in
                switch mode {
                case .limitType:
                    settings.iconStyleMode = .colorTranslucent
                    settings.paceAwareBarColors = false
                case .usage:
                    settings.iconStyleMode = .colorTranslucent
                    settings.paceAwareBarColors = true
                case .monochrome:
                    settings.iconStyleMode = .monochrome
                    // Left as the user had it: switching to Monochrome and back should not
                    // silently forget that they wanted pace colours.
                    break
                }
            }
        )
    }

    /// Segmented, because the three are peers and one is always active.
    ///
    /// Sits in a `SettingRow` like every switch in this card: label on the left, control on the
    /// right, description underneath. Stacked full width under its own heading it read as a
    /// different kind of setting from its neighbours and left the row's right half empty.
    ///
    /// The description is the selected mode's own, so the card explains the current choice instead
    /// of listing all three and leaving the reader to work out which one applies.
    private var colorModePicker: some View {
        SettingRow(title: L.Display.colorMode) {
            Picker("", selection: colorMode) {
                ForEach(ColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .focusable(false)
            // Intrinsic width would let the three segments stretch across the row's whole right
            // half; this keeps them tight next to the label without clipping the longest one.
            .fixedSize()
        }
    }

    var body: some View {
        SettingSection(
            icon: "gauge.with.dots.needle.0percent",
            iconColor: .blue,
            title: L.SettingsGeneral.displaySection
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Live preview at the top of the card, so the colour choice below it is judged
                // against the thing it actually changes. `MenuBarIconPreview` renders through the
                // real `MenuBarIconRenderer` on mock 66% data, so it picks up the pace ramp, the
                // monochrome mode and the icon/percentage switches with no extra wiring.
                // Recovered from the deleted welcome screen setup step, which is where it lived.
                HStack {
                    Spacer()
                    MenuBarIconPreview()
                    Spacer()
                }

                Divider()

                // One picker rather than two switches. The three modes are mutually exclusive
                // (a bar has exactly one colour source), but as separate toggles nothing said so:
                // Monochrome silently won over Pace-Aware, so a user could have both on and see
                // only one take effect. A picker makes the exclusivity the control's own shape.
                colorModePicker

                Divider()

                // Battery style display: remaining capacity instead of used percentage
                SettingToggleRow(
                    title: L.Display.showRemaining,
                    isOn: $settings.showRemainingPercentage
                )

                Divider()

                // Time marker: a tick at how far through the period we are
                SettingToggleRow(
                    title: L.Display.showTimeMarker,
                    isOn: $settings.showTimeMarker
                )

                Divider()

                // Display content picker, last in the section
                VStack(alignment: .leading, spacing: 8) {
                    // Same face as the toggle row titles above, so it reads as a peer
                    Text(L.SettingsGeneral.displayContent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    HStack(spacing: 16) {
                        Toggle(isOn: Binding(
                            get: { settings.iconDisplayMode == .iconOnly || settings.iconDisplayMode == .both },
                            set: { showIcon in
                                let showPercentage = settings.iconDisplayMode == .percentageOnly || settings.iconDisplayMode == .both
                                if showIcon && showPercentage {
                                    settings.iconDisplayMode = .both
                                } else if showIcon {
                                    settings.iconDisplayMode = .iconOnly
                                } else {
                                    settings.iconDisplayMode = .percentageOnly
                                }
                            }
                        )) {
                            // Regular weight: these are checkbox labels, not row titles, so
                            // they should not compete with the Display Content heading above
                            Text(L.Display.showIcon)
                                .font(.system(size: 13, weight: .regular))
                        }
                        .toggleStyle(.checkbox)
                        .focusable(false)
                        .disabled(settings.iconDisplayMode == .iconOnly)

                        Toggle(isOn: Binding(
                            get: { settings.iconDisplayMode == .percentageOnly || settings.iconDisplayMode == .both },
                            set: { showPercentage in
                                let showIcon = settings.iconDisplayMode == .iconOnly || settings.iconDisplayMode == .both
                                if showIcon && showPercentage {
                                    settings.iconDisplayMode = .both
                                } else if showPercentage {
                                    settings.iconDisplayMode = .percentageOnly
                                } else {
                                    settings.iconDisplayMode = .iconOnly
                                }
                            }
                        )) {
                            Text(L.Display.showPercentage)
                                .font(.system(size: 13, weight: .regular))
                        }
                        .toggleStyle(.checkbox)
                        .focusable(false)
                        .disabled(settings.iconDisplayMode == .percentageOnly)
                    }
                }
            }
        }
    }
}
