//
//  InfoRow.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Info row
/// Shows one line of information: an icon, a title and a value
struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    var tintColor: Color = .blue  // New: a customizable icon color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(tintColor)  // Use the custom color
                .frame(width: 8)
                .font(.system(size: 12))  // Icon size

            Text(title)
                .font(.system(size: 12))  // First column font size
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 12))  // Second column font size
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)  // Row height
        .padding(.horizontal, 12) // Row width
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
