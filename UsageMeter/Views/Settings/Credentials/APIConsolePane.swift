//
//  APIConsolePane.swift
//  UsageMeter
//
//  API Billing pane: console.anthropic.com pay as you go spend and prepaid credits.
//  Three step configuration, matching the Claude.ai pane: paste the console session key,
//  pick the organization it can see, confirm.
//

import AppKit
import SwiftUI

struct APIConsolePane: View {
    @ObservedObject private var console = ConsoleAPIService.shared

    @State private var step: CredentialStep = .enterKey
    @State private var sessionKey = ""
    @State private var organizations: [ConsoleOrganization] = []
    @State private var selectedOrganization: ConsoleOrganization?
    @State private var isFetching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CredentialPageHeader(
                title: L.APIConsole.paneTitle,
                subtitle: L.APIConsole.paneSubtitle
            )

            statusCard

            if console.isConfigured {
                figuresCard
            } else {
                configurationCard
            }

            CredentialInfoBox(
                title: L.APIConsole.aboutTitle,
                points: [L.APIConsole.aboutPoint1, L.APIConsole.aboutPoint2, L.APIConsole.aboutPoint3]
            )
        }
        .onAppear {
            if console.isConfigured { Task { await console.refresh() } }
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        CredentialStatusCard(
            isConnected: console.isConfigured,
            title: console.isConfigured ? L.CredentialsNav.connected : L.CredentialsNav.notConnected,
            detail: console.isConfigured ? console.credentials.maskedSessionKey : nil
        ) {
            if console.isConfigured {
                CredentialDestructiveButton(title: L.CLISync.remove) {
                    console.remove()
                    resetWizard()
                }
            }
        }
    }

    // MARK: - Figures once configured

    private var figuresCard: some View {
        CredentialCardCustomHeader {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.APIConsole.currentPeriod)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.75))
                    Text(L.APIConsole.currentPeriodSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                CredentialSecondaryButton(title: L.CLISync.refresh, systemImage: "arrow.clockwise") {
                    Task { await console.refresh() }
                }
            }
        } content: {
            CredentialDetailRows {
                CredentialDetailRow(
                    icon: "building.2",
                    label: L.APIConsole.organization,
                    value: console.credentials.organizationName
                )

                if let spend = console.currentSpend {
                    CredentialDetailRow(
                        icon: "dollarsign.circle",
                        label: L.APIConsole.currentSpend,
                        value: formatted(spend.dollars)
                    )
                }

                if let credits = console.prepaidCredits {
                    CredentialDetailRow(
                        icon: "creditcard",
                        label: L.APIConsole.prepaidCredits,
                        value: formatted(credits.dollars, currency: credits.currency)
                    )
                }
            }

            if console.isBusy {
                ProgressView().controlSize(.small)
            }

            if let error = console.lastError {
                CredentialInlineError(message: error)
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
            Text(L.APIConsole.signInHint)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            CredentialPrimaryButton(title: L.APIConsole.openConsole, systemImage: "globe") {
                NSWorkspace.shared.open(URL(string: "https://console.anthropic.com/settings/billing")!)
            }

            CredentialOrDivider()

            Text(L.APIConsole.manualKeyTitle)
                .font(.system(size: 12, weight: .semibold))

            SecureField("sk-ant-api03-...", text: $sessionKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            Text(L.APIConsole.manualKeyHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if let errorMessage { CredentialInlineError(message: errorMessage) }

            HStack {
                Spacer()
                CredentialPrimaryButton(
                    title: L.APIConsole.fetchOrganizations,
                    systemImage: "building.2",
                    isBusy: isFetching,
                    isEnabled: !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    fetchOrganizations()
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
                    guard let organization = selectedOrganization else { return }
                    let key = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await console.save(sessionKey: key, organization: organization)
                        sessionKey = ""
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func fetchOrganizations() {
        let key = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isFetching = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await console.fetchOrganizations(sessionKey: key)
                isFetching = false
                guard !fetched.isEmpty else {
                    errorMessage = L.APIConsole.errorNoOrganizations
                    return
                }
                organizations = fetched
                // A single organization needs no picking, go straight to confirmation
                if fetched.count == 1 {
                    selectedOrganization = fetched[0]
                    step = .confirm
                } else {
                    step = .selectOrganization
                }
            } catch {
                isFetching = false
                errorMessage = L.APIConsole.errorInvalidKey
            }
        }
    }

    private func resetWizard() {
        step = .enterKey
        organizations = []
        selectedOrganization = nil
        errorMessage = nil
        sessionKey = ""
    }

    private func formatted(_ amount: Double, currency: String? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

}
