//
//  ColorScheme.swift
//  UsageMeter
//
//  Created by Claude on 2025-11-26.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit
import OSLog

/// Central color scheme
/// Colors for the 5 hour and 7 day limits, for both AppKit and SwiftUI
enum UsageColorScheme {

    // MARK: - Brand color

    /// App brand color #D97757, the same display-p3 value as the app icon
    static let brand = Color(.displayP3, red: 0.8510, green: 0.4667, blue: 0.3412)

    // MARK: - Flat per-limit identity colors

    /// The percentage the per-limit palettes are asked for when the color must not escalate.
    ///
    /// In Limit color mode a bar's color says *which* limit it is, never how full it is, so every
    /// render site calls its palette with this instead of the real figure. Each palette's safe
    /// step already is that limit's identity color, so this returns it without duplicating a
    /// second set of hex values that could drift from the first.
    ///
    /// Escalation lives in the other two color modes only: the pace ramp in Usage mode, and
    /// `ShapeIconRenderer.monochromeOpacity` in Monochrome. Do not reintroduce it here.
    static let flatPercentage: Double = 0

    // MARK: - Appearance detection

    /// Detect whether dark mode is active
    /// - Parameter statusButton: optional status item button, used to read the appearance
    /// - Returns: true for dark mode, false for light mode
    /// Per-display render override. Set while drawing into a specific menu bar window
    /// (the dynamic image handler and the replicant pass in MenuBarPerDisplayIcon), so a
    /// render can be forced to that bar's appearance regardless of which display the main
    /// button sits on. Main thread only, always reset right after the render.
    static var drawingIsDarkOverride: Bool?

    static func isDarkMode(for statusButton: NSStatusBarButton? = nil) -> Bool {
        // Method 0: per-display override, wins over every probe below
        if let forced = drawingIsDarkOverride { return forced }

        // Method 1: read the appearance from the status item button (most accurate, it reflects the real menu bar appearance)
        if let button = statusButton,
           let appearance = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return appearance == .darkAqua
        }

        // Method 2: read the system appearance setting directly (unaffected by NSApp.appearance)
        // Once the user picks an app appearance preference, NSApp.effectiveAppearance reflects the app setting rather than the system one
        // Menu bar icon rendering must always follow the system appearance, so read the real system state here
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Detect whether dark mode is active (convenience property)
    static var isDarkMode: Bool {
        return isDarkMode(for: nil)
    }

    // MARK: - Menu bar foreground color (color mode)

    /// Foreground color in color mode (digits, glyphs).
    /// The monochrome image is a template, so AppKit keeps only its alpha and tints it to the menu bar, which makes any color correct;
    /// a color mode image is not a template, so whatever is drawn is used literally and has to be resolved against the menu bar appearance:
    /// white on a dark menu bar, near black on a light one. A hardcoded NSColor.black is exactly why the glyph vanished on a dark bar.
    /// - Parameter statusButton: the status item button, the only place the real menu bar appearance can come from
    static func menuBarForeground(for statusButton: NSStatusBarButton? = nil) -> NSColor {
        isDarkMode(for: statusButton) ? .white : NSColor(white: 0.1, alpha: 1.0)
    }

    /// Track color of the progress ring (the unused arc), a translucent version of the foreground
    static func menuBarTrack(for statusButton: NSStatusBarButton? = nil) -> NSColor {
        menuBarForeground(for: statusButton).withAlphaComponent(0.25)
    }

    // MARK: - 5 hour limit colors (green to orange to red)

