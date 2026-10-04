//
//  CompactInfoRow.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Minimal info row (for the two line dual mode display)
/// Icons in place of text labels, so everything fits compactly on one line
struct CompactInfoRow: View {
    let limitIcon: String      // Limit type icon (a clock or a calendar)
    let limitLabel: String     // Limit label (5h or 7d)
    let remainingIcon: String  // Time left icon (an hourglass)
    let remaining: String      // Time left (1h48m or 3d12h)
    let resetIcon: String      // Reset icon (a refresh arrow)
    let resetTime: String      // Reset time (15:07 or 11/29-12h)
    var tintColor: Color = .blue

    var body: some View {
        HStack(spacing: 6) {
            // Limit type
            HStack(spacing: 3) {
                Text(limitIcon)
                    .font(.system(size: 14))
                Text(limitLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tintColor)
            }

            // Time left
            HStack(spacing: 3) {
                Text(remainingIcon)
                    .font(.system(size: 12))
                Text(remaining)
                    .font(.system(size: 13, weight: .medium))
            }

            // Reset time
            HStack(spacing: 3) {
                Text(resetIcon)
                    .font(.system(size: 12))
                Text(resetTime)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(tintColor.opacity(0.08))
        .cornerRadius(6)
    }
}

