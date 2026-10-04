//
//  SessionSentinel.swift
//  UsageMeter
//
//  Answers "why did the app quit" by proving what did NOT happen.
//

import Foundation
import AppKit

/// Tracks whether each run of the app ended on purpose.
///
/// This is the part that actually explains a menu bar app disappearing. A
/// crash handler can only report crashes, and the most common way a menu bar
/// agent vanishes is not a crash at all:
///
///   - jetsam kills it under memory pressure, with SIGKILL, uncatchable
///   - the user force quits it
///   - Control Center stops loading the status item, so the process may still
///     be alive while the icon is gone
///   - a logout or restart tears it down
///   - Sparkle terminates it to install an update
///
/// None of those write a crash report. The only way to see them is to notice
/// that a session began and never recorded an orderly ending.
///
/// The mechanism is a heartbeat file. Launch writes it, `markCleanExit()`
/// deletes it, and a heartbeat timer keeps its contents fresh. If the file is
/// still present at the next launch, the previous run died without warning,
/// and the heartbeat timestamp inside says roughly when.
@MainActor
final class SessionSentinel {

    static let shared = SessionSentinel()

    // MARK: - Types

    /// What the previous run's ending looked like.
    enum Outcome {
        /// No previous session on record. First launch, or state was cleared.
        case firstRun
        /// Ended through `applicationWillTerminate`. Nothing to explain.
        case clean
        /// Died from a signal or an uncaught exception, with a marker to prove it.
        case crashed(CrashReporter.Report)
        /// Started, never ended cleanly, and left no crash marker.
        ///
        /// This is the interesting verdict. It means something outside the app
        /// stopped the process: almost always jetsam, a force quit, or a
        /// system shutdown. `lastHeartbeat` bounds when it happened and
        /// `ranFor` says how long it had been up, which is the signal that
        /// separates "dies after 20 seconds every time" from "dies after two
        /// days".
        case killed(lastHeartbeat: Date?, ranFor: TimeInterval?)

        /// One line fit for a log or a settings row.
        var summary: String {
            switch self {
            case .firstRun:
                return "First run, no previous session on record."
            case .clean:
                return "Previous session exited cleanly."
            case .crashed(let report):
                return "Previous session crashed: \(report.cause.rawValue), \(report.detail)"
            case .killed(let heartbeat, let ranFor):
                var text = "Previous session was terminated without a crash report."
                text += " Likely killed from outside: memory pressure, force quit, or logout."
                if let ranFor {
                    text += " It had been running for \(Int(ranFor))s."
                }
                if let heartbeat {
                    text += " Last heartbeat \(ISO8601DateFormatter().string(from: heartbeat))."
                }
                return text
            }
        }

        /// Whether this deserves the user's attention.
        var isAbnormal: Bool {
            switch self {
            case .firstRun, .clean: return false
            case .crashed, .killed: return true
            }
        }
    }

    /// The live session file's contents.
    private struct Heartbeat: Codable {
        let startedAt: Date
        var updatedAt: Date
        let pid: Int32
        let version: String
        /// Resident size at the last heartbeat, bytes. A steady climb here
        /// across sessions that all end in `.killed` is the fingerprint of a
        /// leak being reaped by jetsam, which is otherwise invisible.
        var footprintBytes: UInt64
    }

    // MARK: - Paths

    private var directory: URL { CrashReporter.directory }

    private var heartbeatURL: URL {
        directory.appendingPathComponent("session.heartbeat", isDirectory: false)
    }

    /// Append only record of every ending, so a pattern can be seen over days.
    private var ledgerURL: URL {
        directory.appendingPathComponent("sessions.log", isDirectory: false)
    }

    // MARK: - State

    private var current: Heartbeat?
    private var timer: Timer?
    private var didMarkExit = false

    /// Frequent enough to bound the time of death usefully, rare enough to be
    /// free. 30s means a kill is located to within half a minute.
    private let heartbeatInterval: TimeInterval = 30

    private init() {}

    // MARK: - Lifecycle

    /// Reads the previous run's fate, then opens a session for this run.
    ///
    /// Order matters: the previous heartbeat has to be read and cleared before
    /// this run's heartbeat overwrites it.
    @discardableResult
    func begin() -> Outcome {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let outcome = readPreviousOutcome()
        recordToLedger(outcome)
        startCurrentSession()
        observeTermination()
        return outcome
    }

