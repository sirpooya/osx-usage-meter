//
//  CompactMenuBarPlayground.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-10-28.
//

#if DEBUG
import SwiftUI

// MARK: - Compact Menu Bar Playground
//
// A dev-only window for tuning the compact menu bar (percentages as plain text, no rings). The
// stage renders through the real `MenuBarIconRenderer` on mock data, over a dark and a light menu
// bar strip. The style knobs write `CompactMenuBarStyle.shared`, which the shipping renderer reads,
// so the real status item redraws live as well. The Menu Bar section drives the real settings.

/// The mock: the rendered icon on a dark and a light bar, at real size and zoomed.
struct CompactMenuBarStage: View {
    @ObservedObject private var style = CompactMenuBarStyle.shared
    @ObservedObject private var settings = UserSettings.shared

    // Stage-only: mock figures and zoom, persisted so a session survives a rebuild
    @AppStorage("usagemeter.compactPlayground.fiveHour") private var fiveHour: Double = 0
    @AppStorage("usagemeter.compactPlayground.weekly") private var weekly: Double = 52
    @AppStorage("usagemeter.compactPlayground.model") private var model: Double = 8
    @AppStorage("usagemeter.compactPlayground.codex") private var showCodex: Bool = true
    @AppStorage("usagemeter.compactPlayground.codexWeekly") private var codexWeekly: Double = 17
    @AppStorage("usagemeter.compactPlayground.zoom") private var zoom: Double = 3

