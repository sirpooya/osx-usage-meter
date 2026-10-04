//
//  ClaudeOAuthLoginView.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-06-19.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import SwiftUI

/// Claude OAuth login progress window
///
/// The authentication itself happens in the default browser and this window only shows progress and the result,
/// which fully sidesteps WKWebView's limits on Google and passkey logins (Issue #49).
struct ClaudeOAuthLoginView: View {
    @StateObject private var coordinator = ClaudeOAuthCoordinator()
    var onAccountCreated: ((Account) -> Void)?

    private let purple = Color(red: 122 / 255.0, green: 90 / 255.0, blue: 195 / 255.0)

    @State private var showManualInput = false
    @State private var manualPastedLink = ""
    @State private var manualError: String?

    var body: some View {
        VStack(spacing: 18) {
            content
        }
        .padding(32)
        .frame(width: 440, height: 380)
        .onAppear { coordinator.start(onAccountCreated: onAccountCreated) }
        .onDisappear { coordinator.cancel() }
        .onChange(of: coordinator.loginState) { state in
            if case .success = state {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    WebLoginWindowManager.shared.closeLoginWindow()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.loginState {
        case .starting:
            spinner(L.WebLogin.codexOAuthPreparing)

        case .waitingForBrowser:
            VStack(spacing: 14) {
                Image(systemName: "safari")
                    .font(.system(size: 44))
                    .foregroundColor(purple)
                Text(L.WebLogin.codexOAuthWaitingBrowser)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(L.WebLogin.codexOAuthWaitingHint)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(L.WebLogin.codexOAuthReopenBrowser) { coordinator.reopenBrowser() }
                    .buttonStyle(.link)

                manualFallback
            }

        case .exchanging:
            spinner(L.WebLogin.codexOAuthExchanging)

        case .success(let name):
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
                Text(L.WebLogin.success(name))
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }

        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(L.WebLogin.codexOAuthRetry) {
                    coordinator.start(onAccountCreated: onAccountCreated)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The manual fallback area (Issue #68): in some browsers and environments the system browser has already reached the localhost callback page
    /// while the local callback server never receives that request, leaving the user stuck on the localhost page with no automatic return.
    /// This lets them paste that http://localhost link straight back to finish the login.
    @ViewBuilder
    private var manualFallback: some View {
        if showManualInput {
            VStack(spacing: 8) {
                TextField(L.WebLogin.claudeOAuthManualPrompt, text: $manualPastedLink)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                    .onSubmit(submitManualLink)
                if let manualError {
                    Text(manualError)
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
                Button(L.WebLogin.claudeOAuthManualSubmit, action: submitManualLink)
                    .keyboardShortcut(.defaultAction)
                    .disabled(manualPastedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        } else {
            Button(L.WebLogin.claudeOAuthManualHint) { showManualInput = true }
                .buttonStyle(.link)
                .font(.footnote)
        }
    }

    private func submitManualLink() {
        manualError = nil
        if !coordinator.submitManualCallback(manualPastedLink) {
            manualError = L.WebLogin.claudeOAuthManualInvalid
        }
    }

    private func spinner(_ text: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
