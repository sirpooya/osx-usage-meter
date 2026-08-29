//
//  UsageRowComponents.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Percentage Helpers

enum UsagePercentDisplay {
    static func clampedPercentage(_ percentage: Double) -> Double {
        min(100, max(0, percentage))
    }

    static func usedFraction(_ usedPercentage: Double) -> CGFloat {
        CGFloat(clampedPercentage(usedPercentage) / 100.0)
    }

    /// The percentage to show and to fill with: used, or remaining when battery style display is on.
    /// Status colors deliberately stay keyed off the used percentage, so escalation still means "close to the limit".
    static func displayPercentage(_ usedPercentage: Double) -> Double {
        let clamped = clampedPercentage(usedPercentage)
        return UserSettings.shared.showRemainingPercentage ? 100 - clamped : clamped
    }

    static func displayFraction(_ usedPercentage: Double) -> CGFloat {
        CGFloat(displayPercentage(usedPercentage) / 100.0)
    }
}

// MARK: - Provider Divider

/// The soft vertical line down the middle of the dual provider window, matching the settings page tab divider
struct ProviderDivider: View {
    let height: CGFloat

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.secondary.opacity(0.0),
                Color.secondary.opacity(0.3),
                Color.secondary.opacity(0.3),
                Color.secondary.opacity(0.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1, height: height)
    }
}

// MARK: - Usage Limit Bar

/// The horizontal bar for one limit. Full width, capsule shaped, replacing the old large ring.
struct UsageLimitBar: View {
    let fraction: CGFloat
    let color: Color
    var isRefreshing: Bool = false
    var height: CGFloat = 5
    /// Where the period itself has got to (0-1), drawn as a tick across the bar.
    /// nil hides it: either the setting is off or this limit has no window to measure.
    var markerFraction: CGFloat? = nil
    /// The unfilled remainder. nil keeps the neutral grey; Usage mode passes a tint of the fill,
    /// the way claude.ai draws its own bars.
    var trackColor: Color? = nil

    /// While refreshing, the whole bar breathes gently in place of the old ring's spinner
    @State private var isPulsing = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor ?? Color.primary.opacity(0.10))

                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: fillWidth(in: geometry.size.width))
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.05),
                        value: fraction
                    )

                if let markerFraction {
                    timeMarker(in: geometry.size.width, at: markerFraction)
                }
            }
        }
        .frame(height: height)
        .opacity(isRefreshing && isPulsing ? 0.4 : 1)
        .onAppear { updatePulse(isRefreshing) }
        .onChange(of: isRefreshing) { newValue in updatePulse(newValue) }
    }

    /// Fill width. A very small percentage still keeps one dot of width, otherwise the user cannot tell whether there is any usage at all
    private func fillWidth(in totalWidth: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return min(totalWidth, max(height, totalWidth * fraction))
    }

    /// The period tick. Drawn over both the fill and the track, in `labelColor` so it stays
    /// legible against either: near-black over a light track, white over a dark one, and in both
    /// cases readable on top of the saturated fill.
    private func timeMarker(in totalWidth: CGFloat, at markerFraction: CGFloat) -> some View {
        let markerWidth: CGFloat = 1.5
        let clamped = min(max(markerFraction, 0), 1)
        // Inset by half the tick so it sits fully inside the capsule at 0% and 100% instead of
        // half-hanging off the rounded ends.
        let centreX = markerWidth / 2 + (totalWidth - markerWidth) * clamped
        return Capsule(style: .continuous)
            .fill(Color(nsColor: .labelColor).opacity(0.55))
            .frame(width: markerWidth, height: height)
            .position(x: centreX, y: height / 2)
            .animation(.easeInOut(duration: 0.25), value: clamped)
    }

    private func updatePulse(_ refreshing: Bool) {
        if refreshing {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isPulsing = false
            }
        }
    }
}

// MARK: - Usage Limit Bar Row

/// One limit row: title and countdown on the upper left, percentage on the upper right, full width bar underneath
struct UsageLimitBarRow: View {
    /// One size for all three labels in the row, so title, countdown and percentage sit on one optical line.
    /// Hierarchy comes from weight and color instead, never from size.
    ///
    /// No `minimumScaleFactor` on any of them, deliberately. The title and countdown used to carry one,
    /// and since the percentage always has room it never shrank: a tight row ("5-Hour Limit  4h 51m left")
    /// scaled those two down to 10.2pt while the percentage stayed at 12, so a row declaring one size
    /// rendered two. Overflow truncates instead, and the title's `layoutPriority` makes the countdown
    /// give way first.
    private static let labelSize: CGFloat = 12

