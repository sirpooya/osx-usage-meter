//
//  UsagePaceStatus.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2026-08-22.
//

import AppKit
import SwiftUI

/// Three step pace ramp, used to colour the period tick on a limit bar.
///
/// The reading is always "how far ahead of the clock am I". Projected under 70% of the cap means
/// the pace is sustainable for the rest of the window, so the tick stays blue. Past that it goes
/// orange, then red once the projection is close enough to the cap that the window ends at it.
/// More usage per unit of elapsed time is always worse, so the ramp only ever escalates.
///
/// Blue rather than green for the healthy step: the five hour limit's own bar is already green, so
/// a green tick would blur into the fill on that row.
enum UsagePaceStatus: Int, Comparable, CaseIterable {
    case onPace  = 0   // projected under 70%, sustainable
    case ahead   = 1   // projected 70-90%, pulling ahead of the clock
    case overrun = 2   // projected 90% or more, on course to hit the cap

    static func < (lhs: UsagePaceStatus, rhs: UsagePaceStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Below this much of the window elapsed there is nothing worth projecting from.
    ///
    /// Deliberately the same 15% as `UsagePaceCalculator.minimumElapsedFraction`, not lower. It
    /// used to be 3%, justified by this ramp only tinting a 2pt tick; that stopped being true
    /// once Usage mode took over the bars and the menu bar icons. At 3% a five hour window is
    /// projectable nine minutes in, so 9% used read as 180% of cap and painted a barely started
    /// window red. One early request divided by a tiny elapsed fraction is not a pace.
    static let minimumElapsedFraction: Double = UsagePaceCalculator.minimumElapsedFraction

    /// Pace step from the usage so far and how much of the window has gone.
    /// nil when the window has barely started or has already lapsed, in which case callers leave
    /// the tick its neutral colour.
    static func calculate(usedPercentage: Double, elapsedFraction: Double) -> UsagePaceStatus? {
        guard elapsedFraction >= minimumElapsedFraction, elapsedFraction < 1.0 else { return nil }
        guard usedPercentage > 0 else { return .onPace }
        let projected = (usedPercentage / 100.0) / elapsedFraction
        switch projected {
        case ..<0.70:     return .onPace
        case 0.70..<0.90: return .ahead
        default:          return .overrun
        }
    }

    /// The bar / icon colour. System colours, so each one adapts to light and dark itself.
    var nsColor: NSColor {
        switch self {
        case .onPace:  return .systemBlue
        case .ahead:   return .systemOrange
        case .overrun: return .systemRed
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// The ramp step from a percentage alone, with no pace in it: the same 70/90 breakpoints read
    /// against current usage.
    ///
    /// This is what a limit with no window to project across gets. In Usage mode **every** bar and
    /// icon has to be on the ramp: leaving one on its own palette (the pink Extra Usage hexagon)
    /// made the odd one out look like a bug, and it also read as a *limit* colour in a mode where
    /// colour is supposed to mean rate.
    static func level(usedPercentage: Double) -> UsagePaceStatus {
        switch usedPercentage {
        case ..<70:  return .onPace
        case 70..<90: return .ahead
        default:      return .overrun
        }
    }

    /// The ramp colour for one limit, from its percentage and reset time.
    ///
    /// The single entry point for both the popover bars and the menu bar icons, so the two cannot
    /// disagree about what colour a given pace is. Never nil: where a projection is available it
    /// wins, and otherwise the current percentage carries the ramp. The cases with no projection
    /// are the Extra Usage buckets (no fixed window), the first 3% of a window, and a window whose
    /// reset has already passed.
    static func color(
        usedPercentage: Double,
        resetsAt: Date?,
        type: LimitType,
        now: Date = Date()
    ) -> UsagePaceStatus {
        if let duration = UsagePaceCalculator.windowDuration(for: type),
           let elapsed = UsagePaceCalculator.elapsedFraction(
               resetsAt: resetsAt,
               duration: duration,
               now: now
           ),
           let paced = calculate(usedPercentage: usedPercentage, elapsedFraction: elapsed) {
            return paced
        }
        return level(usedPercentage: usedPercentage)
    }
}
