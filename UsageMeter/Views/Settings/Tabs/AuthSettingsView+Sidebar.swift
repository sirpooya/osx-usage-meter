//
//  AuthSettingsView+Sidebar.swift
//  UsageMeter
//
//  Two pane credentials layout: a sidebar listing every login method with its own
//  connected dot, and a detail pane for the selected one. Each method is independent,
//  so configuring any single one of them is enough to produce data.
//

import SwiftUI

extension AuthSettingsView {

    /// The login methods, one sidebar row each
    enum CredentialSection: String, CaseIterable, Identifiable {
        case claudeAI
        case apiConsole
        case cliAccount
        case codex
        case diagnostics

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .cliAccount: return "terminal.fill"
            case .claudeAI: return "key.fill"
            case .apiConsole: return "dollarsign.circle"
            case .codex: return "chevron.left.forwardslash.chevron.right"
            case .diagnostics: return "stethoscope"
            }
        }

        var title: String {
            switch self {
            case .cliAccount: return L.CLISync.title
            case .claudeAI: return L.CredentialsNav.claudeAI
            case .apiConsole: return L.CredentialsNav.apiConsole
            case .codex: return L.CredentialsNav.codex
            case .diagnostics: return L.CredentialsNav.diagnostics
            }
        }

        /// Pane heading and one line of subtitle
        var paneTitle: String {
            switch self {
            case .cliAccount: return L.CredentialsNav.cliPaneTitle
            case .claudeAI: return L.CredentialsNav.claudePaneTitle
            case .apiConsole: return L.APIConsole.paneTitle
            case .codex: return L.CredentialsNav.codexPaneTitle
            case .diagnostics: return L.CredentialsNav.diagnostics
            }
        }

        var paneSubtitle: String {
            switch self {
            case .cliAccount: return L.CredentialsNav.cliPaneSubtitle
            case .claudeAI: return L.CredentialsNav.claudePaneSubtitle
            case .apiConsole: return L.APIConsole.paneSubtitle
            case .codex: return L.CredentialsNav.codexPaneSubtitle
            case .diagnostics: return L.CredentialsNav.diagnosticsSubtitle
            }
        }
    }

    // MARK: - Two pane shell

    var credentialsSplitView: some View {
        HStack(alignment: .top, spacing: 0) {
            credentialsSidebar
            Divider()
            credentialsDetailPane
        }
    }

    // MARK: - Sidebar

    private var credentialsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Grouped by provider, each group headed by that provider's own icon.
            // "Claude" and "Codex" are brand names, so they are deliberately not localized.
            sectionHeader("Claude", icon: ImageHelper.createClaudeMark(size: sectionIconSize), topPadding: 0)

            ForEach([CredentialSection.claudeAI, .apiConsole, .cliAccount]) { section in
                sidebarRow(section)
            }

            sectionHeader("Codex", icon: ImageHelper.createCodexMark(size: sectionIconSize), topPadding: 14)

            sidebarRow(.codex)

            sectionHeader(L.CredentialsNav.sectionTools, icon: nil, topPadding: 14)

            sidebarRow(.diagnostics)

            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 168)
    }

    /// Sidebar group header. Provider groups carry their brand icon, plain groups just the label.
    private var sectionIconSize: CGFloat { 13 }

    private func sectionHeader(_ title: String, icon: NSImage?, topPadding: CGFloat) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: sectionIconSize, height: sectionIconSize)
            }

            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 10)
        .padding(.top, topPadding)
        .padding(.bottom, 4)
    }

    private func sidebarRow(_ section: CredentialSection) -> some View {
        let isSelected = credentialSection == section

        return Button {
            credentialSection = section
        } label: {
            HStack(spacing: 7) {
                Image(systemName: section.icon)
                    .font(.caption)
                    .frame(width: 15)
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(section.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Diagnostics is a tool rather than a credential, so it carries no connected dot
                if section != .diagnostics {
                    Circle()
                        .fill(isConnected(section) ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    /// Whether a login method currently holds usable credentials
    func isConnected(_ section: CredentialSection) -> Bool {
        switch section {
        case .cliAccount:
            return cliSync.isSynced
        case .apiConsole:
            return ConsoleAPIService.shared.isConfigured
        case .claudeAI:
            // Only manually pasted or browser OAuth accounts count here, a CLI synced one belongs to its own row
            return settings.accounts.contains { !$0.credentialSource.isCLISynced }
        case .codex:
            return !settings.codexAccounts.isEmpty
        case .diagnostics:
            return false
        }
    }

    // MARK: - Detail pane

    private var credentialsDetailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                paneContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch credentialSection {
        case .claudeAI:
            ClaudeAIPane()

        case .apiConsole:
            APIConsolePane()

        case .cliAccount:
            CLIAccountPane()

        case .codex:
            CredentialPageHeader(
                title: L.CredentialsNav.codexPaneTitle,
                subtitle: L.CredentialsNav.codexPaneSubtitle
            )
            CredentialStatusCard(
                isConnected: isConnected(.codex),
                title: isConnected(.codex) ? L.CredentialsNav.connected : L.CredentialsNav.notConnected
            )
            if let currentCodexAccount = settings.currentCodexAccount {
                currentCodexAccountDetailView(account: currentCodexAccount)
            } else {
                codexConnectCard
            }

        case .diagnostics:
            CredentialPageHeader(
                title: L.CredentialsNav.diagnostics,
                subtitle: L.CredentialsNav.diagnosticsSubtitle
            )
            diagnosticsCard
            howToCard
        }
    }

    /// Codex has no wizard of its own, its login is the browser flow
    private var codexConnectCard: some View {
        CredentialCard(title: L.APIConsole.configuration) {
            CredentialPrimaryButton(title: L.Account.addCodexAccount, systemImage: "globe") {
                WebLoginWindowManager.shared.showCodexLoginWindow()
            }
        }
    }

    func inlineSuccessBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { successMessage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }
}
