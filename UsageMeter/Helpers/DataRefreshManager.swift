//
//  DataRefreshManager.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine
import OSLog
import AppKit

/// Data refresh manager
/// Owns every data refresh, timer, update check and reset validation
class DataRefreshManager: ObservableObject {

    // MARK: - Dependencies

    /// Claude API service instance
    private let apiService = ClaudeAPIService()
    /// Codex API service instance
    private let codexApiService = CodexAPIService()
    /// Timer manager
    private let timerManager = TimerManager()
    /// User settings instance
    private let settings = UserSettings.shared

    // MARK: - Published State

    /// Claude usage data
    @Published var usageData: UsageData?
    /// Codex usage data (nil means no Codex account, or a failed fetch)
    @Published var codexUsageData: CodexUsageData?
    /// Loading state
    @Published var isLoading = false
    /// Error message
    @Published var errorMessage: String?
    /// Codex error message (separate from Claude, so it is not hidden silently in dual provider mode)
    @Published var codexErrorMessage: String?
    /// Refresh state manager
    let refreshState = RefreshState()

    // MARK: - Private State

    /// Claude's previous reset time (used to detect a completed reset)
    private var lastResetsAt: Date?
    /// Codex's previous reset time
    private var lastCodexResetsAt: Date?
    /// Time of the last manual refresh
    private var lastManualRefreshTime: Date?
    /// Time of the last API request
    private var lastAPIFetchTime: Date?
    /// When the refresh animation started (used to enforce a minimum visible duration)
    private var refreshAnimationStartTime: Date?
    /// Minimum animation duration (seconds)
    private let minimumAnimationDuration: TimeInterval = 1.0
    /// App Nap protection activity token
    private var refreshActivity: NSObjectProtocol?
    /// System wake observer token
    private var wakeObserver: NSObjectProtocol?
    /// All three Codex refresh levels failed, the user has to sign in again manually
    /// Exposed to the UI layer so it can show a "sign in again" button
    @Published private(set) var codexNeedsRelogin = false
    /// The Codex expiry notification has been sent, so it is not repeated
    private var codexSessionExpiredNotified = false
    /// While set, automatic polls are skipped: the server told us to back off (429).
    /// Manual refreshes still go through, because the user explicitly asked.
    private var claudeBackoffUntil: Date?
    /// How long to sit out after a 429. The endpoint's own window is not exposed, so this is a
    /// deliberately unaggressive guess. Never poll faster than this after being told to stop.
    private let rateLimitBackoff: TimeInterval = 10 * 60
    /// UserDefaults keys for the last good snapshot, so a cold start has something to show
    private let cachedUsageKey = "cachedClaudeUsage"
    private let cachedUsageAtKey = "cachedClaudeUsageAt"

    private var shouldFetchClaudeUsage: Bool {
        #if DEBUG
        if shouldSuppressDebugClaudeUsageForDisplayOptions {
            return false
        }
        return settings.debugModeEnabled || settings.hasValidCredentials
        #else
        return settings.hasValidCredentials
        #endif
    }

    private var shouldSuppressDebugClaudeUsageForDisplayOptions: Bool {
        #if DEBUG
        return settings.debugModeEnabled
            && settings.displayMode == .custom
            && !settings.customDisplayMenuBarOnly
            && !settings.customDisplayTypes.contains { $0.provider == .claude }
        #else
        return false
        #endif
    }

    private var shouldSuppressDebugCodexUsageForDisplayOptions: Bool {
        #if DEBUG
        return settings.debugModeEnabled
            && settings.displayMode == .custom
            && !settings.customDisplayMenuBarOnly
            && !settings.customDisplayTypes.contains { $0.provider == .codex }
        #else
        return false
        #endif
    }

    private var shouldFetchCodexUsage: Bool {
        #if DEBUG
        if shouldSuppressDebugCodexUsageForDisplayOptions {
            return false
        }
        return settings.debugModeEnabled || settings.hasValidCodexCredentials
        #else
        return settings.hasValidCodexCredentials
        #endif
    }

    /// Timer identifiers all live in TimerManager.Identifier, so the two sides cannot drift apart
    private typealias TimerID = TimerManager.Identifier

    // MARK: - Initialization

    init() {
        setupWakeObserver()
        restoreCachedUsage()
    }

    // MARK: - Data Fetching

