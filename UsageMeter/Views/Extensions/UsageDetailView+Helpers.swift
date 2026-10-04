//
//  UsageDetailView+Helpers.swift
//  UsageMeter
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Helper Methods Extension

extension UsageDetailView {

    // MARK: - Animation Methods

    /// Start the spinner animation
    func startRotationAnimation() {
        // Clear the old timer
        stopRotationAnimation()

        // Reset the angle
        rotationAngle = 0

        // Create the new timer, updating every 0.016 seconds (about 60fps)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            withAnimation(.linear(duration: 0.016)) {
                rotationAngle += 6  // 6 degrees per frame, one full turn a second
                if rotationAngle >= 360 {
                    rotationAngle -= 360
                }
            }
        }
    }

    /// Stop the spinner animation
    func stopRotationAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        withAnimation(.default) {
            rotationAngle = 0
        }
    }

    // MARK: - Text Helper Methods

    /// Build the rainbow text
    /// - Parameter text: the text to show
    /// - Returns: the text view with the rainbow effect
    @ViewBuilder
    func rainbowText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(
                LinearGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }

    /// Build the menu update text (part of it colored)
    /// - Returns: the colored AttributedString
    func createUpdateMenuText() -> AttributedString {
        let baseText = L.Menu.checkUpdates
        let badgeText = L.Update.Notification.badgeShort
        let fullText = baseText + "   " + badgeText

        var attributedString = AttributedString(fullText)

        // Find the badge text range and color it
        if let range = attributedString.range(of: badgeText) {
            attributedString[range].foregroundColor = .orange
        }

        return attributedString
    }
}
