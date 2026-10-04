//
//  MenuBarIconRenderer.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit

/// Menu bar icon renderer
/// Owns all icon drawing, in both color and monochrome mode
/// Extracted from MenuBarUI to separate responsibilities
class MenuBarIconRenderer {
    
    // MARK: - Settings Reference
    
    /// User settings instance
    private let settings: UserSettings
    /// Menu bar brand icon size
    private let providerBrandIconSize: CGFloat = 16
    /// Menu bar metric icon size
    private let metricIconSize: CGFloat = 18
    
    // MARK: - Initialization
    
    init(settings: UserSettings = .shared) {
        self.settings = settings
    }
    
    // MARK: - Public API

    /// Create the menu bar icon
    /// - Parameters:
    ///   - usageData: Claude usage data
    ///   - codexUsageData: Codex usage data (nil means no Codex account)
    ///   - hasUpdate: whether an update is available
    ///   - button: status item button (used to read the appearance mode)
    /// - Returns: the rendered icon image
    func createIcon(
        usageData: UsageData?,
        codexUsageData: CodexUsageData? = nil,
        hasUpdate: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        // Decide between monochrome and color mode
        let isMonochrome: Bool
        if let data = usageData {
            let canUseColor = settings.canUseColoredTheme(usageData: data)
            let forceMonochrome = !canUseColor && settings.iconStyleMode != .monochrome
            isMonochrome = settings.iconStyleMode == .monochrome || forceMonochrome
        } else {
            isMonochrome = settings.iconStyleMode == .monochrome
        }

        var icon: NSImage

        if let codex = codexUsageData {
            // Path with Codex data
            let allTypes = settings.getActiveDisplayTypes(usageData: usageData, codexUsageData: codex, forMenuBar: true)
            let codexTypes = allTypes.filter { $0.provider == .codex }

            if settings.isMultiProviderActive, let data = usageData {
                // Dual provider mode
                let claudeTypes = allTypes.filter { $0.provider == .claude }
                icon = createMultiProviderIcon(data: data, codex: codex, claudeTypes: claudeTypes, codexTypes: codexTypes, isMonochrome: isMonochrome, button: button)
            } else {
                // Codex only (no Claude account) or the degraded path
                icon = createCodexOnlyIcon(codex: codex, codexTypes: codexTypes, isMonochrome: isMonochrome, button: button)
            }
        } else {
            // Claude only path (the original logic)
            guard let data = usageData else {
                let size = NSSize(width: 22, height: 22)
                let defaultIcon: NSImage
                if settings.iconDisplayMode == .none {
                    defaultIcon = createMenuBarDividerIcon(isMonochrome: isMonochrome)
                } else {
                    defaultIcon = isMonochrome ?
                        createCircleTemplateImage(percentage: 0, size: size, button: button, removeBackground: true) :
                        createCircleImage(percentage: 0, size: size, button: button, removeBackground: true)
                }
                if hasUpdate { return addBadgeToImage(defaultIcon) }
                return defaultIcon
            }

            let activeTypes = settings.getActiveDisplayTypes(usageData: data, forMenuBar: true)

            switch settings.iconDisplayMode {
            case .percentageOnly:
                icon = createCombinedPercentageIcon(data: data, types: activeTypes, isMonochrome: isMonochrome, button: button)
            case .iconOnly:
                let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
                if let iconCopy = ImageHelper.createSquareIcon(named: iconName, size: providerBrandIconSize, isTemplate: isMonochrome) {
                    icon = iconCopy
                } else {
                    icon = createSimpleCircleIcon()
                }
            case .both:
                icon = createCombinedIconWithAppIcon(data: data, types: activeTypes, isMonochrome: isMonochrome, button: button)
            case .none:
                icon = createMenuBarDividerIcon(isMonochrome: isMonochrome)
            }
        }

        if hasUpdate { icon = addBadgeToImage(icon) }
        return icon
    }

    // MARK: - Multi-Provider Icon Creation

