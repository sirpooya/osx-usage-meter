//
//  UsagePaceCalculator.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-08-22.
//

import Foundation

/// Projects end-of-window usage from the pace so far, for the pace-aware bar colours.
///
/// The question a percentage cannot answer is "am I on track to hit this cap". 40% used means
/// something very different two hours into a five hour window than it does ten minutes in. So
/// the projection extrapolates the current rate to the end of the window, and the bar colour
/// escalates on that instead of on the raw figure.
///
/// The maths here takes primitives rather than the app's models so it stays pure and checkable.
enum UsagePaceCalculator {

    /// Below this much of the window elapsed, the projection is not trustworthy: a single early
    /// request divided by a tiny elapsed fraction extrapolates to an absurd figure, which would
    /// paint the bar red seconds into a fresh window. Matches the competitor's threshold.
    static let minimumElapsedFraction: Double = 0.15

    /// How long each limit's window runs. `nil` for the Extra Usage buckets, which have no fixed
    /// window to project across, so those keep colouring on current usage.
    static func windowDuration(for type: LimitType) -> TimeInterval? {
        switch type {
        case .fiveHour, .codexPrimary:
            return 5 * 60 * 60
        case .sevenDay, .opusWeekly, .sonnetWeekly, .codexSecondary:
            return 7 * 24 * 60 * 60
        case .extraUsage, .codexExtraUsage:
            return nil
        }
    }

    /// Fraction of the window already gone (0-1), derived from the reset time.
    /// `nil` when there is no reset time, or the window has already lapsed (the reset is in the
    /// past, so a refresh is pending and there is nothing to project).
    static func elapsedFraction(resetsAt: Date?, duration: TimeInterval, now: Date = Date()) -> Double? {
        guard let resetsAt, duration > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        // Guard against a reset further out than one whole window, which would imply a negative
        // elapsed time and read as "no usage yet" rather than as bad data.
        guard remaining <= duration else { return nil }
        let elapsed = duration - remaining
        return min(max(elapsed / duration, 0), 1)
    }

    /// The projected end-of-window percentage, clamped to 100.
    /// `nil` whenever the projection would be meaningless, in which case callers fall back to the
    /// current percentage: no usage yet, too early in the window, or no window to project across.
    static func projectedPercentage(
        usedPercentage: Double,
        resetsAt: Date?,
        duration: TimeInterval?,
        now: Date = Date()
    ) -> Double? {
        guard usedPercentage > 0,
              let duration,
              let elapsed = elapsedFraction(resetsAt: resetsAt, duration: duration, now: now),
              elapsed >= minimumElapsedFraction,
              elapsed < 1.0
        else { return nil }
        return min(100, usedPercentage / elapsed)
    }

    /// Convenience over `projectedPercentage` that reads the window length from the limit type.
    static func projectedPercentage(
        usedPercentage: Double,
        resetsAt: Date?,
        type: LimitType,
        now: Date = Date()
    ) -> Double? {
        projectedPercentage(
            usedPercentage: usedPercentage,
            resetsAt: resetsAt,
            duration: windowDuration(for: type),
            now: now
        )
    }
}
