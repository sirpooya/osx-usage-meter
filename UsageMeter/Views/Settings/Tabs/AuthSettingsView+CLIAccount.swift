//
//  AuthSettingsView+CLIAccount.swift
//  UsageMeter
//
//  The "CLI Account" card: adopt the account Claude Code CLI already signed in, a zero paste login.
//  It sits alongside the manual sessionKey and browser OAuth paths, and configuring any one of the three produces data.
//

import SwiftUI

extension AuthSettingsView {

    // MARK: - CLI Account Card

    var cliAccountCard: some View {
        SettingCard(
            icon: "terminal.fill",
            iconColor: .green,
            title: L.CLISync.title,
            hint: L.CLISync.hint
        ) {
            VStack(alignment: .leading, spacing: 16) {
                cliStatusRow

                if cliSync.isSynced, let credentials = cliSync.credentials {
                    cliAccountDetails(credentials: credentials)
                }

                cliActionRow

                // Only a machine with several CLAUDE_CONFIG_DIRs needs the entry picked by hand, so a single account setup is left alone
                if cliSync.availableEntries.count > 1 {
                    Divider()
                    cliCredentialsSourceSection
                }
            }
            .onAppear { cliSync.refreshEntries() }
        }
    }

    // MARK: - Status row

    private var cliStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cliStatusColor)
                .frame(width: 8, height: 8)

            Text(cliStatusText)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            if case .syncing = cliSync.state {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var cliStatusColor: Color {
        switch cliSync.state {
        case .synced: return .green
        case .failed: return .orange
        case .syncing: return .blue
        case .notSynced: return cliSync.isSynced ? .green : .secondary
        }
    }

    private var cliStatusText: String {
        switch cliSync.state {
        case .synced: return L.CLISync.statusSynced
        case .syncing: return L.CLISync.statusSyncing
        case .failed(let message): return message
        case .notSynced:
            if cliSync.isSynced { return L.CLISync.statusSynced }
            return cliSync.isAvailable ? L.CLISync.statusAvailable : L.CLISync.statusUnavailable
        }
    }

    // MARK: - Synced account detail

    private func cliAccountDetails(credentials: ClaudeCodeCredentials) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only the masked token is shown: the full value is never displayed, copied or logged
            cliDetailRow(
                icon: "key.fill",
                iconColor: .red,
                label: L.CLISync.accessToken,
                value: credentials.maskedAccessToken,
                monospaced: true
            )

            if !credentials.subscriptionType.isEmpty {
                cliDetailRow(
                    icon: "person.crop.circle.badge.checkmark",
                    iconColor: .blue,
                    label: L.CLISync.subscription,
                    value: credentials.subscriptionType,
                    monospaced: false
                )
            }

            if !credentials.scopes.isEmpty {
                cliDetailRow(
                    icon: "checkmark.shield.fill",
                    iconColor: .green,
                    label: L.CLISync.scopes,
                    value: credentials.scopes.joined(separator: ", "),
                    monospaced: false
                )
            }
        }
    }

    private func cliDetailRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: String,
        monospaced: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(iconColor)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Action buttons

    private var cliActionRow: some View {
        HStack(spacing: 8) {
            if cliSync.isSynced {
                Button {
                    Task { await cliSync.sync() }
                } label: {
                    Label(L.CLISync.resync, systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    cliSync.removeSync()
                } label: {
                    Label(L.CLISync.remove, systemImage: "trash")
                }
                .controlSize(.small)
            } else {
                Button {
                    Task { await cliSync.sync() }
                } label: {
                    Label(L.CLISync.syncNow, systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(!cliSync.isAvailable)

                if !cliSync.isAvailable {
                    Button {
                        cliSync.refreshEntries()
                    } label: {
                        Label(L.CLISync.refresh, systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
            }

            Spacer()
        }
    }

    // MARK: - Advanced: credential source

    private var cliCredentialsSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.CLISync.advancedTitle)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Picker(L.CLISync.keychainEntry, selection: Binding(
                    get: { cliSync.pinnedService ?? "" },
                    set: { cliSync.pinnedService = $0.isEmpty ? nil : $0 }
                )) {
                    Text(L.CLISync.automatic).tag("")
                    ForEach(cliSync.availableEntries) { entry in
                        Text(entry.displayName).tag(entry.service)
                    }
                }
                .labelsHidden()

                Button {
                    cliSync.refreshEntries()
                } label: {
                    Label(L.CLISync.refresh, systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            Text(L.CLISync.advancedHint)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
