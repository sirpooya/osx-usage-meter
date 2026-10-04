//
//  CrashReporter.swift
//  UsageMeter
//
//  Captures abnormal termination so a vanished menu bar app can be explained
//  after the fact.
//

import Foundation
import Darwin

/// Writes a marker file the instant the process is dying, so the next launch
/// can say what happened.
///
/// Two very different failure modes have to be told apart, because they have
/// opposite fixes:
///
///   1. The process crashed. A signal or an uncaught exception. macOS also
///      writes an .ips report in ~/Library/Logs/DiagnosticReports for these.
///   2. The process was killed from outside. Memory pressure (jetsam), a
///      force quit, Control Center unloading the status item, or a logout.
///      macOS writes no crash report at all for these, which is exactly why
///      "it just quits and I do not know why" is so hard to chase.
///
/// This type covers case 1. `SessionSentinel` covers case 2 by noticing that
/// a session started and never ended cleanly and yet left no crash marker.
///
/// Everything on the dying path is async signal safe: raw `write(2)` to an
/// already open descriptor, no Foundation, no allocation, no locks. A signal
/// handler that calls `malloc` or `String` interpolation can deadlock against
/// whatever the interrupted thread was holding, and then nothing is written at
/// all. That is worse than useless, so the format here is deliberately crude.
enum CrashReporter {

    // MARK: - Types

    /// How the previous run ended.
    enum Cause: String, Codable {
        /// A fatal POSIX signal. Includes Swift `fatalError`, array bounds
        /// traps, and force unwrap of nil, which arrive as SIGILL or SIGTRAP.
        case signal
        /// An uncaught NSException, typically from AppKit or KVO.
        case exception
    }

    /// The parsed contents of a crash marker.
    struct Report: Codable {
        let cause: Cause
        /// Signal number, or the exception name.
        let detail: String
        /// Symbol names, best effort. Empty when the backtrace could not be
        /// taken.
        let frames: [String]
        /// When the marker was written, seconds since epoch. Recorded as a
        /// raw number because formatting a date is not signal safe.
        let timestamp: TimeInterval

        var date: Date { Date(timeIntervalSince1970: timestamp) }
    }

    // MARK: - Paths

