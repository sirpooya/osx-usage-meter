//
//  ClaudeAIPane.swift
//  UsageMeter
//
//  Claude.ai pane: subscription usage through a claude.ai login. Sign in through the
//  browser, or paste the sessionKey cookie by hand, then pick the organization.
//
//  A CLI Account synced login is deliberately not counted here: it has its own pane, so
//  this one reflects only what the user configured through claude.ai itself.
//

import SwiftUI

struct ClaudeAIPane: View {
    @ObservedObject private var settings = UserSettings.shared

    @State private var step: CredentialStep = .enterKey
    @State private var sessionKey = ""
    @State private var organizations: [Organization] = []
    @State private var selectedOrganization: Organization?
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var accountToRemove: Account?
    @State private var showRemoveConfirmation = false

    private let apiService = ClaudeAPIService.shared

    /// Accounts configured through claude.ai, so CLI synced ones are excluded
    private var claudeAIAccounts: [Account] {
        settings.accounts.filter { !$0.credentialSource.isCLISynced }
    }

    private var isConnected: Bool { !claudeAIAccounts.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CredentialPageHeader(
                title: L.CredentialsNav.claudePaneTitle,
                subtitle: L.CredentialsNav.claudePaneSubtitle
            )

            statusCard

            if isConnected {
                accountsCard
            } else {
                configurationCard
            }
        }
        .alert(L.Account.deleteConfirmTitle, isPresented: $showRemoveConfirmation) {
            Button(L.Account.cancel, role: .cancel) {}
            Button(L.Account.delete, role: .destructive) {
                if let accountToRemove { settings.removeAccount(accountToRemove) }
            }
        } message: {
            Text(L.Account.deleteConfirmMessage)
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        CredentialStatusCard(
            isConnected: isConnected,
            title: isConnected ? L.CredentialsNav.connected : L.CredentialsNav.notConnected,
            detail: isConnected ? maskedKey(claudeAIAccounts.first?.sessionKey ?? "") : nil
        )
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 20 else { return String(repeating: "•", count: max(key.count, 8)) }
        return "\(key.prefix(14))\(String(repeating: "•", count: 6))\(key.suffix(4))"
    }

    // MARK: - Configured accounts

    private var accountsCard: some View {
        CredentialCardCustomHeader {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.Account.listTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.75))
                    Text(L.ClaudeAIPane.accountsSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                CredentialPrimaryButton(title: L.Account.addAccount, systemImage: "plus") {
                    WebLoginWindowManager.shared.showLoginWindow()
                }
            }
        } content: {
            ForEach(claudeAIAccounts, id: \.id) { account in
                HStack(spacing: 8) {
                    Circle()
                        .fill(settings.currentAccount?.id == account.id ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.displayName)
                            .font(.subheadline)
                        Text(maskedKey(account.sessionKey))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if settings.currentAccount?.id != account.id {
                        CredentialSecondaryButton(title: L.Account.switchTo) {
                            settings.switchToAccount(account)
                        }
                    }

                    CredentialDestructiveButton(title: L.Account.delete) {
                        accountToRemove = account
                        showRemoveConfirmation = true
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.03))
                )
            }
        }
    }

    // MARK: - Configuration wizard

    private var configurationCard: some View {
        CredentialCardCustomHeader {
            VStack(alignment: .leading, spacing: 12) {
                Text(L.APIConsole.configuration)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.75))

                CredentialStepIndicator(current: step, titles: [
                    .enterKey: L.APIConsole.stepEnterKey,
                    .selectOrganization: L.APIConsole.stepSelectOrg,
                    .confirm: L.APIConsole.stepConfirm
                ])
            }
        } content: {
            switch step {
            case .enterKey: enterKeyStep
            case .selectOrganization: selectOrganizationStep
            case .confirm: confirmStep
            }
        }
    }

    private var enterKeyStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.ClaudeAIPane.signInHint)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            CredentialPrimaryButton(title: L.ClaudeAIPane.signIn, systemImage: "globe") {
                WebLoginWindowManager.shared.showLoginWindow()
            }

            CredentialOrDivider()

            Text(L.Welcome.manualSessionKey)
                .font(.system(size: 12, weight: .semibold))

            SecureField("sk-ant-sid01-...", text: $sessionKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            Text(L.ClaudeAIPane.manualKeyHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if let errorMessage { CredentialInlineError(message: errorMessage) }

            HStack {
                Spacer()
                CredentialPrimaryButton(
                    title: L.ClaudeAIPane.testConnection,
                    systemImage: "checkmark.seal",
                    isBusy: isValidating,
                    isEnabled: !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    testConnection()
                }
            }
        }
    }

    private var selectOrganizationStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.APIConsole.selectOrgHint)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            ForEach(organizations) { organization in
                Button {
                    selectedOrganization = organization
                    step = .confirm
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "building.2")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                        Text(organization.name)
                            .font(.system(size: 13))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            CredentialSecondaryButton(title: L.Account.cancel) { resetWizard() }
        }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let organization = selectedOrganization {
                CredentialDetailRow(
                    icon: "building.2",
                    label: L.APIConsole.organization,
                    value: organization.name
                )
            }

            HStack {
                CredentialSecondaryButton(title: L.APIConsole.back) { step = .selectOrganization }
                Spacer()
                CredentialPrimaryButton(title: L.APIConsole.connect, systemImage: "checkmark.circle") {
                    addAccount()
                }
            }
        }
    }

    // MARK: - Actions

    private func testConnection() {
        let key = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isValidating = true
        errorMessage = nil

        apiService.fetchOrganizations(sessionKey: key) { result in
            isValidating = false
            switch result {
            case .success(let fetched):
                guard !fetched.isEmpty else {
                    errorMessage = L.APIConsole.errorNoOrganizations
                    return
                }
                organizations = fetched
                if fetched.count == 1 {
                    selectedOrganization = fetched[0]
                    step = .confirm
                } else {
                    step = .selectOrganization
                }
            case .failure:
                errorMessage = L.ClaudeAIPane.errorInvalidKey
            }
        }
    }

    private func addAccount() {
        guard let organization = selectedOrganization else { return }
        let account = Account(
            sessionKey: sessionKey.trimmingCharacters(in: .whitespacesAndNewlines),
            organizationId: organization.uuid,
            organizationName: organization.name,
            provider: .claude
        )
        settings.addAccount(account)
        settings.switchToAccount(account)
        resetWizard()
    }

    private func resetWizard() {
        step = .enterKey
        organizations = []
        selectedOrganization = nil
        errorMessage = nil
        sessionKey = ""
    }

}
