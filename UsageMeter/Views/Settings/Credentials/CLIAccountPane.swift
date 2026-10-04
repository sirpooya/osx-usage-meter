//
//  CLIAccountPane.swift
//  UsageMeter
//
//  CLI Account pane: adopt the account Claude Code is already signed in to.
//  Status with elapsed time, the synced account details, the credentials source picker
//  for people running more than one CLAUDE_CONFIG_DIR, then the explainer.
//

import Combine
import SwiftUI

struct CLIAccountPane: View {
    @ObservedObject private var cliSync = ClaudeCodeSyncService.shared

    /// Drives the elapsed time line, which would otherwise sit frozen at its first value
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CredentialPageHeader(
                title: L.CLISync.title,
                subtitle: L.CredentialsNav.cliPaneSubtitle
            )

            statusCard

            if cliSync.isSynced, let credentials = cliSync.credentials {
                accountDetailsCard(credentials: credentials)
            } else {
                connectCard
            }

            if cliSync.availableEntries.count > 1 {
                credentialsSourceCard
            }

            CredentialInfoBox(
                title: L.CLISync.aboutTitle,
                points: [L.CLISync.aboutPoint1, L.CLISync.aboutPoint2, L.CLISync.aboutPoint3]
            )
        }
        .onAppear { cliSync.refreshEntries() }
        .onReceive(ticker) { tick = $0 }
    }

    // MARK: - Status

    private var statusCard: some View {
        CredentialStatusCard(
            isConnected: cliSync.isSynced,
            title: statusTitle,
            detail: statusDetail
        ) {
            if case .syncing = cliSync.state {
                ProgressView().controlSize(.small)
            }
        }
        .id(tick)
    }

    /// The state alone, one or two words. The pane header above already says "CLI Account",
    /// so repeating it here left two competing bold lines with nothing between them.
    private var statusTitle: String {
        switch cliSync.state {
        case .synced: return L.CLISync.statusSynced
        case .syncing: return L.CLISync.statusSyncing
        case .failed: return L.CLISync.statusFailed
        case .notSynced:
            if cliSync.isSynced { return L.CLISync.statusSynced }
            return cliSync.isAvailable ? L.CLISync.statusAvailable : L.CLISync.statusUnavailable
        }
    }

    /// The line under the title: what the state means, or how long ago the sync happened.
    /// A bare "3m" was the whole second line before, which named nothing.
    private var statusDetail: String? {
        if case .failed(let message) = cliSync.state { return message }
        if cliSync.isSynced { return cliSync.timeSinceSync.map(L.CLISync.lastSynced) }
        if case .syncing = cliSync.state { return nil }
        return cliSync.isAvailable ? L.CLISync.statusAvailableDetail : L.CLISync.statusUnavailableDetail
    }

    // MARK: - Synced details

    private func accountDetailsCard(credentials: ClaudeCodeCredentials) -> some View {
        CredentialCard(
            title: L.CLISync.accountDetails,
            subtitle: L.CLISync.accountDetailsSubtitle
        ) {
            CredentialDetailRows {
                // Masked only: the full token is never displayed, copied or logged
                CredentialDetailRow(
                    icon: "key",
                    label: L.CLISync.accessToken,
                    value: credentials.maskedAccessToken,
                    monospaced: true
                )

                if !credentials.subscriptionType.isEmpty {
                    CredentialDetailRow(
                        icon: "person.crop.circle",
                        label: L.CLISync.subscription,
                        value: credentials.subscriptionType
                    )
                }

                if !credentials.scopes.isEmpty {
                    CredentialDetailRow(
                        icon: "checkmark.shield",
                        label: L.CLISync.scopes,
                        value: credentials.scopes.joined(separator: ", ")
                    )
                }
            }

            HStack(spacing: 8) {
                CredentialPrimaryButton(
                    title: L.CLISync.resync,
                    systemImage: "arrow.triangle.2.circlepath",
                    isBusy: isSyncing
                ) {
                    Task { await cliSync.sync() }
                }

                CredentialDestructiveButton(title: L.CLISync.remove) {
                    cliSync.removeSync()
                }

                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private var isSyncing: Bool {
        if case .syncing = cliSync.state { return true }
        return false
    }

    // MARK: - Not synced yet

    private var connectCard: some View {
        CredentialCard(title: L.CLISync.configuration) {
            Text(cliSync.isAvailable ? L.CLISync.readyHint : L.CLISync.notFoundHint)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                CredentialPrimaryButton(
                    title: L.CLISync.syncNow,
                    systemImage: "arrow.down.circle",
                    isBusy: isSyncing,
                    isEnabled: cliSync.isAvailable
                ) {
                    Task { await cliSync.sync() }
                }

                CredentialSecondaryButton(title: L.CLISync.refresh, systemImage: "arrow.clockwise") {
                    cliSync.refreshEntries()
                }

                Spacer()
            }
        }
    }

    // MARK: - Credentials source

    private var credentialsSourceCard: some View {
        CredentialCard(
            title: L.CLISync.advancedTitle,
            subtitle: L.CLISync.advancedSubtitle
        ) {
            HStack(spacing: 8) {
                Text(L.CLISync.keychainEntry)
                    .font(.system(size: 12))

                Picker("", selection: Binding(
                    get: { cliSync.pinnedService ?? "" },
                    set: { cliSync.pinnedService = $0.isEmpty ? nil : $0 }
                )) {
                    Text(L.CLISync.automatic).tag("")
                    ForEach(cliSync.availableEntries) { entry in
                        Text(entry.displayName).tag(entry.service)
                    }
                }
                .labelsHidden()

                CredentialSecondaryButton(title: L.CLISync.refresh, systemImage: "arrow.clockwise") {
                    cliSync.refreshEntries()
                }
            }

            Text(L.CLISync.advancedHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
