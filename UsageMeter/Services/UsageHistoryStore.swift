//
//  UsageHistoryStore.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-08-21.
//
//  Records usage samples so the History tab has something to chart. Ported from
//  hamed-elfayome/Claude-Usage-Tracker (MIT). Its issue #260 is why this is a
//  JSON file in Application Support and not UserDefaults: multi megabyte history
//  blobs pushed their UserDefaults domain past the 4 MB CFPreferences hard limit,
//  which silently dropped every write to the domain, credentials included.
//

import Combine
import Foundation
import OSLog

/// Persists usage and billing samples to a single JSON file and publishes them
/// for the History tab. Recording is throttled here (not at the call sites), so
/// callers just report every success and the store decides what is worth keeping.
@MainActor
final class UsageHistoryStore: ObservableObject {
    static let shared = UsageHistoryStore()

    @Published private(set) var history = UsageHistoryData()

    /// Minimum spacing between recorded usage samples. Polls run every 60s when
    /// active; charting all of them would triple the file for no visible gain.
    private let usageRecordingInterval: TimeInterval = 5 * 60
    /// Billing figures only move on API traffic and are fetched on demand, so an
    /// hourly sample is plenty.
    private let billingRecordingInterval: TimeInterval = 60 * 60
    /// Time based retention. 90 days at 5 minute spacing is ~26k samples, well
    /// under a megabyte of JSON.
    private let retention: TimeInterval = 90 * 24 * 60 * 60

    private let lastUsageRecordKey = "usageHistory.lastRecordedAt"
    private let lastBillingRecordKey = "usageHistory.lastBillingRecordedAt"

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("UsageMeter", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("usageHistory.json")
    }

    private init() {
        history = loadFromDisk()
    }

    // MARK: - Recording

    /// Report a successful usage fetch. Throttled internally; most calls are no-ops.
    func record(_ data: UsageData) {
        guard data.fiveHour != nil || data.sevenDay != nil else { return }

        let now = Date()
        if let last = UserDefaults.standard.object(forKey: lastUsageRecordKey) as? Date,
           now.timeIntervalSince(last) < usageRecordingInterval {
            return
        }

        var models: [String: Double] = [:]
        for model in data.weeklyModels {
            if let name = model.modelName {
                models[name] = model.limit.percentage
            }
        }

        history.usage.append(UsageSnapshot(
            timestamp: now,
            sessionPercentage: data.fiveHour?.percentage,
            weeklyPercentage: data.sevenDay?.percentage,
            modelPercentages: models
        ))

        prune(now: now)
        save()
        UserDefaults.standard.set(now, forKey: lastUsageRecordKey)
    }

    /// Report a successful API Console spend fetch. Throttled internally.
    func recordBilling(spendCents: Int, currency: String) {
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: lastBillingRecordKey) as? Date,
           now.timeIntervalSince(last) < billingRecordingInterval {
            return
        }

        history.billing.append(BillingSnapshot(timestamp: now, spendCents: spendCents, currency: currency))
        prune(now: now)
        save()
        UserDefaults.standard.set(now, forKey: lastBillingRecordKey)
    }

    // MARK: - Persistence

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        history.usage.removeAll { $0.timestamp < cutoff }
        history.billing.removeAll { $0.timestamp < cutoff }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            Logger.settings.error("UsageHistoryStore: save failed: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() -> UsageHistoryData {
        guard let data = try? Data(contentsOf: fileURL) else { return UsageHistoryData() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(UsageHistoryData.self, from: data)
        } catch {
            Logger.settings.error("UsageHistoryStore: load failed: \(error.localizedDescription)")
            return UsageHistoryData()
        }
    }
}
