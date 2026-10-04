//
//  ClaudeAPIResponseModels.swift
//  UsageMeter
//
//  Pure-data types for the Claude.ai API: wire models (`UsageResponse`,
//  `ExtraUsageResponse`, `ErrorResponse`, `Organization`) and the in-memory
//  models they decode into (`UsageData`, `ExtraUsageData`).
//
//  Lives in Helpers/ so it can be cherry-picked into a SwiftPM test target —
//  every symbol here must stay free of `L.*`, `Logger`, `UserSettings`, or any
//  UI dependency. The display-side formatting (locale-aware reset strings,
//  status colors, etc.) lives in `UsageData+Formatting.swift` as extensions.
//

import Foundation

// MARK: - Organization

/// Organization model
/// Matches the organization info returned by the Claude API /api/organizations
nonisolated struct Organization: Codable, Sendable, Identifiable, Equatable {
    /// Numeric organization ID
    let id: Int
    /// Organization UUID (used in API calls)
    let uuid: String
    /// Organization name
    let name: String
    /// Created at
    let createdAt: String?
    /// Updated at
    let updatedAt: String?
    /// Organization capabilities
    let capabilities: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, name, capabilities
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func == (lhs: Organization, rhs: Organization) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}

// MARK: - Usage Response (wire model)

