//
//  AboutView.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// About page
/// Mirrors the About tab of the other osx-* apps (osx-launchpad's layout):
/// icon, name, version pill, grouped cards of rows, copyright. Cards fill the
/// vertical space instead of a Spacer pushing lonely buttons to the bottom.
struct AboutView: View {
    /// Read the app version from the bundle
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private enum Links {
        static let github = URL(string: "https://github.com/sirpooya/osx-usage-meter")!
        static let issues = URL(string: "https://github.com/sirpooya/osx-usage-meter/issues")!
        static let coffee = URL(string: "https://ko-fi.com/pooya")!
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let icon = ImageHelper.createAppIcon(size: 104) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 104, height: 104)
                        .padding(.top, 28)
                }

                Text("Usage Meter")
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.top, 14)

                AboutVersionPill(text: appVersion)
                    .padding(.top, 8)

                Text(L.SettingsAbout.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                // Info card
                AboutCard {
                    AboutValueRow(title: L.SettingsAbout.developer, value: "Pooya Kamel")
                    AboutCardDivider()
                    AboutValueRow(title: L.SettingsAbout.license, value: L.SettingsAbout.licenseValue)
                }
                .padding(.top, 24)

                // Links card
                AboutCard {
                    AboutLinkRow(title: L.SettingsAbout.github, url: Links.github)
                    AboutCardDivider()
                    AboutLinkRow(title: L.SettingsAbout.reportIssue, url: Links.issues)
                    AboutCardDivider()
                    AboutLinkRow(title: L.SettingsAbout.coffee, url: Links.coffee)
                }
                .padding(.top, 12)

                Text(L.SettingsAbout.copyright)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pieces (matching osx-launchpad's SettingsComponents look)

/// The light grey rounded version chip under the app name.
private struct AboutVersionPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// A grouped rounded container. Insert `AboutCardDivider` between rows.
private struct AboutCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .labelColor).opacity(0.05))
            )
    }
}

/// Hairline separator floating inside the card with matching side margins.
private struct AboutCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

/// One row: leading title, trailing static value.
private struct AboutValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
    }
}

/// One fully tappable row that opens a URL, with an accent arrow and a
/// pointing-hand cursor on hover.
private struct AboutLinkRow: View {
    let title: String
    let url: URL

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .underline(hovering)
            Spacer(minLength: 10)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
