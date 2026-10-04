//
//  LoggerExtension.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-11-10.
//  Copyright © 2025 f-is-h. All rights reserved.
//


import OSLog

extension Logger {
    /// The app's shared subsystem identifier
    private static var subsystem = Bundle.main.bundleIdentifier ?? "in.pooya.usagemeter"

    /// Menu bar manager log
    /// Records menu bar, refresh and update check activity
    static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")

    /// User settings log
    /// Records settings changes, smart mode switches, launch at login and similar activity
    static let settings = Logger(subsystem: subsystem, category: "Settings")

    /// Keychain log
    /// Records reads, writes and deletes of sensitive data
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")

    /// API service log
    /// Records API requests, responses and errors
    static let api = Logger(subsystem: subsystem, category: "API")

    /// Localization log
    /// Records language switches and other localization activity
    static let localization = Logger(subsystem: subsystem, category: "Localization")
}

// MARK: - Log levels
/*
 OSLog has 5 log levels, and a Release build disables the low ones automatically:

 1. .debug    - debug detail, printed while developing only, not executed in Release
 2. .info     - general information, not persisted by default
 3. .notice   - notable events, persisted by default
 4. .error    - errors, always persisted
 5. .fault    - critical failures, always persisted

 Examples:
 ```swift
 Logger.menuBar.debug("debug detail")
 Logger.menuBar.info("general info")
 Logger.menuBar.notice("notable event")
 Logger.menuBar.error("Error: \(error.localizedDescription)")
 Logger.menuBar.fault("critical failure")
 ```

 Reading the logs:
 1. Xcode Console (while developing)
 2. Console.app (search subsystem:in.pooya.usagemeter)
 3. Command line: log show --predicate 'subsystem == "in.pooya.usagemeter"' --last 1h
 */
