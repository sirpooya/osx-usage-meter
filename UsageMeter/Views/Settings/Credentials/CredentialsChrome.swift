//
//  CredentialsChrome.swift
//  UsageMeter
//
//  Shared furniture for the credential panes: page header, connected status card,
//  numbered step indicator, the card container and its rows.
//
//  Visual contract, kept in one place so the three panes cannot drift apart:
//  - Primary action in a card is `.borderedProminent` (filled), never a plain bordered button.
//  - Destructive action is bordered with a red tint, so it reads as secondary to the primary one.
//  - Card headers are title case with a secondary subtitle line, divided from the content.
//  - Detail rows are separated by hairlines, and their icons all use the accent color.
//

import SwiftUI

// MARK: - Page header

struct CredentialPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Status card

/// The connected / not connected card at the top of every pane: a dot, a bold title, an
/// optional second line (elapsed time or the masked credential) and an optional action.
struct CredentialStatusCard<Trailing: View>: View {
    let isConnected: Bool
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 9, height: 9)

            // Medium, not semibold: the pane header right above is 17pt semibold, and two
            // bold lines in a row read as two headings rather than a heading and its status.
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

extension CredentialStatusCard where Trailing == EmptyView {
    init(isConnected: Bool, title: String, detail: String? = nil) {
        self.init(isConnected: isConnected, title: title, detail: detail) { EmptyView() }
    }
}

// MARK: - Step indicator

/// Three step wizard state, shared by the Claude.ai and API Console panes
enum CredentialStep: Int, Comparable, CaseIterable {
    case enterKey = 1
    case selectOrganization = 2
    case confirm = 3

    static func < (lhs: CredentialStep, rhs: CredentialStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The 1 - 2 - 3 header. Only the current step carries a label, and the connectors stretch
/// so the last circle sits hard against the right edge of the card.
struct CredentialStepIndicator: View {
    let current: CredentialStep
    let titles: [CredentialStep: String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(CredentialStep.allCases.enumerated()), id: \.element) { index, step in
                let isCurrent = current == step
                let isCompleted = current > step

                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(circleFill(isCurrent: isCurrent, isCompleted: isCompleted))
                            .frame(width: 22, height: 22)

                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(isCurrent ? .white : .secondary)
                        }
                    }

                    if isCurrent, let title = titles[step] {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }

                if index < CredentialStep.allCases.count - 1 {
                    Rectangle()
                        .fill(isCompleted ? Color.green.opacity(0.35) : Color.secondary.opacity(0.18))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func circleFill(isCurrent: Bool, isCompleted: Bool) -> Color {
        if isCompleted { return .green }
        if isCurrent { return .accentColor }
        return Color.secondary.opacity(0.18)
    }
}

// MARK: - Card container

/// The bordered container the pane sections live in: a title case header with an optional
/// subtitle, a divider, then the content.
struct CredentialCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.75))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

/// A card whose header is fully custom (used where the header carries a trailing button)
struct CredentialCardCustomHeader<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Detail rows

/// Label above value with an accent colored icon. Rows are meant to be wrapped in
/// `CredentialDetailRows` so they get the hairline separators.
struct CredentialDetailRow: View {
    let icon: String
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

/// Stacks detail rows with a hairline between each pair, the way the reference design does
struct CredentialDetailRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            _VariadicView.Tree(SeparatedLayout()) {
                content
            }
        }
    }

    private struct SeparatedLayout: _VariadicView_MultiViewRoot {
        @ViewBuilder
        func body(children: _VariadicView.Children) -> some View {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                if index > 0 {
                    Divider().padding(.vertical, 9)
                }
                child
            }
        }
    }
}

// MARK: - Buttons

/// The filled primary action. Every card's main action uses this, so "the blue one" always
/// means "the thing you came here to do".
struct CredentialPrimaryButton: View {
    let title: String
    let systemImage: String
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(!isEnabled || isBusy)
    }
}

/// The destructive secondary action: bordered, red tinted, never filled
struct CredentialDestructiveButton: View {
    let title: String
    var systemImage: String = "trash"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(.red)
    }
}

/// A quiet bordered action, for Refresh and Back
struct CredentialSecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

// MARK: - Bits and pieces

/// The "OR" rule between the sign in button and the manual key field
struct CredentialOrDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 1)
            Text(L.APIConsole.or)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 1)
        }
    }
}

struct CredentialInlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The "About" explainer at the bottom of a pane
struct CredentialInfoBox: View {
    let title: String
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }

            ForEach(points, id: \.self) { point in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(point)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.07))
        )
    }
}
