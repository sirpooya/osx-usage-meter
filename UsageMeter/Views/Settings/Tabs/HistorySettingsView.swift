//
//  HistorySettingsView.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-08-21.
//
//  The History tab: a combined session + weekly usage chart over a pageable time
//  window, plus an API billing chart when Console spend samples exist. Ported
//  from hamed-elfayome/Claude-Usage-Tracker's UsageHistoryView (MIT) with its
//  known bugs left behind (duplicated billing title, hardcoded dollar sign,
//  macOS 14 only onChange signature).
//

import SwiftUI
import Charts

/// Chart window options. The raw value is the window length in hours, which is
/// what makes the paging math trivial.
enum ChartTimeScale: Double, CaseIterable {
    case hours5 = 5
    case hours24 = 24
    case days7 = 168
    case days30 = 720

    var label: String {
        switch self {
        case .hours5: return L.History.range5h
        case .hours24: return L.History.range24h
        case .days7: return L.History.range7d
        case .days30: return L.History.range30d
        }
    }
}

struct HistorySettingsView: View {
    @ObservedObject private var store = UsageHistoryStore.shared
    @State private var selectedTimeScale: ChartTimeScale = .hours24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Page header with the time scale dropdown
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.History.title)
                            .font(.system(size: 20, weight: .semibold))
                        Text(L.History.subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Picker("", selection: $selectedTimeScale) {
                        ForEach(ChartTimeScale.allCases, id: \.self) { scale in
                            Text(scale.label).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                UsageOverviewChart(
                    snapshots: store.history.usage,
                    timeScale: $selectedTimeScale
                )

                billingSection

                Spacer()
            }
            .padding(20)
        }
    }

    // MARK: - Billing

    @ViewBuilder
    private var billingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(L.History.apiBilling)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            if store.history.billing.isEmpty {
                HStack {
                    Spacer()
                    Text(L.History.noData)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 100)
                .background(HistoryChartCard.background)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                BillingHistoryChart(snapshots: store.history.billing)
            }
        }
    }
}

// MARK: - Shared card chrome

enum HistoryChartCard {
    static let background = Color.primary.opacity(0.05)
}

// MARK: - Usage overview chart

/// Which data series a chart point belongs to
private enum UsageSeries: String {
    case session
    case weekly

    var color: Color {
        switch self {
        case .session: return .accentColor
        case .weekly: return .indigo
        }
    }

    var lineStyle: StrokeStyle {
        switch self {
        case .session: return StrokeStyle(lineWidth: 2)
        case .weekly: return StrokeStyle(lineWidth: 2, dash: [6, 4])
        }
    }

    var label: String {
        switch self {
        case .session: return L.History.sessionUsage
        case .weekly: return L.History.weeklyUsage
        }
    }
}

private struct ChartDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let percentage: Double
    let series: UsageSeries
}

/// Session (solid, area filled) and weekly (dashed) usage on one shared 0-100 axis,
/// windowed to the selected scale and pageable by half a window per step.
struct UsageOverviewChart: View {
    let snapshots: [UsageSnapshot]
    @Binding var timeScale: ChartTimeScale

    /// Window offset in hours. 0 is now, negative is the past.
    @State private var timeOffset: Double = 0

    private var windowHours: Double { timeScale.rawValue }
    private var stepHours: Double { windowHours / 2 }

    private var visibleRange: (start: Date, end: Date) {
        let end = Date().addingTimeInterval(timeOffset * 3600)
        let start = end.addingTimeInterval(-windowHours * 3600)
        return (start, end)
    }

    private var chartDataPoints: [ChartDataPoint] {
        let range = visibleRange
        let visible = snapshots.filter { $0.timestamp >= range.start && $0.timestamp <= range.end }
        var points: [ChartDataPoint] = []
        for snapshot in visible {
            if let value = snapshot.sessionPercentage {
                points.append(ChartDataPoint(
                    timestamp: snapshot.timestamp,
                    percentage: min(max(value, 0), 100),
                    series: .session
                ))
            }
            if let value = snapshot.weeklyPercentage {
                points.append(ChartDataPoint(
                    timestamp: snapshot.timestamp,
                    percentage: min(max(value, 0), 100),
                    series: .weekly
                ))
            }
        }
        return points
    }

