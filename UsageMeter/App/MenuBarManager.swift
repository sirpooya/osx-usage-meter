//
//  MenuBarManager.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit
import Combine
import OSLog
import Sparkle

/// Refresh state manager
/// Keeps refresh state in sync across views, with reactive updates
class RefreshState: ObservableObject {
    /// Whether a refresh is in flight
    @Published var isRefreshing = false
    /// The provider currently refreshing; nil means a full refresh
    @Published var refreshingProvider: ProviderType?
    /// Whether a refresh is allowed (debounce control)
    @Published var canRefresh = true
    /// Notification message
    @Published var notificationMessage: String?
    /// Notification type
    @Published var notificationType: NotificationType = .loading
    /// Whether the last Claude error was transient (rate limit, network blip, server error).
    /// Transient failures are never worth a UI state of their own: there is a retry coming, so the
    /// popover keeps showing data, or the loading state, and never an error screen.
    @Published var claudeErrorIsTransient = false
    /// When the currently displayed Claude data was actually fetched.
    /// Set from the cached snapshot at launch, then from every successful fetch. The popover uses
    /// it to say how old the numbers are when a refresh fails, instead of hiding them behind an error.
    @Published var lastUpdatedAt: Date?
    
    /// Notification type
    enum NotificationType {
        case loading          // Rainbow loading animation
        case updateAvailable  // Rainbow text notification
    }

    func isRefreshingProvider(_ provider: ProviderType) -> Bool {
        isRefreshing && (refreshingProvider == nil || refreshingProvider == provider)
    }
}

/// Menu bar manager
/// Coordinates the UI and data layers, owns the settings window
class MenuBarManager: ObservableObject {
    // MARK: - Properties

    /// UI manager
    private let ui = MenuBarUI()
    /// Data refresh manager
    private let dataManager = DataRefreshManager()
    /// Settings window
    private var settingsWindow: NSWindow?
    #if DEBUG
    /// The dev-only playground window. Debug builds only, so it cannot reach a release build.
    private var playgroundWindow: NSWindow?
    #endif
    /// User settings instance
    @ObservedObject private var settings = UserSettings.shared
    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    /// Window close observer
    private var windowCloseObserver: NSObjectProtocol?
    /// Language change observer
    private var languageChangeObserver: NSObjectProtocol?

    /// Current usage data (synced from dataManager)
    @Published var usageData: UsageData?
    /// Codex usage data (synced from dataManager)
    @Published var codexUsageData: CodexUsageData?
    /// Loading state (synced from dataManager)
    @Published var isLoading = false
    /// Error message (synced from dataManager)
    @Published var errorMessage: String?
    /// Codex error message (independent of Claude)
    @Published var codexErrorMessage: String?
    /// All three Codex refresh levels failed, the user has to sign in again manually
    @Published var codexNeedsRelogin = false
    /// Whether an update is available (driven by Sparkle's SPUUpdaterDelegate callbacks)
    @Published var hasAvailableUpdate = false
    /// Latest version (from the appcast entry Sparkle found)
    @Published var latestVersion: String?
    /// Version the user has acknowledged (recorded when they click check for updates)
    private var acknowledgedVersion: String?

    /// Refresh state manager (referenced from dataManager)
    var refreshState: RefreshState {
        return dataManager.refreshState
    }

    /// Whether the badge and notification should show (only while the user has not acknowledged)
    var shouldShowUpdateBadge: Bool {
        guard hasAvailableUpdate, let latest = latestVersion else { return false }
        return acknowledgedVersion != latest
    }

    // MARK: - Initialization