    /// Sits next to the logs so one folder holds the whole diagnostic story.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("UsageMeter/logs", isDirectory: true)
    }

    static var markerURL: URL {
        directory.appendingPathComponent("last-crash.marker", isDirectory: false)
    }

    // MARK: - Signal handler state
    //
    // Only these three globals may be touched from the handler. `nonisolated(unsafe)`
    // is the honest annotation: the handler runs on whichever thread took the
    // signal, and no amount of actor isolation can make that safe. Safety comes
    // from writing to a preopened descriptor and nothing else.

    /// Opened before any signal can arrive, because `open(2)` inside a handler
    /// after heap corruption is not reliable.
    private nonisolated(unsafe) static var markerFD: Int32 = -1

    /// Previous dispositions, so a debugger or Sparkle keeps working. Chaining
    /// rather than swallowing matters: replacing SIGTRAP outright would stop
    /// lldb from breaking on Swift traps.
    private nonisolated(unsafe) static var previousActions: [Int32: sigaction] = [:]

    private nonisolated(unsafe) static var isInstalled = false

    /// The signals worth catching. SIGKILL and SIGSTOP are deliberately absent
    /// because they cannot be caught, and a SIGKILL is precisely the jetsam
    /// case that `SessionSentinel` has to infer instead.
    private static let fatalSignals: [Int32] = [
        SIGABRT,  // abort(), assertion failures
        SIGBUS,   // bad memory access, misaligned
        SIGFPE,   // arithmetic fault
        SIGILL,   // illegal instruction, some Swift traps
        SIGSEGV,  // null or wild pointer dereference
        SIGTRAP,  // Swift runtime traps: force unwrap nil, bounds, overflow
        SIGQUIT,  // quit from a terminal or a watchdog
    ]

    // MARK: - Install

    /// Call once, as early in launch as possible.
    ///
    /// Earlier is strictly better. Anything that dies before this runs is
    /// invisible, and startup is a common place to die.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        prepareMarkerDescriptor()
        installExceptionHandler()
        installSignalHandlers()
    }

    /// Opens the marker file now and keeps the descriptor for later. Truncating
    /// on open means a stale marker from a session that was already reported
    /// cannot be mistaken for a fresh one, since `consumePreviousReport()`
    /// deletes what it reads.
    private static func prepareMarkerDescriptor() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // O_APPEND so the exception handler and a subsequent signal handler
        // both land in the file rather than overwriting each other. A crash
        // during exception unwinding is common and both halves are useful.
        markerFD = open(markerURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
    }

    private static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            // This handler is not signal context, so Foundation is legal here.
            // It still avoids anything that could itself throw.
            let name = exception.name.rawValue
            let reason = exception.reason ?? "no reason"
            let frames = exception.callStackSymbols

            CrashReporter.writeMarker(
                cause: .exception,
                detail: "\(name): \(reason)",
                frames: frames
            )
        }
    }

    private static func installSignalHandlers() {
        for signalNumber in fatalSignals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { received in
                CrashReporter.handleSignal(received)
            }
            // SA_NODEFER off, SA_RESETHAND on: after we write the marker the
            // default action must run so the process actually dies and macOS
            // still gets a chance to write its own .ips report. Swallowing the
            // signal would leave a zombie menu bar app, which is a worse bug
            // than the one being diagnosed.
            action.sa_flags = Int32(SA_RESETHAND)
            sigemptyset(&action.sa_mask)

            var previous = sigaction()
            if sigaction(signalNumber, &action, &previous) == 0 {
                previousActions[signalNumber] = previous
            }
        }
    }

    // MARK: - Dying path
    //
    // Async signal safe only. Do not add Foundation calls below this line.

    private static func handleSignal(_ received: Int32) {
        writeSignalMarker(received)

        // Re-raise so the default disposition terminates us and macOS records
        // its own report. SA_RESETHAND already restored the default handler.
        raise(received)
    }

    /// Hand rolled, allocation free marker write.
    ///
    /// Format is one `key=value` per line rather than JSON, because emitting
    /// JSON without allocating is not worth the complexity and a human reading
    /// the raw file during a panic should not need a parser.
    private static func writeSignalMarker(_ received: Int32) {
        guard markerFD >= 0 else { return }

        writeRaw("--- crash ---\n")
        writeRaw("cause=signal\n")
        writeRaw("signal=")
        writeInt(Int(received))
        writeRaw("\n")
        writeRaw("time=")
        // `time(nil)` is on the signal safe list. `Date()` is not.
        writeInt(Int(time(nil)))
        writeRaw("\n")

        writeRaw("frames:\n")
        // backtrace and backtrace_symbols_fd are documented signal safe.
        // backtrace_symbols (no _fd) allocates, so it must not be used here.
        var buffer = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
        let count = backtrace(&buffer, Int32(buffer.count))
        backtrace_symbols_fd(&buffer, count, markerFD)

        writeRaw("--- end ---\n")
        fsync(markerFD)
    }

    private static func writeRaw(_ text: StaticString) {
        guard markerFD >= 0 else { return }
        _ = write(markerFD, text.utf8Start, text.utf8CodeUnitCount)
    }

    /// Signal safe integer formatting. No String, no allocation.
    private static func writeInt(_ value: Int) {
        guard markerFD >= 0 else { return }
        var digits = [UInt8]()
        digits.reserveCapacity(24)
        var remaining = value
        if remaining < 0 {
            _ = write(markerFD, "-", 1)
            remaining = -remaining
        }
        if remaining == 0 {
            _ = write(markerFD, "0", 1)
            return
        }
        while remaining > 0 {
            digits.append(UInt8(48 + remaining % 10))
            remaining /= 10
        }
        for byte in digits.reversed() {
            var copy = byte
            _ = write(markerFD, &copy, 1)
        }
    }

    // MARK: - Exception path (not signal context)

    /// Used by the exception handler, where allocation is allowed.
    private static func writeMarker(cause: Cause, detail: String, frames: [String]) {
        guard markerFD >= 0 else { return }

        var text = "--- crash ---\n"
        text += "cause=\(cause.rawValue)\n"
        text += "detail=\(SensitiveDataRedactor.redactText(detail))\n"
        text += "time=\(Int(Date().timeIntervalSince1970))\n"
        text += "frames:\n"
        for frame in frames.prefix(64) {
            text += "\(frame)\n"
        }
        text += "--- end ---\n"

        if let data = text.data(using: .utf8) {
            data.withUnsafeBytes { raw in
                _ = write(markerFD, raw.baseAddress, raw.count)
            }
        }
        fsync(markerFD)
    }

    // MARK: - Reading back

    /// Reads and removes any marker left by a previous run.
    ///
    /// Consuming rather than merely reading is what keeps the report honest:
    /// a marker that survives would be re-reported on every subsequent launch
    /// and every launch would look like a crash.
    static func consumePreviousReport() -> Report? {
        let url = markerURL
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            return nil
        }

        // Keep the raw text for the report script, then clear the live marker.
        let archive = directory.appendingPathComponent("last-crash.txt", isDirectory: false)
        try? text.write(to: archive, atomically: true, encoding: .utf8)

        // Truncate through the open descriptor rather than deleting the file,
        // so the descriptor captured at install time stays valid.
        if markerFD >= 0 {
            ftruncate(markerFD, 0)
            lseek(markerFD, 0, SEEK_SET)
        } else {
            try? FileManager.default.removeItem(at: url)
        }

        return parse(text)
    }

    /// Parses the last `--- crash ---` block in the file. The last one wins
    /// because a cascading failure appends several and the final one is the
    /// proximate cause.
    static func parse(_ text: String) -> Report? {
        let blocks = text.components(separatedBy: "--- crash ---")
        guard let block = blocks.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }

        var cause: Cause = .signal
        var detail = "unknown"
        var timestamp = Date().timeIntervalSince1970
        var frames: [String] = []
        var inFrames = false

        for rawLine in block.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "--- end ---" { continue }

            if inFrames {
                frames.append(line)
                continue
            }

            if line == "frames:" {
                inFrames = true
            } else if line.hasPrefix("cause=") {
                cause = Cause(rawValue: String(line.dropFirst("cause=".count))) ?? .signal
            } else if line.hasPrefix("signal=") {
                let number = Int32(line.dropFirst("signal=".count)) ?? 0
                detail = "\(Self.name(for: number)) (\(number))"
            } else if line.hasPrefix("detail=") {
                detail = String(line.dropFirst("detail=".count))
            } else if line.hasPrefix("time=") {
                timestamp = TimeInterval(line.dropFirst("time=".count)) ?? timestamp
            }
        }

        return Report(cause: cause, detail: detail, frames: frames, timestamp: timestamp)
    }

    /// Plain language names, because "signal 11" means nothing at 2am.
    static func name(for signalNumber: Int32) -> String {
        switch signalNumber {
        case SIGABRT: return "SIGABRT, aborted"
        case SIGBUS: return "SIGBUS, bad memory access"
        case SIGFPE: return "SIGFPE, arithmetic fault"
        case SIGILL: return "SIGILL, illegal instruction"
        case SIGSEGV: return "SIGSEGV, invalid pointer"
        case SIGTRAP: return "SIGTRAP, Swift runtime trap"
        case SIGQUIT: return "SIGQUIT, quit"
        default: return "signal"
        }
    }
}
