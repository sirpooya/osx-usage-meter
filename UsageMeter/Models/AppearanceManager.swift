//
//  AppearanceManager.swift
//  UsageMeter
//
//  Extracted from UserSettings.swift (audit report 4.1): appearance mode persistence, applying it to NSApp,
//  and the system theme change observer, moved over unchanged.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import Combine

/// App appearance (light / dark / follow the system)
final class AppearanceManager: ObservableObject {
    private let defaults = UserDefaults.standard
    private var themeObserver: NSObjectProtocol?

    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            apply()
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    init() {
        if let appearanceString = defaults.string(forKey: "appearance"),
           let loaded = AppAppearance(rawValue: appearanceString) {
            appearance = loaded
        } else {
            appearance = .system
        }

        apply()

        // Watch for system appearance changes, updating automatically in "follow the system" mode
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.appearance == .system else { return }
            self.apply()
            // Appearance dependent icon rendering (the colored with background style, say) has to be redrawn too, otherwise the icon cache shows a stale appearance
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    deinit {
        if let themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
        }
    }

    /// Apply the current appearance setting to NSApp, so it takes effect globally
    /// Note: for a menu bar app (the accessory activation policy), NSApp.appearance = nil does not reliably follow the system appearance
    /// so "follow the system" mode reads the system appearance and sets it explicitly
    func apply() {
        DispatchQueue.main.async {
            switch self.appearance {
            case .system:
                let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
                NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
}