    /// Call from `applicationWillTerminate`. Absence of this call is the whole
    /// signal, so it must not be skipped on any orderly path.
    func markCleanExit() {
        guard !didMarkExit else { return }
        didMarkExit = true

        timer?.invalidate()
        timer = nil

        appendLedger("exit clean pid=\(ProcessInfo.processInfo.processIdentifier) uptime=\(Int(uptime()))s")
        try? FileManager.default.removeItem(at: heartbeatURL)
    }

    // MARK: - Previous run

    private func readPreviousOutcome() -> Outcome {
        // A crash marker is definitive, so it is checked first and consumed
        // either way to keep it from being reported twice.
        let crash = CrashReporter.consumePreviousReport()

        guard
            let data = try? Data(contentsOf: heartbeatURL),
            let previous = try? ISO8601JSON.decoder.decode(Heartbeat.self, from: data)
        else {
            // No heartbeat file. Either a clean exit removed it, or this is
            // the first run. A crash marker with no heartbeat still counts as
            // a crash, since the marker is the stronger evidence.
            if let crash { return .crashed(crash) }
            return FileManager.default.fileExists(atPath: ledgerURL.path) ? .clean : .firstRun
        }

        // Heartbeat present means the previous run never called markCleanExit.
        try? FileManager.default.removeItem(at: heartbeatURL)

        if let crash { return .crashed(crash) }

        return .killed(
            lastHeartbeat: previous.updatedAt,
            ranFor: previous.updatedAt.timeIntervalSince(previous.startedAt)
        )
    }

    // MARK: - Current run

    private func startCurrentSession() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        current = Heartbeat(
            startedAt: Date(),
            updatedAt: Date(),
            pid: ProcessInfo.processInfo.processIdentifier,
            version: version,
            footprintBytes: Self.residentFootprint()
        )
        writeHeartbeat()
        appendLedger("start pid=\(ProcessInfo.processInfo.processIdentifier) version=\(version)")

        let timer = Timer(timeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.beat() }
        }
        // .common so the heartbeat keeps ticking while a menu or popover is
        // tracking. On the default mode it would stall exactly when the app is
        // being interacted with, which is when it is most likely to die.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func beat() {
        guard var beat = current else { return }
        beat.updatedAt = Date()
        beat.footprintBytes = Self.residentFootprint()
        current = beat
        writeHeartbeat()
    }

    private func writeHeartbeat() {
        guard let current, let data = try? ISO8601JSON.encoder.encode(current) else { return }
        // Atomic so a kill mid-write cannot leave an unparseable file, which
        // would downgrade a `.killed` verdict to `.firstRun` and hide the bug.
        try? data.write(to: heartbeatURL, options: .atomic)
    }

    /// Catches the orderly-shutdown paths that do not always reach
    /// `applicationWillTerminate`, notably logout and restart.
    private func observeTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in SessionSentinel.shared.markCleanExit() }
        }
    }

    // MARK: - Ledger

    private func recordToLedger(_ outcome: Outcome) {
        switch outcome {
        case .firstRun:
            appendLedger("previous none")
        case .clean:
            appendLedger("previous clean")
        case .crashed(let report):
            appendLedger("previous CRASHED cause=\(report.cause.rawValue) detail=\(report.detail)")
        case .killed(let heartbeat, let ranFor):
            let last = heartbeat.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
            appendLedger("previous KILLED lastHeartbeat=\(last) ranFor=\(ranFor.map { String(Int($0)) } ?? "?")s")
        }
    }

    private func appendLedger(_ line: String) {
        let stamped = "[\(ISO8601DateFormatter().string(from: Date()))] \(line)\n"
        guard let data = stamped.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: ledgerURL.path) {
            guard let handle = try? FileHandle(forWritingTo: ledgerURL) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: ledgerURL, options: .atomic)
        }
    }

    // MARK: - Memory

    private func uptime() -> TimeInterval {
        guard let current else { return 0 }
        return Date().timeIntervalSince(current.startedAt)
    }

    /// Physical footprint, the same number jetsam decides on. `task_info` with
    /// TASK_VM_INFO is the only route that matches what the kernel enforces;
    /// resident_size alone overstates it and would make a leak look worse than
    /// it is.
    static func residentFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }
}

/// Shared coders. Kept separate so both the sentinel and any future reader
/// agree on the date format rather than each rolling their own.
enum ISO8601JSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
