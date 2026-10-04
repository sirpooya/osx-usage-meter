//
//  TimeFormatHelper.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-02-05.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Shared time formatting helper
/// Consistent time formatting that follows the user's time format preference
enum TimeFormatHelper {

    // MARK: - Format Strings

    /// Get the time format string (hour:minute)
    /// - Returns: the "HH:mm" or "h:mm a" format string
    static var timeOnlyFormat: String {
        return uses24HourFormat ? "HH:mm" : "h:mm a"
    }

    /// Get the hour format string (hour only)
    /// - Returns: the "HH" or "h a" format string
    static var hourOnlyFormat: String {
        return uses24HourFormat ? "HH" : "h a"
    }

    /// Get the date plus time template
    /// - Parameter dateTemplate: template for the date part (for example "MMMd")
    /// - Returns: the full date and time template
    static func dateTimeTemplate(dateTemplate: String) -> String {
        if uses24HourFormat {
            return "\(dateTemplate) HH:mm"
        } else {
            return "\(dateTemplate) h:mm a"
        }
    }

    /// Get the date plus hour template
    /// - Parameter dateTemplate: template for the date part (for example "MMMd")
    /// - Returns: the full date and hour template
    static func dateHourTemplate(dateTemplate: String) -> String {
        if uses24HourFormat {
            return "\(dateTemplate) HH"
        } else {
            return "\(dateTemplate) h a"
        }
    }

    // MARK: - Formatting Methods

    /// Format a time (hour:minute)
    /// - Parameter date: the date to format
    /// - Returns: the formatted time string
    static func formatTimeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = timeOnlyFormat
        return formatter.string(from: date)
    }

    /// Format an hour
    /// - Parameter date: the date to format
    /// - Returns: the formatted hour string
    static func formatHourOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = hourOnlyFormat
        return formatter.string(from: date)
    }

    /// Format a date and time
    /// - Parameters:
    ///   - date: the date to format
    ///   - dateTemplate: template for the date part
    /// - Returns: the formatted date and time string
    static func formatDateTime(_ date: Date, dateTemplate: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.timeZone = TimeZone.current
        formatter.setLocalizedDateFormatFromTemplate(dateTimeTemplate(dateTemplate: dateTemplate))
        return formatter.string(from: date)
    }

    /// Format a date and hour
    /// - Parameters:
    ///   - date: the date to format
    ///   - dateTemplate: template for the date part
    /// - Returns: the formatted date and hour string
    static func formatDateHour(_ date: Date, dateTemplate: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.timeZone = TimeZone.current

        // Build the format string from the language and the time format
        let langCode = UserSettings.shared.appLocale.identifier
        let dateString: String
        let timeString: String

        // Date format
        let dateFormatter = DateFormatter()
        dateFormatter.locale = UserSettings.shared.appLocale
        dateFormatter.timeZone = TimeZone.current
        if langCode.hasPrefix("zh") || langCode.hasPrefix("ja") {
            dateFormatter.dateFormat = "M月d日"
        } else if langCode.hasPrefix("ko") {
            dateFormatter.dateFormat = "M월d일"
        } else {
            dateFormatter.dateFormat = "MMM d"
        }
        dateString = dateFormatter.string(from: date)

        // Time format (hour only)
        let timeFormatter = DateFormatter()
        timeFormatter.locale = UserSettings.shared.appLocale
        timeFormatter.timeZone = TimeZone.current
        if uses24HourFormat {
            // 24 hour clock: show "15时" / "15時" or "15"
            if langCode.hasPrefix("zh") {
                timeFormatter.dateFormat = "H时"
            } else if langCode.hasPrefix("ja") {
                timeFormatter.dateFormat = "H時"
            } else if langCode.hasPrefix("ko") {
                timeFormatter.dateFormat = "H시"
            } else {
                timeFormatter.dateFormat = "HH':00'"
            }
        } else {
            // 12 hour clock: use the localized template
            timeFormatter.setLocalizedDateFormatFromTemplate("j")
        }
        timeString = timeFormatter.string(from: date)

        return "\(dateString) \(timeString)"
    }

    /// Format a date and minute (minute precision)
    /// - Parameters:
    ///   - date: the date to format
    ///   - dateTemplate: template for the date part
    /// - Returns: the formatted date plus hour and minute string (for example "12月16日 15:42")
    static func formatDateMinute(_ date: Date, dateTemplate: String) -> String {
        let langCode = UserSettings.shared.appLocale.identifier

        let dateFormatter = DateFormatter()
        dateFormatter.locale = UserSettings.shared.appLocale
        dateFormatter.timeZone = TimeZone.current
        if langCode.hasPrefix("zh") || langCode.hasPrefix("ja") {
            dateFormatter.dateFormat = "M月d日"
        } else if langCode.hasPrefix("ko") {
            dateFormatter.dateFormat = "M월d일"
        } else {
            dateFormatter.dateFormat = "MMM d"
        }
        let dateString = dateFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = UserSettings.shared.appLocale
        timeFormatter.timeZone = TimeZone.current
        timeFormatter.dateFormat = timeOnlyFormat  // "HH:mm" or "h:mm a"
        let timeString = timeFormatter.string(from: date)

        return "\(dateString) \(timeString)"
    }

    // MARK: - Detection

    /// Detect whether the 24 hour format should be used
    /// - Returns: true for the 24 hour clock, false for the 12 hour clock
    static var uses24HourFormat: Bool {
        let preference = UserSettings.shared.timeFormatPreference

        switch preference {
        case .system:
            return detectSystem24HourFormat()
        case .twelveHour:
            return false
        case .twentyFourHour:
            return true
        }
    }

    /// Detect whether the system uses the 24 hour clock
    /// - Returns: true when the system uses the 24 hour clock
    static func detectSystem24HourFormat() -> Bool {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let timeString = formatter.string(from: Date())

        // An AM/PM marker means the 12 hour clock
        // Check the common AM/PM variants
        let ampmIndicators = ["AM", "PM", "am", "pm", "上午", "下午", "午前", "午後", "오전", "오후"]
        for indicator in ampmIndicators {
            if timeString.contains(indicator) {
                return false
            }
        }

        return true
    }
}