    /// Dual provider icon: [Claude brand] + [Claude metrics] + [Codex brand] + [Codex metrics]
    private func createMultiProviderIcon(
        data: UsageData,
        codex: CodexUsageData,
        claudeTypes: [LimitType],
        codexTypes: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        var icons: [NSImage] = []

        switch settings.iconDisplayMode {
        case .iconOnly:
            let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
            if let copy = ImageHelper.createSquareIcon(named: iconName, size: providerBrandIconSize, isTemplate: isMonochrome) {
                icons.append(copy)
            }

        case .percentageOnly, .both:
            // Claude part
            let claudeIcons = claudeTypes.compactMap { createIconForType($0, data: data, isMonochrome: isMonochrome, button: button) }
            if !claudeIcons.isEmpty {
                if settings.iconDisplayMode == .both {
                    let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
                    if let copy = ImageHelper.createSquareIcon(named: iconName, size: providerBrandIconSize, isTemplate: isMonochrome) {
                        icons.append(copy)
                    }
                }
                icons.append(contentsOf: claudeIcons)
            }

            // Codex part
            let codexIcons = buildCodexIcons(codex: codex, types: codexTypes, isMonochrome: isMonochrome, button: button)
            if !codexIcons.isEmpty {
                if settings.iconDisplayMode == .percentageOnly, !claudeIcons.isEmpty {
                    icons.append(createMenuBarDividerIcon(isMonochrome: isMonochrome))
                } else if settings.iconDisplayMode == .both,
                   let brand = createProviderBrandIcon(.codex, isMonochrome: isMonochrome, size: providerBrandIconSize) {
                    icons.append(brand)
                }
                icons.append(contentsOf: codexIcons)
            }

        case .none:
            // No icon shown: draw only a light separator, keeping a clickable status item anchor
            icons.append(createMenuBarDividerIcon(isMonochrome: isMonochrome))
        }

        let combined = icons.isEmpty ? createSimpleCircleIcon() : combineIcons(icons, spacing: 2.0, height: metricIconSize)
        combined.isTemplate = isMonochrome
        return combined
    }

    /// Codex only icon (when there is no Claude account)
    private func createCodexOnlyIcon(
        codex: CodexUsageData,
        codexTypes: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        switch settings.iconDisplayMode {
        case .none:
            return createMenuBarDividerIcon(isMonochrome: isMonochrome)

        case .iconOnly:
            return createProviderBrandIcon(.codex, isMonochrome: isMonochrome, size: providerBrandIconSize) ?? createSimpleCircleIcon()

        case .percentageOnly, .both:
            var icons: [NSImage] = []
            if settings.iconDisplayMode == .both,
               let brand = createProviderBrandIcon(.codex, isMonochrome: isMonochrome, size: providerBrandIconSize) {
                icons.append(brand)
            }
            icons.append(contentsOf: buildCodexIcons(codex: codex, types: codexTypes, isMonochrome: isMonochrome, button: button))
            if icons.isEmpty { return createSimpleCircleIcon() }
            let combined = icons.count == 1 ? icons[0] : combineIcons(icons, spacing: 3.0, height: metricIconSize)
            combined.isTemplate = isMonochrome
            return combined
        }
    }

    /// Build the list of Codex metric icons
    private func buildCodexIcons(codex: CodexUsageData, types: [LimitType], isMonochrome: Bool, button: NSStatusBarButton?) -> [NSImage] {
        let showPlaceholder = settings.displayMode == .custom
        return types.compactMap { type -> NSImage? in
            switch type {
            case .codexPrimary:
                let percentage = codex.primary?.percentage ?? (showPlaceholder ? 0 : nil)
                return percentage.flatMap { createCodexIcon(type: type, percentage: $0, isMonochrome: isMonochrome, button: button, resetsAt: codex.primary?.resetsAt) }
            case .codexSecondary:
                let percentage = codex.secondary?.percentage ?? (showPlaceholder ? 0 : nil)
                return percentage.flatMap { createCodexIcon(type: type, percentage: $0, isMonochrome: isMonochrome, button: button, resetsAt: codex.secondary?.resetsAt) }
            case .codexExtraUsage:
                let percentage: Double?
                if let extra = codex.extraUsage, extra.enabled {
                    percentage = extra.percentage
                } else if showPlaceholder {
                    percentage = 0
                } else {
                    percentage = nil
                }
                return percentage.flatMap { createCodexIcon(type: type, percentage: $0, isMonochrome: isMonochrome, button: button) }
            default:
                return nil
            }
        }
    }

