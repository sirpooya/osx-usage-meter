//
//  UsageData+Formatting.swift
//  ClaudeUsage
//
//  Locale-aware display formatting for `UsageData` / `ExtraUsageData`. Lives
//  outside `ClaudeAPIResponseModels.swift` because it depends on `L.*` and
//  `UserSettings.shared` — both main-app-only — and the response-models file
//  is shared with a SwiftPM test target.
//

import Foundation

// MARK: - UsageData.LimitData formatting

extension UsageData.LimitData {
    /// Formatted time left (for the 5 hour limit, shows X hours Y minutes)
    /// - Returns: the localized description of the time left (for example "2 hours 30 minutes")
    var formattedResetsInHours: String {
        guard let resetsAt = resetsAt else {
            return L.UsageData.notStartedReset
        }

        let resetsIn = resetsAt.timeIntervalSinceNow

        guard resetsIn > 0 else {
            return L.UsageData.resettingSoon
        }

        // Round up to the minute (with ceil)
        let totalMinutes = Int(ceil(resetsIn / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return L.UsageData.resetsInHours(hours, minutes)
        } else {
            return L.UsageData.resetsInMinutes(minutes)
        }
    }

    /// Formatted time left (for the 7 day limit, shows X days Y hours)
    /// - Returns: the localized description of the time left (for example "about 3 days 12 hours left")
    var formattedResetsInDays: String {
        guard let resetsAt = resetsAt else {
            return L.UsageData.notStartedReset
        }

        let resetsIn = resetsAt.timeIntervalSinceNow

        guard resetsIn > 0 else {
            return L.UsageData.resettingSoon
        }

        // Round up to the hour
        let totalHours = Int(ceil(resetsIn / 3600))
        let days = totalHours / 24
        let hours = totalHours % 24

        if days > 0 {
            return L.UsageData.resetsInDays(days, hours)
        } else {
            // Under a day, show "about X hours"
            return L.UsageData.resetsInHours(hours, 0)
        }
    }

    /// Formatted reset time (short form, for the 5 hour limit)
    /// - Returns: the localized reset time (for example "Today 14:30" or "Tomorrow 09:00")
    var formattedResetTimeShort: String {
        guard let resetsAt = resetsAt else {
            return L.UsageData.unknown
        }

        var calendar = Calendar.current
        calendar.locale = UserSettings.shared.appLocale
        let timeString = TimeFormatHelper.formatTimeOnly(resetsAt)

        if calendar.isDateInToday(resetsAt) {
            return "\(L.UsageData.today) \(timeString)"
        } else if calendar.isDateInTomorrow(resetsAt) {
            return "\(L.UsageData.tomorrow) \(timeString)"
        } else {
            return TimeFormatHelper.formatDateTime(resetsAt, dateTemplate: "Md")
        }
    }

    /// Formatted reset time (long form, for the 7 day limit)
    /// - Returns: the localized reset date (for example "11月29日 14时" or "Nov 29 2 PM")
    var formattedResetDateLong: String {
        guard let resetsAt = resetsAt else {
            return L.UsageData.unknown
        }

        return TimeFormatHelper.formatDateHour(resetsAt, dateTemplate: "MMMd")
    }

    // MARK: - Minimal formatting (for the two line dual mode display)

    /// Minimally formatted time left (zero units omitted)
    /// - Examples: "45m", "1h30m", "3d12h"
    var formattedCompactRemaining: String {
        guard let resetsAt = resetsAt else {
            return "-"
        }

        let resetsIn = resetsAt.timeIntervalSinceNow
        guard resetsIn > 0 else {
            return L.UsageData.compactResettingSoon
        }

        let totalMinutes = Int(ceil(resetsIn / 60))

        // Under an hour, show minutes only
        if totalMinutes < 60 {
            return L.UsageData.compactRemainingMinutes(totalMinutes)
        }

        let totalHours = totalMinutes / 60

        // Under two hours, keep the minutes. This is the range where the countdown is actually
        // being acted on, and "1h left" covers everything from 60 to 119 minutes, which is the
        // difference between starting another task and not.
        if totalHours < 2 {
            return L.UsageData.compactRemainingHours(totalHours, totalMinutes % 60)
        }

        // Two hours and up but under a day, show hours only. Same reasoning as the days branch
        // below: once hours are the unit being read, the minutes beside them are precision nobody
        // acts on, and floored hours mean the reset can only land later than the label says,
        // never earlier.
        if totalHours < 24 {
            return L.UsageData.compactRemainingHoursOnly(totalHours)
        }

        // Over a day, show days only. Days are the coarse unit the user is reading at that point,
        // so the hours beside them add precision nobody acts on ("1d 0h left" reads worse than
        // "1d left").
        //
        // Floored, the same count the days-plus-hours version used, so "1d left" means a full day
        // is left and the reset can only come later than the label implies. Rounding up instead
        // would print "2d left" with 25h to go, promising time the user does not have.
        let days = totalHours / 24

        return L.UsageData.compactRemainingDaysOnly(days)
    }

    /// Formatted reset time (for the 5 hour limit)
    /// - Examples: "Today 15:07" / "Today 3:07 PM", "Tomorrow 09:30" / "Tomorrow 9:30 AM"
    var formattedCompactResetTime: String {
        guard let resetsAt = resetsAt else {
            return "-"
        }

        let calendar = Calendar.current

        // Decide between today and tomorrow
        let prefix: String
        if calendar.isDateInToday(resetsAt) {
            prefix = L.UsageData.today
        } else if calendar.isDateInTomorrow(resetsAt) {
            prefix = L.UsageData.tomorrow
        } else {
            // Any other date shows month and day
            let formatter = DateFormatter()
            formatter.locale = UserSettings.shared.appLocale
            formatter.timeZone = TimeZone.current
            // Different date formats per language
            let langCode = UserSettings.shared.appLocale.identifier
            if langCode.hasPrefix("zh") || langCode.hasPrefix("ja") {
                formatter.dateFormat = "M月d日"  // Chinese / Japanese: 12月25日
            } else if langCode.hasPrefix("ko") {
                formatter.dateFormat = "M월d일"  // Korean: 12월25일
            } else {
                formatter.dateFormat = "MMM d"   // English: Dec 25
            }
            prefix = formatter.string(from: resetsAt)
        }

        let timeString = TimeFormatHelper.formatTimeOnly(resetsAt)

        return "\(prefix) \(timeString)"
    }

    /// Formatted reset date (for the 7 day limit, hour precision)
    /// - Examples: "Dec 16 15:00" / "Dec 16 3 PM" (English), "12月16日 15时" (Chinese)
    var formattedCompactResetDate: String {
        guard let resetsAt = resetsAt else {
            return "-"
        }

        return TimeFormatHelper.formatDateHour(resetsAt, dateTemplate: "MMMd")
    }

    /// Formatted reset date (minute precision, Codex secondary_window only)
    /// - Examples: "Dec 16 15:42" / "Dec 16 3:42 PM", "12月16日 15:42"
    var formattedCompactResetDateWithMinutes: String {
        guard let resetsAt = resetsAt else {
            return "-"
        }

        return TimeFormatHelper.formatDateMinute(resetsAt, dateTemplate: "MMMd")
    }

    /// Minimally formatted time left (minute precision, Codex secondary_window only)
    /// - Examples: "45m", "1h30m", "3d12h35m"
    var formattedCompactRemainingWithMinutes: String {
        guard let resetsAt = resetsAt else {
            return "-"
        }

        let resetsIn = resetsAt.timeIntervalSinceNow
        guard resetsIn > 0 else {
            return L.UsageData.compactResettingSoon
        }

        let totalMinutes = Int(ceil(resetsIn / 60))

        if totalMinutes < 60 {
            return L.UsageData.compactRemainingMinutes(totalMinutes)
        }

        let totalHours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60

        if totalHours < 24 {
            return L.UsageData.compactRemainingHours(totalHours, remainingMinutes)
        }

        let days = totalHours / 24
        let hours = totalHours % 24

        return L.UsageData.compactRemainingDaysWithMinutes(days, hours, remainingMinutes)
    }
}

// MARK: - UsageData formatting (backward-compat shims)

extension UsageData {
    /// Formatted time left
    /// - Note: backward compatible property
    var formattedResetsIn: String {
        return primaryLimit?.formattedResetsInHours ?? L.UsageData.notStartedReset
    }

