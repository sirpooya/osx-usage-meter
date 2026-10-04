//
//  UsageHistory.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-08-21.
//
//  History sample models. Ported from hamed-elfayome/Claude-Usage-Tracker (MIT)
//  and simplified: our OAuth usage endpoint returns session and weekly figures in
//  one response, so a single snapshot carries both series instead of the
//  competitor's per-series snapshots with a resetType discriminator.
//

import Foundation

/// One recorded usage sample, taken from a successful `/api/oauth/usage` poll.
struct UsageSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    /// When the sample was recorded
    let timestamp: Date
    /// Session (5 hour) utilization percentage, 0-100
    let sessionPercentage: Double?
    /// Weekly (7 day, all models) utilization percentage, 0-100
    let weeklyPercentage: Double?
    /// Weekly per model utilization keyed by the API's display name ("Fable", "Opus", ...).
    /// Not charted yet, recorded so per model history exists when the UI grows into it.
    let modelPercentages: [String: Double]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sessionPercentage: Double?,
        weeklyPercentage: Double?,
        modelPercentages: [String: Double] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionPercentage = sessionPercentage
        self.weeklyPercentage = weeklyPercentage
        self.modelPercentages = modelPercentages
    }
}

/// One recorded API Console billing sample (pay as you go spend, in minor units).
struct BillingSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let spendCents: Int
    let currency: String

    init(id: UUID = UUID(), timestamp: Date = Date(), spendCents: Int, currency: String) {
        self.id = id
        self.timestamp = timestamp
        self.spendCents = spendCents
        self.currency = currency
    }
}

/// Everything the history file holds. Both arrays are kept in insertion
/// (chronological) order.
struct UsageHistoryData: Codable, Equatable {
    var usage: [UsageSnapshot]
    var billing: [BillingSnapshot]

    init(usage: [UsageSnapshot] = [], billing: [BillingSnapshot] = []) {
        self.usage = usage
        self.billing = billing
    }

    var isEmpty: Bool { usage.isEmpty && billing.isEmpty }
}
