//
//  MenuBarUI.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit
import Combine

/// Menu bar UI manager
/// Owns the menu bar icon, the popover, menu creation and icon drawing
/// Holds the whole UI layer, every UI responsibility extracted from MenuBarManager
class MenuBarUI {

    // MARK: - UI Components

    /// System menu bar status item
    private(set) var statusItem: NSStatusItem!
    /// Detail popover
    private(set) var popover: NSPopover!
    /// Popover dismissal monitor, watches mouse clicks
    private var popoverCloseObserver: Any?
    /// App deactivation observer, closes the popover when the app loses focus
    private var appResignActiveObserver: NSObjectProtocol?

    // MARK: - Icon Cache

    /// Icon cache: the key covers mode/style/percentage and the other render parameters (appearance excluded, because on an
    /// appearance change UserSettings' AppleInterfaceThemeChangedNotification observer posts
    /// `.settingsChanged`, which clears the cache; see UserSettings.swift)
    private var iconCache: [String: NSImage] = [:]
    /// Insertion order of the cache keys, for FIFO eviction (a Swift Dictionary is unordered, so keys.first is not enough)
    private var iconCacheOrder: [String] = []
    /// Maximum number of cache entries
    private let maxCacheSize = 50

    // MARK: - Per-Display Icon state

    /// Render closure and size of the current color icon; nil while a template icon is
    /// shown (templates are tinted and dimmed per display by AppKit, nothing to do)
    private var lastRender: ((Bool) -> NSImage)?
    private var lastIconSize: NSSize?
    /// Active-menu-bar display at the time the current wrapper was built. The dim state is
    /// baked into the wrapper's per-appearance cache, so a change here means rebuild.
    private var lastActiveBarUUID: String?
    /// Display connect/disconnect re-checks the dim state
    private var screenParamsObserver: NSObjectProtocol?
    /// Active-menu-bar-display changes (focus moved to the other monitor) re-check the dim
    private var activeDisplayObservers: [NSObjectProtocol] = []
    /// No event fires when focus moves between displays within one app, so the active
    /// display is polled on a cheap heartbeat (one string compare; rebuild only on change)
    private var dimHeartbeat: Timer?
    /// Rate limit for the visibility blip in refreshDimIfNeeded
    private var lastVisibilityBlip = Date.distantPast

    // MARK: - Settings Reference

    /// User settings instance (injected)
    private let settings = UserSettings.shared

    // MARK: - Icon Renderer

    /// Icon renderer, owns all icon drawing
    private let iconRenderer = MenuBarIconRenderer()

    // MARK: - Initialization

