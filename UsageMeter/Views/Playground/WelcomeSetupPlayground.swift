//
//  WelcomeSetupPlayground.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-08-22.
//

#if DEBUG
// `Combine` is not optional here: `ObservableObject` and `@Published` are defined there and
// `import SwiftUI` does not re-export them. Same trap as `UsageHistoryStore`.
import Combine
import SwiftUI

// MARK: - Welcome Setup Playground
//
// A dev-only window for looking at `RevivedSetupStepView`, the welcome flow's deleted second page,
// at the size it actually shipped at. The page is a design reference rather than live UI, so this
// stage deliberately has no knobs that restyle it: what is worth adjusting is the *frame* it is
// judged in and the settings state it renders against, since the page branches on display mode,
// icon style and the custom limit set.

/// Stage-only state. Nothing here is promoted into the app: it exists to frame the mock.
/// Persisted for the same reason every other playground's stage switches are, so a session
/// survives a rebuild.
@MainActor
final class WelcomeSetupStageState: ObservableObject {
    static let shared = WelcomeSetupStageState()

    /// The reference size the page shipped at, from the deleted `WelcomeView`'s own `.frame`.
    static let referenceSize = CGSize(width: 550, height: 600)

    /// Written straight to `UserDefaults` rather than through `@AppStorage`, which is a `View`
    /// property wrapper: in a class it neither publishes nor satisfies `ObservableObject`.
    /// Reading a missing key back as 0 would collapse the stage, so each getter falls back to the
    /// reference value the same way `showRemainingMode` does elsewhere in the app.
    @Published var width: Double = defaults(.width) ?? referenceSize.width {
        didSet { store(.width, width) }
    }

    @Published var height: Double = defaults(.height) ?? referenceSize.height {
        didSet { store(.height, height) }
    }

    /// Draws the reference frame's edge, so a page that overflows 550x600 is obvious.
    @Published var showFrame: Bool = (UserDefaults.standard.object(forKey: Key.showFrame.rawValue) as? Bool) ?? true {
        didSet { UserDefaults.standard.set(showFrame, forKey: Key.showFrame.rawValue) }
    }

    private enum Key: String {
        case width = "usagemeter.welcomeSetupPlayground.width"
        case height = "usagemeter.welcomeSetupPlayground.height"
        case showFrame = "usagemeter.welcomeSetupPlayground.showFrame"
    }

    private static func defaults(_ key: Key) -> Double? {
        UserDefaults.standard.object(forKey: key.rawValue) as? Double
    }

    private func store(_ key: Key, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    private init() {}
}

/// The mock: the page inside a window shaped frame at the size being judged.
struct WelcomeSetupStage: View {
    @ObservedObject private var stage = WelcomeSetupStageState.shared

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            RevivedSetupStepView(
                sessionKey: .constant(""),
                isShowingPassword: .constant(false)
            )
            .frame(width: stage.width, height: stage.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if stage.showFrame {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct WelcomeSetupPlaygroundView: View {
    @ObservedObject private var stage = WelcomeSetupStageState.shared
    @ObservedObject private var settings = UserSettings.shared

    /// Shared row geometry, so every control's trailing edge agrees.
    private static let rowInset: CGFloat = 10

    @AppStorage("usagemeter.welcomeSetupPlayground.expanded")
    private var expandedRaw: String = "Frame\nPage state"

    private var expanded: Set<String> {
        get { Set(expandedRaw.split(separator: "\n").map(String.init)) }
        nonmutating set { expandedRaw = newValue.sorted().joined(separator: "\n") }
    }

    var body: some View {
        HSplitView {
            WelcomeSetupStage()

            Form {
                accordion("Frame") {
                    VStack(alignment: .leading, spacing: 14) {
                        slider("Width", $stage.width, 360...900, "pt")
                        slider("Height", $stage.height, 380...1000, "pt")
                        toggle("Show reference frame", $stage.showFrame)
                    }
                }

                // The page branches on these, so they are the only way to see all of its states.
                accordion("Page state") {
                    VStack(alignment: .leading, spacing: 14) {
                        picker("Display mode", Binding(
                            get: { settings.displayMode == .smart ? 0 : 1 },
                            set: { settings.displayMode = $0 == 0 ? .smart : .custom }
                        ), [(0, "Smart"), (1, "Custom")])

                        picker("Icon style", Binding(
                            get: { settings.iconStyleMode == .monochrome ? 1 : 0 },
                            set: { settings.iconStyleMode = $0 == 1 ? .monochrome : .colorTranslucent }
                        ), [(0, "Color"), (1, "Monochrome")])
                    }
                }

                Section {
                    HStack {
                        Button("Reset to reference") {
                            stage.width = WelcomeSetupStageState.referenceSize.width
                            stage.height = WelcomeSetupStageState.referenceSize.height
                            stage.showFrame = true
                        }
                        Spacer()
                        Button("Copy size") {
                            let snippet = """
                            static let contentSize = NSSize(width: \(Int(stage.width)), height: \(Int(stage.height)))
                            """
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(snippet, forType: .string)
                        }
                    }
                    .padding(.horizontal, Self.rowInset)
                }
            }
            .formStyle(.grouped)
            .frame(width: 320)
        }
        .frame(minWidth: 900, minHeight: 640)
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
                        // Statement body, not a ternary: `Set.insert` returns a tuple and
                        // `remove` an Optional, so the two branches have no common type.
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