    private var canGoForward: Bool { timeOffset < 0 }

    private var canGoBack: Bool {
        guard let oldest = snapshots.first?.timestamp else { return false }
        return oldest < visibleRange.start
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title row with the inline legend
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(L.History.usageOverview)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    legendItem(series: .session)
                    legendItem(series: .weekly)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if chartDataPoints.isEmpty {
                HStack {
                    Spacer()
                    Text(L.History.noData)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 160)
            } else {
                Chart(chartDataPoints) { point in
                    if point.series == .session {
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Usage", point.percentage)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.stepEnd)
                    }

                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Usage", point.percentage),
                        series: .value("Series", point.series.rawValue)
                    )
                    .foregroundStyle(point.series.color)
                    .interpolationMethod(.stepEnd)
                    .lineStyle(point.series.lineStyle)
                }
                .chartXScale(domain: visibleRange.start...visibleRange.end)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)%")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: xAxisFormat)
                            .font(.system(size: 9))
                    }
                }
                .frame(height: 160)
                .padding(12)
            }

            // Bottom bar: paging
            HStack(spacing: 12) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { timeOffset -= stepHours } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.3)

                Spacer()

                Text(timeRangeLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { timeOffset = 0 } }) {
                    Text(L.History.now)
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(timeOffset == 0)
                .opacity(timeOffset == 0 ? 0.3 : 1)

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { timeOffset = min(timeOffset + stepHours, 0) } }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.3)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(HistoryChartCard.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: timeScale) { _ in
            timeOffset = 0
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func legendItem(series: UsageSeries) -> some View {
        HStack(spacing: 4) {
            if series == .session {
                ZStack {
                    Rectangle()
                        .fill(series.color.opacity(0.2))
                        .frame(width: 16, height: 8)
                    Rectangle()
                        .fill(series.color)
                        .frame(width: 16, height: 2)
                }
            } else {
                // Dashes drawn as positive marks, not knocked out of a solid bar,
                // so the swatch reads on any background
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(series.color)
                            .frame(width: 4, height: 2)
                    }
                }
            }

            Text(series.label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private var timeRangeLabel: String {
        let range = visibleRange
        let style: Date.FormatStyle
        switch timeScale {
        case .hours5, .hours24:
            style = .dateTime.month(.abbreviated).day().hour().minute()
        case .days7, .days30:
            style = .dateTime.month(.abbreviated).day()
        }
        return String(
            format: L.History.rangeFormat,
            range.start.formatted(style),
            range.end.formatted(style)
        )
    }

    private var xAxisFormat: Date.FormatStyle {
        switch timeScale {
        case .hours5, .hours24:
            return .dateTime.hour().minute()
        case .days7:
            return .dateTime.weekday(.abbreviated).hour()
        case .days30:
            return .dateTime.month(.abbreviated).day()
        }
    }
}

// MARK: - Billing chart

/// Recorded Console spend over time, one accent colored bar per sample.
struct BillingHistoryChart: View {
    let snapshots: [BillingSnapshot]
    private let maxItems = 60

    private var chartData: [BillingSnapshot] {
        Array(snapshots.suffix(maxItems))
    }

    private var maxSpend: Double {
        let maxCents = chartData.map { $0.spendCents }.max() ?? 0
        return Swift.max(Double(maxCents) / 100.0, 10.0)
    }

    /// Axis unit prefix: "$" for USD, otherwise the ISO code
    private var currencyPrefix: String {
        let code = chartData.last?.currency ?? "USD"
        return code == "USD" ? "$" : "\(code) "
    }

    var body: some View {
        Chart(chartData) { snapshot in
            BarMark(
                x: .value("Date", snapshot.timestamp, unit: .hour),
                y: .value("Spend", Double(snapshot.spendCents) / 100.0)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartYScale(domain: 0...maxSpend * 1.1)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text("\(currencyPrefix)\(Int(doubleValue))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 9))
            }
        }
        .frame(height: 140)
        .padding(12)
        .background(HistoryChartCard.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Preview

struct HistorySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        HistorySettingsView()
            .frame(width: 720, height: 600)
    }
}
