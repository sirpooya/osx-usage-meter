//
//  AlignedInfoRow.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Aligned info row (used to line things up vertically when there are two limits)
/// Fixed width layout, so the time data on both rows lines up vertically
struct AlignedInfoRow: View {
    let icon: String
    let title: String
    let remainingIcon: String
    let remaining: String
    let resetIcon: String
    let resetTime: String
    var tintColor: Color = .blue

    var body: some View {
        HStack(spacing: 6) {  // Full row width
            // Left: icon plus title (a fixed area)
            HStack(spacing: 4) {  // Spacing between icon and title
                Image(systemName: icon)
                    .foregroundColor(tintColor)
                    .frame(width: 18)  // Width

                Text(title)
                    .font(.system(size: 12))  // Font
                    .foregroundColor(.secondary)
            }
            .frame(width: 50, alignment: .leading)  // Total width of the left side

            Spacer()

            // Right: a fixed width layout so the time data lines up
            HStack(spacing: 8) {
                // Time left
                HStack(spacing: 3) {  // Spacing between icon and text
                    Image(systemName: remainingIcon)
                        .font(.system(size: 12))  // Icon size
                        .foregroundColor(.secondary)
                    Text(remaining)
                        .font(.system(size: 12))  // Font size
                        .fontWeight(.medium)
                }
                .frame(width: 75, alignment: .leading)  // Display width

                // Reset time
                HStack(spacing: 3) {  // Spacing between icon and text
                    Image(systemName: resetIcon)
                        .font(.system(size: 12))  // Icon size
                        .foregroundColor(.secondary)
                    Text(resetTime)
                        .font(.system(size: 12))  // Display width
                        .fontWeight(.medium)
                }
                .frame(width: 90, alignment: .leading)  // Display width
            }
        }
        .padding(.vertical, 6) // Row height
        .padding(.horizontal, 12)  // Row width
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