/// API response model
/// Matches the JSON the Claude API returns
nonisolated struct UsageResponse: Codable, Sendable {
    /// 5 hour usage limit data
    let five_hour: LimitUsage
    /// 7 day usage limit data
    let seven_day: LimitUsage?
    /// 7 day OAuth app usage (unused for now)
    let seven_day_oauth_apps: LimitUsage?
    /// 7 day Opus usage limit data
    let seven_day_opus: LimitUsage?
    /// 7 day Sonnet usage limit data (new field)
    let seven_day_sonnet: LimitUsage?

    /// The unified limits array of the newer API (the Claude 5 era).
    /// Weekly limits scoped to a specific model (Fable, say) no longer arrive in the separate
    /// `seven_day_opus` / `seven_day_sonnet` fields; they show up here as entries with
    /// `kind == "weekly_scoped"`, identified by `scope.model.display_name`.
    let limits: [LimitEntry]?

    /// Generic limit usage detail (covers 5 hour, 7 day and every other limit)
    struct LimitUsage: Codable, Sendable {
        /// Current utilization (0-100, may be fractional)
        let utilization: Double
        /// Reset time (ISO 8601), nil means usage has not started yet
        let resets_at: String?
    }

    /// A single entry in the newer `limits` array.
    /// - `kind`: "session" / "weekly_all" / "weekly_scoped" and so on
    /// - `percent`: usage percentage (0-100)
    /// - `scope.model.display_name`: the model name when the limit is scoped to one (for example "Fable")
    struct LimitEntry: Codable, Sendable {
        let kind: String?
        let group: String?
        let percent: Double?
        let severity: String?
        let resets_at: String?
        let is_active: Bool?
        let scope: Scope?

        struct Scope: Codable, Sendable {
            let model: Model?
            let surface: String?

            struct Model: Codable, Sendable {
                let id: String?
                let display_name: String?
            }
        }
    }

    /// Convert the API response into the app's own UsageData model
    /// - Returns: the converted UsageData
    /// - Note: times are rounded automatically, so the display is accurate
    func toUsageData() -> UsageData {
        // Parse the 5 hour limit data
        let fiveHourData = parseLimitData(five_hour)

        // Parse the 7 day limit data. Every Claude account has a 7 day limit;
        // before usage starts the API may return 0 with no resets_at, which is still kept as a 0% placeholder.
        let sevenDayData: UsageData.LimitData = {
            guard let sevenDay = seven_day else {
                return UsageData.LimitData(percentage: 0, resetsAt: nil)
            }
            let parsed = parseLimitData(sevenDay)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }()

        // Parse the Opus limit data (the legacy separate field, only when present and valid)
        let legacyOpus: UsageData.LimitData? = {
            guard let opus = seven_day_opus else {
                return nil
            }
            if opus.utilization == 0 && opus.resets_at == nil {
                return nil
            }
            let parsed = parseLimitData(opus)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }()

        // Parse the Sonnet limit data (the legacy separate field, only when present and valid)
        let legacySonnet: UsageData.LimitData? = {
            guard let sonnet = seven_day_sonnet else {
                return nil
            }
            if sonnet.utilization == 0 && sonnet.resets_at == nil {
                return nil
            }
            let parsed = parseLimitData(sonnet)
            return UsageData.LimitData(percentage: parsed.percentage, resetsAt: parsed.resetsAt)
        }()

        // Parse the per model weekly limits from the newer `limits` array (the Claude 5 era, Fable for instance).
        // These no longer arrive in the separate seven_day_opus / seven_day_sonnet fields, they appear
        // in limits as entries carrying scope.model. Keep the order they arrive in, and drop entries
        // with no model name or no percentage.
        let scopedModels: [(name: String, limit: UsageData.LimitData)] = (limits ?? []).compactMap { entry in
            guard let name = entry.scope?.model?.display_name, !name.isEmpty,
                  let percent = entry.percent else { return nil }
            let limit = UsageData.LimitData(percentage: percent, resetsAt: parseResetDate(entry.resets_at))
            return (name, limit)
        }

        // Merge the weekly model limits: the legacy seven_day_opus / seven_day_sonnet fields become the first two entries,
        // followed by the model entries from the newer limits array. Purely in source order, no local reordering and no truncation:
        // order and model names both come from the Claude API. The legacy fields carry no display_name, so it is left nil and
        // the UI falls back to "Opus/Sonnet Weekly" per slot.
        var weeklyModels: [UsageData.WeeklyModelLimit] = []
        if let legacyOpus = legacyOpus {
            weeklyModels.append(UsageData.WeeklyModelLimit(modelName: nil, limit: legacyOpus))
        }
        if let legacySonnet = legacySonnet {
            weeklyModels.append(UsageData.WeeklyModelLimit(modelName: nil, limit: legacySonnet))
        }
        weeklyModels.append(contentsOf: scopedModels.map {
            UsageData.WeeklyModelLimit(modelName: $0.name, limit: $0.limit)
        })

        return UsageData(
            fiveHour: UsageData.LimitData(percentage: fiveHourData.percentage, resetsAt: fiveHourData.resetsAt),
            sevenDay: sevenDayData,
            weeklyModels: weeklyModels,
            extraUsage: nil  // Extra Usage is fetched through its own API in phase 5
        )
    }

    /// Parse an ISO 8601 reset time string into a Date (rounded to the second).
    /// Matches the time parsing inside parseLimitData, and is reused for limits array entries.
    private func parseResetDate(_ resetString: String?) -> Date? {
        guard let resetString = resetString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: resetString) else { return nil }
        let rounded = round(date.timeIntervalSinceReferenceDate)
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    /// Parse the data of a single limit (5 hour or 7 day)
    /// - Parameter limit: the LimitUsage struct
    /// - Returns: a tuple of the percentage and the reset time
    private func parseLimitData(_ limit: LimitUsage) -> (percentage: Double, resetsAt: Date?) {
        let resetsAt: Date?
        if let resetString = limit.resets_at {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: resetString) {
                // Round the time to the nearest second
                // For example: 05:59:59.645 becomes 06:00:00
                //       06:00:00.159 → 06:00:00
                let interval = date.timeIntervalSinceReferenceDate
                let roundedInterval = round(interval)
                resetsAt = Date(timeIntervalSinceReferenceDate: roundedInterval)
            } else {
                resetsAt = nil
            }
        } else {
            resetsAt = nil
        }

        return (percentage: Double(limit.utilization), resetsAt: resetsAt)
    }
}

// MARK: - Extra Usage Response (wire model)

