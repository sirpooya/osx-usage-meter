//
//  MenuBarPerDisplayIcon.swift
//  UsageMeter
//
//  Per-display menu bar icon support.
//
//  One NSStatusItem holds one NSImage and macOS shows that item on every display, so a
//  color icon whose grays were resolved against one menu bar is wrong on a second display
//  whose wallpaper gives the bar the opposite appearance. Template images do not have the
//  problem because AppKit re-tints them per bar; color images are drawn literally.
//
//  The fix: dynamicImage(size:render:) wraps the renderer in
//  NSImage(size:flipped:drawingHandler:). The handler runs once per bar appearance (NSImage
//  caches rendered variants per appearance since 10.14), reads
//  NSAppearance.currentDrawing(), pins UsageColorScheme.drawingIsDarkOverride and
//  re-renders, so tonal parts resolve per display while accent colors stay literal.
//
//  The handler also applies the inactive-bar dim at draw time. macOS dims menu bar items on
//  the display whose menu bar is inactive, but only through the template tint (measured:
//  appearsDisabled stays NO, window alpha stays 1), so color icons must dim themselves.
//
//  Approaches that FAILED on macOS 26, kept here so they are not retried:
//  - Assigning images directly to the replicant windows' buttons (the private
//    NSStatusItemReplicant machinery, reachable via NSApp.windows). AppKit recreates those
//    windows and re-syncs their content behind us, and repeated writes make Control Center
//    pull the item from every bar. `killall ControlCenter` brings it back.
//  - SLSSetWindowAlpha on the status bar windows. They report a bogus windowNumber
//    (Control Center owns the real surface) and the item vanishes the same way.
//

import AppKit

enum MenuBarPerDisplayIcon {

    /// Alpha for the icon on an inactive menu bar, eyeballed against the system's dimming
    /// of template icons.
    static let inactiveDimAlpha: CGFloat = 0.45

    // MARK: - Dynamic icon