    let title: String
    let percentage: Double?
    let color: Color
    var isRefreshing: Bool = false
    /// How far through the period this limit is (0-1), or nil for no tick.
    /// Already mirrored for the remaining-percentage mode by the caller.
    var markerFraction: CGFloat? = nil
    /// The unfilled remainder, or nil for the neutral grey. See `UsageLimitBar.trackColor`.
    var trackColor: Color? = nil
    /// Observed so flipping the remaining percentage setting re-renders open popover rows
    @ObservedObject private var settings = UserSettings.shared
    /// The trailing text (reset time or time left).
    /// A closure rather than a snapshot value, so TimelineView can recompute it once a minute itself
    /// instead of relying on the outer objectWillChange rebuilding the whole popover every second.
    let trailing: () -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: Self.labelSize, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)

                // The countdown sits with the title rather than out on the right edge, so the row
                // reads as one phrase ("5-Hour Limit . 26m left") and the percentage stands alone.
                // The dot takes the countdown's secondary colour: it belongs to the countdown side
                // of the phrase, not to the title, and it disappears with the countdown.
                // TimelineView refreshes it at minute granularity itself (minute precision is all it needs, so 60s is enough)
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    let countdown = trailing()
                    if !countdown.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: "\u{00B7}")
                                .font(.system(size: Self.labelSize))
                                .foregroundColor(.secondary)
                            Text(countdown)
                                .font(.system(size: Self.labelSize))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                if let percentageText {
                    Text(percentageText)
                        .font(.system(size: Self.labelSize))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            UsageLimitBar(
                fraction: UsagePercentDisplay.displayFraction(percentage ?? 0),
                color: color,
                isRefreshing: isRefreshing,
                markerFraction: markerFraction,
                trackColor: trackColor
            )
        }
    }

    /// nil when the limit carries no percentage at all, so the row does not print a bare "%"
    private var percentageText: String? {
        guard let percentage else { return nil }
        return "\(Int(UsagePercentDisplay.displayPercentage(percentage)))%"
    }
}

// MARK: - Unified Limit Row Component