    /// Fetch usage data (Claude and Codex concurrently)
    /// - Parameter isManual: the user asked for this one, so it ignores the 429 backoff window
    func fetchUsage(isManual: Bool = false) {
        let claudeAvailable = shouldFetchClaudeUsage
        let codexAvailable = shouldFetchCodexUsage

        // A 429 means the server asked us to stop, so automatic polls sit out the backoff window.
        // Note this only skips the *request*: the cached data stays on screen either way.
        let claudeBackedOff = !isManual && claudeAvailable && isWithinClaudeBackoff
        if claudeBackedOff && !codexAvailable {
            Logger.menuBar.debug("Automatic poll skipped, still inside the rate limit backoff window")
            return
        }

        isLoading = true
        // Only clear the Claude note when we are actually about to retry Claude, otherwise a
        // Codex-only round would silently drop a rate limit note that still applies.
        if claudeAvailable && !claudeBackedOff {
            errorMessage = nil
        }
        codexErrorMessage = nil
        lastAPIFetchTime = Date()

        let fetchClaude = claudeAvailable && !claudeBackedOff
        let fetchCodex = codexAvailable

        // Clear only when the account itself is gone. A failed or skipped fetch keeps the last
        // good data, which is the whole point of caching it.
        if !claudeAvailable {
            clearClaudeUsageState()
        }
        if !fetchCodex {
            clearCodexUsageState()
        }

        guard fetchClaude || fetchCodex else {
            isLoading = false
            endRefreshAnimationWithMinimumDuration { }
            errorMessage = UsageError.noCredentials.localizedDescription
            return
        }

        // Claude and Codex are fetched concurrently: both child tasks start immediately and the results are awaited in order on the MainActor
        // (audit report 4.2: replaces the old DispatchGroup plus a shared mutable result variable across threads)
        let claudeTask: Task<Result<UsageData, Error>, Never>? =
            fetchClaude ? Task { await self.apiService.fetchUsageResult() } : nil
        let codexTask: Task<Result<CodexUsageData, Error>, Never>? =
            fetchCodex ? Task { await self.codexApiService.fetchUsageResult() } : nil

        Task { @MainActor [weak self] in
            let claudeResult = await claudeTask?.value
            let codexResult = await codexTask?.value

            guard let self = self else { return }
            self.isLoading = false
            self.endRefreshAnimationWithMinimumDuration { }

            var monitoringUtilizations: [ProviderType: Double] = [:]
            if fetchCodex {
                switch codexResult {
                case .success(let codex):
                    if let utilization = self.monitoringUtilization(for: codex) {
                        monitoringUtilizations[.codex] = utilization
                    }
                    self.processCodexSuccess(codex)

                case .failure(let error):
                    Logger.menuBar.info("Codex request failed (does not affect core functionality): \(error.localizedDescription)")
                    if case UsageError.unauthorized = error {
                        self.attemptTokenRefreshAndRetry()
                    } else {
                        // Same rule as Claude: an error annotates the last good data, it does not erase it
                        self.codexErrorMessage = error.localizedDescription
                    }

                case .none:
                    self.clearCodexUsageState()
                }
            } else {
                self.clearCodexUsageState()
            }

            // Handle the Claude result
            if fetchClaude {
                switch claudeResult {
                case .success(let data):
                    let previousData = self.usageData
                    self.usageData = data
                    self.errorMessage = nil
                    self.refreshState.lastUpdatedAt = Date()
                    self.refreshState.claudeErrorIsTransient = false
                    self.claudeBackoffUntil = nil
                    self.persistCachedUsage(data)
                    UsageHistoryStore.shared.record(data)
                    monitoringUtilizations[.claude] = data.percentage

                    if self.settings.notificationsEnabled {
                        NotificationManager.shared.checkAndNotify(usageData: data, previousData: previousData)
                    }

                    let newResetsAt = data.resetsAt
                    let hasResetChanged = hasResetTimeChanged(from: self.lastResetsAt, to: newResetsAt)
                    if hasResetChanged {
                        self.cancelResetVerification()
                    } else if let resetsAt = newResetsAt {
                        self.scheduleResetVerification(resetsAt: resetsAt)
                    }
                    self.lastResetsAt = newResetsAt

                case .failure(let error):
                    // Never drop the numbers we already have. `usageData` is deliberately left
                    // untouched here so the popover and the menu bar icon keep showing the last
                    // good fetch; `errorMessage` is only a note on top of it.
                    self.errorMessage = error.localizedDescription
                    self.refreshState.claudeErrorIsTransient = Self.isTransient(error)
                    if Self.isRateLimit(error) {
                        self.claudeBackoffUntil = Date().addingTimeInterval(self.rateLimitBackoff)
                        Logger.menuBar.info("Claude API rate limited. Pausing automatic polls for \(Int(self.rateLimitBackoff / 60)) min")
                    }
                    Logger.menuBar.error("Claude API request failed: \(error.localizedDescription)")

                case .none:
                    break
                }
            }

            self.settings.updateSmartMonitoringMode(providerUtilizations: monitoringUtilizations)
        }
    }

