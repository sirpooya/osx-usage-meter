//
//  ShapeIconRenderer.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import SwiftUI

/// Shape icon renderer
/// Draws the progress ring for the non circular icons (square, diamond, hexagon)
class ShapeIconRenderer {

    // MARK: - Helper Methods

    /// Compute the opacity for the monochrome theme (from the percentage)
    /// - Parameter percentage: usage percentage (0-100)
    /// - Returns: opacity (0.8-1.0)
    static func monochromeOpacity(for percentage: Double) -> CGFloat {
        if percentage <= 50 {
            return 0.8
        } else if percentage <= 75 {
            return 0.9
        } else {
            return 1.0
        }
    }

    // MARK: - Outline Geometry

    /// Perimeter of the rounded square: 4 straight runs plus 4 quarter arcs, which together make
    /// one full circle's worth of corner.
    static func roundedSquarePerimeter(in rect: NSRect, cornerRadius: CGFloat) -> CGFloat {
        let straightLength = 4 * (rect.width - 2 * cornerRadius)
        let arcLength = 2 * CGFloat.pi * cornerRadius
        return straightLength + arcLength
    }

    /// The rounded square outline, walked clockwise from 12 o'clock (the middle of the top edge).
    /// Shared by the progress stroke and the period tick so both measure distance along exactly
    /// the same path, which is what keeps the tick on the shape through its corners.
    static func roundedSquareOutlinePath(in rect: NSRect, cornerRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let startPoint = NSPoint(x: rect.midX, y: rect.maxY)
        path.move(to: startPoint)

        // 12 o'clock to 3
        path.line(to: NSPoint(x: rect.maxX - cornerRadius, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                       radius: cornerRadius, startAngle: 90, endAngle: 0, clockwise: true)
        // 3 to 6
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + cornerRadius))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: 0, endAngle: 270, clockwise: true)
        // 6 to 9
        path.line(to: NSPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: 270, endAngle: 180, clockwise: true)
        // 9 back to 12
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - cornerRadius))
        path.appendArc(withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                       radius: cornerRadius, startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: startPoint)
        return path
    }

    /// Perimeter of the chamfered square (the Sonnet shape): the rounded square, adjusted for the
    /// cut top right corner, which drops one quarter arc, lengthens the top and right edges and
    /// adds the diagonal.
    static func chamferedPerimeter(in rect: NSRect, cornerRadius: CGFloat, cutSize: CGFloat) -> CGFloat {
        let base = roundedSquarePerimeter(in: rect, cornerRadius: cornerRadius)
        let cornerArcReduction = -cornerRadius * .pi / 2
        let edgeAdjustment = 2.0 * cornerRadius
        let cutAdjustment = cutSize * (sqrt(2.0) - 2.0)
        return base + cornerArcReduction + edgeAdjustment + cutAdjustment
    }

    /// The chamfered square outline, walked clockwise from 12 o'clock. Same contract as
    /// `roundedSquareOutlinePath`: shared by the progress stroke and the period tick.
    static func chamferedOutlinePath(in rect: NSRect, cornerRadius: CGFloat, cutSize: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let startPoint = NSPoint(x: rect.midX, y: rect.maxY)
        path.move(to: startPoint)

        // Top edge into the chamfer, then the chamfer itself
        path.line(to: NSPoint(x: rect.maxX - cutSize, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cutSize))
        // Right edge down to 6
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + cornerRadius))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: 0, endAngle: 270, clockwise: true)
        // Bottom edge to 9
        path.line(to: NSPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: 270, endAngle: 180, clockwise: true)
        // Left edge back to 12
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - cornerRadius))
        path.appendArc(withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                       radius: cornerRadius, startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: startPoint)
        return path
    }

    /// The period tick, drawn as a radial spoke crossing the border at `point`, measured outward
    /// from `center`. Every icon shape routes through this one function, so a circle's ring and a
    /// square's edge get an identical mark. Drawing it along the outline instead (the obvious
    /// thing, since the progress stroke already walks that path) made the square's tick a dash
    /// running *parallel* to its flat edge while the circles got a crossing spoke.
    static func drawRadialTimeMarker(
        at point: NSPoint,
        center: NSPoint,
        strokeWidth: CGFloat,
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) {
        var dx = point.x - center.x
        var dy = point.y - center.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.001 else { return }
        dx /= length
        dy /= length
        let half = strokeWidth / 2 + 0.25

        func segment(width: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: point.x - dx * half, y: point.y - dy * half))
            path.line(to: NSPoint(x: point.x + dx * half, y: point.y + dy * half))
            path.lineWidth = width
            path.lineCapStyle = .butt
            return path
        }

        // Knock out a window through the border first, then mark inside it. Neither half works
        // alone on a template icon: it keeps only alpha, so a mark drawn over the solid sweep is
        // invisible, and a bare gap in the faint 0.3-alpha track is invisible too. Clearing a
        // window and marking inside it reads against both.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        segment(width: 2.6).stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        if isMonochrome {
            // Template: only alpha survives, so any opaque colour gives a solid tick
            NSColor.controlTextColor.setStroke()
        } else {
            UsageColorScheme.menuBarForeground(for: button).setStroke()
        }
        segment(width: 1.0).stroke()
    }

    /// The point `fraction` of the way along `path`, found by walking its flattened segments.
    ///
    /// Takes a fraction rather than a distance on purpose: flattening approximates the corner arcs
    /// with straight lines, so the flattened length is slightly shorter than the analytic
    /// perimeter, and mixing the two would drift the tick.
    static func point(on path: NSBezierPath, atFraction fraction: CGFloat) -> NSPoint? {
        let flat = path.flattened
        guard flat.elementCount > 0 else { return nil }

        /// Walks the flattened path. With `target` nil it just measures; otherwise it returns the
        /// point once `target` is reached.
        func walk(target: CGFloat?) -> (total: CGFloat, point: NSPoint?) {
            var points = [NSPoint](repeating: .zero, count: 3)
            var current = NSPoint.zero
            var subpathStart = NSPoint.zero
            var travelled: CGFloat = 0

            for index in 0..<flat.elementCount {
                let element = flat.element(at: index, associatedPoints: &points)
                let next: NSPoint
                switch element {
                case .moveTo:
                    current = points[0]
                    subpathStart = current
                    continue
                case .lineTo:
                    next = points[0]
                case .closePath:
                    next = subpathStart
                case .curveTo:
                    // A flattened path carries no curves; keep the pen in step regardless.
                    current = points[2]
                    continue
                @unknown default:
                    continue
                }

                let segmentLength = hypot(next.x - current.x, next.y - current.y)
                if let target, segmentLength > 0, travelled + segmentLength >= target {
                    let t = (target - travelled) / segmentLength
                    return (travelled, NSPoint(x: current.x + (next.x - current.x) * t,
                                               y: current.y + (next.y - current.y) * t))
                }
                travelled += segmentLength
                current = next
            }
            return (travelled, current)
        }

        let total = walk(target: nil).total
        guard total > 0 else { return nil }
        let clamped = min(max(fraction, 0), 1)
        return walk(target: total * clamped).point
    }

    // MARK: - Shape Drawing Methods

    /// Draw the rounded square progress ring and percentage (used by Opus)
    /// - Parameters:
    ///   - rect: drawing area
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button (used to read colors)
    ///   - removeBackground: whether to remove the background fill
    static func drawRoundedSquareWithPercentage(in rect: NSRect, percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false, markerFraction: CGFloat? = nil, colorPercentage: Double? = nil, paceColor: NSColor? = nil) {
        // Pace-aware colours escalate on the projection; the sweep and glyph stay on actual usage
        let escalationPercentage = colorPercentage ?? percentage
        // Battery style display: the progress border and the glyph show remaining; colors stay keyed off used
        let displayPercentage = UsagePercentDisplay.displayPercentage(percentage)
        let cornerRadius: CGFloat = 3.0
        let borderWidth: CGFloat = 1.5
        let progressWidth: CGFloat = 2.5  // Thicker progress stroke
        let center = NSPoint(x: rect.midX, y: rect.midY)

        // 1. Draw the background fill (colored background mode)
        if !removeBackground && !isMonochrome {
            let backgroundFillPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            // Same reason as the track: a hardcoded translucent white reads gray and muddy on a
            // light bar. The circle icons use this faint foreground-derived plate.
            UsageColorScheme.menuBarForeground(for: button).withAlphaComponent(0.10).setFill()
            backgroundFillPath.fill()
        }

        // 2. Draw the background border
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        if isMonochrome {
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
        } else {
            // Adaptive, not a hardcoded gray: on a dark menu bar a literal gray 0.5 reads as a
            // dark track while the circle icons (which already use this) resolve to a light one,
            // so the shapes looked wrong next to them.
            UsageColorScheme.menuBarTrack(for: button).setStroke()
        }
        backgroundPath.lineWidth = borderWidth
        backgroundPath.stroke()

        // The outline both the progress stroke and the period tick measure along
        let perimeter = roundedSquarePerimeter(in: rect, cornerRadius: cornerRadius)
        let outline = roundedSquareOutlinePath(in: rect, cornerRadius: cornerRadius)

        // 2. Draw the progress border (clockwise, starting at 12 o'clock)
        if displayPercentage > 0 {
            // Compute the progress length
            // Progressive subtraction: the amount subtracted grows linearly with the percentage and is fully applied at 50%
            // Below 50%: smooth ramp, the subtracted amount goes from 0 up to progressWidth
            // At or above 50%: exact, always subtract the full progressWidth
            // At 100% nothing is subtracted because .butt caps are used (no overhang)
            let baseProgressLength = perimeter * CGFloat(displayPercentage / 100.0)
            let progressLength = displayPercentage >= 100 ? baseProgressLength : (baseProgressLength - progressWidth * min(1.0, CGFloat(displayPercentage / 50.0)))

            let progressPath = outline.copy() as? NSBezierPath ?? outline

            // Draw with a dash pattern
            // Below 100% a negative phase pre draws half a round cap at the start, so the subtracted lineWidth is split evenly across both ends
            let phase: CGFloat = displayPercentage >= 100 ? 0 : -progressWidth / 2
            let pattern: [CGFloat] = [progressLength, perimeter - progressLength]
            progressPath.setLineDash(pattern, count: 2, phase: phase)
            progressPath.lineWidth = progressWidth
            // At 100% butt caps close the shape perfectly, every other value uses round caps
            progressPath.lineCapStyle = displayPercentage >= 100 ? .butt : .round

            if isMonochrome {
                let opacity = monochromeOpacity(for: percentage)
                NSColor.controlTextColor.withAlphaComponent(opacity).setStroke()
            } else {
                (paceColor ?? UsageColorScheme.opusWeeklyColorAdaptive(escalationPercentage, for: button)).setStroke()
            }
            progressPath.stroke()
        }

        if let markerFraction, let markerPoint = point(on: outline, atFraction: markerFraction) {
            drawRadialTimeMarker(at: markerPoint, center: center, strokeWidth: progressWidth,
                                 isMonochrome: isMonochrome, button: button)
        }

        // 3. Draw the percentage text
        let percentageText = "\(Int(displayPercentage))"
        let percentageFontSize: CGFloat = displayPercentage >= 100 ? 5.0 : 7.2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: percentageFontSize, weight: displayPercentage >= 100 ? .bold : .semibold),
            .foregroundColor: UsageColorScheme.menuBarForeground(for: button)
        ]
        let textSize = percentageText.size(withAttributes: attributes)
        let textRect = NSRect(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2, width: textSize.width, height: textSize.height)
        percentageText.draw(in: textRect, withAttributes: attributes)
    }

    /// Draw the diamond progress ring and percentage (used by Sonnet, a square rotated 45 degrees)
    /// - Parameters:
    ///   - rect: drawing area
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button (used to read colors)
    ///   - removeBackground: whether to remove the background fill
    static func drawDiamondWithPercentage(in rect: NSRect, percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false, markerFraction: CGFloat? = nil, colorPercentage: Double? = nil, paceColor: NSColor? = nil) {
        // Pace-aware colours escalate on the projection; the sweep and glyph stay on actual usage
        let escalationPercentage = colorPercentage ?? percentage
        // Battery style display: the progress border and the glyph show remaining; colors stay keyed off used
        let displayPercentage = UsagePercentDisplay.displayPercentage(percentage)
        // Exactly the same parameters as Opus
        let cornerRadius: CGFloat = 3.0
        let borderWidth: CGFloat = 1.5
        let progressWidth: CGFloat = 2.5  // Thicker progress stroke
        let cutSize: CGFloat = 3.5  // Size of the top right chamfer (nudged slightly smaller)
        let center = NSPoint(x: rect.midX, y: rect.midY)

        // Build the rounded rect path with a chamfered top right corner (same as Opus, only that corner is cut)
        func createChamferedRectPath(_ rect: NSRect) -> NSBezierPath {
            let path = NSBezierPath()

            // Start at the bottom left corner (rounded)
            path.move(to: NSPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 180,
                endAngle: 270,
                clockwise: false
            )

            // Bottom edge to the bottom right corner (rounded)
            path.line(to: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 270,
                endAngle: 0,
                clockwise: false
            )

            // Right edge up to the chamfer
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cutSize))

            // Chamfer line
            path.line(to: NSPoint(x: rect.maxX - cutSize, y: rect.maxY))

            // Top edge to the top left corner (rounded)
            path.line(to: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 90,
                endAngle: 180,
                clockwise: false
            )

            // Back to the start
            path.close()

            return path
        }

        // 1. Draw the background fill (colored background mode)
        if !removeBackground && !isMonochrome {
            let backgroundFillPath = createChamferedRectPath(rect)
            // Same reason as the track: a hardcoded translucent white reads gray and muddy on a
            // light bar. The circle icons use this faint foreground-derived plate.
            UsageColorScheme.menuBarForeground(for: button).withAlphaComponent(0.10).setFill()
            backgroundFillPath.fill()
        }

        // 2. Draw the background border (exactly as Opus does)
        let backgroundPath = createChamferedRectPath(rect)
        if isMonochrome {
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
        } else {
            // Adaptive, not a hardcoded gray: on a dark menu bar a literal gray 0.5 reads as a
            // dark track while the circle icons (which already use this) resolve to a light one,
            // so the shapes looked wrong next to them.
            UsageColorScheme.menuBarTrack(for: button).setStroke()
        }
        backgroundPath.lineWidth = borderWidth
        backgroundPath.stroke()

        // The outline both the progress stroke and the period tick measure along
        let perimeter = chamferedPerimeter(in: rect, cornerRadius: cornerRadius, cutSize: cutSize)
        let outline = chamferedOutlinePath(in: rect, cornerRadius: cornerRadius, cutSize: cutSize)

        // 2. Draw the progress border (clockwise, starting at 12 o'clock)
        if displayPercentage > 0 {
            let progressPath = outline.copy() as? NSBezierPath ?? outline

            // Compute the progress length
            // Progressive subtraction: the amount subtracted grows linearly with the percentage and is fully applied at 50%
            // Below 50%: smooth ramp, the subtracted amount goes from 0 up to progressWidth
            // At or above 50%: exact, always subtract the full progressWidth
            // At 100% nothing is subtracted because .butt caps are used (no overhang)
            let baseProgressLength = perimeter * CGFloat(displayPercentage / 100.0)
            let progressLength = displayPercentage >= 100 ? baseProgressLength : (baseProgressLength - progressWidth * min(1.0, CGFloat(displayPercentage / 50.0)))

            // Draw with a dash pattern
            // Below 100% a negative phase pre draws half a round cap at the start, so the subtracted lineWidth is split evenly across both ends
            let phase: CGFloat = displayPercentage >= 100 ? 0 : -progressWidth / 2
            let pattern: [CGFloat] = [progressLength, perimeter - progressLength]
            progressPath.setLineDash(pattern, count: 2, phase: phase)
            progressPath.lineWidth = progressWidth
            // At 100% butt caps close the shape perfectly, every other value uses round caps
            progressPath.lineCapStyle = displayPercentage >= 100 ? .butt : .round

            if isMonochrome {
                let opacity = monochromeOpacity(for: percentage)
                NSColor.controlTextColor.withAlphaComponent(opacity).setStroke()
            } else {
                (paceColor ?? UsageColorScheme.sonnetWeeklyColorAdaptive(escalationPercentage, for: button)).setStroke()
            }
            progressPath.stroke()
        }

        if let markerFraction, let markerPoint = point(on: outline, atFraction: markerFraction) {
            drawRadialTimeMarker(at: markerPoint, center: center, strokeWidth: progressWidth,
                                 isMonochrome: isMonochrome, button: button)
        }

        // 3. Draw the percentage text (exactly as Opus does)
        let percentageText = "\(Int(displayPercentage))"
        let percentageFontSize: CGFloat = displayPercentage >= 100 ? 5.0 : 7.2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: percentageFontSize, weight: displayPercentage >= 100 ? .bold : .semibold),
            .foregroundColor: UsageColorScheme.menuBarForeground(for: button)
        ]
        let textSize = percentageText.size(withAttributes: attributes)
        let textRect = NSRect(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2, width: textSize.width, height: textSize.height)
        percentageText.draw(in: textRect, withAttributes: attributes)
    }

    /// Draw the flat top hexagon progress ring and percentage (used by Extra Usage)
    /// - Parameters:
    ///   - center: center point
    ///   - size: hexagon size
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button (used to read colors)
    ///   - removeBackground: whether to remove the background fill
    static func drawHexagonWithPercentage(center: NSPoint, size: CGFloat, percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false, colorOverride: NSColor? = nil) {
        // Battery style display: the progress border and the glyph show remaining; colors stay keyed off used
        let displayPercentage = UsagePercentDisplay.displayPercentage(percentage)
        let radius = size / 2
        let borderWidth: CGFloat = 1.5
        let progressWidth: CGFloat = 2.5  // Thicker progress stroke

        // Build the flat top hexagon path (flat top means the top and bottom edges are flat)
        let hexagonPath = NSBezierPath()
        for i in 0..<6 {
            let angle = CGFloat(i) * CGFloat.pi / 3.0  // Keep the flat top orientation
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            if i == 0 {
                hexagonPath.move(to: NSPoint(x: x, y: y))
            } else {
                hexagonPath.line(to: NSPoint(x: x, y: y))
            }
        }
        hexagonPath.close()

        // 1. Draw the background fill (colored background mode)
        if !removeBackground && !isMonochrome {
            // Same reason as the track: a hardcoded translucent white reads gray and muddy on a
            // light bar. The circle icons use this faint foreground-derived plate.
            UsageColorScheme.menuBarForeground(for: button).withAlphaComponent(0.10).setFill()
            hexagonPath.fill()
        }

        // 2. Draw the background border
        if isMonochrome {
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
        } else {
            // Adaptive, not a hardcoded gray: on a dark menu bar a literal gray 0.5 reads as a
            // dark track while the circle icons (which already use this) resolve to a light one,
            // so the shapes looked wrong next to them.
            UsageColorScheme.menuBarTrack(for: button).setStroke()
        }
        hexagonPath.lineWidth = borderWidth
        hexagonPath.lineJoinStyle = .round
        hexagonPath.stroke()

        // 2. Draw the progress border
        if displayPercentage > 0 {
            // Compute the hexagon perimeter
            let sideLength = radius  // Every side of a regular hexagon is as long as its radius
            let perimeter = sideLength * 6

            // Compute the progress length
            // Progressive subtraction: the amount subtracted grows linearly with the percentage and is fully applied at 50%
            // Below 50%: smooth ramp, the subtracted amount goes from 0 up to progressWidth
            // At or above 50%: exact, always subtract the full progressWidth
            // At 100% nothing is subtracted because .butt caps are used (no overhang)
            let baseProgressLength = perimeter * CGFloat(displayPercentage / 100.0)
            let progressLength = displayPercentage >= 100 ? baseProgressLength : (baseProgressLength - progressWidth * min(1.0, CGFloat(displayPercentage / 50.0)))

            // Build the clockwise path from the top by hand, starting at 12 o'clock
            // First compute the 6 vertex positions (keeping the flat top orientation)
            var vertices: [NSPoint] = []
            for i in 0..<6 {
                let angle = CGFloat(i) * CGFloat.pi / 3.0
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                vertices.append(NSPoint(x: x, y: y))
            }
            // vertices[0] = 3 o'clock (right)
            // vertices[1] = 1 o'clock (upper right)
            // vertices[2] = 11 o'clock (upper left)
            // vertices[3] = 9 o'clock (left)
            // vertices[4] = 7 o'clock (lower left)
            // vertices[5] = 5 o'clock (lower right)

            // Start at 12 o'clock (the top edge midpoint, between vertices[1] and vertices[2])
            let topMidpoint = NSPoint(
                x: (vertices[1].x + vertices[2].x) / 2,
                y: (vertices[1].y + vertices[2].y) / 2
            )

            let progressHexagon = NSBezierPath()
            progressHexagon.move(to: topMidpoint)

            // Clockwise: 12 to 1 to 3 to 5 to 7 to 9 to 11 and back to 12
            progressHexagon.line(to: vertices[1])  // To the 1 o'clock vertex
            progressHexagon.line(to: vertices[0])  // To the 3 o'clock vertex
            progressHexagon.line(to: vertices[5])  // To the 5 o'clock vertex
            progressHexagon.line(to: vertices[4])  // To the 7 o'clock vertex
            progressHexagon.line(to: vertices[3])  // To the 9 o'clock vertex
            progressHexagon.line(to: vertices[2])  // To the 11 o'clock vertex
            progressHexagon.line(to: topMidpoint)  // Back to 12 o'clock

            // Draw with a dash pattern
            // Below 100% a negative phase pre draws half a round cap at the start, so the subtracted lineWidth is split evenly across both ends
            let phase: CGFloat = displayPercentage >= 100 ? 0 : -progressWidth / 2
            let pattern: [CGFloat] = [progressLength, perimeter - progressLength]
            progressHexagon.setLineDash(pattern, count: 2, phase: phase)
            progressHexagon.lineWidth = progressWidth
            // At 100% butt caps close the shape perfectly, every other value uses round caps
            progressHexagon.lineCapStyle = displayPercentage >= 100 ? .butt : .round
            progressHexagon.lineJoinStyle = .round

            if isMonochrome {
                let opacity = monochromeOpacity(for: percentage)
                NSColor.controlTextColor.withAlphaComponent(opacity).setStroke()
            } else if let colorOverride {
                colorOverride.setStroke()
            } else {
                // No window to project across, so the Extra Usage colour is always flat
                UsageColorScheme.extraUsageColorAdaptive(UsageColorScheme.flatPercentage, for: button).setStroke()
            }
            progressHexagon.stroke()
        }

        // 3. Draw the percentage text
        let percentageText = "\(Int(displayPercentage))"
        let percentageFontSize: CGFloat = displayPercentage >= 100 ? 5.0 : 7.2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: percentageFontSize, weight: displayPercentage >= 100 ? .bold : .semibold),
            .foregroundColor: UsageColorScheme.menuBarForeground(for: button)
        ]
        let textSize = percentageText.size(withAttributes: attributes)
        let textRect = NSRect(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2, width: textSize.width, height: textSize.height)
        percentageText.draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - Icon Creation Methods

    /// Create the rounded square icon (Opus)
    /// - Parameters:
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button
    ///   - removeBackground: whether to remove the background fill
    /// - Returns: icon image (18x18)
    static func createVerticalRectangleIcon(percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false, markerFraction: CGFloat? = nil, colorPercentage: Double? = nil, paceColor: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(dx: 2, dy: 2)
        drawRoundedSquareWithPercentage(in: rect, percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground, markerFraction: markerFraction, colorPercentage: colorPercentage, paceColor: paceColor)

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }

    /// Create the diamond icon (Sonnet, a square rotated 45 degrees)
    /// - Parameters:
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button
    ///   - removeBackground: whether to remove the background fill
    /// - Returns: icon image (18x18)
    static func createHorizontalRectangleIcon(percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false, markerFraction: CGFloat? = nil, colorPercentage: Double? = nil, paceColor: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(dx: 2, dy: 2)
        drawDiamondWithPercentage(in: rect, percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground, markerFraction: markerFraction, colorPercentage: colorPercentage, paceColor: paceColor)

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }

    /// Create the flat top hexagon icon (Extra Usage)
    /// - Parameters:
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button
    ///   - removeBackground: whether to remove the background (false by default)
    /// - Returns: icon image (18x18)
    static func createHexagonIcon(percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false, colorOverride: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        drawHexagonWithPercentage(center: center, size: 16, percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground, colorOverride: colorOverride)

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }
}