/// Extra Usage API response model
/// Parses what /api/organizations/{id}/overage_spend_limit returns
nonisolated struct ExtraUsageResponse: Codable, Sendable {
    /// Limit type (for example "organization")
    let limit_type: String?
    /// Whether it is enabled
    let is_enabled: Bool?
    /// Monthly limit (in cents), new field name
    let monthly_limit: Int?
    /// Monthly limit (in cents), old field name
    let monthly_credit_limit: Int?
    /// Currency (for example "EUR", "USD")
    let currency: String?
    /// Amount used (in cents, the API may return a float such as 21.0)
    let used_credits: Double?
    /// Credits exhausted
    let out_of_credits: Bool?

    // MARK: - Legacy fields (backwards compatibility)
    let type: String?
    let spend_limit_currency: String?
    let spend_limit_amount_cents: Int?
    let balance_cents: Int?

    /// Convert to ExtraUsageData
    /// - Returns: the converted ExtraUsageData, or nil when the data is invalid
    func toExtraUsageData() -> ExtraUsageData? {
        let resolvedCurrency = (currency ?? spend_limit_currency ?? "USD").uppercased()
        // Prefer the new monthly_limit field, falling back to the old name, both in cents
        let limitCents = monthly_limit ?? monthly_credit_limit ?? spend_limit_amount_cents
        // used_credits is in cents (the API may return a float, so 21.0 means 21 cents)
        let usedCents = used_credits ?? balance_cents.map { Double($0) }

        // Use the is_enabled field, falling back to a limit check
        let enabled = is_enabled ?? (limitCents.map { $0 > 0 } ?? false)

        guard enabled, let limitCents = limitCents, limitCents > 0 else {
            return ExtraUsageData(
                enabled: false,
                used: nil,
                limit: nil,
                currency: resolvedCurrency
            )
        }

        // Cents to dollars: divide by 100
        let limit = Double(limitCents) / 100.0
        let used = (usedCents ?? 0.0) / 100.0

        return ExtraUsageData(
            enabled: true,
            used: used,
            limit: limit,
            currency: resolvedCurrency
        )
    }
}

// MARK: - Error Response (wire model)

/// API error response model
/// Matches the error structure the Claude API returns
nonisolated struct ErrorResponse: Codable, Sendable {
    let type: String
    let error: ErrorDetail

    /// Error detail
    struct ErrorDetail: Codable, Sendable {
        let type: String
        let message: String
    }
}

// MARK: - Usage Data (in-memory storage)

/// Usage data model
/// The app's normalized usage data structure
///
/// Storage-only here — locale-aware formatting (resetsInHours, statusColor,
/// etc.) lives in `UsageData+Formatting.swift` as extensions, so this file
/// can be compiled by a SwiftPM test target without dragging in
/// `LocalizationHelper` / `UserSettings`.
struct UsageData: Codable, Sendable {
    /// 5 hour limit data (optional)
    let fiveHour: LimitData?
    /// 7 day limit data (optional)
    let sevenDay: LimitData?
    /// Weekly per model limits, in the order the Claude API `limits` returns them (Fable / Opus / Sonnet, say).
    /// Carries any number of model limits, with no local reordering or truncation: order and model names both come from the API;
    /// the legacy seven_day_opus / seven_day_sonnet fields become the first two entries of this array.
    /// The menu bar has room for the first two only (see the `opus` and `sonnet` computed properties), while the popover walks all of them.
    let weeklyModels: [WeeklyModelLimit]
    /// Extra Usage limit data (optional)
    let extraUsage: ExtraUsageData?

    /// First model slot (the rounded square menu bar icon). Derived from the first entry of `weeklyModels`, reused by the menu bar and older code.
    var opus: LimitData? { weeklyModels.first?.limit }
    /// Second model slot (the chamfered square menu bar icon). Derived from the second entry of `weeklyModels`.
    var sonnet: LimitData? { weeklyModels.count > 1 ? weeklyModels[1].limit : nil }
    /// Real model display name for the opus slot (for example "Fable"). When nil the UI falls back to "Opus Weekly".
    var opusModelName: String? { weeklyModels.first?.modelName }
    /// Real model display name for the sonnet slot. When nil the UI falls back to "Sonnet Weekly".
    var sonnetModelName: String? { weeklyModels.count > 1 ? weeklyModels[1].modelName : nil }

