//
//  DiagnosticsView.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-11.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Diagnostics view
/// Shown at the bottom of the authentication settings page, offering a connection test and report export
struct DiagnosticsView: View {

    @StateObject private var diagnosticManager = DiagnosticManager()
    @State private var showDetailedReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Action button row
            HStack {
                Button(action: {
                    Task { await diagnosticManager.runDiagnosticTest() }
                }) {
                    HStack {
                        if diagnosticManager.isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(L.Diagnostic.testButton)
                    }
                }
                .disabled(diagnosticManager.isTesting)

                if diagnosticManager.latestReport != nil {
                    Button(L.Diagnostic.viewDetailsButton) {
                        showDetailedReport.toggle()
                    }

                    Button(L.Diagnostic.exportButton) {
                        diagnosticManager.saveReportWithDialog()
                    }
                }

                Button(L.Diagnostic.openLogFolder) {
                    if let logPath = DiagnosticLogger.shared.getLogFilePath() {
                        let folderURL = URL(fileURLWithPath: logPath).deletingLastPathComponent()
                        NSWorkspace.shared.open(folderURL)
                    }
                }
            }

            // Status message
            if !diagnosticManager.statusMessage.isEmpty {
                Text(diagnosticManager.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Diagnostic results (one card per provider)
            if let report = diagnosticManager.latestReport {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.providers, id: \.providerType) { result in
                        ProviderResultCard(result: result)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.textBackgroundColor))
                )
            }

            // Privacy note
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 10))
                    .foregroundColor(.green)

                Text(L.Diagnostic.privacyNotice)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showDetailedReport) {
            DetailedReportView(report: diagnosticManager.latestReport)
        }
    }
}

// MARK: - Provider Result Card

private struct ProviderResultCard: View {

    let result: ProviderDiagnosticResult

    private var providerIcon: String {
        switch result.providerType {
        case .claude: return "c.circle.fill"
        case .codex: return "sparkle"
        }
    }

    private var providerName: String {
        result.providerType.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Provider title row
            HStack(spacing: 6) {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.success ? .green : .red)
                    .font(.system(size: 13))

                Text(providerName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(result.success ? L.Diagnostic.resultSuccess : L.Diagnostic.resultFailed)
                    .font(.caption)
                    .foregroundColor(result.success ? .green : .red)
            }

            // Step summary
            if !result.steps.isEmpty {
                ForEach(result.steps, id: \.name) { step in
                    StepSummaryRow(step: step)
                }
            }

            // Show the diagnosis and suggestions on a failure
            if !result.success {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L.Diagnostic.diagnosis)
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text(result.diagnosis)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !result.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.Diagnostic.suggestions)
                            .font(.caption)
                            .fontWeight(.semibold)

                        ForEach(Array(result.suggestions.prefix(3).enumerated()), id: \.offset) { _, suggestion in
                            Text("• \(suggestion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - Step Summary Row

private struct StepSummaryRow: View {
    let step: DiagnosticStep

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: step.success ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 10))
                .foregroundColor(step.success ? .green : .red)

            Text(step.name)
                .font(.caption)
                .foregroundColor(.secondary)

            if let statusCode = step.httpStatusCode {
                Text("HTTP \(statusCode)")
                    .font(.caption)
                    .foregroundColor(statusCodeColor(statusCode))
            }

            if let responseTime = step.responseTime {
                Spacer()
                Text(String(format: "%.0f ms", responseTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if step.cloudflareChallenge {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
    }

    private func statusCodeColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .secondary
        }
    }
}

// MARK: - Detailed Report View

/// The full report view (a sheet), showing the complete diagnostic report as Markdown
struct DetailedReportView: View {

    let report: DiagnosticReport?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(L.Diagnostic.detailedReportTitle)
                    .font(.headline)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Report content
            if let report = report {
                ScrollView {
                    Text(report.toMarkdown())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(L.Diagnostic.noReportAvailable)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Bottom buttons
            HStack {
                Spacer()

                Button(L.Diagnostic.copyToClipboard) {
                    if let report = report {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.toMarkdown(), forType: .string)
                    }
                }

                Button(L.Update.okButton) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 700, height: 600)
    }
}

// MARK: - Preview

struct DiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        DiagnosticsView()
            .frame(width: 500)
            .padding()
    }
}