    init() {
        setupStatusItem()
        setupPopover()

        // The per-display dim decision anchors on the real item's window
        MenuBarPerDisplayIcon.mainWindowProvider = { [weak statusItem] in
            statusItem?.button?.window
        }

        // Display connect/disconnect lazily creates or destroys replicant status bar windows
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.refreshDimIfNeeded()
            }
        }

        // Which display owns the active menu bar changes with focus. The first name is the
        // dedicated (undocumented) notification; the other two are public fallbacks that
        // fire on the interactions that move focus between displays.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let activeDisplayNames: [Notification.Name] = [
            Notification.Name("NSWorkspaceActiveDisplayDidChangeNotification"),
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ]
        activeDisplayObservers = activeDisplayNames.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshDimIfNeeded()
            }
        }

        dimHeartbeat = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDimIfNeeded()
        }
        dimHeartbeat?.tolerance = 0.5
    }

    // MARK: - Status Item Setup

    /// Set up the menu bar status item
    /// Wire up click handling
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Initial icon
            button.image = createSimpleCircleIcon()
        }
    }

    /// Configure status item click handling
    /// - Parameters:
    ///   - target: target object
    ///   - action: click handler method
    func configureClickHandler(target: AnyObject?, action: Selector) {
        guard let button = statusItem.button else { return }
        button.action = action
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = target
    }

    // MARK: - Popover Setup

    /// Set up the popover
    /// Configure the window size and appearance
    private func setupPopover() {
        popover = NSPopover()
        // Fixed size, so the layout does not jump
        popover.contentSize = NSSize(width: 280, height: 240)
        // Set the behavior, allowing a custom appearance
        popover.behavior = .semitransient
    }

    /// Set the popover content view
    /// - Parameter contentView: the SwiftUI view
    /// - Note: sizingOptions = .preferredContentSize lets NSHostingController push the SwiftUI
    ///   content's ideal size to the popover, so row counts and heights need no manual math.
    func setPopoverContent<Content: View>(_ contentView: Content) {
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    // MARK: - Popover Control

    /// Open the popover
    /// - Parameter button: the menu bar button
    func openPopover(relativeTo button: NSStatusBarButton) {
        // Activate the app so the popover responds to focus changes correctly
        NSApp.activate(ignoringOtherApps: true)

        // The popover hangs off the system status bar, so it inherits the status bar appearance rather than NSApp.appearance
        // It has to be set explicitly on every open to stay in sync with the user's preference
        switch settings.appearance {
        case .system:
            let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            popover.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        case .light:
            popover.appearance = NSAppearance(named: .aqua)
        case .dark:
            popover.appearance = NSAppearance(named: .darkAqua)
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Configure the popover window properties
        configurePopoverWindow()

        // Install the monitors
        setupPopoverCloseObserver()
        setupAppResignActiveObserver()
    }

    /// Configure the popover window properties
    private func configurePopoverWindow() {
        guard let popoverWindow = popover.contentViewController?.view.window else { return }

        // Set the window level so it sits above other windows
        popoverWindow.level = .popUpMenu

        // Let the window become key, showing focus state
        popoverWindow.makeKey()

        #if DEBUG
        // Set the background color from the debug switch
        if settings.debugKeepDetailWindowOpen {
            // On: solid opaque white background
            popoverWindow.backgroundColor = NSColor.white
            popoverWindow.isOpaque = true
            // Set the content view background
            if let contentView = popover.contentViewController?.view {
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.white.cgColor
            }
        } else {
            // Off: use the default transparent background
            popoverWindow.backgroundColor = NSColor.clear
            popoverWindow.isOpaque = false
            // Restore the content view's transparent background
            if let contentView = popover.contentViewController?.view {
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
        #endif
    }

    /// Close the popover
    func closePopover() {
        // Make sure the popover is closed
        if popover.isShown {
            popover.performClose(nil)
        }
        // Remove the event monitors
        removePopoverCloseObserver()
        removeAppResignActiveObserver()
    }

    /// Set up the outside click monitor for the popover
    /// Closes automatically when a click lands outside the popover
    private func setupPopoverCloseObserver() {
        // Remove the old observer first so they do not pile up
        removePopoverCloseObserver()

        // Use a global event monitor to watch mouse clicks
        popoverCloseObserver = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }

            #if DEBUG
            // Debug mode: do not auto close when "keep detail window open" is enabled
            if UserSettings.shared.debugKeepDetailWindowOpen {
                return
            }
            #endif

            self.closePopover()
        }
    }

    /// Remove the popover monitors
    private func removePopoverCloseObserver() {
        if let observer = popoverCloseObserver {
            NSEvent.removeMonitor(observer)
            popoverCloseObserver = nil
        }
    }

    /// Set up the app deactivation monitor
    /// Closes the popover automatically when the app loses focus
    private func setupAppResignActiveObserver() {
        // Remove the old observer first so they do not pile up
        removeAppResignActiveObserver()

        // Listen for the app losing focus
        appResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }

            #if DEBUG
            // Debug mode: do not auto close when "keep detail window open" is enabled
            if UserSettings.shared.debugKeepDetailWindowOpen {
                return
            }
            #endif

            self.closePopover()
        }
    }

    /// Remove the app deactivation monitor
    private func removeAppResignActiveObserver() {
        if let observer = appResignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignActiveObserver = nil
        }
    }

    // MARK: - Menu Management

    /// Create the standard menu
    /// Used by the right click menu and by the three dot menu in the popover
    /// - Parameters:
    ///   - hasUpdate: whether an update is available
    ///   - shouldShowBadge: whether to show the update badge
    ///   - target: target object for the menu items
    /// - Returns: the configured NSMenu
    func createStandardMenu(hasUpdate: Bool, shouldShowBadge: Bool, target: AnyObject?) -> NSMenu {
        let menu = NSMenu()
        // Control the enabled state ourselves, otherwise AppKit overrides the disabled state of Check for Updates
        menu.autoenablesItems = false

        // Account picker submenu (shown when there is more than one account)
        var hasAccountMenuItems = false

        if settings.accounts.count > 1 {
            let accountSubmenu = createAccountSubmenu(target: target)
            let currentAccountName = settings.currentAccountName ?? L.Menu.account
            let accountItem = NSMenuItem(
                title: "\(L.Menu.accountPrefix) \(currentAccountName)",
                action: nil,
                keyEquivalent: ""
            )
            accountItem.submenu = accountSubmenu
            menu.addItem(accountItem)
            hasAccountMenuItems = true
        }

        if settings.codexAccounts.count > 1 {
            let codexSubmenu = createCodexAccountSubmenu(target: target)
            let currentCodexName = settings.currentCodexAccount?.displayName ?? "Codex"
            let codexItem = NSMenuItem(
                title: "Codex: \(currentCodexName)",
                action: nil,
                keyEquivalent: ""
            )
            codexItem.submenu = codexSubmenu
            menu.addItem(codexItem)
            hasAccountMenuItems = true
        }

        if hasAccountMenuItems {
            menu.addItem(NSMenuItem.separator())
        }

        // Settings (General and Authentication merged into one item)
        let settingsItem = NoAutoIconMenuItem(
            title: L.Menu.settings,
            action: #selector(MenuBarManager.openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = target
        menu.addItem(settingsItem)

        // Check for Updates
        let updateItem = NSMenuItem(
            title: "",
            action: #selector(MenuBarManager.checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = target

        // Different styling depending on whether an update is available
        if hasUpdate {
            // Update available: rainbow text
            let baseText = L.Menu.checkUpdates
            let highlightText = L.Update.Notification.badgeMenu
            let title = "\(baseText)\t\(highlightText)"

            let highlightLocation = baseText.utf16.count + 1
            let highlightLength = highlightText.utf16.count
            let highlightRange = NSRange(location: highlightLocation, length: highlightLength)

            let attributedTitle = createRainbowText(title, highlightRange: highlightRange)
            updateItem.attributedTitle = attributedTitle

        } else {
            // No update: plain styling
            updateItem.title = L.Menu.checkUpdates
        }

        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: L.Menu.quit,
            action: #selector(MenuBarManager.quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = target
        menu.addItem(quitItem)

        return menu
    }

    /// Set the icon on a menu item
    /// - Parameters:
    ///   - item: the menu item
    ///   - systemName: SF Symbol name
    private func setMenuItemIcon(_ item: NSMenuItem, systemName: String) {
        if let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            item.image = image
        }
    }

    /// Create the account picker submenu
    /// - Parameter target: target object for the menu items
    /// - Returns: the account picker submenu
    private func createAccountSubmenu(target: AnyObject?) -> NSMenu {
        let submenu = NSMenu()

        for account in settings.accounts {
            let item = NSMenuItem(
                title: account.displayName,
                action: #selector(MenuBarManager.switchAccount(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = account

            // The currently selected account shows a checkmark
            if account.id == settings.currentAccountId {
                item.state = .on
            }

            submenu.addItem(item)
        }

        return submenu
    }

    /// Create the Codex account picker submenu
    private func createCodexAccountSubmenu(target: AnyObject?) -> NSMenu {
        let submenu = NSMenu()

        for account in settings.codexAccounts {
            let item = NSMenuItem(
                title: account.displayName,
                action: #selector(MenuBarManager.switchCodexAccount(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = account

            if account.id == settings.currentCodexAccountId {
                item.state = .on
            }

            submenu.addItem(item)
        }

        return submenu
    }

    /// Create the rainbow text NSAttributedString
    /// - Parameters:
    ///   - text: the full text
    ///   - highlightRange: the range to highlight
    /// - Returns: attributed string with the rainbow effect
    private func createRainbowText(_ text: String, highlightRange: NSRange) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)

        let font = NSFont.menuFont(ofSize: 0)
        attributedString.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.utf16.count))

        let paragraphStyle = NSMutableParagraphStyle()
        let nsText = text as NSString
        let baseText = nsText.substring(to: highlightRange.location)
        let baseTextSize = (baseText as NSString).size(withAttributes: [.font: font])

        let tabLocation = baseTextSize.width + 20
        let tabStop = NSTextTab(textAlignment: .left, location: tabLocation, options: [:])
        paragraphStyle.tabStops = [tabStop]

        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: text.utf16.count))

        let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
        let highlightText = nsText.substring(with: highlightRange) as String

        var utf16Offset = 0
        for (index, char) in highlightText.enumerated() {
            let charString = String(char)
            let charUtf16Count = charString.utf16.count
            let colorIndex = index % colors.count

            attributedString.addAttribute(
                .foregroundColor,
                value: colors[colorIndex],
                range: NSRange(location: highlightRange.location + utf16Offset, length: charUtf16Count)
            )

            utf16Offset += charUtf16Count
        }

        return attributedString
    }

    /// Create the badge icon (small red dot)
    /// - Returns: the icon with its badge
    private func createBadgeIcon() -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        if let icon = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) {
            icon.size = NSSize(width: 12, height: 12)
            icon.draw(in: NSRect(x: 0, y: 2, width: 12, height: 12))
        }

        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 10, y: 10, width: 6, height: 6)).fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Icon Management

    /// Update the menu bar icon
    /// - Parameters:
    ///   - usageData: Claude usage data
    ///   - codexUsageData: Codex usage data
    ///   - hasUpdate: whether an update is available
    ///   - shouldShowBadge: whether to show the update badge
    func updateMenuBarIcon(usageData: UsageData?, codexUsageData: CodexUsageData? = nil, hasUpdate: Bool, shouldShowBadge: Bool) {
        guard let button = statusItem.button else { return }

        // Decide whether the badge is actually shown
        let showBadge = hasUpdate && shouldShowBadge

        // Build the cache key
        let cacheKey = generateCacheKey(usageData: usageData, codexUsageData: codexUsageData, hasUpdate: showBadge)

        // Shared re-render closure for the per-display fixes. Appearance comes solely from
        // UsageColorScheme.drawingIsDarkOverride, so button is nil on purpose. Captures
        // iconRenderer instead of self to avoid a retain cycle via lastReplicantRender.
        let render: (Bool) -> NSImage = { [iconRenderer] _ in
            iconRenderer.createIcon(
                usageData: usageData,
                codexUsageData: codexUsageData,
                hasUpdate: showBadge,
                button: nil
            )
        }

        // Template path: cache as before, AppKit tints and dims templates per display itself
        if let cachedImage = iconCache[cacheKey], cachedImage.isTemplate {
            button.image = cachedImage
            lastRender = nil
            return
        }

        // Probe render decides template vs color and fixes the size for the dynamic wrapper
        let probe = iconRenderer.createIcon(
            usageData: usageData,
            codexUsageData: codexUsageData,
            hasUpdate: showBadge,
            button: button
        )

        if probe.isTemplate {
            // Store it in the cache (FIFO eviction, rather than the random eviction an unordered Dictionary walk gives)
            if iconCache.count >= maxCacheSize, !iconCacheOrder.isEmpty {
                let oldestKey = iconCacheOrder.removeFirst()
                iconCache.removeValue(forKey: oldestKey)
            }
            iconCache[cacheKey] = probe
            iconCacheOrder.append(cacheKey)
            button.image = probe
            lastRender = nil
            return
        }

        // Color path: a fresh dynamic wrapper every update. Wrapper creation is free (the
        // rendering happens lazily per bar draw), and a fresh instance keeps the baked-in
        // dim state current. Only the main button is ever written; AppKit mirrors it to
        // the other bars and the wrapper resolves appearance and dim per draw. Writing to
        // the replicant windows directly makes Control Center hide the item, see
        // MenuBarPerDisplayIcon's header.
        lastRender = render
        lastIconSize = probe.size
        lastActiveBarUUID = MenuBarPerDisplayIcon.activeMenuBarDisplayUUID()
        button.image = MenuBarPerDisplayIcon.dynamicImage(size: probe.size, render: render)
    }

    /// Rebuild the dynamic wrapper when the active menu bar display changed, so the dim
    /// baked into its per-appearance cache tracks focus. No-op otherwise.
    ///
    /// The rebuild alone only reaches the bar hosting the real item. The replicant bars on
    /// other displays keep a snapshot that nothing refreshes: not reassignment, not
    /// needsDisplay, not pixel changes, only item (re)creation (all verified live). So a
    /// visibility blip forces the system to rebuild the snapshots. Public API, fired only
    /// on an actual focus-display change, rate-limited to stay far away from the rapid
    /// write patterns that make Control Center pull the item.
    private func refreshDimIfNeeded() {
        guard let render = lastRender, let size = lastIconSize,
              let button = statusItem.button else { return }
        let current = MenuBarPerDisplayIcon.activeMenuBarDisplayUUID()
        guard current != lastActiveBarUUID else { return }
        lastActiveBarUUID = current
        button.image = MenuBarPerDisplayIcon.dynamicImage(size: size, render: render)

        // Blip visibility to re-snapshot the replicant bars, at most once per 5s
        let now = Date()
        guard now.timeIntervalSince(lastVisibilityBlip) > 5 else { return }
        lastVisibilityBlip = now
        statusItem.isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.statusItem.isVisible = true
        }
    }

    /// Clear the icon cache
    func clearIconCache() {
        iconCache.removeAll()
        iconCacheOrder.removeAll()
    }

    /// Build the icon cache key
    /// - Parameters:
    ///   - usageData: Claude usage data
    ///   - codexUsageData: Codex usage data
    ///   - hasUpdate: whether the update badge is shown
    /// - Returns: the cache key string
    private func generateCacheKey(usageData: UsageData?, codexUsageData: CodexUsageData? = nil, hasUpdate: Bool) -> String {
        let isMulti = settings.isMultiProviderActive
        // The remaining/used display flips the rendered glyph and sweep without changing the data, so it has to be part of the key
        let remainingFlag = settings.showRemainingPercentage ? "_rem" : ""

        // The period tick moves with the clock, not with the data, so a key built only from
        // percentages would keep serving the old image and freeze the tick in place. Quantised to
        // whole percent: one step is about 3 minutes of a 5h window, current enough without
        // rebuilding the icon on every poll.
        func markerToken(_ label: String, _ resetsAt: Date?, _ type: LimitType) -> String {
            guard let fraction = iconRenderer.timeMarkerFraction(resetsAt: resetsAt, type: type) else { return "" }
            return "_\(label)m\(Int(fraction * 100))"
        }

        // Pace-aware colours also move with the clock rather than with the data, so the escalation
        // figure has to be in the key too, for the same reason as the tick.
        func paceToken(_ label: String, _ percentage: Double, _ resetsAt: Date?, _ type: LimitType) -> String {
            guard settings.paceAwareBarColors else { return "" }
            // The ramp *step*, not the projected figure. The projection is clamped to 100, so two
            // very different paces can share a figure while landing on different colours; keying
            // on the figure would then serve a stale icon in exactly the case the colour changed.
            let step = UsagePaceStatus.color(usedPercentage: percentage, resetsAt: resetsAt, type: type)
            return "_\(label)p\(step.rawValue)"
        }
        guard let data = usageData else {
            var key = "no_data_\(settings.iconDisplayMode.rawValue)_\(settings.iconStyleMode.rawValue)_\(settings.displayMode.rawValue)_mp\(isMulti)\(remainingFlag)"
            if let codex = codexUsageData {
                let activeTypes = settings.getActiveDisplayTypes(usageData: nil, codexUsageData: codex, forMenuBar: true)
                    .map(\.rawValue)
                    .sorted()
                    .joined(separator: ",")
                key += "_types\(activeTypes)"

                if let primary = codex.primary {
                    key += "_cxp\(Int(primary.percentage))"
                } else {
                    key += "_cxpnil"
                }

                if let secondary = codex.secondary {
                    key += "_cxs\(Int(secondary.percentage))"
                } else {
                    key += "_cxsnil"
                }

                if let extraUsage = codex.extraUsage {
                    key += "_cxe\(extraUsage.enabled ? 1 : 0)"
                    if let percentage = extraUsage.percentage {
                        key += "_\(Int(percentage))"
                    }
                } else {
                    key += "_cxenil"
                }
            }

            if hasUpdate {
                key += "_badge"
            }

            return key
        }

        var key = "\(settings.iconDisplayMode.rawValue)_\(settings.iconStyleMode.rawValue)_mp\(isMulti)\(remainingFlag)"

        if let fiveHour = data.fiveHour {
            key += "_5h\(Int(fiveHour.percentage))"
            key += markerToken("5h", fiveHour.resetsAt, .fiveHour)
            key += paceToken("5h", fiveHour.percentage, fiveHour.resetsAt, .fiveHour)
        }
        if let sevenDay = data.sevenDay {
            key += "_7d\(Int(sevenDay.percentage))"
            key += markerToken("7d", sevenDay.resetsAt, .sevenDay)
            key += paceToken("7d", sevenDay.percentage, sevenDay.resetsAt, .sevenDay)
        }
        if let opus = data.opus {
            key += "_opus\(Int(opus.percentage))"
            key += markerToken("opus", opus.resetsAt, .opusWeekly)
            key += paceToken("opus", opus.percentage, opus.resetsAt, .opusWeekly)
        }
        if let sonnet = data.sonnet {
            key += "_sonnet\(Int(sonnet.percentage))"
            key += markerToken("sonnet", sonnet.resetsAt, .sonnetWeekly)
            key += paceToken("sonnet", sonnet.percentage, sonnet.resetsAt, .sonnetWeekly)
        }
        if let extraUsage = data.extraUsage, extraUsage.enabled, let percentage = extraUsage.percentage {
            key += "_extra\(Int(percentage))"
        }

        if let codex = codexUsageData {
            if let p = codex.primary {
                key += "_cxp\(Int(p.percentage))"
                key += markerToken("cxp", p.resetsAt, .codexPrimary)
            }
            if let s = codex.secondary {
                key += "_cxs\(Int(s.percentage))"
                key += markerToken("cxs", s.resetsAt, .codexSecondary)
            }
            if let e = codex.extraUsage?.percentage { key += "_cxe\(Int(e))" }
        }

        if hasUpdate {
            key += "_badge"
        }

        return key
    }

    // MARK: - Utility Icons

    /// Create a simple circular icon (fallback)
    /// Used to set up the status item button
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

    // MARK: - Cleanup

    /// Release all resources
    func cleanup() {
        removePopoverCloseObserver()
        removeAppResignActiveObserver()

        if popover.isShown {
            popover.performClose(nil)
        }
    }

    deinit {
        cleanup()
        if let observer = screenParamsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in activeDisplayObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        dimHeartbeat?.invalidate()
    }
}

/// A menu item that refuses the icon macOS puts on it.
///
/// macOS 26 decorates the item it recognises as the standard Settings command with a gear: it
/// assigns a 17x16 template image itself, before `menuWillOpen`, so no amount of not setting an
/// image in `createStandardMenu` removes it. Confirmed by logging every item's `image` at open
/// time: only the Settings row came back non-nil, and nothing in this app had touched it.
///
/// Suppressing it has to happen in the property, not at a call site. Assigning nil after
/// `addItem` is too early (AppKit sets it later) and assigning an empty image leaves the gutter
/// and drops the item's key equivalent. Swallowing the setter and always answering nil is the
/// one point both AppKit's write and its draw have to pass through.
///
/// The item keeps its title, its action and its Cmd-comma, so it is still the standard Settings
/// command for the keyboard and for VoiceOver. Only the glyph is gone.
final class NoAutoIconMenuItem: NSMenuItem {
    override var image: NSImage? {
        get { nil }
        set { _ = newValue }
    }
}
