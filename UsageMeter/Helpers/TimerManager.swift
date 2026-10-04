//
//  TimerManager.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// Central timer manager
/// Creates, schedules and tears down every timer in the app, so none leak
/// Type safe timer identifiers
class TimerManager {
    // MARK: - Properties

    /// Timer storage, keyed by identifier with the Timer as the value
    private var timers: [String: Timer] = [:]

    /// Thread safe queue
    private let queue = DispatchQueue(label: "in.pooya.usagemeter.timer", attributes: .concurrent)

    // MARK: - Public Methods

    /// Schedule a timer
    /// - Parameters:
    ///   - identifier: unique timer identifier
    ///   - interval: interval in seconds
    ///   - repeats: whether it repeats
    ///   - block: the closure run when the timer fires
    /// - Note: an existing timer with the same identifier is cancelled first
    func schedule(
        _ identifier: String,
        interval: TimeInterval,
        repeats: Bool = true,
        block: @escaping () -> Void
    ) {
        // Timer.scheduledTimer registers on the calling thread's RunLoop; when schedule is called from a background
        // thread with no running RunLoop (a Combine subscription without receive(on:), say), the timer never fires.
        // Guarantee creation on the main thread. Run synchronously when already there, because deferring by one
        // runloop turn would make "invalidate(X) in the same turn as schedule(X)" create X after the invalidate (a resurrected timer).
        runOnMain { [weak self] in
            guard let self else { return }

            // Cancel the old timer and create the new one synchronously, to avoid a race
            self.queue.sync(flags: .barrier) {
                if let oldTimer = self.timers[identifier] {
                    oldTimer.invalidate()
                    self.timers.removeValue(forKey: identifier)
                }
            }

            let timer = Timer.scheduledTimer(
                withTimeInterval: interval,
                repeats: repeats
            ) { _ in
                block()
            }

            // Store the new timer
            self.queue.async(flags: .barrier) {
                self.timers[identifier] = timer
            }

            Logger.menuBar.info("⏰ Timer scheduled: \(identifier) (interval: \(interval)s, repeats: \(repeats))")
        }
    }

    /// Run synchronously when already on the main thread, otherwise dispatch to it
    private func runOnMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    /// Cancel one timer
    /// - Parameter identifier: timer identifier
    func invalidate(_ identifier: String) {
        queue.sync(flags: .barrier) {
            if let timer = self.timers[identifier] {
                timer.invalidate()
                self.timers.removeValue(forKey: identifier)
                Logger.menuBar.info("⏹️ Timer invalidated: \(identifier)")
            }
        }
    }

    /// Cancel every timer
    /// - Note: normally called when the app quits or on a major state change
    func invalidateAll() {
        queue.sync(flags: .barrier) {
            let count = self.timers.count
            self.timers.values.forEach { $0.invalidate() }
            self.timers.removeAll()
            Logger.menuBar.info("🛑 All timers invalidated (count: \(count))")
        }
    }

    /// Check whether a timer is active
    /// - Parameter identifier: timer identifier
    /// - Returns: true when the timer exists and is valid
    func isActive(_ identifier: String) -> Bool {
        return queue.sync {
            return timers[identifier]?.isValid ?? false
        }
    }

    /// Get the list of currently active timers
    /// - Returns: identifiers of the active timers
    /// - Note: mainly for debugging and diagnostics
    func activeTimers() -> [String] {
        return queue.sync {
            return timers.keys.filter { timers[$0]?.isValid == true }
        }
    }

    // MARK: - Deinit

    deinit {
        invalidateAll()
    }
}

// MARK: - Timer Identifiers

/// Timer identifier namespace
/// Type safe timer identifier constants
extension TimerManager {
    /// Timer identifiers
    enum Identifier {
        /// Main data refresh timer
        static let mainRefresh = "mainRefresh"
        /// Popover live refresh timer (1 second interval)
        static let popoverRefresh = "popoverRefresh"
        /// Reset validation timer, 1 second after the reset
        static let resetVerify1 = "resetVerify1"
        /// Reset validation timer, 10 seconds after the reset
        static let resetVerify2 = "resetVerify2"
        /// Reset validation timer, 30 seconds after the reset
        static let resetVerify3 = "resetVerify3"
        /// Codex reset validation timer, 1 second after the reset
        static let codexResetVerify1 = "codexResetVerify1"
        /// Codex reset validation timer, 10 seconds after the reset
        static let codexResetVerify2 = "codexResetVerify2"
        /// Codex reset validation timer, 30 seconds after the reset
        static let codexResetVerify3 = "codexResetVerify3"
        /// Codex accessToken renewal timer (separate from the usage fetch timer)
        static let codexTokenRefresh = "codexTokenRefresh"
    }
}