    /// NSColor for a 5 hour limit usage percentage
    /// - Parameter percentage: usage percentage (0-100)
    /// - Returns: the matching status color
    /// - Note: 0-70% green (safe), 70-90% orange (warning), 90-100% red (danger)
    static func fiveHourColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 40/255.0, green: 180/255.0, blue: 70/255.0, alpha: 1.0)  // Slightly darker green #28B446
        } else if percentage < 90 {
            return NSColor.systemOrange
        } else {
            return NSColor.systemRed
        }
    }

    /// SwiftUI Color for a 5 hour limit usage percentage
    /// - Parameter percentage: usage percentage (0-100)
    /// - Returns: the matching status color
    /// - Note: 0-70% green (safe), 70-90% orange (warning), 90-100% red (danger)
    ///         The detail UI adds opacity on top to soften the colors
    static func fiveHourColorSwiftUI(_ percentage: Double, opacity: Double = 0.9) -> Color {
        if percentage < 70 {
            return .green.opacity(opacity)  // System green
        } else if percentage < 90 {
            return .orange.opacity(opacity)
        } else {
            return .red.opacity(opacity)
        }
    }

    /// Adaptive NSColor for a 5 hour limit usage percentage (brightness follows the system appearance)
    /// - Parameters:
    ///   - percentage: usage percentage (0-100)
    ///   - statusButton: status item button, used to read the accurate appearance
    /// - Returns: status color matched to the current appearance
    /// - Note: brightness is raised automatically in dark mode, so it stays legible on a dark background
    static func fiveHourColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = fiveHourColor(percentage)

        if isDarkMode(for: statusButton) {
            // Dark mode: raise the brightness for a brighter color
            return baseColor.adjustedForDarkMode()
        } else {
            // Light mode: the original color, or slightly darker
            return baseColor
        }
    }

    // MARK: - 7 day limit colors

    /// NSColor for a 7 day limit usage percentage
    /// - Parameter percentage: usage percentage (0-100)
    /// - Returns: the matching status color
    /// - Note: current scheme, light purple to deep purple to purple red
    ///         0-70% light purple (safe), 70-90% deep purple (warning), 90-100% purple red (danger)
    static func sevenDayColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 192/255.0, green: 132/255.0, blue: 252/255.0, alpha: 1.0)  // Light purple #C084FC
        } else if percentage < 90 {
            return NSColor(red: 180/255.0, green: 80/255.0, blue: 240/255.0, alpha: 1.0)  // Deep purple #B450F0
        } else {
            return NSColor(red: 180/255.0, green: 30/255.0, blue: 160/255.0, alpha: 1.0)   // Purple red #B41EA0 (strong warning)
        }
    }

    /// SwiftUI Color for a 7 day limit usage percentage
    /// - Parameter percentage: usage percentage (0-100)
    /// - Returns: the matching status color
    /// - Note: current scheme, light purple to deep purple to purple red
    ///         0-70% light purple (safe), 70-90% deep purple (warning), 90-100% purple red (danger)
    ///         The detail UI adds opacity on top to soften the colors
    static func sevenDayColorSwiftUI(_ percentage: Double, opacity: Double = 0.9) -> Color {
        if percentage < 70 {
            return Color(red: 192/255.0, green: 132/255.0, blue: 252/255.0).opacity(opacity)  // Light purple #C084FC
        } else if percentage < 90 {
            return Color(red: 180/255.0, green: 80/255.0, blue: 240/255.0).opacity(opacity)  // Deep purple #B450F0
        } else {
            return Color(red: 180/255.0, green: 30/255.0, blue: 160/255.0).opacity(opacity)   // Purple red #B41EA0 (strong warning)
        }
    }

    /// Adaptive NSColor for a 7 day limit usage percentage (brightness follows the system appearance)
    /// - Parameters:
    ///   - percentage: usage percentage (0-100)
    ///   - statusButton: status item button, used to read the accurate appearance
    /// - Returns: status color matched to the current appearance
    /// - Note: brightness and saturation are raised automatically in dark mode, so it stays legible on a dark background
    static func sevenDayColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = sevenDayColor(percentage)

        if isDarkMode(for: statusButton) {
            // Dark mode: raise brightness and saturation
            return baseColor.adjustedForDarkMode()
        } else {
            // Light mode: the original color
            return baseColor
        }
    }

    // MARK: - Extra Usage colors (pink to red to magenta)

    /// NSColor for an Extra Usage percentage
    /// - Parameter percentage: usage percentage (0-100)
    /// - Returns: the matching status color
    /// - Note: 0-70% pink (safe), 70-90% rose (warning), 90-100% magenta (danger)
    static func extraUsageColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 255/255.0, green: 158/255.0, blue: 205/255.0, alpha: 1.0)  // Pink #FF9ECD
        } else if percentage < 90 {
            return NSColor(red: 236/255.0, green: 72/255.0, blue: 153/255.0, alpha: 1.0)   // Rose #EC4899
        } else {
            return NSColor(red: 217/255.0, green: 70/255.0, blue: 239/255.0, alpha: 1.0)   // Magenta #D946EF
        }
    }

    /// Adaptive NSColor for an Extra Usage percentage
    static func extraUsageColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = extraUsageColor(percentage)
        if isDarkMode(for: statusButton) {
            return baseColor.adjustedForDarkMode()
        } else {
            return baseColor
        }
    }

    // MARK: - Opus Weekly colors (light orange to orange to orange red)

    /// NSColor for an Opus Weekly usage percentage
    /// - Parameter percentage: usage percentage (0-100)
    /// - Returns: the matching status color
    /// - Note: 0-70% amber (safe), 70-90% orange (warning), 90-100% orange red (danger)
    static func opusWeeklyColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 251/255.0, green: 191/255.0, blue: 36/255.0, alpha: 1.0)  // Amber #FBBF24
        } else if percentage < 90 {
            return NSColor.systemOrange
        } else {
            return NSColor(red: 255/255.0, green: 100/255.0, blue: 50/255.0, alpha: 1.0)   // Orange red #FF6432
        }
    }

    /// Adaptive NSColor for an Opus Weekly usage percentage
    static func opusWeeklyColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = opusWeeklyColor(percentage)
        if isDarkMode(for: statusButton) {
            return baseColor.adjustedForDarkMode()
        } else {
            return baseColor
        }
    }

    // MARK: - Sonnet Weekly colors (light blue to blue to blue violet)

    /// NSColor for a Sonnet Weekly usage percentage
    /// - Parameter percentage: usage percentage (0-100)
    /// - Returns: the matching status color
    /// - Note: 0-70% light blue (safe), 70-90% blue (warning), 90-100% deep indigo (danger)
    static func sonnetWeeklyColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 100/255.0, green: 200/255.0, blue: 255/255.0, alpha: 1.0)  // Light blue #64C8FF
        } else if percentage < 90 {
            return NSColor.systemBlue
        } else {
            return NSColor(red: 79/255.0, green: 70/255.0, blue: 229/255.0, alpha: 1.0)   // Deep indigo #4F46E5
        }
    }

    /// Adaptive NSColor for a Sonnet Weekly usage percentage
    static func sonnetWeeklyColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = sonnetWeeklyColor(percentage)
        if isDarkMode(for: statusButton) {
            return baseColor.adjustedForDarkMode()
        } else {
            return baseColor
        }
    }

    // MARK: - Codex Primary colors (bright teal to deep teal to darkest teal, circle)

    /// NSColor for a Codex primary usage percentage
    /// - Note: 0-70% bright teal (safe), 70-90% deep teal (warning), 90-100% darkest teal (danger)
    static func codexPrimaryColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 45/255.0, green: 212/255.0, blue: 191/255.0, alpha: 1.0)  // #2DD4BF bright teal
        } else if percentage < 90 {
            return NSColor(red: 13/255.0, green: 148/255.0, blue: 136/255.0, alpha: 1.0)  // #0D9488 deep teal
        } else {
            return NSColor(red: 19/255.0, green: 78/255.0, blue: 74/255.0, alpha: 1.0)    // #134E4A darkest teal
        }
    }

    /// SwiftUI Color for a Codex primary usage percentage
    static func codexPrimaryColorSwiftUI(_ percentage: Double, opacity: Double = 0.9) -> Color {
        if percentage < 70 {
            return Color(red: 45/255.0, green: 212/255.0, blue: 191/255.0).opacity(opacity)   // #2DD4BF
        } else if percentage < 90 {
            return Color(red: 13/255.0, green: 148/255.0, blue: 136/255.0).opacity(opacity)   // #0D9488
        } else {
            return Color(red: 19/255.0, green: 78/255.0, blue: 74/255.0).opacity(opacity)     // #134E4A
        }
    }

    /// Adaptive NSColor for a Codex primary usage percentage
    static func codexPrimaryColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = codexPrimaryColor(percentage)
        if isDarkMode(for: statusButton) {
            return baseColor.adjustedForDarkMode()
        } else {
            return baseColor
        }
    }

    // MARK: - Codex Secondary colors (sky blue to blue to deep blue, dashed circle)

    /// NSColor for a Codex secondary usage percentage
    /// - Note: 0-70% sky blue (safe), 70-90% blue (warning), 90-100% deep blue (danger)
    ///         Kept apart from primary's teal family, so the two rings do not look alike
    static func codexSecondaryColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 96/255.0, green: 165/255.0, blue: 250/255.0, alpha: 1.0)   // #60A5FA sky blue
        } else if percentage < 90 {
            return NSColor(red: 37/255.0, green: 99/255.0, blue: 235/255.0, alpha: 1.0)    // #2563EB blue
        } else {
            return NSColor(red: 30/255.0, green: 58/255.0, blue: 138/255.0, alpha: 1.0)    // #1E3A8A deep blue
        }
    }

    /// SwiftUI Color for a Codex secondary usage percentage
    static func codexSecondaryColorSwiftUI(_ percentage: Double, opacity: Double = 0.9) -> Color {
        if percentage < 70 {
            return Color(red: 96/255.0, green: 165/255.0, blue: 250/255.0).opacity(opacity)  // #60A5FA
        } else if percentage < 90 {
            return Color(red: 37/255.0, green: 99/255.0, blue: 235/255.0).opacity(opacity)   // #2563EB
        } else {
            return Color(red: 30/255.0, green: 58/255.0, blue: 138/255.0).opacity(opacity)   // #1E3A8A
        }
    }

    /// Adaptive NSColor for a Codex secondary usage percentage
    static func codexSecondaryColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = codexSecondaryColor(percentage)
        if isDarkMode(for: statusButton) {
            return baseColor.adjustedForDarkMode()
        } else {
            return baseColor
        }
    }

    // MARK: - Codex Extra Usage colors (gold credits to deep gold to darkest amber, hexagon)

    /// NSColor for a Codex Extra Usage percentage
    /// - Note: the real Codex credits API only reports balance and capped state; debug mode drives the visual preview from a percentage.
    static func codexExtraUsageColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 245/255.0, green: 158/255.0, blue: 11/255.0, alpha: 1.0)  // #F59E0B
        } else if percentage < 90 {
            return NSColor(red: 217/255.0, green: 119/255.0, blue: 6/255.0, alpha: 1.0)   // #D97706
        } else {
            return NSColor(red: 120/255.0, green: 53/255.0, blue: 15/255.0, alpha: 1.0)   // #78350F darkest amber
        }
    }

    /// SwiftUI Color for a Codex Extra Usage percentage
    static func codexExtraUsageColorSwiftUI(_ percentage: Double, opacity: Double = 0.9) -> Color {
        if percentage < 70 {
            return Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0).opacity(opacity)
        } else if percentage < 90 {
            return Color(red: 217/255.0, green: 119/255.0, blue: 6/255.0).opacity(opacity)
        } else {
            return Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0).opacity(opacity)
        }
    }

    /// Adaptive NSColor for a Codex Extra Usage percentage
    static func codexExtraUsageColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = codexExtraUsageColor(percentage)
        if isDarkMode(for: statusButton) {
            return baseColor.adjustedForDarkMode()
        } else {
            return baseColor
        }
    }

    // MARK: - Alternative color schemes (kept commented out, so they are easy to try)

    /*
    // Scheme 2: pink to magenta to deep magenta
    static func sevenDayColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 255/255.0, green: 158/255.0, blue: 205/255.0, alpha: 1.0)  // Pink #FF9ECD
        } else if percentage < 90 {
            return NSColor(red: 217/255.0, green: 70/255.0, blue: 239/255.0, alpha: 1.0)  // Magenta #D946EF
        } else {
            return NSColor(red: 168/255.0, green: 85/255.0, blue: 247/255.0, alpha: 1.0)   // Deep magenta #A855F7
        }
    }

    static func sevenDayColorSwiftUI(_ percentage: Double, opacity: Double = 0.7) -> Color {
        if percentage < 70 {
            return Color(red: 255/255.0, green: 158/255.0, blue: 205/255.0).opacity(opacity)  // Pink #FF9ECD
        } else if percentage < 90 {
            return Color(red: 217/255.0, green: 70/255.0, blue: 239/255.0).opacity(opacity)  // Magenta #D946EF
        } else {
            return Color(red: 168/255.0, green: 85/255.0, blue: 247/255.0).opacity(opacity)   // Deep magenta #A855F7
        }
    }
    */

    /*
    // Scheme 3: mint green to violet to indigo
    static func sevenDayColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 107/255.0, green: 237/255.0, blue: 227/255.0, alpha: 1.0)  // Mint green #6BEDE3
        } else if percentage < 90 {
            return NSColor(red: 129/255.0, green: 140/255.0, blue: 248/255.0, alpha: 1.0)  // Violet #818CF8
        } else {
            return NSColor(red: 76/255.0, green: 81/255.0, blue: 191/255.0, alpha: 1.0)   // Indigo #4C51BF
        }
    }

    static func sevenDayColorSwiftUI(_ percentage: Double, opacity: Double = 0.7) -> Color {
        if percentage < 70 {
            return Color(red: 107/255.0, green: 237/255.0, blue: 227/255.0).opacity(opacity)  // Mint green #6BEDE3
        } else if percentage < 90 {
            return Color(red: 129/255.0, green: 140/255.0, blue: 248/255.0).opacity(opacity)  // Violet #818CF8
        } else {
            return Color(red: 76/255.0, green: 81/255.0, blue: 191/255.0).opacity(opacity)   // Indigo #4C51BF
        }
    }
    */

    /*
    // Scheme 4: amber to orange purple to deep purple
    static func sevenDayColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 251/255.0, green: 191/255.0, blue: 36/255.0, alpha: 1.0)  // Amber #FBBF24
        } else if percentage < 90 {
            return NSColor(red: 192/255.0, green: 132/255.0, blue: 252/255.0, alpha: 1.0)  // Orange purple #C084FC
        } else {
            return NSColor(red: 124/255.0, green: 58/255.0, blue: 237/255.0, alpha: 1.0)   // Deep purple #7C3AED
        }
    }

    static func sevenDayColorSwiftUI(_ percentage: Double, opacity: Double = 0.7) -> Color {
        if percentage < 70 {
            return Color(red: 251/255.0, green: 191/255.0, blue: 36/255.0).opacity(opacity)  // Amber #FBBF24
        } else if percentage < 90 {
            return Color(red: 192/255.0, green: 132/255.0, blue: 252/255.0).opacity(opacity)  // Orange purple #C084FC
        } else {
            return Color(red: 124/255.0, green: 58/255.0, blue: 237/255.0).opacity(opacity)   // Deep purple #7C3AED
        }
    }
    */
}

// MARK: - NSColor extensions

extension NSColor {
    /// Adjust a color for dark mode (raise brightness and saturation)
    /// - Returns: a brighter version suited to a dark background
    func adjustedForDarkMode() -> NSColor {
        guard let rgbColor = self.usingColorSpace(.deviceRGB) else {
            return self
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Raise brightness: at least 0.75, at most a 40% increase (up from 0.7/1.3 to 0.75/1.4)
        let adjustedBrightness = min(1.0, max(0.75, brightness * 1.4))

        // Leave saturation alone so the color stays vivid (changed from 0.9 to 1.0)
        let adjustedSaturation = min(1.0, saturation * 1.0)

        return NSColor(hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: alpha)
    }
}
