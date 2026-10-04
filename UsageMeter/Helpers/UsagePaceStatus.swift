//
//  UsagePaceStatus.swift
//  UsageMeter
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

    /// The bar / icon fill colour.
    ///
    /// The amber and the red are sampled straight off claude.ai's own usage bars, so a percentage
    /// that reads amber on the web reads the same amber here. `systemBlue` for the healthy step is
    /// ours: neither reference bar was under 70%, so there was nothing to sample.
    var nsColor: NSColor {
        switch self {
        case .onPace:  return .systemBlue
        case .ahead:   return NSColor(srgbRed: 0xF3/255.0, green: 0xB6/255.0, blue: 0x3F/255.0, alpha: 1)
        case .overrun: return NSColor(srgbRed: 0xC5/255.0, green: 0x4A/255.0, blue: 0x41/255.0, alpha: 1)
        }
    }

    /// The unfilled remainder behind the fill.
    ///
    /// claude.ai tints this to match the fill (light amber behind amber, light pink behind red)
    /// rather than leaving it neutral grey, and the two tints are their own tokens, not the fill
    /// blended with white: #F3B63F over white at any single alpha lands on #F6C8xx, not #F6DDAA.
    /// So both are sampled literally.
    ///
    /// Those samples come from a light background, and dropped onto a dark popover they read as
    /// near-white bars with a hint of colour. Dark mode gets the fill at low alpha instead, which
    /// keeps the same "track is a quiet version of the fill" reading at the right weight.
    var trackNSColor: NSColor {
        let light: NSColor
        switch self {
        case .onPace:  light = NSColor(srgbRed: 0xC7/255.0, green: 0xDD/255.0, blue: 0xF8/255.0, alpha: 1)
        case .ahead:   light = NSColor(srgbRed: 0xF6/255.0, green: 0xDD/255.0, blue: 0xAA/255.0, alpha: 1)
        case .overrun: light = NSColor(srgbRed: 0xF6/255.0, green: 0xD8/255.0, blue: 0xD7/255.0, alpha: 1)
        }
        let dark = nsColor.withAlphaComponent(0.28)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var trackColor: Color { Color(nsColor: trackNSColor) }

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

    /// The ramp colour for one limit, from the percentage actually used.
    ///
    /// The single entry point for both the popover bars and the menu bar icons, so the two cannot
    /// disagree about what colour a given figure is.
    ///
    /// **Reads the plain used percentage, not a pace projection**, which is what claude.ai's own
    /// usage bars do: 78% used is amber there and 93% used is red, off the number alone. This
    /// deliberately replaced a projection (`used / elapsedFraction`), which coloured by *rate*
    /// rather than by amount and so disagreed with the web at the same percentage. At its worst
    /// it painted a barely started window red: 9% used a quarter hour into a five hour window
    /// projects to 180% of cap. `resetsAt` and `type` are kept in the signature because callers
    /// pass them and a window-aware variant may come back as its own mode.
    static func color(
        usedPercentage: Double,
        resetsAt: Date? = nil,
        type: LimitType? = nil,
        now: Date = Date()
    ) -> UsagePaceStatus {
        level(usedPercentage: usedPercentage)
    }
}