    /// Create a provider brand icon (visual grouping for multi provider mode)
    private func createProviderBrandIcon(_ provider: ProviderType, isMonochrome: Bool, size: CGFloat = 14) -> NSImage? {
        switch provider {
        case .claude:
            let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
            return ImageHelper.createSquareIcon(named: iconName, size: size, isTemplate: isMonochrome)
        case .codex:
            let iconName = isMonochrome ? "CodexIconReverse" : "CodexIcon"
            return ImageHelper.createSquareIcon(named: iconName, size: size, isTemplate: isMonochrome, sourceInset: isMonochrome ? 0 : 2)
        }
    }

    /// Create the percentage only composite icon
    private func createCombinedPercentageIcon(
        data: UsageData,
        types: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        guard !types.isEmpty else {
            return createSimpleCircleIcon()
        }

        // Create an icon for each type
        let icons = types.compactMap { type in
            createIconForType(type, data: data, isMonochrome: isMonochrome, button: button)
        }

        // Combine the icons
        if icons.isEmpty {
            return createSimpleCircleIcon()
        } else if icons.count == 1 {
            return icons[0]
        } else {
            let combined = combineIcons(icons, spacing: 3.0, height: 18)
            combined.isTemplate = isMonochrome
            return combined
        }
    }

    /// Create the app icon plus percentage composite icon
    private func createCombinedIconWithAppIcon(
        data: UsageData,
        types: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        // Get the app icon (monochrome mode uses the reversed icon)
        let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
        guard let appIconCopy = ImageHelper.createSquareIcon(named: iconName, size: providerBrandIconSize, isTemplate: isMonochrome) else {
            return createCombinedPercentageIcon(data: data, types: types, isMonochrome: isMonochrome, button: button)
        }

        // Create the percentage icon
        let percentageIcons = types.compactMap { type in
            createIconForType(type, data: data, isMonochrome: isMonochrome, button: button)
        }

        // Combine app icon and percentage icon
        var allIcons = [appIconCopy]
        allIcons.append(contentsOf: percentageIcons)

        let combined = combineIcons(allIcons, spacing: 3.0, height: metricIconSize)
        combined.isTemplate = isMonochrome
        return combined
    }
    
    // MARK: - Icon Drawing - Colored Mode

    /// The percentage the icon's *colour* escalates on: the projected end-of-window figure when
    /// pace-aware colours are on, and `flatPercentage` otherwise. The glyph and the sweep always
    /// stay on actual usage, so only the colour changes meaning, exactly as in the popover rows.
    ///
    /// Flat is the answer in Limit mode because the palette there names *which* limit this is and
    /// must not move with the figure. Do not send the real percentage back through here: that was
    /// the bug where a limit crossing 70% silently darkened its own identity colour.
    func colorPercentage(_ percentage: Double, resetsAt: Date?, type: LimitType) -> Double {
        guard settings.paceAwareBarColors else { return UsageColorScheme.flatPercentage }
        // Usage mode escalates on the figure itself, not on a projection, matching claude.ai.
        return percentage
    }

    /// The pace ramp colour for this limit's icon, or nil to leave the per-limit palette in charge.
    ///
    /// Same three steps and the same source as the popover bars (`UsagePaceStatus`), so a limit
    /// that is orange in the popover is orange in the menu bar. The glyph and the sweep stay on
    /// actual usage; only the colour changes meaning.
    func paceColor(_ percentage: Double, resetsAt: Date?, type: LimitType) -> NSColor? {
        guard settings.paceAwareBarColors else { return nil }
        return UsagePaceStatus.color(
            usedPercentage: percentage,
            resetsAt: resetsAt,
            type: type
        ).nsColor
    }

