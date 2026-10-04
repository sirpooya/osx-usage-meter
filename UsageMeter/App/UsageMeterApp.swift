//
//  UsageMeterApp.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import Combine
import Sparkle

/// Usage Meter app entry point
@main
struct UsageMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // The empty Settings scene above only exists because an App needs a scene. Left alone,
            // its default Cmd+, command opens it as a blank "Usage Meter Settings" window, so the
            // command is replaced with one that opens the real AppKit settings window.
            CommandGroup(replacing: .appSettings) {
                Button(L.Menu.settings) {
                    AppDelegate.shared?.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// App delegate
/// Owns the app lifecycle, resource setup and teardown
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    /// Shared app delegate instance
    /// SwiftUI's NSApplicationDelegateAdaptor wraps the delegate, so
    /// `NSApp.delegate as? AppDelegate` cannot reliably return this type; MenuBarManager
    /// needs this static reference to call `updaterController.checkForUpdates(_:)`.
    static weak var shared: AppDelegate?

    /// Keep this the first stored property. Stored properties initialize in declaration order,
    /// and the pre-rename ClaudeUsage data has to be copied into place before `settings`
    /// below loads `UserSettings.shared`.
    private let legacyRenameMigration: Void = LegacyRenameMigration.runIfNeeded()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    /// Menu bar manager, owns everything menu bar related
    private var menuBarManager: MenuBarManager!

    /// Welcome window, shown on first launch
    private var welcomeWindow: NSWindow?

    /// User settings instance
    private let settings = UserSettings.shared

    /// Sparkle updater controller
    /// - `startingUpdater: true` lets Sparkle check in the background on its own, following
    ///   SUEnableAutomaticChecks / SUScheduledCheckInterval from Info.plist (24 hours by default)
    /// - `updaterDelegate: self` makes AppDelegate the SPUUpdaterDelegate, forwarding
    ///   `didFindValidUpdate` / `updaterDidNotFindUpdate` to the menu bar badge state machine,
    ///   so the rainbow text / red dot badge coexists with Sparkle's own modal dialog; EdDSA
    ///   signature checking still goes through SUPublicEDKey in Info.plist
    /// - Exposed as internal so MenuBarManager can reach it via `AppDelegate.shared`
    ///
    /// Built after super.init() inside init(): updaterDelegate needs self, and Swift
    /// forbids referencing self in a stored property initializer (still well before any background check).
    private(set) var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()

        // Install crash capture as early as possible: any fatal error before this line is invisible,
        // and launch is exactly where things tend to die. install() is idempotent.
        CrashReporter.install()

        AppDelegate.shared = self
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Combine subscriptions, so observer lifetimes are managed automatically
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Application Lifecycle
    
    /// Called once the app has finished launching
    /// Sets up the menu bar manager, then either shows the welcome window or starts refreshing data
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Work out how the previous run ended before doing anything else.
        // This one log line is the answer to "why did it suddenly quit".
        reportPreviousSessionOutcome()

        // Memory pressure is the main reason an .accessory app gets killed silently by jetsam,
        // and the system writes no crash report in that case. Record pressure events here
        // so they line up in time with a killed verdict from SessionSentinel.
        observeMemoryPressure()

        // Request notification permission
        NotificationManager.shared.requestPermission()

        menuBarManager = MenuBarManager()

        #if DEBUG
        // Dev only: `defaults write in.pooya.usagemeter openPlaygroundAtLaunch -bool true`
        // opens the welcome setup playground straight away, so the window can be reached without
        // clicking through the status item menu (which an .accessory app hides from AX scripting).
        if UserDefaults.standard.bool(forKey: "openPlaygroundAtLaunch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.menuBarManager.openWelcomeSetupPlayground()
            }
        }
        #endif

        // Before the login window, try to adopt the account Claude Code CLI already signed in.
        // When the Keychain already holds usable credentials the user sees no window at all (and pastes no key).
        Task { @MainActor in
            let syncedFromCLI = await ClaudeCodeSyncService.shared.syncOnLaunchIfNeeded()
            if syncedFromCLI {
                // A usable account is already in hand, so the first launch onboarding has no reason to exist
                self.settings.isFirstLaunch = false
                logInfo("CLI account synced from the Claude Code keychain. Skipping the welcome window")
            }

            if self.settings.isFirstLaunch || !self.settings.hasAnyValidCredentials {
                self.showWelcomeWindow()
            } else {
                self.menuBarManager.startRefreshing()
            }
        }

        // Subscribe to notifications with Combine so lifetimes are managed automatically
        NotificationCenter.default.publisher(for: .openSettings)
            .sink { [weak self] notification in
                self?.openSettingsFromNotification(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.settings.syncLaunchAtLoginStatus()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Diagnostics

    /// Memory pressure source. Must be held strongly, otherwise it is released immediately and no event ever arrives.
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// Work out and record how the previous run ended.
    ///
    /// The three outcomes point at three completely different investigations, so keep them apart:
    /// - crashed: a bug in the app itself, read the backtrace
    /// - killed: an external cause (memory pressure / force quit / logout), the app code may be innocent
    /// - clean: normal exit, nothing to investigate
    private func reportPreviousSessionOutcome() {
        let outcome = SessionSentinel.shared.begin()

        switch outcome {
        case .firstRun, .clean:
            logInfo("Session start. \(outcome.summary)")
        case .crashed(let report):
            // The error level is flushed synchronously, so this line has to survive
            logError("ABNORMAL EXIT. \(outcome.summary)")
            for frame in report.frames.prefix(24) {
                logError("  frame: \(frame)")
            }
        case .killed:
            logError("ABNORMAL EXIT. \(outcome.summary)")
            logError("  No crash report means the process did not crash. Check Console.app for jetsam, and Control Center for a blocked status item.")
        }
    }

    /// Record a memory pressure event.
    /// A killed verdict plus one critical pressure record is close to proof of jetsam.
    private func observeMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler {
            let footprint = SessionSentinel.residentFootprint() / (1024 * 1024)
            let event = source.data.contains(.critical) ? "critical" : "warning"
            Task { @MainActor in
                logError("Memory pressure \(event). Footprint \(footprint) MB. A kill may follow.")
            }
        }
        source.activate()
        memoryPressureSource = source
    }

    // MARK: - Private Methods

    /// Show the welcome window
    /// Called on first launch, or when no authentication is configured
    private func showWelcomeWindow() {
        NSApp.setActivationPolicy(.regular)

        let welcomeView = WelcomeView()
        let hostingController = NSHostingController(rootView: welcomeView)

        welcomeWindow = NSWindow(
            contentViewController: hostingController
        )
        welcomeWindow?.title = L.Window.loginTitle
        welcomeWindow?.styleMask = [.titled, .closable]

        // Do not use center(): it computes from the window size at call time, while SwiftUI's fixed frame
        // only lands after Auto Layout, so the window then shrinks from its top left corner and keeps the wrong origin, sitting too high and too far left.
        // Instead compute the final frame from the content size we already know, setting size and position in one go.
        if let window = welcomeWindow, let screen = NSScreen.main {
            let contentRect = NSRect(origin: .zero, size: WelcomeView.contentSize)
            let frameSize = window.frameRect(forContentRect: contentRect).size
            // Center horizontally on the whole screen (true optical center, unaffected by which edge the Dock is on),
            // and vertically on the visible frame (avoids the menu bar, which would otherwise bias it upward).
            let origin = NSPoint(
                x: screen.frame.midX - frameSize.width / 2,
                y: screen.visibleFrame.midY - frameSize.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: frameSize), display: false)
        }

        // Subscribe to the window close notification with Combine
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: welcomeWindow)
            .sink { _ in
                // The window no longer has a Finish or Skip button, so closing it is what ends first time setup,
                // otherwise it would pop up again on the next launch.
                UserSettings.shared.isFirstLaunch = false
                NSApp.setActivationPolicy(.accessory)
            }
            .store(in: &cancellables)

        welcomeWindow?.makeKeyAndOrderFront(nil)
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Handle the open settings notification
    /// Close the welcome window and start refreshing if authentication is configured
    /// Opens the real settings window (General tab); used by the Cmd+, command.
    func openSettingsWindow() {
        menuBarManager?.openSettings()
    }

    private func openSettingsFromNotification(_ notification: Notification) {
        welcomeWindow?.close()
        welcomeWindow = nil

        if settings.hasAnyValidCredentials {
            menuBarManager.startRefreshing()
        }
    }
    
    /// Called just before the app quits
    /// Tear down timers and window resources
    /// Note: Combine subscriptions are cleaned up automatically when cancellables is released
    func applicationWillTerminate(_ notification: Notification) {
        // Mark this as a clean exit. Without this step the next launch treats it as a kill,
        // which turns every quit into a bogus abnormal record.
        logInfo("Session ending cleanly.")
        SessionSentinel.shared.markCleanExit()

        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        menuBarManager?.cleanup()
        welcomeWindow?.close()
        welcomeWindow = nil
        cancellables.removeAll()

        // One last flush, so trailing log lines do not sit in the queue
        DiagnosticLogger.shared.flush()
    }
}

// MARK: - SPUUpdaterDelegate

extension AppDelegate: SPUUpdaterDelegate {
    /// Called when Sparkle finds an update, in a background or manual check: lights up the menu bar badge /
    /// rainbow text state machine, alongside Sparkle's own "update available" modal dialog.
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        menuBarManager?.applyUpdateAvailable(version: item.displayVersionString)
    }

    /// Called when a Sparkle check finds no update: clears any leftover badge state.
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        menuBarManager?.applyUpdateNotFound()
    }
}