    /// Appearance-resolving wrapper. The render closure re-runs per bar appearance with
    /// UsageColorScheme.drawingIsDarkOverride pinned, and the result is drawn dimmed when
    /// the draw is for an inactive bar. Only useful for color icons; template icons already
    /// adapt natively.
    ///
    /// The dim decision is baked into the per-appearance cached variant, so when the active
    /// display changes the wrapper must be REBUILT (a new NSImage instance) for the dim to
    /// update. MenuBarUI does that from its heartbeat by watching activeMenuBarDisplayUUID.
    static func dynamicImage(size: NSSize, render: @escaping (Bool) -> NSImage) -> NSImage {
        return NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            UsageColorScheme.drawingIsDarkOverride = isDark
            defer { UsageColorScheme.drawingIsDarkOverride = nil }
            let fraction: CGFloat = shouldDimDraw(forDark: isDark) ? inactiveDimAlpha : 1.0
            render(isDark).draw(in: rect, from: .zero, operation: .sourceOver, fraction: fraction)

            // Invisible state beacon. The replicant bars only re-snapshot the item after
            // the MAIN bar's rendered pixels change, and on a focus flip the main (active,
            // undimmed) variant renders pixel-identical, so the other bar would keep its
            // stale dim state forever (verified: 28s and a dozen reassignments with no
            // repaint). One corner pixel whose alpha depends on the active display makes
            // every variant differ across flips, which forces the re-snapshot. Invisible
            // at alpha <= 0.008.
            // Alpha must survive 8-bit quantization or the pixels do not actually change;
            // 0.004 vs 0.008 both rounded away and the re-snapshot never fired.
            let beaconBit = (activeMenuBarDisplayUUID()?.hashValue ?? 0) & 1
            if beaconBit == 1 {
                NSColor.black.withAlphaComponent(0.05).setFill()
                NSRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: 1).fill()
            }
            return true
        }
    }

    /// Provider for the window hosting the REAL status item button, set by MenuBarUI.
    /// The main window is the only bar window whose screen and appearance are always live
    /// and trustworthy; replicant windows show zero frames and nil screens mid-lifecycle,
    /// which made every windows-scan decision scheme misfire at snapshot time.
    static var mainWindowProvider: (() -> NSWindow?)?

    /// Dim decision at draw time, anchored on the main window only:
    /// - Main bar active: any OTHER appearance can only belong to inactive bars, dim it.
    /// - Main bar inactive: the other appearance belongs to the active bar, keep it
    ///   bright; the main bar's own appearance is dimmed only when a second bar with a
    ///   DIFFERENT appearance is observable, otherwise both bars share one variant and
    ///   dimming it would dim the active bar too.
    private static func shouldDimDraw(forDark isDark: Bool) -> Bool {
        guard let active = activeMenuBarDisplayUUID(),
              let mainWindow = mainWindowProvider?(),
              let mainUUID = displayUUID(for: mainWindow) else { return false }
        let mainIsDark = barIsDark(mainWindow)
        let mainIsActive = mainUUID.caseInsensitiveCompare(active) == .orderedSame
        if mainIsActive {
            return isDark != mainIsDark
        }
        if isDark != mainIsDark { return false }
        return statusBarWindows().contains { window in
            window !== mainWindow && barIsDark(window) != mainIsDark
        }
    }

    /// Display UUID hosting this window: its screen when set, otherwise the screen whose
    /// frame contains the window (ordered-out bar windows report screen == nil)
    private static func displayUUID(for window: NSWindow) -> String? {
        let frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = window.screen ?? NSScreen.screens.first { NSPointInRect(center, $0.frame) }
        guard let screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuidFn = uuidFromDisplayIDFn,
              let uuid = uuidFn(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Whether the menu bar hosting this window currently renders dark
    static func barIsDark(_ window: NSWindow) -> Bool {
        window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// This app's status bar windows: the main one plus the per-display/per-Space
    /// replicants AppKit maintains. Read-only use only; writing to them is what got the
    /// item hidden (see header).
    static func statusBarWindows() -> [NSWindow] {
        NSApp.windows.filter { String(describing: type(of: $0)).contains("NSStatusBarWindow") }
    }

    // MARK: - Active menu bar display (private SkyLight, runtime-guarded)

    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias ActiveMenuBarFn = @convention(c) (Int32) -> Unmanaged<CFString>?
    private typealias UUIDFromIDFn = @convention(c) (UInt32) -> Unmanaged<CFUUID>?

    private static let skyLightHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static let mainConnectionFn: MainConnFn? = {
        guard let handle = skyLightHandle, let sym = dlsym(handle, "SLSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: MainConnFn.self)
    }()

    private static let activeMenuBarFn: ActiveMenuBarFn? = {
        guard let handle = skyLightHandle, let sym = dlsym(handle, "SLSCopyActiveMenuBarDisplayIdentifier") else { return nil }
        return unsafeBitCast(sym, to: ActiveMenuBarFn.self)
    }()

    /// CGDisplayCreateUUIDFromDisplayID is public but deprecated; dlsym keeps the build clean
    private static let uuidFromDisplayIDFn: UUIDFromIDFn? = {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "CGDisplayCreateUUIDFromDisplayID") else { return nil }
        return unsafeBitCast(sym, to: UUIDFromIDFn.self)
    }()

    /// UUID string of the display whose menu bar is currently active, nil when the private
    /// call is unavailable. MenuBarUI watches this to rebuild the icon when it changes.
    static func activeMenuBarDisplayUUID() -> String? {
        guard let mainConnection = mainConnectionFn, let active = activeMenuBarFn,
              let uuid = active(mainConnection())?.takeRetainedValue() else { return nil }
        return uuid as String
    }

    /// Whether the menu bar hosting this window is the active one. true when any part of
    /// the signal is unavailable, which keeps the icon at full brightness (the old behavior).
    static func isBarActive(on window: NSWindow) -> Bool {
        guard let active = activeMenuBarDisplayUUID(),
              let uuid = displayUUID(for: window) else { return true }
        return uuid.caseInsensitiveCompare(active) == .orderedSame
    }
}
