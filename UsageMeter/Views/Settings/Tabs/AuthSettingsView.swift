//
//  AuthSettingsView.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//
//  The account detail card, the add account flow and the help and diagnostics cards were split into
//  AuthSettingsView+AccountDetail.swift / +AddAccount.swift / +Help.swift
//  to keep this file manageable. The @State shared across those files therefore cannot be private (an extension cannot reach it across files).

import SwiftUI

/// Authentication settings page
/// A card layout for managing multiple accounts
struct AuthSettingsView: View {
    @ObservedObject var settings = UserSettings.shared
    /// CLI account sync service (a singleton, the card itself is in AuthSettingsView+CLIAccount.swift)
    @ObservedObject var cliSync = ClaudeCodeSyncService.shared
    @State var isAddingAccount = false
    @State var newSessionKey = ""
    @State var newAlias = ""
    @State var isValidating = false
    @State var validationError: String?
    @State var isShowingPassword = false
    @State var showDeleteConfirmation = false
    @State var accountToDelete: Account?
    @State var successMessage: String?
    @State var showDeleteCodexConfirmation = false
    @State var codexAccountToDelete: Account?
    /// The selected login method in the credentials sidebar (see AuthSettingsView+Sidebar.swift)
    @State var credentialSection: CredentialSection = .cliAccount

    var body: some View {
        credentialsSplitView
        .alert(L.Account.deleteConfirmTitle, isPresented: $showDeleteConfirmation) {
            Button(L.Account.cancel, role: .cancel) {}
            Button(L.Account.delete, role: .destructive) {
                if let account = accountToDelete {
                    settings.removeAccount(account)
                }
            }
        } message: {
            Text(L.Account.deleteConfirmMessage)
        }
        .alert(L.Account.deleteConfirmTitle, isPresented: $showDeleteCodexConfirmation) {
            Button(L.Account.cancel, role: .cancel) {}
            Button(L.Account.delete, role: .destructive) {
                if let account = codexAccountToDelete {
                    settings.removeCodexAccount(account)
                }
            }
        } message: {
            Text(L.Account.deleteConfirmMessage)
        }
    }

    /// The previous single scroll layout, kept for reference by the preview only
    private var legacyStackedBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isAddingAccount {
                    // Add account view
                    addAccountView
                } else {
                    // Success message when several organizations were added
                    if let message = successMessage {
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

                    // Account list view
                    accountListView

                    // CLI account sync (the account Claude Code already signed in, zero paste)
                    cliAccountCard

                    // Current Claude account detail
                    if let currentAccount = settings.currentAccount {
                        currentAccountDetailView(account: currentAccount)
                    }

                    // Current Codex account detail
                    if let currentCodexAccount = settings.currentCodexAccount {
                        currentCodexAccountDetailView(account: currentCodexAccount)
                    }

                    // Help card
                    howToCard

                    // Diagnostics card
                    diagnosticsCard
                }
            }
            .padding()
        }
        .alert(L.Account.deleteConfirmTitle, isPresented: $showDeleteConfirmation) {
            Button(L.Account.cancel, role: .cancel) {}
            Button(L.Account.delete, role: .destructive) {
                if let account = accountToDelete {
                    settings.removeAccount(account)
                }
            }
        } message: {
            Text(L.Account.deleteConfirmMessage)
        }
        .alert(L.Account.deleteConfirmTitle, isPresented: $showDeleteCodexConfirmation) {
            Button(L.Account.cancel, role: .cancel) {}
            Button(L.Account.delete, role: .destructive) {
                if let account = codexAccountToDelete {
                    settings.removeCodexAccount(account)
                }
            }
        } message: {
            Text(L.Account.deleteConfirmMessage)
        }
    }

    // MARK: - Account List View

    var accountListView: some View {
        let hasCodex = !settings.codexAccounts.isEmpty
        let hasBothProviders = !settings.accounts.isEmpty && hasCodex

        return SettingCard(
            icon: "person.2.fill",
            iconColor: .blue,
            title: L.Account.listTitle,
            hint: ""
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if settings.accounts.isEmpty && settings.codexAccounts.isEmpty {
                    // The message shown when there is no account
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(L.Account.noAccounts)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    // Claude account group
                    if !settings.accounts.isEmpty {
                        if hasBothProviders {
                            providerSectionHeader(provider: .claude, label: L.Account.claudeAccounts)
                        }
                        ForEach(settings.accounts) { account in
                            accountRow(account: account, provider: .claude)
                        }
                    }

                    // Codex account group
                    if hasCodex {
                        if hasBothProviders {
                            providerSectionHeader(provider: .codex, label: L.Account.codexAccounts)
                                .padding(.top, 4)
                        }
                        ForEach(settings.codexAccounts) { account in
                            accountRow(account: account, provider: .codex)
                        }
                    }
                }

                // Add account entry point
                addAccountActionsView
            }
        }
    }

    var addAccountActionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.Account.addAccount)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                addAccountActionButton(
                    provider: .claude,
                    title: L.WebLogin.browserLogin,
                    help: "\(ProviderType.claude.displayName) \(L.WebLogin.browserLogin)"
                ) {
                    WebLoginWindowManager.shared.showLoginWindow()
                }

                addAccountActionButton(
                    provider: .claude,
                    title: L.WebLogin.manualInput,
                    help: L.SettingsAuth.manualInputClaudeOnlyHelp
                ) {
                    withAnimation {
                        isAddingAccount = true
                        newSessionKey = ""
                        newAlias = ""
                        validationError = nil
                    }
                }

                addAccountActionButton(
                    provider: .codex,
                    title: L.WebLogin.browserLogin,
                    help: "\(ProviderType.codex.displayName) \(L.WebLogin.browserLogin)"
                ) {
                    WebLoginWindowManager.shared.showCodexLoginWindow()
                }
            }
        }
        .padding(.top, 8)
    }

    func addAccountActionButton(
        provider: ProviderType,
        title: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                providerIcon(provider: provider, size: 16)

                Text(title)
                    .font(.subheadline)
            }
        }
        .buttonStyle(.bordered)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    func providerIcon(provider: ProviderType, size: CGFloat) -> some View {
        switch provider {
        case .claude:
            if let icon = ImageHelper.createAppIcon(size: size) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "sparkles")
                    .frame(width: size, height: size)
            }
        case .codex:
            if let icon = ImageHelper.createCodexIcon(size: size) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "sparkles")
                    .frame(width: size, height: size)
            }
        }
    }

    func providerSectionHeader(provider: ProviderType, label: String) -> some View {
        HStack(spacing: 4) {
            if provider == .codex, let icon = ImageHelper.createCodexIcon(size: 12) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 12, height: 12)
            } else if provider == .claude, let icon = ImageHelper.createAppIcon(size: 12) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 12, height: 12)
            }
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Divider()
                .frame(height: 10)
        }
    }

    // MARK: - Account Row

    func accountRow(account: Account, provider: ProviderType) -> some View {
        let isSelected = provider == .codex
            ? account.id == settings.currentCodexAccountId
            : account.id == settings.currentAccountId
        let accentColor: Color = provider == .codex
            ? Color(red: 45/255.0, green: 212/255.0, blue: 191/255.0)
            : .blue

        return Button(action: {
            if provider == .codex {
                settings.switchToCodexAccount(account)
            } else {
                settings.switchToAccount(account)
            }
        }) {
            HStack(spacing: 12) {
                // Selection indicator
                Circle()
                    .fill(isSelected ? accentColor : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )

                // Account info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(account.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(accentColor)
                        }
                    }

                    if account.alias != nil && !account.alias!.isEmpty {
                        Text(account.organizationName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