    /// Formatted reset time
    /// - Note: backward compatible property
    var formattedResetTime: String {
        return primaryLimit?.formattedResetTimeShort ?? L.UsageData.unknown
    }

    /// Status color for a usage percentage
    /// - Note: backward compatible property
    var statusColor: String {
        let percentage = self.percentage
        if percentage < 50 {
            return "green"
        } else if percentage < 70 {
            return "yellow"
        } else if percentage < 90 {
            return "orange"
        } else {
            return "red"
        }
    }
}

// MARK: - ExtraUsageData formatting

extension ExtraUsageData {
    /// Formatted used amount over total amount (default mode)
    /// - Returns: for example "$12.50 / $50.00"
    var formattedUsageAmount: String {
        guard enabled, let used = used, let limit = limit else {
            return L.ExtraUsage.notEnabled
        }
        return L.ExtraUsage.usageAmount(used, limit, symbol: currencySymbol)
    }

    /// Formatted remaining amount (remaining mode)
    /// - Returns: for example "$37 left"
    var formattedRemainingAmount: String {
        guard enabled, let used = used, let limit = limit else {
            return L.ExtraUsage.notEnabled
        }
        let remaining = max(0, limit - used)
        return L.ExtraUsage.remainingAmount(remaining, symbol: currencySymbol)
    }

    /// Minimally formatted used amount (for list rows)
    /// - Returns: for example "$10.47/$25"
    var formattedCompactAmount: String {
        guard enabled, let used = used, let limit = limit else {
            return "-"
        }
        let sym = currencySymbol
        return String(format: "%@%.2f/%@%.0f", sym, used, sym, limit)
    }
}
