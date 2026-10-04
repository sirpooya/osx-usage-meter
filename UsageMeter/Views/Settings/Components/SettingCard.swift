//
//  SettingCard.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Reusable settings card
/// A consistent card layout with a title, content and a hint. The icon
/// parameters are accepted but no longer rendered, so the many call sites
/// did not have to change when the header glyphs were dropped.
struct SettingCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let hint: String
    @ViewBuilder let content: Content

    init(
        icon: String,
        iconColor: Color = .blue,
        title: String,
        hint: String = "",
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Divider()

            // Content area
            VStack(alignment: .leading, spacing: 8) {
                content
            }

            // Hint
            if !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.03))
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
}