/// The shared limit row (covers every Claude and Codex limit type)
struct UnifiedLimitRow: View {
    let type: LimitType
    var data: UsageData? = nil
    var codexData: CodexUsageData? = nil
    let showRemainingMode: Bool
    /// This provider is refreshing, so the bar breathes to say so
    var isRefreshing: Bool = false
    /// Overflow model row override: when it is given, the row's percentage, label and reset time come straight from this model entry
    /// and `type` only picks the color slot. Used by the popover to show the third and later models
    /// beyond the first two slots (when Fable, Opus and Sonnet all appear at once).
    var weeklyModelOverride: UsageData.WeeklyModelLimit? = nil
    /// Observed so flipping the Monochrome icon setting recolors open popover rows live
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        UsageLimitBarRow(
            title: limitName,
            percentage: percentageValue,
            color: barColor,
            isRefreshing: isRefreshing,
            markerFraction: markerFraction,
            trackColor: paceTrackColor,
            trailing: { displayValue }
        )
    }

    /// Where to put the period tick, as a fraction of the bar.
    ///
    /// Mirrored to `1 - elapsed` in remaining-percentage mode, because the fill is mirrored too:
    /// leaving it un-mirrored would put the tick on the opposite side of the fill from where the
    /// comparison it exists to support actually lies.
    ///
    /// nil (no tick) when the setting is off, or the limit has no fixed window to measure
    /// (the Extra Usage buckets), or there is no reset time to measure from.
    private var markerFraction: CGFloat? {
        guard settings.showTimeMarker, let elapsed = rawElapsedFraction else { return nil }
        return CGFloat(settings.showRemainingPercentage ? 1 - elapsed : elapsed)
    }

    /// How much of this limit's window has gone, un-mirrored.
    /// The pace ramp has to read this rather than `markerFraction`, which is already flipped for
    /// remaining-percentage mode and would invert the projection with it.
    private var rawElapsedFraction: Double? {
        guard let duration = UsagePaceCalculator.windowDuration(for: type) else { return nil }
        return UsagePaceCalculator.elapsedFraction(resetsAt: resetsAtValue, duration: duration)
    }

    // MARK: - Computed Properties

    private var limitName: String {
        if let override = weeklyModelOverride {
            return override.modelName ?? L.DetailRow.opusWeekly
        }
        switch type {
        case .fiveHour, .codexPrimary:
            return L.DetailRow.fiveHour
        case .sevenDay, .codexSecondary:
            return L.DetailRow.sevenDay
        case .opusWeekly:
            // The Claude 5 era: this slot may carry a per model weekly limit from the limits array (Fable, for instance).
            // A real model name wins, otherwise it falls back to the default "Opus Weekly".
            return data?.opusModelName ?? L.DetailRow.opusWeekly
        case .sonnetWeekly:
            return data?.sonnetModelName ?? L.DetailRow.sonnetWeekly
        case .extraUsage, .codexExtraUsage:
            return L.DetailRow.extraUsage
        }
    }

    /// Bar color.
    ///
    /// Three sources, in priority order:
    ///
    /// 1. **Pace-aware mode.** The bar takes the pace ramp: blue while the rate is sustainable,
    ///    orange once it pulls ahead of the clock, red when the window is on course to end at the
    ///    cap. This is the whole point of the setting, so it wins over the palette. Falls through
    ///    when there is nothing to project from (no window, too early, no usage yet).
    /// 2. **Monochrome icon mode**, where the Claude bars all take the brand color.
    /// 3. Otherwise each limit type takes its own flat identity color, which never moves with the
    ///    percentage. That is the whole point of Limit mode: the color says *which* limit this is,
    ///    and the number and the fill say how full it is.
    private var barColor: Color {
        // Limit mode is flat, so the palettes are asked for their identity color, not the real
        // figure. Pace-aware mode replaces them outright below and never reaches this.
        let percentage = UsageColorScheme.flatPercentage
        if let pace = paceColor {
            return pace
        }
        if settings.iconStyleMode == .monochrome {
            switch type {
            case .fiveHour, .sevenDay, .opusWeekly, .sonnetWeekly, .extraUsage:
                return UsageColorScheme.brand
            case .codexPrimary, .codexSecondary, .codexExtraUsage:
                break
            }
        }
        switch type {
        case .fiveHour:
            return UsageColorScheme.fiveHourColorSwiftUI(percentage, opacity: 1.0)
        case .sevenDay:
            return UsageColorScheme.sevenDayColorSwiftUI(percentage, opacity: 1.0)
        case .opusWeekly:
            return Color(nsColor: UsageColorScheme.opusWeeklyColor(percentage))
        case .sonnetWeekly:
            return Color(nsColor: UsageColorScheme.sonnetWeeklyColor(percentage))
        case .extraUsage:
            return Color(nsColor: UsageColorScheme.extraUsageColor(percentage))
        case .codexPrimary:
            return UsageColorScheme.codexPrimaryColorSwiftUI(percentage, opacity: 1.0)
        case .codexSecondary:
            return UsageColorScheme.codexSecondaryColorSwiftUI(percentage, opacity: 1.0)
        case .codexExtraUsage:
            return UsageColorScheme.codexExtraUsageColorSwiftUI(percentage, opacity: 1.0)
        }
    }

    private var iconColor: Color {
        switch type {
        case .fiveHour:
            return .green
        case .sevenDay:
            return .purple
        case .opusWeekly:
            return .orange
        case .sonnetWeekly:
            return .blue
        case .extraUsage:
            return .pink
        case .codexPrimary:
            return Color(red: 45/255.0, green: 212/255.0, blue: 191/255.0)   // #2DD4BF
        case .codexSecondary:
            return Color(red: 96/255.0, green: 165/255.0, blue: 250/255.0)   // #60A5FA
        case .codexExtraUsage:
            return Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0)    // #F59E0B
        }
    }

    /// The pace ramp colour for this row's bar, or nil only when pace-aware mode is off.
    ///
    /// Every limit gets a ramp colour in this mode, including the Extra Usage buckets, which have
    /// no window to project across and so colour on their current percentage instead. Leaving
    /// those on their palette put one pink bar in a row of blue and red, which read as a bug and
    /// also meant colour said *which limit* in a mode where colour is supposed to mean rate.
    private var paceColor: Color? {
        guard settings.paceAwareBarColors else { return nil }
        return paceStatus?.color
    }

    /// The tinted track that goes with `paceColor`, or nil outside Usage mode so the bar keeps
    /// the neutral grey remainder.
    private var paceTrackColor: Color? {
        guard settings.paceAwareBarColors else { return nil }
        return paceStatus?.trackColor
    }

    private var paceStatus: UsagePaceStatus? {
        guard settings.paceAwareBarColors else { return nil }
        return UsagePaceStatus.color(
            usedPercentage: percentageValue ?? 0,
            resetsAt: resetsAtValue,
            type: type
        )
    }

    /// Reset time for this row's limit, the anchor the pace projection measures the window from.
    private var resetsAtValue: Date? {
        if let override = weeklyModelOverride {
            return override.limit.resetsAt
        }
        switch type {
        case .fiveHour:        return data?.fiveHour?.resetsAt
        case .sevenDay:        return data?.sevenDay?.resetsAt
        case .opusWeekly:      return data?.opus?.resetsAt
        case .sonnetWeekly:    return data?.sonnet?.resetsAt
        case .extraUsage:      return nil
        case .codexPrimary:    return codexData?.primary?.resetsAt
        case .codexSecondary:  return codexData?.secondary?.resetsAt
        case .codexExtraUsage: return nil
        }
    }

    private var percentageValue: Double? {
        if let override = weeklyModelOverride {
            return override.limit.percentage
        }
        switch type {
        case .fiveHour:       return data?.fiveHour?.percentage
        case .sevenDay:       return data?.sevenDay?.percentage
        case .opusWeekly:     return data?.opus?.percentage
        case .sonnetWeekly:   return data?.sonnet?.percentage
        case .extraUsage:     return data?.extraUsage?.percentage
        case .codexPrimary:   return codexData?.primary?.percentage
        case .codexSecondary: return codexData?.secondary?.percentage
        case .codexExtraUsage: return codexData?.extraUsage?.percentage
        }
    }

    private var displayValue: String {
        if let override = weeklyModelOverride {
            return showRemainingMode
                ? override.limit.formattedCompactRemaining
                : override.limit.formattedCompactResetDate
        }
        switch type {
        case .fiveHour:
            guard let fiveHour = data?.fiveHour else { return "-" }
            return showRemainingMode ? fiveHour.formattedCompactRemaining : detailCompactResetTime(fiveHour)

        case .sevenDay:
            guard let sevenDay = data?.sevenDay else { return "-" }
            return showRemainingMode ? sevenDay.formattedCompactRemaining : sevenDay.formattedCompactResetDate

        case .opusWeekly:
            guard let opus = data?.opus else { return "-" }
            return showRemainingMode ? opus.formattedCompactRemaining : opus.formattedCompactResetDate

        case .sonnetWeekly:
            guard let sonnet = data?.sonnet else { return "-" }
            return showRemainingMode ? sonnet.formattedCompactRemaining : sonnet.formattedCompactResetDate

        case .extraUsage:
            guard let extra = data?.extraUsage else { return "-" }
            return showRemainingMode ? extra.formattedRemainingAmount : extra.formattedCompactAmount

        case .codexPrimary:
            guard let limitData = codexData?.primary?.asUsageLimitData() else { return "-" }
            return showRemainingMode ? limitData.formattedCompactRemaining : detailCompactResetTime(limitData)

        case .codexSecondary:
            guard let limitData = codexData?.secondary?.asUsageLimitData() else { return "-" }
            // Two units, days plus hours, like every other row: minutes on a multi day countdown are just noise
            return showRemainingMode ? limitData.formattedCompactRemaining : limitData.formattedCompactResetDateWithMinutes

        case .codexExtraUsage:
            guard let extra = codexData?.extraUsage else { return "-" }
            return showRemainingMode ? extra.formattedDetailRemainingAmount : extra.formattedDetailCompactAmount
        }
    }

    private func detailCompactResetTime(_ limitData: UsageData.LimitData) -> String {
        guard let resetsAt = limitData.resetsAt else {
            return "-"
        }

        var calendar = Calendar.current
        calendar.locale = UserSettings.shared.appLocale
        let timeString = TimeFormatHelper.formatTimeOnly(resetsAt)

        if calendar.isDateInToday(resetsAt) {
            return "\(L.DetailRow.today) \(timeString)"
        }
        if calendar.isDateInTomorrow(resetsAt) {
            return "\(L.UsageData.tomorrow) \(timeString)"
        }
        return TimeFormatHelper.formatDateTime(resetsAt, dateTemplate: "Md")
    }
}
