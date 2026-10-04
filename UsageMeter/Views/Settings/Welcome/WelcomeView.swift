//
//  WelcomeView.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// First launch login UI
/// Two pages: the main one holds only the claude.ai browser login, the second is the advanced manual session key with a back arrow.
/// The page content is split into SetupStepView.swift and ManualSessionKeyView.swift, to keep this file manageable
struct WelcomeView: View {
    /// The login window's fixed size.
    /// The window is created with this same value as its contentSize, and the two have to agree or the centering comes out wrong.
    static let contentSize = NSSize(width: 300, height: 400)

    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager.shared

    /// Whether it is sitting on the manual session key page
    @State private var showManualEntry = false
    @State private var sessionKey: String = ""
    @State private var isShowingPassword: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var submitError: String?

    var body: some View {
        Group {
            if showManualEntry {
                ManualSessionKeyView(
                    sessionKey: $sessionKey,
                    isShowingPassword: $isShowingPassword,
                    isSubmitting: isSubmitting,
                    errorMessage: submitError,
                    onBack: leaveManualEntry,
                    onSubmit: submitSessionKey
                )
            } else {
                SetupStepView(
                    onSignedIn: finishSetup,
                    onManualEntry: { showManualEntry = true }
                )
            }
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .animation(.easeInOut(duration: 0.18), value: showManualEntry)
        .id(localization.updateTrigger)
    }

    // MARK: - Navigation Methods

    /// Go back to the main page. The session key already typed is kept, only the error message is cleared.
    private func leaveManualEntry() {
        submitError = nil
        showManualEntry = false
    }

    /// Finish first time setup.
    /// On a successful OAuth login the account was already stored by ClaudeOAuthCoordinator, so that path creates no account here.
    /// Closing the window lands here too (see willClose in showWelcomeWindow), which counts as configuring later.
    private func finishSetup() {
        settings.isFirstLaunch = false

        // Post the notification that starts the data refresh
        NotificationCenter.default.post(name: .openSettings, object: nil)

        dismiss()
    }

    /// The manual path: a session key is only a credential, and the account has to be built by querying the organization with it.
    /// On a failure it stays on this page and shows the error so the user can fix it, rather than closing the window.
    private func submitSessionKey() {
        let trimmedKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        submitError = nil

        ClaudeAPIService.shared.fetchOrganizations(sessionKey: trimmedKey) { result in
            DispatchQueue.main.async {
                isSubmitting = false

                switch result {
                case .success(let organizations) where !organizations.isEmpty:
                    for org in organizations {
                        let newAccount = Account(
                            sessionKey: trimmedKey,
                            organizationId: org.uuid,
                            organizationName: org.name,
                            alias: nil
                        )
                        settings.addAccount(newAccount)
                    }
                    finishSetup()

                case .success, .failure:
                    submitError = L.Welcome.fetchOrgIdFailed
                }
            }
        }
    }
}