    /// Where the period tick belongs for this limit, or nil for no tick: the setting is off, the
    /// limit has no fixed window (the Extra Usage buckets), or there is no reset time to measure.
    /// Mirrored in remaining-percentage mode, because the sweep is mirrored too.
    func timeMarkerFraction(resetsAt: Date?, type: LimitType) -> CGFloat? {
        guard settings.showTimeMarker,
              let duration = UsagePaceCalculator.windowDuration(for: type),
              let elapsed = UsagePaceCalculator.elapsedFraction(resetsAt: resetsAt, duration: duration)
        else { return nil }
        return CGFloat(settings.showRemainingPercentage ? 1 - elapsed : elapsed)
    }

    /// The period tick on a ring icon: a short radial dash crossing the stroke where the window
    /// has got to. 12 o'clock is zero and it runs clockwise, matching the progress sweep.
    private func drawRingTimeMarker(
        center: NSPoint,
        radius: CGFloat,
        fraction: CGFloat,
        ringWidth: CGFloat,
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) {
        let clamped = min(max(fraction, 0), 1)
        // 12 o'clock is zero and it runs clockwise, matching the progress sweep
        let angle = (90 - Double(clamped) * 360) * .pi / 180
        let pointOnRing = NSPoint(x: center.x + radius * cos(angle),
                                  y: center.y + radius * sin(angle))
        // Shared with the shape icons so every tick looks identical
        ShapeIconRenderer.drawRadialTimeMarker(
            at: pointOnRing,
            center: center,
            strokeWidth: ringWidth,
            isMonochrome: isMonochrome,
            button: button
        )
    }

