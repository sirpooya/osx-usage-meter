//
//  SetupStepView.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Setup Step (Authentication)
// Split out of WelcomeView.swift to keep single file size manageable
// First time setup has one path only: sign in with a claude.ai account through the browser.
// The layout is the standard welcome window: icon / title / one line pitch / one primary action / one note.
// The manual session key entry point is gone; anyone who needs several accounts can add them in Settings.

struct SetupStepView: View {
    /// Called after a successful login. The account is already written to settings by ClaudeOAuthCoordinator, so this only wraps up.
    let onSignedIn: () -> Void
    /// Go to the second page for entering a session key by hand
    let onManualEntry: () -> Void

    /// The title comes from the app's own name, so a rename needs no copy change here
    private var appName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "Usage Meter"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Only one flexible Spacer in the middle, with fixed spacing above and below:
            // the title sits near the top, the action near the bottom, and the slack collects in the middle.
            Spacer().frame(height: 26)

            appMark

            Spacer().frame(height: 14)

            Text(appName)
                .font(.system(size: 22, weight: .semibold))

            Spacer().frame(height: 5)

            Text(L.Welcome.tagline)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 20)

            browserSignIn

            Spacer().frame(height: 10)

            manualEntryButton

            Spacer().frame(height: 12)

            Text(L.Welcome.signInNote)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 22)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sections

    /// The app icon. The AppIcon fallback logic is contained in ImageHelper.namedImage.
    @ViewBuilder
    private var appMark: some View {
        if let icon = ImageHelper.createAppIcon(size: 72) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 72, height: 72)
        }
    }

    /// The browser login button (the only entry point, full width)
    private var browserSignIn: some View {
        Button(action: {
            WebLoginWindowManager.shared.showLoginWindow { _ in
                onSignedIn()
            }
        }) {
            Text(L.WebLogin.browserLoginRecommended)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(UsageColorScheme.brand)
    }

    /// Secondary entry point: advanced users pasting a session key by hand, whose content is on the second page
    private var manualEntryButton: some View {
        Button(action: onManualEntry) {
            Text(L.Welcome.manualSessionKey)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.black)
    }
}