    var body: some View {
        VStack(spacing: 28) {
            bar(isDark: true)
            bar(isDark: false)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func bar(isDark: Bool) -> some View {
        let icon = render(isDark: isDark)
        return VStack(spacing: 14) {
            strip(icon, isDark: isDark, scale: 1)
            strip(icon, isDark: isDark, scale: zoom)
        }
    }

    /// A menu bar strip, 24 pt tall like the real one, with the item centred in it.
    private func strip(_ icon: NSImage, isDark: Bool, scale: Double) -> some View {
        Image(nsImage: icon)
            .renderingMode(icon.isTemplate ? .template : .original)
            .resizable()
            .interpolation(.high)
            .frame(width: icon.size.width * scale, height: icon.size.height * scale)
            .foregroundStyle(isDark ? Color.white : Color.black)
            .padding(.horizontal, 10 * scale)
            .frame(height: 24 * scale)
            .background(isDark ? Color(white: 0.16) : Color(white: 0.93))
            .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
    }

    /// Same appearance pin the per-display wrapper uses, so the tonal colours resolve for this strip.
    private func render(isDark: Bool) -> NSImage {
        _ = style.cacheToken   // re-render on any style change
        UsageColorScheme.drawingIsDarkOverride = isDark
        defer { UsageColorScheme.drawingIsDarkOverride = nil }
        return MenuBarIconRenderer(settings: settings).createIcon(
            usageData: mockClaude,
            codexUsageData: showCodex ? mockCodex : nil,
            hasUpdate: false,
            button: nil
        )
    }

    private var mockClaude: UsageData {
        UsageData(
            fiveHour: .init(percentage: fiveHour, resetsAt: Date().addingTimeInterval(3600 * 3)),
            sevenDay: .init(percentage: weekly, resetsAt: Date().addingTimeInterval(86400 * 4)),
            opus: .init(percentage: model, resetsAt: Date().addingTimeInterval(86400 * 4)),
            sonnet: nil,
            extraUsage: nil,
            opusModelName: "Fable"
        )
    }

    private var mockCodex: CodexUsageData {
        CodexUsageData(
            primary: nil,
            secondary: .init(percentage: codexWeekly, resetsAt: Date().addingTimeInterval(86400 * 3)),
            extraUsage: nil
        )
    }
}

struct CompactMenuBarPlaygroundView: View {
    @ObservedObject private var style = CompactMenuBarStyle.shared
    @ObservedObject private var settings = UserSettings.shared

    @AppStorage("usagemeter.compactPlayground.fiveHour") private var fiveHour: Double = 0
    @AppStorage("usagemeter.compactPlayground.weekly") private var weekly: Double = 52
    @AppStorage("usagemeter.compactPlayground.model") private var model: Double = 8
    @AppStorage("usagemeter.compactPlayground.codex") private var showCodex: Bool = true
    @AppStorage("usagemeter.compactPlayground.codexWeekly") private var codexWeekly: Double = 17
    @AppStorage("usagemeter.compactPlayground.zoom") private var zoom: Double = 3

    /// Shared row geometry, so every control's trailing edge agrees.
    private static let rowInset: CGFloat = 10

    @AppStorage("usagemeter.compactPlayground.expanded")
    private var expandedRaw: String = "Compact style\nMenu bar\nMock data"

    private var expanded: Set<String> {
        get { Set(expandedRaw.split(separator: "\n").map(String.init)) }
        nonmutating set { expandedRaw = newValue.sorted().joined(separator: "\n") }
    }

    /// Category / Usage / Monochrome, mapped onto the two stored settings exactly as the
    /// General tab's Color By picker does.
    private var colorBy: Binding<Int> {
        Binding(
            get: {
                if settings.iconStyleMode == .monochrome { return 2 }
                return settings.paceAwareBarColors ? 1 : 0
            },
            set: { mode in
                switch mode {
                case 0:
                    settings.iconStyleMode = .colorTranslucent
                    settings.paceAwareBarColors = false
                case 1:
                    settings.iconStyleMode = .colorTranslucent
                    settings.paceAwareBarColors = true
                default:
                    settings.iconStyleMode = .monochrome
                }
            }
        )
    }

    private var showIcon: Binding<Bool> {
        Binding(
            get: { settings.iconDisplayMode == .both },
            set: { settings.iconDisplayMode = $0 ? .both : .percentageOnly }
        )
    }

    var body: some View {
        HSplitView {
            CompactMenuBarStage()

            Form {
                accordion("Compact style") {
                    VStack(alignment: .leading, spacing: 14) {
                        picker("Layout", Binding(
                            get: { style.stacked ? 1 : 0 },
                            set: { style.stacked = $0 == 1 }
                        ), [(0, "Inline"), (1, "Stacked")])
                        if style.stacked {
                            slider("Font Size", $style.stackedFontSize, 6...11, "pt", step: 0.5)
                            slider("Line Gap", $style.lineGap, 0...5, "pt", step: 0.5)
                        } else {
                            slider("Font Size", $style.fontSize, 9...18, "pt", step: 0.5)
                        }
                        picker("Weight", $style.weightIndex,
                               CompactMenuBarStyle.weights.enumerated().map { ($0.offset, $0.element.title) })
                        slider("Spacing", $style.spacing, 0...16, "pt")
                        toggle("Show % Sign", $style.showPercentSign)
                    }
                }

                // The real settings, so every combination the renderer branches on is reachable here
                accordion("Menu bar") {
                    VStack(alignment: .leading, spacing: 14) {
                        toggle("Compact Menu Bar", $settings.compactMenuBar)
                        picker("Color By", colorBy, [(0, "Category"), (1, "Usage"), (2, "Monochrome")])
                        toggle("Show Icon", showIcon)
                        toggle("Show Remaining", $settings.showRemainingPercentage)
                    }
                }

                accordion("Mock data") {
                    VStack(alignment: .leading, spacing: 14) {
                        slider("5-Hour", $fiveHour, 0...100, "%", step: 1)
                        slider("Weekly All Models", $weekly, 0...100, "%", step: 1)
                        slider("Weekly Fable", $model, 0...100, "%", step: 1)
                        toggle("Codex", $showCodex)
                        slider("Codex Weekly", $codexWeekly, 0...100, "%", step: 1)
                        slider("Zoom", $zoom, 1...6, "×", step: 0.5)
                    }
                }

                Section {
                    HStack {
                        Button("Reset to defaults") { style.reset() }
                        Spacer()
                        Button("Copy as Swift") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(style.swiftSnippet, forType: .string)
                        }
                    }
                    .padding(.horizontal, Self.rowInset)
                }
            }
            .formStyle(.grouped)
            .frame(width: 320)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    // MARK: - Control Helpers

    /// Knobs snap by rounding inside the binding, never with `Slider`'s `step:`,
    /// which would make AppKit draw tick marks under the track.
    private func slider(
        _ label: String, _ value: Binding<Double>,
        _ range: ClosedRange<Double>, _ unit: String = "",
        step: Double? = nil
    ) -> some View {
        let step = step ?? (unit == "pt" ? 1 : 0.1)
        let format = step >= 1 ? "%.0f" : (step >= 0.1 ? "%.1f" : "%.2f")
        let snapped = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = ($0 / step).rounded() * step }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue, specifier: format) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            // Not optional: inside a grouped Form a Slider reserves a leading
            // label column even with no label, so the track starts halfway across.
            Slider(value: snapped, in: range)
                .labelsHidden()
                .padding(.vertical, 3)
        }
        // The inset belongs to the whole row, applied exactly once.
        .padding(.horizontal, Self.rowInset)
    }

    /// One row shape for controls with a natural width. The label is a plain `Text`
    /// styled here, never the control's own, which a grouped Form would restyle.
    private func inlineRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, Self.rowInset)
    }

    private func toggle(_ label: String, _ isOn: Binding<Bool>) -> some View {
        inlineRow(label) {
            Toggle("", isOn: isOn).labelsHidden().accessibilityLabel(label)
        }
    }

    private func picker(
        _ label: String, _ selection: Binding<Int>,
        _ options: [(tag: Int, title: String)]
    ) -> some View {
        inlineRow(label) {
            Picker("", selection: selection) {
                ForEach(options, id: \.tag) { Text($0.title).tag($0.tag) }
            }
            .labelsHidden()
            .accessibilityLabel(label)
            .font(.caption)
            .fixedSize()   // a width would centre the popup inside it
        }
    }

    private func accordion(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        let body = content()
        return Section {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expanded.contains(title) },
                    set: { isOpen in
                        var next = expanded
                        if isOpen { next.insert(title) } else { next.remove(title) }
                        expanded = next
                    }
                )
            ) {
                body.padding(.top, 4).padding(.bottom, 6)
            } label: {
                Text(title).font(.headline)
            }
        }
    }
}
#endif