    private func createCircleImage(percentage: Double, size: NSSize, useSevenDayColor: Bool = false, colorOverride: NSColor? = nil, useDashedStyle: Bool = false, button: NSStatusBarButton?, removeBackground: Bool = false, markerFraction: CGFloat? = nil, colorPercentage: Double? = nil, paceColor: NSColor? = nil) -> NSImage {
        // Battery style display: the sweep and the glyph show remaining; the color stays keyed off used
        let displayPercentage = UsagePercentDisplay.displayPercentage(percentage)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 2

        if !removeBackground {
            let backgroundCircle = NSBezierPath()
            backgroundCircle.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
            // Very faint backing plate that follows the menu bar appearance. A hardcoded translucent white looks gray and muddy on a light menu bar.
            UsageColorScheme.menuBarForeground(for: button).withAlphaComponent(0.10).setFill()
            backgroundCircle.fill()
        }

        UsageColorScheme.menuBarTrack(for: button).setStroke()
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        backgroundPath.lineWidth = 1.5

        // 7 day and Codex secondary limits use a dashed stroke to tell them apart from the solid circle
        if useSevenDayColor || useDashedStyle {
            let dashPattern: [CGFloat] = [3, 1]
            backgroundPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        }

        backgroundPath.stroke()

        // Pace-aware colours escalate on the projection; the sweep and glyph stay on actual usage
        let escalationPercentage = colorPercentage ?? percentage
        let color: NSColor
        if let override = colorOverride {
            color = override
        } else if let pace = paceColor {
            // Pace-aware mode replaces the palette outright, the same priority the popover uses
            color = pace
        } else {
            color = useSevenDayColor
                ? UsageColorScheme.sevenDayColorAdaptive(escalationPercentage, for: button)
                : UsageColorScheme.fiveHourColorAdaptive(escalationPercentage, for: button)
        }
        color.setStroke()

        let progressPath = NSBezierPath()
        let lineWidth: CGFloat = 2.5

        // Compute the progress angle
        let baseAngle = CGFloat(displayPercentage) / 100.0 * 360
        let circumference = 2 * CGFloat.pi * radius  // Circumference
        let capAngle = (lineWidth / circumference) * 360  // Angle covered by the round cap overhang

        let progressAngle: CGFloat
        let startAngle: CGFloat

        if displayPercentage >= 100 {
            // 100%: use the full angle and a fixed start point, because .butt caps do not overhang
            progressAngle = baseAngle
            startAngle = 90
        } else {
            // 5 hour and 7 day limits: progressive subtraction with a fixed start point, for smooth growth
            // The subtracted angle grows linearly with the percentage, fully applied at 50%, so 50% to 100% is exact
            progressAngle = baseAngle - capAngle * min(1.0, CGFloat(displayPercentage / 50.0))
            startAngle = 90 - capAngle / 2 + 0.5
        }

        let endAngle = startAngle - progressAngle

        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.lineWidth = lineWidth
        // At 100% butt caps close the ring perfectly, every other value uses round caps
        progressPath.lineCapStyle = displayPercentage >= 100 ? .butt : .round
        progressPath.stroke()

        if let markerFraction {
            drawRingTimeMarker(center: center, radius: radius, fraction: markerFraction,
                               ringWidth: lineWidth, isMonochrome: false, button: button)
        }

        let fontSize: CGFloat = displayPercentage >= 100 ? size.width * 0.275 : size.width * 0.4
        let font = NSFont.systemFont(ofSize: fontSize, weight: displayPercentage >= 100 ? .bold : .semibold)
        let text = "\(Int(displayPercentage))"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UsageColorScheme.menuBarForeground(for: button),
            .paragraphStyle: paragraphStyle
        ]
        let textSize = text.size(withAttributes: attrs)
        let textOrigin = NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)
        text.draw(at: textOrigin, withAttributes: attrs)

        image.unlockFocus()
        return image
    }

    // MARK: - Icon Drawing - Template Mode

    private func createCircleTemplateImage(percentage: Double, size: NSSize, useSevenDayStyle: Bool = false, button: NSStatusBarButton? = nil, removeBackground: Bool = false, markerFraction: CGFloat? = nil) -> NSImage {
        // Battery style display: the sweep and the glyph show remaining
        let displayPercentage = UsagePercentDisplay.displayPercentage(percentage)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 2

        NSColor.labelColor.withAlphaComponent(0.25).setStroke()
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        backgroundPath.lineWidth = 1.5

        // The 7 day limit uses a dashed stroke to tell it apart from the 5 hour limit
        if useSevenDayStyle {
            let dashPattern: [CGFloat] = [3, 1]
            backgroundPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        }

        backgroundPath.stroke()

        NSColor.labelColor.setStroke()
        let progressPath = NSBezierPath()
        let lineWidth: CGFloat = 2.5

        // Compute the progress angle
        let baseAngle = CGFloat(displayPercentage) / 100.0 * 360
        let circumference = 2 * CGFloat.pi * radius  // Circumference
        let capAngle = (lineWidth / circumference) * 360  // Angle covered by the round cap overhang

        let progressAngle: CGFloat
        let startAngle: CGFloat

        if displayPercentage >= 100 {
            // 100%: use the full angle and a fixed start point, because .butt caps do not overhang
            progressAngle = baseAngle
            startAngle = 90
        } else {
            // Monochrome mode: progressive subtraction with a fixed start point, for smooth growth
            // The subtracted angle grows linearly with the percentage, fully applied at 50%, so 50% to 100% is exact
            progressAngle = baseAngle - capAngle * min(1.0, CGFloat(displayPercentage / 50.0))
            startAngle = 90 - capAngle / 2 + 0.5
        }

        let endAngle = startAngle - progressAngle

        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.lineWidth = lineWidth
        // At 100% butt caps close the ring perfectly, every other value uses round caps
        progressPath.lineCapStyle = displayPercentage >= 100 ? .butt : .round
        progressPath.stroke()

        if let markerFraction {
            drawRingTimeMarker(center: center, radius: radius, fraction: markerFraction,
                               ringWidth: lineWidth, isMonochrome: true, button: button)
        }

        let fontSize: CGFloat = displayPercentage >= 100 ? size.width * 0.275 : size.width * 0.4
        let font = NSFont.systemFont(ofSize: fontSize, weight: displayPercentage >= 100 ? .bold : .semibold)
        let text = "\(Int(displayPercentage))"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraphStyle]
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2), withAttributes: attrs)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Utility Icons

    /// Create a simple circular icon (fallback)
    private func createSimpleCircleIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 3, y: 3, width: 12, height: 12)
        let path = NSBezierPath(ovalIn: rect)

        NSColor.labelColor.setStroke()
        path.lineWidth = 2.0
        path.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Add a badge (small red dot) on top of an icon
    private func addBadgeToImage(_ baseImage: NSImage) -> NSImage {
        let size = baseImage.size
        let expandedSize = NSSize(width: size.width + 2.5, height: size.height + 2.5)
        let badgedImage = NSImage(size: expandedSize)

        badgedImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: size))

        let badgeRadius: CGFloat = 2.0
        let badgeDiameter = badgeRadius * 2
        let badgeX = expandedSize.width - badgeDiameter - 1.5
        let badgeY = expandedSize.height - badgeDiameter - 1.5
        let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeDiameter, height: badgeDiameter)

        NSGraphicsContext.saveGraphicsState()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        badgedImage.unlockFocus()
        badgedImage.isTemplate = baseImage.isTemplate

        return badgedImage
    }

    // MARK: - Icon Combination Methods (v2.0)

    /// Combine several icons into a single image
    /// - Parameters:
    ///   - icons: the icons to combine
    ///   - spacing: spacing between icons
    ///   - height: uniform height (18 by default)
    /// - Returns: the combined icon
    private func combineIcons(_ icons: [NSImage], spacing: CGFloat = 3.0, height: CGFloat = 18) -> NSImage {
        guard !icons.isEmpty else {
            return createSimpleCircleIcon()
        }

        // Compute the total width
        let totalWidth = icons.reduce(0) { $0 + $1.size.width } + CGFloat(icons.count - 1) * spacing
        let size = NSSize(width: totalWidth, height: height)

        let image = NSImage(size: size)
        image.lockFocus()

        var currentX: CGFloat = 0
        for icon in icons {
            let y = (height - icon.size.height) / 2  // Vertically centered
            icon.draw(at: NSPoint(x: currentX, y: y),
                     from: NSRect(origin: .zero, size: icon.size),
                     operation: .sourceOver,
                     fraction: 1.0)
            currentX += icon.size.width + spacing
        }

        image.unlockFocus()
        return image
    }

    /// Create a single icon from the limit type and its data
    /// - Parameters:
    ///   - type: limit type
    ///   - data: usage data
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button
    /// - Returns: icon image
    func createIconForType(
        _ type: LimitType,
        data: UsageData,
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage? {
        // The theme mode decides whether the background is removed
        // colorTranslucent: remove the background (see through)
        // colorWithBackground: keep the background (translucent white)
        let removeBackground = settings.iconStyleMode == .colorTranslucent

        // In custom mode show a placeholder icon (0%) even when the data is nil
        // In smart mode return nil when the data is nil
        let showPlaceholder = settings.displayMode == .custom

        switch type {
        case .fiveHour:
            let percentage = data.fiveHour?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            let resetsAt = data.fiveHour?.resetsAt
            let marker = timeMarkerFraction(resetsAt: resetsAt, type: type)
            let paced = colorPercentage(percentage, resetsAt: resetsAt, type: type)
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), button: button, removeBackground: true, markerFraction: marker)
            } else {
                return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), button: button, removeBackground: removeBackground, markerFraction: marker, colorPercentage: paced, paceColor: paceColor(percentage, resetsAt: resetsAt, type: type))
            }

        case .sevenDay:
            let percentage = data.sevenDay?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            let resetsAt = data.sevenDay?.resetsAt
            let marker = timeMarkerFraction(resetsAt: resetsAt, type: type)
            let paced = colorPercentage(percentage, resetsAt: resetsAt, type: type)
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), useSevenDayStyle: true, button: button, removeBackground: true, markerFraction: marker)
            } else {
                return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), useSevenDayColor: true, button: button, removeBackground: removeBackground, markerFraction: marker, colorPercentage: paced, paceColor: paceColor(percentage, resetsAt: resetsAt, type: type))
            }

        case .opusWeekly:
            let percentage = data.opus?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            return ShapeIconRenderer.createVerticalRectangleIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground, markerFraction: timeMarkerFraction(resetsAt: data.opus?.resetsAt, type: type), colorPercentage: colorPercentage(percentage, resetsAt: data.opus?.resetsAt, type: type), paceColor: paceColor(percentage, resetsAt: data.opus?.resetsAt, type: type))

        case .sonnetWeekly:
            let percentage = data.sonnet?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            return ShapeIconRenderer.createHorizontalRectangleIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground, markerFraction: timeMarkerFraction(resetsAt: data.sonnet?.resetsAt, type: type), colorPercentage: colorPercentage(percentage, resetsAt: data.sonnet?.resetsAt, type: type), paceColor: paceColor(percentage, resetsAt: data.sonnet?.resetsAt, type: type))

        case .extraUsage:
            let percentage: Double?
            if let extraUsage = data.extraUsage, extraUsage.enabled {
                percentage = extraUsage.percentage
            } else if showPlaceholder {
                percentage = 0
            } else {
                percentage = nil
            }
            guard let percentage = percentage else { return nil }
            // No window to project across, so `paceColor` ramps on the current percentage. It
            // still has to win over the pink palette: in Usage mode every icon is on the ramp, or
            // the one that is not reads as a bug.
            return ShapeIconRenderer.createHexagonIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground, colorOverride: paceColor(percentage, resetsAt: nil, type: type))

        case .codexPrimary, .codexSecondary, .codexExtraUsage:
            // Codex data is rendered separately by createCodexIcon in Phase 4
            // createIconForType only handles Claude UsageData, so return nil here
            return nil
        }
    }

    /// Create a single icon from Codex usage data (Codex only, wired into the UI in Phase 4)
    func createCodexIcon(
        type: LimitType,
        percentage: Double,
        isMonochrome: Bool,
        button: NSStatusBarButton?,
        resetsAt: Date? = nil
    ) -> NSImage? {
        let removeBackground = settings.iconStyleMode == .colorTranslucent
        let marker = timeMarkerFraction(resetsAt: resetsAt, type: type)
        // Pace-aware colours escalate on the projection; the sweep and glyph stay on actual usage
        let paced = colorPercentage(percentage, resetsAt: resetsAt, type: type)

        switch type {
        case .codexPrimary:
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), button: button, removeBackground: true, markerFraction: marker)
            }
            let color = UsageColorScheme.codexPrimaryColorAdaptive(paced, for: button)
            return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), colorOverride: color, button: button, removeBackground: removeBackground, markerFraction: marker)

        case .codexSecondary:
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), useSevenDayStyle: true, button: button, removeBackground: true, markerFraction: marker)
            }
            let color = UsageColorScheme.codexSecondaryColorAdaptive(paced, for: button)
            return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), colorOverride: color, useDashedStyle: true, button: button, removeBackground: removeBackground, markerFraction: marker)

        case .codexExtraUsage:
            // No window to project across, so the palette is flat and the pace ramp (which reads
            // the current percentage here) takes over whenever Usage mode is on.
            let color = paceColor(percentage, resetsAt: nil, type: type)
                ?? UsageColorScheme.codexExtraUsageColorAdaptive(UsageColorScheme.flatPercentage, for: button)
            return ShapeIconRenderer.createHexagonIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground, colorOverride: color)

        default:
            return nil
        }
    }

    /// Create the light separator icon (used by the "no icon" mode)
    private func createMenuBarDividerIcon(isMonochrome: Bool) -> NSImage {
        let width: CGFloat = 5
        let height: CGFloat = metricIconSize
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        let lineRect = NSRect(x: (width - 1) / 2, y: 1, width: 1, height: height - 2)
        let linePath = NSBezierPath(rect: lineRect)
        let lineColor = isMonochrome ? NSColor.labelColor : NSColor.secondaryLabelColor
        let gradient = NSGradient(colors: [
            lineColor.withAlphaComponent(0.0),
            lineColor.withAlphaComponent(0.55),
            lineColor.withAlphaComponent(0.55),
            lineColor.withAlphaComponent(0.0)
        ])
        gradient?.draw(in: linePath, angle: 90)

        image.unlockFocus()
        if isMonochrome { image.isTemplate = true }
        return image
    }

}