    /// Main initializer: takes the ordered model limit array directly (keeps every model, for the real data path).
    init(
        fiveHour: LimitData?,
        sevenDay: LimitData?,
        weeklyModels: [WeeklyModelLimit],
        extraUsage: ExtraUsageData?
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.weeklyModels = weeklyModels
        self.extraUsage = extraUsage
    }

    /// Compatibility initializer: built from the old opus / sonnet slot parameters (for mocks, previews and DEBUG).
    /// Only non nil slots go into `weeklyModels`, in opus then sonnet order. Real data should use the main initializer,
    /// otherwise the third and later models are lost.
    init(
        fiveHour: LimitData?,
        sevenDay: LimitData?,
        opus: LimitData?,
        sonnet: LimitData?,
        extraUsage: ExtraUsageData?,
        opusModelName: String? = nil,
        sonnetModelName: String? = nil
    ) {
        var models: [WeeklyModelLimit] = []
        if let opus = opus {
            models.append(WeeklyModelLimit(modelName: opusModelName, limit: opus))
        }
        if let sonnet = sonnet {
            models.append(WeeklyModelLimit(modelName: sonnetModelName, limit: sonnet))
        }
        self.init(fiveHour: fiveHour, sevenDay: sevenDay, weeklyModels: models, extraUsage: extraUsage)
    }

    /// Data for a single limit (5 hour, 7 day, Opus, Sonnet)
    struct LimitData: Codable, Sendable {
        /// Current usage percentage (0-100)
        let percentage: Double
        /// Usage reset time, nil means usage has not started yet
        let resetsAt: Date?

        /// Time left until reset (seconds)
        /// - Returns: seconds left, or nil when resetsAt is nil
        var resetsIn: TimeInterval? {
            guard let resetsAt = resetsAt else { return nil }
            return resetsAt.timeIntervalSinceNow
        }
    }

    /// A weekly per model limit entry (model name plus usage data).
    /// `modelName` comes from the Claude API's `scope.model.display_name` (for example "Fable");
    /// the legacy seven_day_opus / seven_day_sonnet fields have no such field, so it is nil and the UI falls back per slot.
    struct WeeklyModelLimit: Codable, Sendable {
        let modelName: String?
        let limit: LimitData
    }

    /// Convenience: the data shown primarily (5 hour first, otherwise 7 day)
    var primaryLimit: LimitData? {
        return fiveHour ?? sevenDay
    }

    /// Whether both kinds of limit data are present
    var hasBothLimits: Bool {
        return fiveHour != nil && sevenDay != nil
    }

    /// Whether only the 7 day limit data is present
    var hasOnlySevenDay: Bool {
        return fiveHour == nil && sevenDay != nil
    }

    // MARK: - Backward compatible properties (kept for older code)

    /// Current usage percentage (0-100)
    /// - Note: backward compatible property, returns the primary limit's percentage
    var percentage: Double {
        return primaryLimit?.percentage ?? 0
    }

    /// Usage reset time, nil means usage has not started yet
    /// - Note: backward compatible property, returns the primary limit's reset time
    var resetsAt: Date? {
        return primaryLimit?.resetsAt
    }

    /// Time left until reset (seconds)
    /// - Note: backward compatible property
    var resetsIn: TimeInterval? {
        return primaryLimit?.resetsIn
    }
}

// MARK: - Extra Usage Data (in-memory storage)

/// Extra Usage data model
/// Extra paid usage (an amount rather than a percentage)
struct ExtraUsageData: Codable, Sendable {
    /// Whether Extra Usage is enabled
    let enabled: Bool
    /// Amount used
    let used: Double?
    /// Total limit
    let limit: Double?
    /// Currency code (ISO 4217, USD / EUR / GBP and so on)
    let currency: String

    /// Usage percentage (for a consistent display)
    var percentage: Double? {
        guard let used = used, let limit = limit, limit > 0 else {
            return nil
        }
        return (used / limit) * 100.0
    }

    /// Currency symbol (resolved from the ISO 4217 currency code)
    /// - Note: NumberFormatter rather than a hand written table, which covers every currency once and for all (KRW, CNY, CHF included),
    ///   always parsed with the en_US locale for a stable symbol ("$", "CA$") that does not follow the system language.
    var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        return formatter.currencySymbol ?? currency
    }
}
