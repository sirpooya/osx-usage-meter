//
//  ResetTimeChange.swift
//  UsageMeter
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Detect whether the reset time changed, which decides whether the reset validation timers are cancelled or rescheduled
/// - Parameters:
///   - oldTime: the previously recorded reset time
///   - newTime: the reset time just fetched
/// - Returns: true when they differ by more than 1 second (including one being nil and the other not)
func hasResetTimeChanged(from oldTime: Date?, to newTime: Date?) -> Bool {
    if oldTime == nil && newTime == nil {
        return false
    }
    if (oldTime == nil) != (newTime == nil) {
        return true
    }
    if let old = oldTime, let new = newTime {
        return abs(old.timeIntervalSince(new)) > 1.0
    }
    return false
}