    private func clearClaudeUsageState() {
        usageData = nil
        lastResetsAt = nil
        cancelResetVerification()
    }

    private func clearCodexUsageState(clearError: Bool = true) {
        codexUsageData = nil
        if clearError {
            codexErrorMessage = nil
        }
        lastCodexResetsAt = nil
        cancelCodexResetVerification()
    }

    private func monitoringUtilization(for codex: CodexUsageData) -> Double? {
        [
            codex.primary?.percentage,
            codex.secondary?.percentage,
            codex.extraUsage?.percentage
        ]
        .compactMap { $0 }
        .max()
    }

    /// Start a data refresh
    /// Fetch once immediately, then start the timers
    func startRefreshing() {
        beginRefreshActivity()
        fetchUsage()
        restartTimer()
        startCodexTokenRefreshTimer()

        #if DEBUG
        // Test: make sure the icon shows a badge
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.objectWillChange.send()
        }
        #endif
    }

    /// Stop refreshing data
    func stopRefreshing() {
        timerManager.invalidate(TimerID.mainRefresh)
        timerManager.invalidate(TimerID.codexTokenRefresh)
        endRefreshActivity()
    }

    /// Start the popover refresh timer
    /// Drives a UI update every second while the popover is open
    /// - Parameter updateHandler: the closure called once a second
    func startPopoverRefreshTimer(updateHandler: @escaping () -> Void) {
        timerManager.schedule(TimerID.popoverRefresh, interval: 1.0, repeats: true) {
            updateHandler()
        }
    }

    /// Stop the popover refresh timer
    func stopPopoverRefreshTimer() {
        timerManager.invalidate(TimerID.popoverRefresh)
    }

    /// Restart the refresh timer
    /// Rebuilds the timer from the user's refresh interval setting
    private func restartTimer() {
        timerManager.invalidate(TimerID.mainRefresh)
        let interval = TimeInterval(settings.effectiveRefreshInterval)
        timerManager.schedule(TimerID.mainRefresh, interval: interval, repeats: true) { [weak self] in
            self?.fetchUsage()
        }
    }

    /// Start the separate Codex accessToken renewal timer (fixed 10 minutes, decoupled from usage fetches)
    private func startCodexTokenRefreshTimer() {
        timerManager.schedule(TimerID.codexTokenRefresh, interval: 10 * 60, repeats: true) { [weak self] in
            self?.codexApiService.proactivelyRefreshIfNeeded()
        }
    }

    // MARK: - App Nap Prevention

    /// Begin the background activity assertion, keeping macOS App Nap from freezing the timers
    private func beginRefreshActivity() {
        guard refreshActivity == nil else { return }
        refreshActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Periodic usage data refresh"
        )
    }

    /// End the background activity assertion
    private func endRefreshActivity() {
        if let activity = refreshActivity {
            ProcessInfo.processInfo.endActivity(activity)
            refreshActivity = nil
        }
    }

    /// Register the system wake observer
    /// Refresh immediately after the system wakes, so a timer paused during sleep does not leave the data stale for a long time
    private func setupWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Logger.menuBar.debug("System woke from sleep, refreshing data immediately")
            // Wait 3 seconds for the network to come back before requesting
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.fetchUsage()
            }
        }
    }

    // MARK: - Smart Refresh

    /// Smart refresh when the popover opens
    /// Refreshes immediately when the last refresh was more than 30 seconds ago
    func refreshOnPopoverOpen() {
        let now = Date()

        // The user opened the detail UI, so force active mode (1 minute refresh)
        if settings.refreshMode == .smart {
            let wasIdle = settings.currentMonitoringMode != .active
            settings.currentMonitoringMode = .active
            settings.unchangedCount = 0
            // Coming from idle mode, the timer has to be restarted for the new interval to apply
            // Otherwise switchToActiveMode() inside updateSmartMonitoringMode returns at its guard and the timer keeps running at the old interval
            if wasIdle {
                restartTimer()
                Logger.menuBar.debug("UI opened: switching from idle to active mode and restarting the timer")
            } else {
                Logger.menuBar.debug("UI opened: already in active mode")
            }
        }

        // Skip when the last refresh was less than 30 seconds ago
        if let lastFetch = lastAPIFetchTime,
           now.timeIntervalSince(lastFetch) < 30 {
            return
        }

        fetchUsage()
    }

    /// Handle a manual refresh
    /// Debounce: at most one refresh per 10 seconds
    func handleManualRefresh() {
        let now = Date()

        // Debounce check: at most one refresh per 10 seconds
        if let lastManual = lastManualRefreshTime,
           now.timeIntervalSince(lastManual) < 10 {
            return
        }

        // The user refreshed on purpose, so force active mode (1 minute refresh)
        if settings.refreshMode == .smart {
            let wasIdle = settings.currentMonitoringMode != .active
            settings.currentMonitoringMode = .active
            settings.unchangedCount = 0
            // Same as refreshOnPopoverOpen: coming from idle mode, the timer has to be restarted
            if wasIdle {
                restartTimer()
                Logger.menuBar.debug("Manual refresh: switching from idle to active mode and restarting the timer")
            } else {
                Logger.menuBar.debug("Manual refresh: already in active mode")
            }
        }

        // Update the state
        lastManualRefreshTime = now
        refreshAnimationStartTime = now  // Record when the animation started
        refreshState.refreshingProvider = nil
        refreshState.isRefreshing = true
        resetCodexReloginState()  // The user refreshed on purpose, so allow another token refresh attempt

        // Arm the debounce
        refreshState.canRefresh = false
        // Release the debounce after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.refreshState.canRefresh = true
        }

        // Kick off the refresh
        fetchUsage(isManual: true)
    }

    /// Refresh Claude data only (triggered by a click on the Claude ring)
    func handleClaudeOnlyRefresh() {
        guard shouldFetchClaudeUsage else { return }
        let now = Date()
        if let lastManual = lastManualRefreshTime,
           now.timeIntervalSince(lastManual) < 10 { return }
        if settings.refreshMode == .smart {
            let wasIdle = settings.currentMonitoringMode != .active
            settings.currentMonitoringMode = .active
            settings.unchangedCount = 0
            if wasIdle { restartTimer() }
        }
        lastManualRefreshTime = now
        refreshAnimationStartTime = now
        refreshState.refreshingProvider = .claude
        refreshState.isRefreshing = true
        refreshState.canRefresh = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.refreshState.canRefresh = true
        }
        fetchClaudeOnly()
    }

    /// Refresh Codex data only (triggered by a click on the Codex ring)
    func handleCodexOnlyRefresh() {
        guard shouldFetchCodexUsage else {
            clearCodexUsageState()
            return
        }
        let now = Date()
        if let lastManual = lastManualRefreshTime,
           now.timeIntervalSince(lastManual) < 10 { return }
        lastManualRefreshTime = now
        refreshAnimationStartTime = now
        refreshState.refreshingProvider = .codex
        refreshState.isRefreshing = true
        refreshState.canRefresh = false
        resetCodexReloginState()  // The user refreshed on purpose, so allow another token refresh attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.refreshState.canRefresh = true
        }
        fetchCodexOnly()
    }

    private func fetchClaudeOnly() {
        guard shouldFetchClaudeUsage else {
            clearClaudeUsageState()
            return
        }
        isLoading = true
        errorMessage = nil
        lastAPIFetchTime = Date()

        // ClaudeAPIService.fetchUsage always calls back on the main thread, so there is no need to wrap this in another DispatchQueue.main.async
        apiService.fetchUsage { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.endRefreshAnimationWithMinimumDuration { }

            switch result {
            case .success(let data):
                let previousData = self.usageData
                self.usageData = data
                self.errorMessage = nil
                Task { @MainActor in
                    UsageHistoryStore.shared.record(data)
                }
                if self.settings.notificationsEnabled {
                    NotificationManager.shared.checkAndNotify(usageData: data, previousData: previousData)
                }
                self.settings.updateSmartMonitoringMode(providerUtilizations: [.claude: data.percentage])
                let newResetsAt = data.resetsAt
                if hasResetTimeChanged(from: self.lastResetsAt, to: newResetsAt) {
                    self.cancelResetVerification()
                } else if let resetsAt = newResetsAt {
                    self.scheduleResetVerification(resetsAt: resetsAt)
                }
                self.lastResetsAt = newResetsAt
            case .failure(let error):
                self.clearClaudeUsageState()
                self.errorMessage = error.localizedDescription
                Logger.menuBar.error("Claude API request failed: \(error.localizedDescription)")
            }
        }
    }

    private func fetchCodexOnly(retryOnUnauthorized: Bool = true) {
        guard shouldFetchCodexUsage else {
            clearCodexUsageState()
            return
        }
        isLoading = true
        codexErrorMessage = nil
        lastAPIFetchTime = Date()

        codexApiService.fetchUsage { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.endRefreshAnimationWithMinimumDuration { }

                switch result {
                case .success(let data):
                    self.processCodexSuccess(data)
                case .failure(let error):
                    if retryOnUnauthorized, case UsageError.unauthorized = error {
                        // A 401 means the cached accessToken is dead, so clear it immediately rather than reusing a broken token next time
                        self.codexApiService.clearAccessTokenCache()
                        self.attemptTokenRefreshAndRetry()
                    } else {
                        self.codexErrorMessage = error.localizedDescription
                        self.clearCodexUsageState(clearError: false)
                        Logger.menuBar.info("Codex request failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func processCodexSuccess(_ data: CodexUsageData) {
        let previousCodexData = codexUsageData
        codexUsageData = data
        codexErrorMessage = nil
        if let utilization = monitoringUtilization(for: data) {
            settings.updateSmartMonitoringMode(providerUtilizations: [.codex: utilization])
        }
        if settings.notificationsEnabled {
            NotificationManager.shared.checkAndNotify(codexUsageData: data, previousData: previousCodexData)
        }
        let newCodexResetsAt = data.primary?.resetsAt
        if hasResetTimeChanged(from: lastCodexResetsAt, to: newCodexResetsAt) {
            cancelCodexResetVerification()
        } else if let resetsAt = newCodexResetsAt {
            scheduleCodexResetVerification(resetsAt: resetsAt)
        }
        lastCodexResetsAt = newCodexResetsAt
    }

    private func attemptTokenRefreshAndRetry() {
        guard !codexNeedsRelogin else {
            Logger.menuBar.info("Codex has confirmed a re-login is required, skipping the refresh")
            markCodexNeedsRelogin()
            return
        }
        // OAuth account: fetchUsage already tried to renew with the refresh_token, so a 401 means the refresh_token is dead.
        // The old three level chatgpt.com refresh chain targets session-token, which is meaningless for OAuth credentials and always fails, so ask for a fresh sign in.
        if CodexAPIService.isOAuthRefreshToken(UserSettings.shared.codexSessionToken) {
            Logger.menuBar.info("Codex OAuth refresh_token is no longer valid, sign in again")
            markCodexNeedsRelogin()
            return
        }
        let prefix = UserSettings.shared.codexSessionToken.prefix(16)
        Logger.menuBar.info("Codex accessToken expired, starting the three level refresh chain (session prefix=\(prefix)…)")
        attemptLevel1SSRRefresh()
    }

    /// Level 1: refresh the accessToken from the SSR bootstrap
    private func attemptLevel1SSRRefresh() {
        Logger.menuBar.info("Codex level 1: SSR bootstrap refresh")
        Task { @MainActor [weak self] in
            guard let self else { return }
            CodexTokenRefreshCoordinator.shared.refresh { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let freshAccessToken):
                    Logger.menuBar.notice("Codex level 1 SSR refresh succeeded, retrying with the new accessToken")
                    self.retryCodexWithAccessToken(freshAccessToken)
                case .failure(let error):
                    Logger.menuBar.info("Codex level 1 failed (\(error.localizedDescription)), falling back to level 2")
                    self.attemptLevel2WebViewRefresh()
                }
            }
        }
    }

    /// Level 2: silently renew the session-token in a hidden WebView
    private func attemptLevel2WebViewRefresh() {
        Logger.menuBar.info("Codex level 2: silent renewal with a hidden WebView")
        Task { @MainActor [weak self] in
            guard let self else { return }
            CodexSilentRefreshCoordinator.shared.refresh { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    Logger.menuBar.notice("Codex level 2 WebView renewal succeeded, refetching usage")
                    // The coordinator already wrote the session-token back, so run the full session to usage flow again
                    self.fetchCodexOnly(retryOnUnauthorized: false)
                case .failure(let error):
                    Logger.menuBar.error("Codex level 2 failed (\(error.localizedDescription)), moving on to level 3")
                    self.markCodexNeedsRelogin()
                }
            }
        }
    }

    /// Query usage directly with a fresh accessToken (skips the session step)
    private func retryCodexWithAccessToken(_ accessToken: String) {
        isLoading = true
        codexApiService.fetchUsageWithAccessToken(accessToken) { [weak self] usageResult in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                self.endRefreshAnimationWithMinimumDuration { }
                switch usageResult {
                case .success(let data):
                    self.processCodexSuccess(data)
                case .failure(let error):
                    Logger.menuBar.error("Codex still failed with a fresh accessToken: \(error.localizedDescription), falling back to level 2")
                    self.attemptLevel2WebViewRefresh()
                }
            }
        }
    }

    /// Reset the re-login state (called on a manual refresh, allowing another run of the three level chain)
    private func resetCodexReloginState() {
        codexNeedsRelogin = false
        codexSessionExpiredNotified = false
    }

    /// Level 3: mark that a re-login is needed and post a system notification (once only)
    private func markCodexNeedsRelogin() {
        codexNeedsRelogin = true
        if !codexSessionExpiredNotified {
            codexSessionExpiredNotified = true
            if settings.notificationsEnabled {
                NotificationManager.shared.sendCodexSessionExpiredNotification()
            }
        }
        codexErrorMessage = UsageError.sessionExpired.localizedDescription
        clearCodexUsageState(clearError: false)
        Logger.menuBar.error("All three Codex refresh levels failed, the user needs to sign in again")
    }

    /// After an account switch, clear and refresh only that provider, so previousData for the other one does not read as a reset.
    /// Notification dedupe state is per account: kept across a switch, and cleaned up precisely by UserSettings when an account is deleted.
    func handleAccountChanged(provider: ProviderType?) {
        switch provider {
        case .claude:
            errorMessage = nil
            clearClaudeUsageState()
            if shouldFetchClaudeUsage {
                fetchClaudeOnly()
            }

        case .codex:
            resetCodexReloginState()
            codexApiService.clearAccessTokenCache()
            clearCodexUsageState()
            if shouldFetchCodexUsage {
                fetchCodexOnly()
            }

        case .none:
            clearClaudeUsageState()
            clearCodexUsageState()
            NotificationManager.shared.resetAllNotificationStates()
            fetchUsage()
        }
    }

    /// End the refresh animation, honoring the minimum duration
    /// - Parameter completion: called once the animation ends
    private func endRefreshAnimationWithMinimumDuration(completion: @escaping () -> Void) {
        guard let startTime = refreshAnimationStartTime else {
            // No recorded start time, so end now
            refreshState.isRefreshing = false
            refreshState.refreshingProvider = nil
            completion()
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = minimumAnimationDuration - elapsed

        if remaining > 0 {
            // Not visible long enough yet, wait out the remainder before ending
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                self?.refreshState.isRefreshing = false
                self?.refreshState.refreshingProvider = nil
                completion()
            }
        } else {
            // Visible long enough already, end now
            refreshState.isRefreshing = false
            refreshState.refreshingProvider = nil
            completion()
        }

        // Clear the recorded start time
        refreshAnimationStartTime = nil
    }

    // MARK: - Reset Verification

    /// Cancel every reset validation timer
    private func cancelResetVerification() {
        timerManager.invalidate(TimerID.resetVerify1)
        timerManager.invalidate(TimerID.resetVerify2)
        timerManager.invalidate(TimerID.resetVerify3)
    }

    /// Schedule reset time validation
    /// Fires one refresh each at 1, 10 and 30 seconds past the reset time
    /// - Parameter resetsAt: the usage reset time
    private func scheduleResetVerification(resetsAt: Date) {
        // Clear the old validation timers
        cancelResetVerification()

        // Compute the interval until the reset time
        let timeUntilReset = resetsAt.timeIntervalSinceNow

        // Only schedule validation for a reset time in the future
        guard timeUntilReset > 0 else {
            Logger.menuBar.debug("Reset time has already passed, skipping verification scheduling")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone.current
        Logger.menuBar.debug("Scheduled reset verification - reset time: \(formatter.string(from: resetsAt))")

        // Validate 1 second after the reset
        timerManager.schedule(TimerID.resetVerify1, interval: timeUntilReset + 1, repeats: false) { [weak self] in
            Logger.menuBar.debug("Reset verification +1s - refreshing")
            self?.fetchUsage()
        }

        // Validate 10 seconds after the reset
        timerManager.schedule(TimerID.resetVerify2, interval: timeUntilReset + 10, repeats: false) { [weak self] in
            Logger.menuBar.debug("Reset verification +10s - refreshing")
            self?.fetchUsage()
        }

        // Validate 30 seconds after the reset
        timerManager.schedule(TimerID.resetVerify3, interval: timeUntilReset + 30, repeats: false) { [weak self] in
            Logger.menuBar.debug("Reset verification +30s - refreshing")
            self?.fetchUsage()
        }
    }

    // MARK: - Codex Reset Verification

    private func cancelCodexResetVerification() {
        timerManager.invalidate(TimerID.codexResetVerify1)
        timerManager.invalidate(TimerID.codexResetVerify2)
        timerManager.invalidate(TimerID.codexResetVerify3)
    }

    private func scheduleCodexResetVerification(resetsAt: Date) {
        cancelCodexResetVerification()

        let timeUntilReset = resetsAt.timeIntervalSinceNow
        guard timeUntilReset > 0 else {
            Logger.menuBar.debug("Codex reset time has already passed, skipping verification scheduling")
            return
        }

        timerManager.schedule(TimerID.codexResetVerify1, interval: timeUntilReset + 1, repeats: false) { [weak self] in
            Logger.menuBar.debug("Codex reset verification +1s - refreshing")
            self?.fetchUsage()
        }

        timerManager.schedule(TimerID.codexResetVerify2, interval: timeUntilReset + 10, repeats: false) { [weak self] in
            Logger.menuBar.debug("Codex reset verification +10s - refreshing")
            self?.fetchUsage()
        }

        timerManager.schedule(TimerID.codexResetVerify3, interval: timeUntilReset + 30, repeats: false) { [weak self] in
            Logger.menuBar.debug("Codex reset verification +30s - refreshing")
            self?.fetchUsage()
        }
    }

    // MARK: - Cleanup

    /// Release all resources
    func cleanup() {
        timerManager.invalidateAll()
        endRefreshActivity()
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    deinit {
        cleanup()
    }

    // MARK: - Cached Snapshot

    /// True while the last 429's backoff window is still open
    private var isWithinClaudeBackoff: Bool {
        guard let until = claudeBackoffUntil else { return false }
        if until > Date() { return true }
        claudeBackoffUntil = nil
        return false
    }

    /// Whether an error will probably fix itself on the next poll. These must never reach the UI as
    /// an error screen: the competitor never shows one at all, and a transient 429 replacing good
    /// numbers with "Too many requests" is exactly the behaviour being removed here.
    private static func isTransient(_ error: Error) -> Bool {
        switch error {
        case UsageError.rateLimited, UsageError.networkError, UsageError.noData, UsageError.decodingError:
            return true
        case UsageError.httpError(let statusCode):
            return statusCode == 429 || (500...599).contains(statusCode)
        default:
            // Auth problems (no credentials, unauthorized, session expired, Cloudflare) are the only
            // ones the user can actually act on, so those are the only ones that get a screen.
            return false
        }
    }

    /// Whether an error means "the server told us to slow down"
    private static func isRateLimit(_ error: Error) -> Bool {
        if case UsageError.rateLimited = error { return true }
        if case UsageError.httpError(let statusCode) = error, statusCode == 429 { return true }
        return false
    }

    /// Save the last good fetch so a cold start has real numbers instead of a spinner or an error.
    /// Percentages and reset times only, no credentials, so UserDefaults is the right place.
    private func persistCachedUsage(_ data: UsageData) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: cachedUsageKey)
        UserDefaults.standard.set(Date(), forKey: cachedUsageAtKey)
    }

    /// Load the last good fetch at launch. Shown with its timestamp until a live fetch replaces it.
    private func restoreCachedUsage() {
        guard let encoded = UserDefaults.standard.data(forKey: cachedUsageKey),
              let decoded = try? JSONDecoder().decode(UsageData.self, from: encoded) else {
            return
        }
        usageData = decoded
        refreshState.lastUpdatedAt = UserDefaults.standard.object(forKey: cachedUsageAtKey) as? Date
        Logger.menuBar.debug("Restored the cached usage snapshot from the last session")
    }

}
