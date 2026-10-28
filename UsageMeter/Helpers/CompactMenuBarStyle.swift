//
//  CompactMenuBarStyle.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-10-28.
//

import AppKit
import Combine

/// Type and spacing of the compact menu bar, where each limit is its percentage as plain text.
///
/// The menu bar renderer reads `shared`, and the debug Compact Menu Bar playground writes it, so
/// tuning there redraws the real status item live. The defaults below are the shipped values; a
/// tuning session is saved as one JSON blob and only a debug build can write it.
final class CompactMenuBarStyle: ObservableObject {
    static let shared = CompactMenuBarStyle()

    /// Weights offered, in picker order. Index is what gets stored.
    static let weights: [(title: String, weight: NSFont.Weight)] = [
        ("Regular", .regular), ("Medium", .medium), ("Semibold", .semibold), ("Bold", .bold)
    ]

    /// Stacked puts each provider's figures two to a column, small, right aligned so the digits
    /// line up; a third limit starts the next column. Inline is one row at menu bar text size.
    @Published var stacked: Bool = true { didSet { changed() } }
    /// Inline size. 13 pt sits just under the system menu bar text (the clock is 13-14), so the
    /// figures read as part of the bar rather than shouting over it.
    @Published var fontSize: Double = 13 { didSet { changed() } }
    /// Stacked size. Two rows of digits have to fit the 18 pt icon height, so about 11 is the cap.
    @Published var stackedFontSize: Double = 9 { didSet { changed() } }
    /// Gap between the two rows of a stacked column, measured between the digits themselves.
    @Published var lineGap: Double = 2 { didSet { changed() } }
    /// Index into `weights`. Medium: regular reads thin next to the clock, semibold heavy.
    @Published var weightIndex: Int = 1 { didSet { changed() } }
    /// Gap between neighbouring figures, and either side of the Claude / Codex dot.
    @Published var spacing: Double = 4 { didSet { changed() } }
    /// Without the sign three bare numbers read as a list of anything.
    @Published var showPercentSign: Bool = true { didSet { changed() } }

    /// The size the current layout draws at.
    var activeFontSize: Double { stacked ? stackedFontSize : fontSize }

    var weight: NSFont.Weight {
        Self.weights[min(max(weightIndex, 0), Self.weights.count - 1)].weight
    }

    /// Part of the icon cache key: these change the image without changing any data.
    var cacheToken: String {
        "_cmp\(stacked ? "st\(stackedFontSize)g\(lineGap)" : "\(fontSize)")w\(weightIndex)s\(Int(spacing))\(showPercentSign ? "p" : "")"
    }

    private static let defaultsKey = "usagemeter.compactMenuBarStyle"
    private var isLoading = false

    private init() {
        load()
    }

    func reset() {
        let defaults = Snapshot()
        isLoading = true
        apply(defaults)
        isLoading = false
        changed()
    }

    /// Theme style snippet of the current values, for promoting a tuning into the defaults above.
    var swiftSnippet: String {
        """
        @Published var stacked: Bool = \(stacked)
        @Published var fontSize: Double = \(fontSize)
        @Published var stackedFontSize: Double = \(stackedFontSize)
        @Published var lineGap: Double = \(lineGap)
        @Published var weightIndex: Int = \(weightIndex)  // \(Self.weights[weightIndex].title)
        @Published var spacing: Double = \(Int(spacing))
        @Published var showPercentSign: Bool = \(showPercentSign)
        """
    }

    // MARK: - Persistence

    /// Decoded key by key with a default each, so adding a knob later does not throw away a saved set.
    private struct Snapshot: Codable {
        var stacked: Bool = true
        var fontSize: Double = 13
        var stackedFontSize: Double = 9
        var lineGap: Double = 2
        var weightIndex: Int = 1
        var spacing: Double = 4
        var showPercentSign: Bool = true

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Snapshot()
            stacked = try c.decodeIfPresent(Bool.self, forKey: .stacked) ?? d.stacked
            fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
            stackedFontSize = try c.decodeIfPresent(Double.self, forKey: .stackedFontSize) ?? d.stackedFontSize
            lineGap = try c.decodeIfPresent(Double.self, forKey: .lineGap) ?? d.lineGap
            weightIndex = try c.decodeIfPresent(Int.self, forKey: .weightIndex) ?? d.weightIndex
            spacing = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? d.spacing
            showPercentSign = try c.decodeIfPresent(Bool.self, forKey: .showPercentSign) ?? d.showPercentSign
        }
    }

    private func apply(_ s: Snapshot) {
        stacked = s.stacked
        fontSize = s.fontSize
        stackedFontSize = s.stackedFontSize
        lineGap = s.lineGap
        weightIndex = s.weightIndex
        spacing = s.spacing
        showPercentSign = s.showPercentSign
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        isLoading = true
        apply(snapshot)
        isLoading = false
    }

    /// Autosave and redraw the status item on every change, batched loads excepted.
    private func changed() {
        guard !isLoading else { return }
        var s = Snapshot()
        s.stacked = stacked
        s.fontSize = fontSize
        s.stackedFontSize = stackedFontSize
        s.lineGap = lineGap
        s.weightIndex = weightIndex
        s.spacing = spacing
        s.showPercentSign = showPercentSign
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