    init() {
        ui.configureClickHandler(target: self, action: #selector(handleClick))
        setupDataBindings()
        setupSettingsObservers()
    }

    /// Set up the data bindings
    /// Sync dataManager state into MenuBarManager
    private func setupDataBindings() {
        dataManager.$usageData
            .sink { [weak self] data in
                self?.usageData = data
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        dataManager.$codexUsageData
            .sink { [weak self] data in
                self?.codexUsageData = data
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        dataManager.$isLoading
            .assign(to: &$isLoading)

        dataManager.$errorMessage
            .assign(to: &$errorMessage)

        dataManager.$codexErrorMessage
            .assign(to: &$codexErrorMessage)

        dataManager.$codexNeedsRelogin
            .assign(to: &$codexNeedsRelogin)
    }
    
    /// Handle clicks on the menu bar icon
    /// Left click toggles the popover, right click shows the menu
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            // Treat it as a left click when the current event is unavailable
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    /// Show the right click menu
    private func showMenu() {
        let menu = ui.createStandardMenu(hasUpdate: hasAvailableUpdate, shouldShowBadge: shouldShowUpdateBadge, target: self)
        ui.statusItem.menu = menu
        ui.statusItem.button?.performClick(nil)
        ui.statusItem.menu = nil
    }
    
    
    // MARK: - Menu Actions
    
    @objc func openClaudeStatus() {
        if let url = URL(string: "https://status.claude.com") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openCodexStatus() {
        if let url = URL(string: "https://status.openai.com/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    /// Handle a menu action
    /// Close the popover and run the matching action
    private func handleMenuAction(_ action: UsageDetailView.MenuAction) {
        switch action {
        case .refresh:
            dataManager.handleManualRefresh()
        case .refreshClaude:
            dataManager.handleClaudeOnlyRefresh()
        case .refreshCodex:
            dataManager.handleCodexOnlyRefresh()
        case .generalSettings:
            closePopover()
            openSettingsWindow(tab: 0)
        case .authSettings:
            closePopover()
            openSettingsWindow(tab: 1)
        case .checkForUpdates:
            closePopover()
            checkForUpdates()
        case .about:
            closePopover()
            openSettingsWindow(tab: 3)
        case .claudeStatus:
            closePopover()
            openClaudeStatus()
        case .codexStatus:
            closePopover()
            openCodexStatus()
        case .coffee:
            closePopover()
            if let url = URL(string: "https://ko-fi.com/pooya") {
                NSWorkspace.shared.open(url)
            }
        case .githubSponsor:
            closePopover()
            openGithubSponsor()
        case .codexRelogin:
            closePopover()
            WebLoginWindowManager.shared.showCodexLoginWindow()
        case .quit:
            quitApp()
        }
    }

    /// Set up the settings change observers
    /// Listens for settings changes, refresh interval changes and similar notifications
    private func setupSettingsObservers() {
        // A Combine publisher delivers on whichever thread posted to NotificationCenter, which cannot be assumed to be the main thread
        // (TimerManager and other downstream code need the main RunLoop), so receive(on:) the main thread before handling.
        let settingsChanged = NotificationCenter.default.publisher(for: .settingsChanged)
            .receive(on: DispatchQueue.main)

        // Clearing the icon cache and redrawing needs instant feedback, so no debounce here
        settingsChanged
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Clear the icon cache when settings change (the display mode may have changed)
                self.ui.clearIconCache()

                // Update the icon right away, no waiting
                self.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        #if DEBUG
        // Nearly every setting, customDisplayTypes and iconStyleMode included, posts settingsChanged,
        // but only a change under the debug simulation mode (debugModeEnabled) needs an immediate refresh, because that path reads local
        // mock data (ClaudeAPIService.createMockData) and makes no real network request.
        // When a developer is wiring up the UI against a real account (debugModeEnabled false), settings like customDisplayTypes
        // have nothing to do with usage data and should not trigger real API requests; the previous unconditional fetchUsage() fired
        // a burst of real requests while metrics were being checked and unchecked, which the API read as too many requests (429).
        // The debounce is only a fallback that merges a batch of mock scenario changes (dragging a slider, say), it is not the point of this fix.
        settingsChanged
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.settings.debugModeEnabled {
                    self.dataManager.fetchUsage()
                }

                // When the simulated update switch changes, drive the Sparkle badge state machine directly (no real appcast needed)
                if self.settings.simulateUpdateAvailable {
                    self.hasAvailableUpdate = true
                    self.latestVersion = "2.0.0"
                    self.updateMenuBarIcon()
                    Logger.menuBar.debug("Simulated update enabled")
                } else {
                    self.hasAvailableUpdate = false
                    self.latestVersion = nil
                    self.updateMenuBarIcon()
                    Logger.menuBar.debug("Simulated update disabled")
                }
            }
            .store(in: &cancellables)
        #endif

        NotificationCenter.default.publisher(for: .refreshIntervalChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Restart the data refresh timer
                self?.dataManager.stopRefreshing()
                self?.dataManager.startRefreshing()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .openSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let tab = notification.userInfo?["tab"] as? Int ?? 0
                self?.openSettingsWindow(tab: tab)
            }
            .store(in: &cancellables)

        // Listen for account change notifications
        NotificationCenter.default.publisher(for: .accountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                Logger.menuBar.notice("Account switched, refreshing data")
                let providerRaw = notification.userInfo?[Notification.UserInfoKey.provider] as? String
                let provider = providerRaw.flatMap { ProviderType(rawValue: $0) }
                // Clear the icon cache so new data is rendered fresh
                self.ui.clearIconCache()
                // Refresh only the provider that changed, so the other one's data and notification state are not wiped by mistake
                self.dataManager.handleAccountChanged(provider: provider)
                // Update the menu bar icon
                self.updateMenuBarIcon()
            }
            .store(in: &cancellables)
    }

    // MARK: - Popover Management

    /// Toggle the popover
    @objc func togglePopover() {
        guard let button = ui.statusItem.button else { return }

        if ui.popover.isShown {
            closePopover()
        } else {
            openPopover(relativeTo: button)
        }
    }

    /// Open the popover
    private func openPopover(relativeTo button: NSStatusBarButton) {
        // Smart data refresh
        dataManager.refreshOnPopoverOpen()

        // Show the update notification (if any)
        showUpdateNotificationIfNeeded()

        // Create and install the content view
        ui.setPopoverContent(UsageDetailView(
            usageData: Binding(
                get: { self.usageData },
                set: { self.usageData = $0 }
            ),
            codexUsageData: Binding(
                get: { self.codexUsageData },
                set: { self.codexUsageData = $0 }
            ),
            errorMessage: Binding(
                get: { self.errorMessage },
                set: { self.errorMessage = $0 }
            ),
            codexErrorMessage: Binding(
                get: { self.codexErrorMessage },
                set: { self.codexErrorMessage = $0 }
            ),
            codexNeedsRelogin: Binding(
                get: { self.codexNeedsRelogin },
                set: { _ in }
            ),
            refreshState: self.refreshState,
            onMenuAction: { [weak self] action in
                self?.handleMenuAction(action)
            },
            hasAvailableUpdate: Binding(
                get: { self.hasAvailableUpdate },
                set: { self.hasAvailableUpdate = $0 }
            ),
            shouldShowUpdateBadge: Binding(
                get: { self.shouldShowUpdateBadge },
                set: { _ in }
            )
        ))

        // Open the popover
        ui.openPopover(relativeTo: button)

        // Start the refresh timer
        startPopoverRefreshTimer()
    }

    /// Show the update notification (if needed)
    private func showUpdateNotificationIfNeeded() {
        guard shouldShowUpdateBadge else { return }

        dataManager.refreshState.notificationMessage = L.Update.Notification.available
        dataManager.refreshState.notificationType = .updateAvailable

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.dataManager.refreshState.notificationMessage = nil
        }
    }

    /// Close the popover
    private func closePopover() {
        ui.closePopover()

        // Tear down the refresh timer
        dataManager.stopPopoverRefreshTimer()
    }

    /// Update the popover content
    private func updatePopoverContent() {
        objectWillChange.send()
    }

    /// Start the popover refresh timer
    private func startPopoverRefreshTimer() {
        dataManager.startPopoverRefreshTimer { [weak self] in
            self?.updatePopoverContent()
        }
    }
    
    // MARK: - Data Fetching

    /// Start a data refresh
    func startRefreshing() {
        dataManager.startRefreshing()
    }
    
    // MARK: - Settings Window
    
    #if DEBUG
    /// Opens the welcome setup playground: the deleted welcome flow second page at its real size.
    /// Reached from the status item menu's "Welcome Setup Playground" item in debug builds.
    @objc func openWelcomeSetupPlayground() {
        if playgroundWindow == nil {
            NSApp.setActivationPolicy(.regular)

            let controller = NSHostingController(rootView: WelcomeSetupPlaygroundView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Welcome Setup Playground"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 980, height: 700))
            window.setFrameAutosaveName("UsageMeter.WelcomeSetupPlayground")
            window.isReleasedWhenClosed = false
            playgroundWindow = window

            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.playgroundWindow = nil
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        playgroundWindow?.makeKeyAndOrderFront(nil)
        playgroundWindow?.center()
    }
    #endif

    @objc func openSettings() {
        openSettingsWindow(tab: 0)
    }

    @objc func openGeneralSettings() {
        openSettingsWindow(tab: 0)
    }

    @objc func openAuthSettings() {
        openSettingsWindow(tab: 1)
    }

    @objc func openAbout() {
        openSettingsWindow(tab: 3)
    }

    @objc func openCoffee() {
        if let url = URL(string: "https://ko-fi.com/pooya") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openGithubSponsor() {
        if let url = URL(string: "https://github.com/sponsors/f-is-h?frequency=one-time") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Switch account
    /// - Parameter sender: the menu item, whose representedObject holds the Account
    @objc func switchAccount(_ sender: NSMenuItem) {
        guard let account = sender.representedObject as? Account else {
            Logger.menuBar.error("Account switch failed: could not read the account info")
            return
        }

        settings.switchToAccount(account)
    }

    /// Switch Codex account
    @objc func switchCodexAccount(_ sender: NSMenuItem) {
        guard let account = sender.representedObject as? Account else { return }
        settings.switchToCodexAccount(account)
    }

    @objc func checkForUpdates() {
        // Record that the user acknowledged this version, hiding the badge and rainbow text
        if let version = latestVersion {
            acknowledgedVersion = version
            objectWillChange.send()
            updateMenuBarIcon()
        }

        // Hand off to Sparkle: the modal dialog, download progress, EdDSA signature check and relaunch are all its job.
        // The controller is reached through AppDelegate.shared because `NSApp.delegate as? AppDelegate`
        // cannot be cast reliably once NSApplicationDelegateAdaptor has wrapped it.
        guard let appDelegate = AppDelegate.shared else {
            Logger.menuBar.error("checkForUpdates: AppDelegate.shared not set")
            return
        }
        appDelegate.updaterController.checkForUpdates(self)
    }
    
    // MARK: - Update Status (driven by Sparkle)

    /// Called when Sparkle finds an update: lights up the badge / rainbow text state machine.
    func applyUpdateAvailable(version: String?) {
        hasAvailableUpdate = true
        latestVersion = version
        updateMenuBarIcon()
    }

    /// Called when Sparkle finds no update: clears the badge state.
    func applyUpdateNotFound() {
        hasAvailableUpdate = false
        latestVersion = nil
        updateMenuBarIcon()
    }

    /// Open the settings window
    /// - Parameter tab: index of the tab to show (0: General, 1: Authentication, 2: History, 3: About)
    private func openSettingsWindow(tab: Int) {
        if settingsWindow == nil {
            // Switch to regular mode so the app appears in the Dock
            NSApp.setActivationPolicy(.regular)
            
            let settingsView = SettingsView(initialTab: tab)
            let hostingController = NSHostingController(rootView: settingsView)
            
            settingsWindow = NSWindow(
                contentViewController: hostingController
            )
            // No title text and a transparent, full-size-content titlebar, matching the other
            // osx-* apps' settings windows: the selected tab already names what you're looking
            // at, and the tab bar sits at the very top instead of below an empty 28pt band.
            // The close button floats over the bar's left end, which is clear because the tab
            // group is centred.
            settingsWindow?.title = ""
            settingsWindow?.titleVisibility = .hidden
            settingsWindow?.titlebarAppearsTransparent = true
            settingsWindow?.styleMask = [.titled, .closable, .fullSizeContentView]
            settingsWindow?.standardWindowButton(.miniaturizeButton)?.isHidden = true
            settingsWindow?.standardWindowButton(.zoomButton)?.isHidden = true
            // The titlebar band is covered by the SwiftUI tab bar, so background dragging is
            // what keeps the window movable. The panes use stock AppKit controls, which win
            // their mouse-down race against a background drag.
            settingsWindow?.isMovableByWindowBackground = true
            settingsWindow?.setFrameAutosaveName("UsageMeter.SettingsWindow")
            // The autosave restore happens here, carrying whatever size the window had the last
            // time it closed. That would override a change to SettingsView.contentSize, so
            // re-apply it: the size is fixed and owned by the view, only the position is restored.
            settingsWindow?.setContentSize(SettingsView.contentSize)

            // Remove the old observer (if there is one)
            if let observer = windowCloseObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            
            // Add the window close observer
            windowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: settingsWindow,
                queue: .main
            ) { [weak self] _ in
                // Switch back to accessory mode when the window closes (no Dock icon)
                NSApp.setActivationPolicy(.accessory)

                self?.settingsWindow = nil
                if self?.settings.hasAnyValidCredentials == true
                    && self?.usageData == nil
                    && self?.codexUsageData == nil {
                    self?.startRefreshing()
                }
            }

            // Add the window focus observer, closing the popover when the settings window becomes key
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: settingsWindow,
                queue: .main
            ) { [weak self] _ in
                #if DEBUG
                // Debug mode: do not auto close when "keep detail window open" is enabled
                if UserSettings.shared.debugKeepDetailWindowOpen {
                    return
                }
                #endif

                if self?.ui.popover.isShown == true {
                    self?.closePopover()
                }
            }

            // No language change observer any more: the window carries no title text.
        }

        // Activate the app first, then center and show the window
        NSApp.activate(ignoringOtherApps: true)

        // Wait a moment so the window is centered only after activation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.settingsWindow?.center()
            self?.settingsWindow?.makeKeyAndOrderFront(nil)
        }

        if ui.popover.isShown {
            closePopover()
        }
    }
    
    // MARK: - Icon Management

    /// Update the menu bar icon
    private func updateMenuBarIcon() {
        ui.updateMenuBarIcon(usageData: usageData, codexUsageData: codexUsageData, hasUpdate: hasAvailableUpdate, shouldShowBadge: shouldShowUpdateBadge)
    }
    
    // MARK: - Cleanup
    
    /// Release all resources
    /// Called when the app quits, stops every timer and removes every observer
    func cleanup() {
        // Stop the popover refresh timer
        dataManager.stopPopoverRefreshTimer()

        // Tear down the window observers
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            windowCloseObserver = nil
        }

        // Tear down the language change observer
        if let observer = languageChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            languageChangeObserver = nil
        }

        // Cancel every Combine subscription
        cancellables.removeAll()

        // Tear down the UI
        ui.cleanup()

        // Tear down the data manager
        dataManager.cleanup()

        // Close the window
        settingsWindow?.close()
        settingsWindow = nil
    }
    
    deinit {
        cleanup()
    }
}
