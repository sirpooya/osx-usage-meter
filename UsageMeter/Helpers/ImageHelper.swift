//
//  ImageHelper.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit

/// Image helpers
/// App icon creation, caching and similar utilities
enum ImageHelper {
    // MARK: - Named Image Lookup

    /// Load a resource image by name.
    /// Note that "AppIcon" is an appiconset: actool compiles it into icon data only and never produces an image
    /// resource of the same name, so NSImage(named: "AppIcon") is always nil (which is why the popover header,
    /// About page, account rows and the color menu bar icon all got nothing and fell back to placeholder shapes).
    /// The fallback here reads the bundle's own icon, which is the exact image Finder shows.
    static func namedImage(_ name: String) -> NSImage? {
        if let image = NSImage(named: name) { return image }
        guard name == "AppIcon" else { return nil }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    // MARK: - App Icon

    /// Create the app icon (non template mode)
    /// - Parameter size: icon size
    /// - Returns: the app icon at the requested size, or nil when it cannot be loaded
    static func createAppIcon(size: CGFloat) -> NSImage? {
        guard let appIcon = namedImage("AppIcon") else { return nil }
        guard let iconCopy = appIcon.copy() as? NSImage else { return nil }
        iconCopy.isTemplate = false
        iconCopy.size = NSSize(width: size, height: size)
        return iconCopy
    }

    /// Create the app icon (non template mode, explicit width and height)
    /// - Parameters:
    ///   - width: icon width
    ///   - height: icon height
    /// - Returns: the app icon at the requested size, or nil when it cannot be loaded
    static func createAppIcon(width: CGFloat, height: CGFloat) -> NSImage? {
        guard let appIcon = namedImage("AppIcon") else { return nil }
        guard let iconCopy = appIcon.copy() as? NSImage else { return nil }
        iconCopy.isTemplate = false
        iconCopy.size = NSSize(width: width, height: height)
        return iconCopy
    }

    // MARK: - Provider Marks

    /// The brand marks used by the credentials sidebar section headers. Separate assets from
    /// AppIcon and CodexIcon on purpose: those two are menu bar / popover icons, these are the
    /// flat provider logos, and they have to stay legible down at 13pt.
    static func createClaudeMark(size: CGFloat) -> NSImage? {
        createSquareIcon(named: "ClaudeMark", size: size, isTemplate: false)
    }

    static func createCodexMark(size: CGFloat) -> NSImage? {
        createSquareIcon(named: "CodexMark", size: size, isTemplate: false)
    }

    // MARK: - Codex Icon

    static func createCodexIcon(size: CGFloat) -> NSImage? {
        createSquareIcon(named: "CodexIcon", size: size, isTemplate: false, sourceInset: 2)
    }

    /// Create a square icon from a resource. Some transparent PNGs have non transparent RGB at the edges,
    /// which AppKit samples into a thin dark line when scaled directly, so crop to a centered square and inset slightly first.
    static func createSquareIcon(named name: String, size: CGFloat, isTemplate: Bool, sourceInset: CGFloat = 0) -> NSImage? {
        guard let source = namedImage(name) else { return nil }
        let targetSize = NSSize(width: size, height: size)
        let image = NSImage(size: targetSize)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        let sourceSize = source.size
        let side = min(sourceSize.width, sourceSize.height) - sourceInset * 2
        let cropRect = NSRect(
            x: (sourceSize.width - side) / 2,
            y: (sourceSize.height - side) / 2,
            width: side,
            height: side
        )

        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: cropRect,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: false,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        )
        image.unlockFocus()
        image.isTemplate = isTemplate
        return image
    }

    // MARK: - System Images

    /// Create a system symbol image
    /// - Parameters:
    ///   - systemName: SF Symbols name
    ///   - size: image size
    ///   - weight: symbol weight
    /// - Returns: the system image, or nil when it cannot be loaded
    static func createSystemImage(
        systemName: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}
