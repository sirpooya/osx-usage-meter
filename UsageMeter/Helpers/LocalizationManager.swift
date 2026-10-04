//
//  LocalizationManager.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-11-05.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine
import OSLog

/// Localization manager
/// Watches for language changes and drives view updates, so switching takes effect immediately
class LocalizationManager: ObservableObject {
    /// Shared instance
    static let shared = LocalizationManager()
    
    /// Update trigger, incremented on a language change to force views to rebuild
    @Published var updateTrigger: Int = 0
    
    /// Notification observer
    private var cancellable: AnyCancellable?
    
    private init() {
        // Listen for language change notifications
        cancellable = NotificationCenter.default
            .publisher(for: .languageChanged)
            .sink { [weak self] _ in
                // Bump the trigger on a language change, so every view using .id(updateTrigger) is rebuilt
                self?.updateTrigger += 1
                Logger.localization.debug("Language changed, triggering a view update")
            }
    }
    
    deinit {
        cancellable?.cancel()
    }
}
