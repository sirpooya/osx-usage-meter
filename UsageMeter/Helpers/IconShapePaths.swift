//
//  IconShapePaths.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Icon shape path helpers
/// Builds the shape path for every limit type icon
/// Supports both SwiftUI Path and NSBezierPath
struct IconShapePaths {

    // MARK: - SwiftUI Path Methods

    /// Create the circular path (clockwise from 12 o'clock, works with a trimmedPath progress arc)
    /// - Parameter rect: drawing area
    /// - Returns: the circular path
    static func circlePath(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: 3, dy: 3)
        let center = CGPoint(x: inset.midX, y: inset.midY)
        let radius = min(inset.width, inset.height) / 2
        return Path { path in
            // Full circle clockwise from 12 o'clock (-90 degrees)
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(-90), endAngle: .degrees(270),
                        clockwise: false)
        }
    }

    /// Create the rounded square path (Opus, clockwise from the top midpoint, scales with rect)
    /// - Parameter rect: drawing area
    /// - Returns: the rounded square path
    static func roundedSquarePath(in rect: CGRect) -> Path {
        let s = (min(rect.width, rect.height) - 8) / 2  // Half the side length (4pt inset so the stroke is not clipped)
        let cx = rect.midX, cy = rect.midY
        let r = s * 0.4  // Corner radius (same 2/10 ratio as the original)
        return Path { path in
            // Draw clockwise from the top midpoint
            path.move(to: CGPoint(x: cx, y: cy - s))
            path.addLine(to: CGPoint(x: cx + s - r, y: cy - s))
            path.addArc(center: CGPoint(x: cx + s - r, y: cy - s + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: cx + s, y: cy + s - r))
            path.addArc(center: CGPoint(x: cx + s - r, y: cy + s - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: cx - s + r, y: cy + s))
            path.addArc(center: CGPoint(x: cx - s + r, y: cy + s - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: cx - s, y: cy - s + r))
            path.addArc(center: CGPoint(x: cx - s + r, y: cy - s + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: cx, y: cy - s))
            path.closeSubpath()
        }
    }

    /// Create the rounded square path with a chamfered top right corner (Sonnet, clockwise from the top midpoint, scales with rect)
    /// - Parameter rect: drawing area
    /// - Returns: the chamfered rounded square path
    static func chamferedSquarePath(in rect: CGRect) -> Path {
        let s = (min(rect.width, rect.height) - 8) / 2  // Half the side length (4pt inset so the stroke is not clipped)
        let cx = rect.midX, cy = rect.midY
        let r = s * 0.4    // Corner radius
        let cut = s * 0.5  // Size of the top right chamfer (same 2.5/5 ratio as the original)
        return Path { path in
            // Draw clockwise from the top midpoint
            path.move(to: CGPoint(x: cx, y: cy - s))
            path.addLine(to: CGPoint(x: cx + s - cut, y: cy - s))  // Top edge to the start of the chamfer
            path.addLine(to: CGPoint(x: cx + s, y: cy - s + cut))  // Chamfer
            path.addLine(to: CGPoint(x: cx + s, y: cy + s - r))    // Right edge
            path.addArc(center: CGPoint(x: cx + s - r, y: cy + s - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: cx - s + r, y: cy + s))
            path.addArc(center: CGPoint(x: cx - s + r, y: cy + s - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: cx - s, y: cy - s + r))
            path.addArc(center: CGPoint(x: cx - s + r, y: cy - s + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: cx, y: cy - s))
            path.closeSubpath()
        }
    }

    /// Create the flat top hexagon path (Extra Usage, clockwise from the top right vertex)
    /// - Parameters:
    ///   - center: center of the hexagon
    ///   - radius: radius of the hexagon
    /// - Returns: the hexagon path
    static func hexagonPath(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            // Clockwise from the top right vertex (-60 degrees, the closest one to 12 o'clock)
            for i in 0..<6 {
                let angleDeg: CGFloat = -60 + CGFloat(i) * 60
                let angle = angleDeg * .pi / 180
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
        }
    }

    /// Get the shape path for a limit type (scales with rect)
    /// - Parameters:
    ///   - type: limit type
    ///   - rect: drawing area
    /// - Returns: the matching shape path
    static func pathForLimitType(_ type: LimitType, in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Hexagon radius: a 3pt inset keeps the stroke from being clipped
        let hexRadius = min(rect.width, rect.height) / 2 - 3

        switch type {
        case .fiveHour, .sevenDay, .codexPrimary, .codexSecondary:
            return circlePath(in: rect)

        case .opusWeekly:
            return roundedSquarePath(in: rect)

        case .sonnetWeekly:
            return chamferedSquarePath(in: rect)

        case .extraUsage, .codexExtraUsage:
            return hexagonPath(center: center, radius: hexRadius)
        }
    }

    // MARK: - NSBezierPath Methods (for MenuBarIconRenderer)

    /// Create the rounded square NSBezierPath (Opus)
    /// - Parameters:
    ///   - center: center point
    ///   - size: side length of the square
    /// - Returns: NSBezierPath
    static func roundedSquareNSPath(center: CGPoint, size: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let rect = CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
        path.appendRoundedRect(rect, xRadius: 2, yRadius: 2)
        return path
    }

    /// Create the rounded square NSBezierPath with a chamfered top right corner (Sonnet)
    /// - Parameters:
    ///   - center: center point
    ///   - size: side length of the square
    /// - Returns: NSBezierPath
    static func chamferedSquareNSPath(center: CGPoint, size: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let rect = CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
        let cornerRadius: CGFloat = 2.0
        let cutSize: CGFloat = 2.5

        // Start at the bottom left corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))

        // Left edge to the bottom left corner radius
        path.appendArc(
            withCenter: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: 180,
            endAngle: 270,
            clockwise: false
        )

        // Bottom edge to the bottom right corner radius
        path.line(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.appendArc(
            withCenter: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: 270,
            endAngle: 0,
            clockwise: false
        )

        // Right edge up to the chamfer
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - cutSize))

        // Chamfer line
        path.line(to: CGPoint(x: rect.maxX - cutSize, y: rect.maxY))

        // Top edge to the top left corner radius
        path.line(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.appendArc(
            withCenter: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: 90,
            endAngle: 180,
            clockwise: false
        )

        path.close()
        return path
    }

    /// Create the flat top hexagon NSBezierPath (Extra Usage)
    /// - Parameters:
    ///   - center: center point
    ///   - radius: radius
    /// - Returns: NSBezierPath
    static func hexagonNSPath(center: CGPoint, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()

        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3.0
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.line(to: CGPoint(x: x, y: y))
            }
        }

        path.close()
        return path
    }
}
