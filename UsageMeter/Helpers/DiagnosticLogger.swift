//
//  DiagnosticLogger.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-11.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// Diagnostic logger
/// Detailed runtime logging, to help trace and diagnose problems
@MainActor
class DiagnosticLogger {

    // MARK: - Singleton

    static let shared = DiagnosticLogger()

    // MARK: - Properties

    /// Log level
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    /// Log file URL
    private var logFileURL: URL?

    /// Log queue (for asynchronous writes)
    private let logQueue = DispatchQueue(label: "in.pooya.usagemeter.logging", qos: .utility)

    /// Maximum log file size (5MB)
    private let maxLogFileSize: UInt64 = 5 * 1024 * 1024

    /// Whether logging is enabled
    private var isEnabled: Bool = true

    /// System logger
    private let osLogger = Logger(subsystem: "in.pooya.usagemeter", category: "Diagnostics")

    // MARK: - Initialization

    private init() {
        setupLogFile()
    }

    // MARK: - Public Methods

    /// Log debug information
    func debug(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .debug, file: file, line: line, function: function)
    }

    /// Log general information
    func info(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .info, file: file, line: line, function: function)
    }

    /// Log a warning
    func warning(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .warning, file: file, line: line, function: function)
    }

    /// Log an error
    func error(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .error, file: file, line: line, function: function)
    }

    /// Get the log file path
    func getLogFilePath() -> String? {
        return logFileURL?.path
    }

    /// Read the log contents
    func readLogs(maxLines: Int = 1000) -> String {
        guard let logFileURL = logFileURL,
              FileManager.default.fileExists(atPath: logFileURL.path) else {
            return "No logs available"
        }

        do {
            let content = try String(contentsOf: logFileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            let recentLines = lines.suffix(maxLines)
            return recentLines.joined(separator: "\n")
        } catch {
            return "Error reading logs: \(error.localizedDescription)"
        }
    }

    /// Clear the log
    func clearLogs() {
        guard let logFileURL = logFileURL else { return }

        logQueue.async {
            do {
                try "".write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                self.osLogger.error("Failed to clear logs: \(error.localizedDescription)")
            }
        }
    }

    /// Export the log file
    func exportLogs() -> URL? {
        return logFileURL
    }

    // MARK: - Private Methods

    /// Set up the log file
    private func setupLogFile() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            osLogger.error("Failed to get Application Support directory")
            return
        }

        let logDirectory = appSupport.appendingPathComponent("UsageMeter/logs")

        // Create the log directory
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            osLogger.error("Failed to create log directory: \(error.localizedDescription)")
            return
        }

        // Set the log file path
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFileURL = logDirectory.appendingPathComponent("usagemeter_\(dateString).log")

        // Check the log and rotate if needed
        checkAndRotateLogIfNeeded()
    }

    /// Core logging method
    private func log(_ message: String, level: LogLevel, file: String, line: Int, function: String) {
        guard isEnabled else { return }

        // Release builds drop debug but keep info.
        //
        // This used to drop info as well, which left Release builds with no
        // breadcrumbs at all before a crash or a kill, and "sudden quit" only ever happens in Release.
        // info is already redacted and there is not much of it (a few lines per poll), so keeping it is
        // the only way to see what the app was doing before it went away.
        #if !DEBUG
        guard level != .debug else { return }
        #endif

        // Redact
        let sanitizedMessage = sanitize(message)

        // Extract the file name
        let fileName = (file as NSString).lastPathComponent

        // Build the log message
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(sanitizedMessage)\n"

        // Print to the console (Debug builds only)
        #if DEBUG
        print(logMessage, terminator: "")
        #endif

        // Send to the system log
        osLogger.log(level: osLogLevel(for: level), "\(sanitizedMessage)")

        // warning and error are flushed synchronously, everything else asynchronously.
        //
        // An async write on a .utility queue means everything still queued is lost when the process is killed,
        // and what is lost is exactly the last few lines before the crash. So severe levels take the synchronous path and fsync:
        // a few milliseconds each, in exchange for those lines being on disk for certain.
        let needsDurability = (level == .warning || level == .error)
        writeToFile(logMessage, synchronous: needsDurability)
    }

    /// Flush pending log lines to disk right now.
    /// Called when a quit is known to be coming (applicationWillTerminate), so the tail is not lost.
    func flush() {
        logQueue.sync { }
    }

    /// Write a log line to the file
    /// - Parameter synchronous: true blocks until the content is fsynced, for severe logs that
    ///   must survive a crash
    private func writeToFile(_ message: String, synchronous: Bool = false) {
        guard let logFileURL = logFileURL else { return }

        let work = {
            do {
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    // The file exists, append
                    let fileHandle = try FileHandle(forWritingTo: logFileURL)
                    defer { try? fileHandle.close() }

                    try fileHandle.seekToEnd()
                    if let data = message.data(using: .utf8) {
                        try fileHandle.write(contentsOf: data)
                    }
                    if synchronous {
                        // Bypass the file system cache. Without this, a SIGKILL leaves the
                        // content in kernel buffers and nothing on disk.
                        try fileHandle.synchronize()
                    }
                } else {
                    // The file does not exist, create it
                    try message.write(to: logFileURL, atomically: true, encoding: .utf8)
                }

                // Check the file size
                Task { @MainActor in
                    self.checkAndRotateLogIfNeeded()
                }
            } catch {
                self.osLogger.error("Failed to write log: \(error.localizedDescription)")
            }
        }

        if synchronous {
            logQueue.sync(execute: work)
        } else {
            logQueue.async(execute: work)
        }
    }

    /// Check the log file and rotate if needed
    private func checkAndRotateLogIfNeeded() {
        guard let logFileURL = logFileURL else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            if let fileSize = attributes[.size] as? UInt64, fileSize > maxLogFileSize {
                // The file is too large, rotate it
                rotateLog()
            }
        } catch {
            // The file is missing or unreadable, ignore
        }
    }

    /// Rotate the log file
    private func rotateLog() {
        guard let logFileURL = logFileURL else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let archiveURL = logFileURL.deletingLastPathComponent()
            .appendingPathComponent("usagemeter_\(timestamp).log.old")

        do {
            // Rename the current log file
            try FileManager.default.moveItem(at: logFileURL, to: archiveURL)

            // Delete old archives (keep the 5 most recent)
            cleanupOldLogs()
        } catch {
            osLogger.error("Failed to rotate log: \(error.localizedDescription)")
        }
    }

    /// Clean up old log files
    private func cleanupOldLogs() {
        guard let logFileURL = logFileURL else { return }

        let logDirectory = logFileURL.deletingLastPathComponent()

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: logDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            // Keep only .old files
            let oldLogs = fileURLs.filter { $0.pathExtension == "old" }

            // Sort by creation time
            let sortedLogs = try oldLogs.sorted { url1, url2 in
                let date1 = try url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 > date2
            }

            // Delete old logs past the first 5
            if sortedLogs.count > 5 {
                for logURL in sortedLogs.dropFirst(5) {
                    try FileManager.default.removeItem(at: logURL)
                }
            }
        } catch {
            osLogger.error("Failed to cleanup old logs: \(error.localizedDescription)")
        }
    }

    /// Redact sensitive information
    private func sanitize(_ message: String) -> String {
        // Use the shared sensitive data redactor
        return SensitiveDataRedactor.redactText(message)
    }

    /// Convert to a system log level
    private func osLogLevel(for level: LogLevel) -> OSLogType {
        switch level {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }
}

// MARK: - Convenience Global Functions

/// Global logging convenience functions
@MainActor
func logDebug(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.debug(message, file: file, line: line, function: function)
}

@MainActor
func logInfo(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.info(message, file: file, line: line, function: function)
}

@MainActor
func logWarning(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.warning(message, file: file, line: line, function: function)
}

@MainActor
func logError(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.error(message, file: file, line: line, function: function)
}
