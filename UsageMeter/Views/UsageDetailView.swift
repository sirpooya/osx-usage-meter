//
//  UsageDetailView.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// The popover's fixed layout metrics. The height has to be computed by hand, because body carries an explicit frame
/// (and NSHostingController's preferredContentSize follows only that frame).
private enum PopoverMetrics {
    /// Height of one limit row: title row 15 + spacing 5 + bar 5, plus 1 of slack
    static let rowHeight: CGFloat = 26
    /// Spacing between limit rows.
    /// `CodexColumnView` carries the same number so the two columns line up in two provider mode,
    /// and it cannot read this one (this enum is private to this file), so change both together.
    static let rowSpacing: CGFloat = 14
    /// Horizontal padding of the limit list
    static let horizontalPadding: CGFloat = 16
    /// Padding above the title bar + the title row + the bottom padding.
    /// The bottom is deliberately tighter than the header-to-bars gap: the bars need air under the
    /// title, and any slack left over lands at the bottom, where it reads as dead space.
    static let chromeHeight: CGFloat = 18 + 20 + bottomPadding
    /// The bottom part of `chromeHeight`
    static let bottomPadding: CGFloat = 10
    /// Two provider mode stacks Codex under Claude: the gap above the hairline plus the hairline.
    /// The Codex header brings its own 18 of top padding below it.
    static let providerDividerTopGap: CGFloat = 16
    static let providerDividerBlock: CGFloat = providerDividerTopGap + 1
    /// Empty states (signed out / error / loading) use a fixed height: an icon, copy and a button are taller than the bar list
    static let stateHeight: CGFloat = 210
    /// Extra breathing room above the "couldn't refresh" note, on top of the row spacing it
    /// already inherits from the bars stack. It is a different kind of line from a limit row, so
    /// it should not sit at the same rhythm as one.
    static let staleNoticeTopGap: CGFloat = 8
    /// The "couldn't refresh" note under the bars: 10pt text, the row spacing above it, plus that gap
    static let staleNoticeHeight: CGFloat = 13 + rowSpacing + staleNoticeTopGap

    /// Height taken by n limit rows
    static func rowsHeight(_ rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowSpacing
    }
}

/// Usage detail view
/// Shows Claude's current usage: percentage bars, countdowns and reset times
struct UsageDetailView: View {
    @Binding var usageData: UsageData?
    @Binding var codexUsageData: CodexUsageData?
    @Binding var errorMessage: String?
    @Binding var codexErrorMessage: String?
    /// All three Codex refresh levels failed, the user has to sign in again manually
    @Binding var codexNeedsRelogin: Bool
    @ObservedObject var refreshState: RefreshState
    /// Menu action callback
    var onMenuAction: ((MenuAction) -> Void)? = nil
    @StateObject private var localization = LocalizationManager.shared
    /// Observed so the header picks up the subscription tier the moment a poll resolves it,
    /// rather than waiting for the next thing that happens to rebuild the popover
    @ObservedObject private var settings = UserSettings.shared
    /// Whether an update is available (drives the text and the badge)
    @Binding var hasAvailableUpdate: Bool
    /// Whether the update badge should show (only while the user has not acknowledged it)
    @Binding var shouldShowUpdateBadge: Bool

    /// Menu action types
    enum MenuAction {
        case generalSettings
        case authSettings
        case checkForUpdates
        case about
        case claudeStatus
        case codexStatus
        case coffee
        case githubSponsor
        case quit
        case refresh
        case refreshClaude
        case refreshCodex
        case codexRelogin
    }
    
    // Animation state (now passed in from outside, so it is not reset every time the view is rebuilt)
    @State var rotationAngle: Double = 0
    @State var animationTimer: Timer?
    // Show the update notification
    @State private var showUpdateNotification = false
    // Display mode toggle (false: reset time, true: time left)
    // Time left is the default: a countdown ("3d 12h left") is more direct than an absolute timestamp ("Aug 24 2 AM"),
    // because the user does not have to work out the difference. Tapping the bars flips to reset times as a peek only:
    // it is not persisted, so a stray click cannot leave every later popover showing dates.
    @State private var showRemainingMode = true
    
    // MARK: - Body

    private var isMultiProviderActive: Bool {
        UserSettings.shared.isMultiProviderActive
            && (codexUsageData != nil || codexErrorMessage != nil || UserSettings.shared.hasValidCodexCredentials)
    }

    private var isCodexOnlyActive: Bool {
        !isMultiProviderActive
            && ((!UserSettings.shared.hasValidCredentials && UserSettings.shared.hasValidCodexCredentials)
                || (usageData == nil && (codexUsageData != nil || codexErrorMessage != nil)))
    }

    private var isClaudeRefreshing: Bool {
        refreshState.isRefreshingProvider(.claude)
    }

    /// Get the Claude display types currently active
    private var activeDisplayTypes: [LimitType] {
        guard let data = usageData else { return [] }
        return UserSettings.shared.getActiveDisplayTypes(usageData: data)
            .filter { $0.provider == .claude }
    }

    /// Get the Codex display types currently active
    private var activeCodexDisplayTypes: [LimitType] {
        guard let codex = codexUsageData else { return [] }
        return UserSettings.shared.getActiveDisplayTypes(usageData: nil, codexUsageData: codex)
            .filter { $0.provider == .codex }
    }

    /// The number of limit rows the Claude column really renders (including model rows past the first two slots)
    private func claudeRowCount(for data: UsageData?) -> Int {
        guard let data else { return 2 }
        let types = UserSettings.shared.getActiveDisplayTypes(usageData: data)
            .filter { $0.provider == .claude }
        var count = types.count
        // Smart mode also turns the third and later models into rows, and the height has to count them or the last one is clipped
        if UserSettings.shared.displayMode == .smart {
            count += max(0, data.weeklyModels.count - 2)
        }
        return max(count, 1)
    }

    /// The number of limit rows the Codex column really renders
    private func codexRowCount(for codex: CodexUsageData?) -> Int {
        guard let codex else { return 2 }
        let types = UserSettings.shared.getActiveDisplayTypes(usageData: nil, codexUsageData: codex)
            .filter { $0.provider == .codex }
        return max(types.count, 1)
    }

    /// Extra height for the stale note, which only appears when cached data is on screen
    private var staleNoticeAllowance: CGFloat {
        (errorMessage != nil && usageData != nil) ? PopoverMetrics.staleNoticeHeight : 0
    }

    /// Height of the Claude column. Mirrors `claudeMainContent`: as long as there is data, even
    /// stale data, the bars are what gets rendered, so the row height is what has to be reserved.
    /// Only a completely empty state falls back to `stateHeight`.
    private var claudeColumnHeight: CGFloat {
        guard usageData != nil else { return PopoverMetrics.stateHeight }
        return PopoverMetrics.chromeHeight
            + contentSpacing
            + PopoverMetrics.rowsHeight(claudeRowCount(for: usageData))
            + staleNoticeAllowance
    }

    /// Height in single provider (Claude) mode
    private var dynamicHeight: CGFloat {
        claudeColumnHeight
    }

    /// Height in Codex only mode
    private var codexOnlyHeight: CGFloat {
        if codexUsageData == nil {
            return PopoverMetrics.stateHeight
        }
        return PopoverMetrics.chromeHeight
            + contentSpacing
            + PopoverMetrics.rowsHeight(codexRowCount(for: codexUsageData))
    }

    /// Height in dual provider mode: Claude stacked over Codex. Each section is its single provider
    /// height minus the shared bottom padding, joined by the divider block, with the bottom padding
    /// counted once.
    private var multiProviderHeight: CGFloat {
        let codexHeight: CGFloat = codexUsageData == nil
            ? PopoverMetrics.stateHeight
            : PopoverMetrics.chromeHeight + contentSpacing
                + PopoverMetrics.rowsHeight(codexRowCount(for: codexUsageData))

        return (claudeColumnHeight - PopoverMetrics.bottomPadding)
            + PopoverMetrics.providerDividerBlock
            + codexHeight
    }

    /// Gap between the title row and the bars group. Fixed now: it used to tighten to 10 for two
    /// or more limits, which mattered when a 114pt ring sat under the title and does not any more.
    private var contentSpacing: CGFloat { 16 }

    private var contentWidth: CGFloat { 290 }

    private var contentHeight: CGFloat {
        if isMultiProviderActive {
            return multiProviderHeight
        }
        if isCodexOnlyActive {
            return codexOnlyHeight
        }
        return dynamicHeight
    }

    /// The signed out state. It is not an error, so there is no warning icon and only one action: sign in.
    private var signedOutState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 30))
                .foregroundColor(UsageColorScheme.brand)

            Text(L.Usage.signInPrompt)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                WebLoginWindowManager.shared.showLoginWindow { _ in
                    // Fetch data right after the login, so the user does not have to hit refresh
                    onMenuAction?(.refresh)
                }
            }) {
                Text(L.WebLogin.browserLoginRecommended)
            }
            .buttonStyle(.borderedProminent)
            .tint(UsageColorScheme.brand)
        }
        .padding()
    }

    /// A genuine error state. A button does what its label says, and "run diagnostics" is no longer a disguised settings entry.
    /// The copy is allowed to wrap; a fixed single line used to truncate the message to "...information in...".
    private func errorState(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundColor(.orange)

            Text(error)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(L.Usage.refresh) { onMenuAction?(.refresh) }
                Button(L.Usage.goToSettings) { onMenuAction?(.authSettings) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    @ViewBuilder
    private var claudeMainContent: some View {
        if let data = usageData {
            // Data always wins. A failed refresh (a 429 above all) must never replace numbers we
            // already have with an error screen: it annotates them with a "couldn't refresh" note
            // and leaves the bars in place. The error branch below is only for having nothing at all.
            claudeLimitRows(data: data)
        } else if let error = errorMessage, !refreshState.claudeErrorIsTransient {
            // Not being signed in is not an error, so it is treated as an empty state; only a genuine error gets the warning icon.
            // This used to guess between the two cases with error.contains("Authentication"/"configured"),
            // while the real copy is "Please configure authentication information...",
            // so neither test held and all that was left was that misnamed "run diagnostics" button.
            if !UserSettings.shared.hasValidCredentials {
                signedOutState
            } else {
                errorState(error)
            }
        } else {
            // Loading
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(L.Usage.loading)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(height: 100)
        }
    }

    /// One full width bar per limit. A click toggles between reset time and time left.
    @ViewBuilder
    private func claudeLimitRows(data: UsageData) -> some View {
        VStack(spacing: PopoverMetrics.rowSpacing) {
            ForEach(activeDisplayTypes, id: \.self) { type in
                UnifiedLimitRow(
                    type: type,
                    data: data,
                    showRemainingMode: showRemainingMode,
                    isRefreshing: isClaudeRefreshing
                )
            }
            // The first two models take the opus and sonnet slots above; the third and later ones
            // (when Fable, Opus and Sonnet all appear) are filled in here in Claude API order,
            // with the colors alternating between the two slots and the labels taken from the API's model names.
            // Only smart mode expands them all; custom mode respects the fixed slots the user checked.
            if UserSettings.shared.displayMode == .smart {
                let overflow = Array(data.weeklyModels.enumerated()).dropFirst(2)
                ForEach(overflow, id: \.offset) { entry in
                    UnifiedLimitRow(
                        type: entry.offset % 2 == 0 ? .opusWeekly : .sonnetWeekly,
                        data: data,
                        showRemainingMode: showRemainingMode,
                        isRefreshing: isClaudeRefreshing,
                        weeklyModelOverride: entry.element
                    )
                }
            }

            staleNotice
        }
        .padding(.horizontal, PopoverMetrics.horizontalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleRemainingMode()
        }
    }

    /// Shown under the bars when the last refresh failed but cached numbers are still on screen.
    /// This is the whole answer to "too many requests": say the data is stale, keep showing it.
    @ViewBuilder
    private var staleNotice: some View {
        if errorMessage != nil {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text(staleNoticeText)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, PopoverMetrics.staleNoticeTopGap)
        }
    }

    private var staleNoticeText: String {
        guard let updatedAt = refreshState.lastUpdatedAt else {
            return L.Usage.staleNoticeUnknown
        }
        return L.Usage.staleNotice(TimeFormatHelper.formatTimeOnly(updatedAt))
    }

    // MARK: - Header Buttons

    /// Refresh button plus Settings gear (shared by the single and dual column headers)
    @ViewBuilder
    private var refreshAndMenuButtons: some View {
        Button(action: { onMenuAction?(.refresh) }) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .opacity(refreshState.canRefresh ? 1.0 : 0.3)
                .rotationEffect(.degrees(refreshState.isRefreshing ? rotationAngle : 0))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(!refreshState.canRefresh || refreshState.isRefreshing)
        .focusable(false)

        // A gear straight into Settings, rather than an ellipsis menu that duplicated the
        // status item's right click menu. Everything that menu carried (accounts, updates,
        // About, status pages, Quit) is still one right click away on the menu bar icon.
        ZStack(alignment: .topTrailing) {
            Button(action: { onMenuAction?(.generalSettings) }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L.Menu.generalSettings)

            // The update dot lived on the ellipsis, so it moves here rather than disappearing
            if shouldShowUpdateBadge {
                Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: 5, y: -5)
            }
        }
    }

    @ViewBuilder
    private func headerView(provider: ProviderType, showsControls: Bool) -> some View {
        let headerIconSize: CGFloat = 18
        let headerRowHeight: CGFloat = 20
        HStack {
            if provider == .claude {
                if let icon = ImageHelper.createClaudeMark(size: headerIconSize) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: headerIconSize, height: headerIconSize)
                } else {
                    Image(systemName: "chart.pie.fill")
                        .foregroundColor(.blue)
                }
            } else if let icon = ImageHelper.createCodexMark(size: headerIconSize) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: headerIconSize, height: headerIconSize)
            }

            // Title and tier in their own tighter stack, so closing the gap between them
            // does not also pull the app icon in
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(provider == .claude ? L.Usage.title : L.Usage.codexTitle)
                    .font(.headline)

                // Subscription tier next to the title, so the header reads "Claude Team" / "Codex Plus".
                // Same size as the title (`.headline` again, so the two cannot drift apart),
                // dimmed and regular weight: it names the plan, it is not a second title.
                // Not localized, it is the plan's own name.
                let tier = provider == .claude ? settings.claudeSubscriptionTierLabel : settings.codexPlanLabel
                if !tier.isEmpty {
                    Text(tier)
                        .font(.headline)
                        .fontWeight(.regular)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if showsControls {
                refreshAndMenuButtons
            }
        }
        .frame(height: headerRowHeight, alignment: .center)
        .padding(.horizontal)
        .padding(.top, 18)
    }

    @ViewBuilder
    private var updateNotificationView: some View {
        if showUpdateNotification {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                rainbowText(L.Update.Notification.available)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 12)
            .padding(.top, -8)
            .padding(.bottom, 6)
            .transition(.opacity.combined(with: .scale))
        }
    }

    @ViewBuilder
    private func codexOnlyMainContent(codex: CodexUsageData?) -> some View {
        if let codex {
            CodexColumnView(
                codexUsageData: codex,
                showRemainingMode: $showRemainingMode,
                refreshState: refreshState,
                onToggleRemainingMode: toggleRemainingMode
            )
        } else if let error = codexErrorMessage {
            VStack(spacing: 12) {
                Image(systemName: codexNeedsRelogin ? "lock.open.trianglebadge.exclamationmark.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                Text(error)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                if codexNeedsRelogin {
                    // All three refresh levels failed: offer a one click sign in again
                    Button(action: {
                        onMenuAction?(.codexRelogin)
                    }) {
                        Label(L.Usage.codexRelogin, systemImage: "arrow.counterclockwise.circle.fill")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    // As above: both buttons used to point at settings, yet one of them read "run diagnostics"
                    HStack(spacing: 10) {
                        Button(L.Usage.refresh) { onMenuAction?(.refreshCodex) }
                        Button(L.Usage.goToSettings) { onMenuAction?(.authSettings) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(L.Usage.loading)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(height: 100)
        }
    }

    private var singleProviderBody: some View {
        VStack(spacing: contentSpacing) {
            headerView(provider: .claude, showsControls: true)
            claudeMainContent
            updateNotificationView
            Spacer()
        }
    }

    private func codexOnlyBody(codex: CodexUsageData?) -> some View {
        VStack(spacing: contentSpacing) {
            headerView(provider: .codex, showsControls: true)
            codexOnlyMainContent(codex: codex)
            updateNotificationView
            Spacer()
        }
    }

    /// Claude on top, Codex below, in the same 290 width as single provider mode. The controls
    /// sit on the top (Claude) header, where they are in single provider mode too.
    private func multiProviderBody(codex: CodexUsageData?) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: contentSpacing) {
                headerView(provider: .claude, showsControls: true)
                claudeMainContent
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, PopoverMetrics.horizontalPadding)
                .padding(.top, PopoverMetrics.providerDividerTopGap)

            VStack(spacing: contentSpacing) {
                headerView(provider: .codex, showsControls: false)
                codexOnlyMainContent(codex: codex)
            }

            updateNotificationView
            Spacer()
        }
    }

    var body: some View {
        Group {
            if isMultiProviderActive {
                multiProviderBody(codex: codexUsageData)
            } else if isCodexOnlyActive {
                codexOnlyBody(codex: codexUsageData)
            } else {
                singleProviderBody
            }
        }
        .frame(width: contentWidth, height: contentHeight)
        .animation(.easeInOut(duration: 0.25), value: isMultiProviderActive)
        .animation(.easeInOut(duration: 0.25), value: isCodexOnlyActive)
        .id(localization.updateTrigger)  // Rebuild the view when the language changes
        .onAppear {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showRemainingMode = true
            }
            // Start the spinner animation when a refresh is already running as this opens
            if refreshState.isRefreshing {
                startRotationAnimation()
            }
            // Show the notification when there is an update message
            if refreshState.notificationMessage != nil {
                withAnimation {
                    showUpdateNotification = true
                }
                // Hide the notification after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showUpdateNotification = false
                    }
                }
            }
        }
        .onChange(of: refreshState.isRefreshing) { newValue in
            if newValue { startRotationAnimation() } else { stopRotationAnimation() }
        }
        .onChange(of: refreshState.notificationMessage) { message in
            // Watch for changes to the notification message
            if message != nil {
                withAnimation {
                    showUpdateNotification = true
                }
                // Hide the notification after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showUpdateNotification = false
                    }
                }
            } else {
                withAnimation {
                    showUpdateNotification = false
                }
            }
        }
        .onDisappear {
            // Tear down the timer when the view disappears
            stopRotationAnimation()
        }
        #if DEBUG
        .background(
            UserSettings.shared.debugKeepDetailWindowOpen ? Color.white : Color.clear
        )
        #endif
    }

    private func toggleRemainingMode() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.05)) {
            showRemainingMode.toggle()
        }
    }
}

// Preview
struct UsageDetailView_Previews: PreviewProvider {
    @State static var sampleData: UsageData? = UsageData(
        fiveHour: UsageData.LimitData(
            percentage: 45,
            resetsAt: Date().addingTimeInterval(3600 * 2.5)
        ),
        sevenDay: nil,
        opus: nil,
        sonnet: nil,
        extraUsage: nil
    )

    @State static var errorMsg: String? = nil
    @State static var codexErrorMsg: String? = nil
    @State static var codexData: CodexUsageData? = nil
    @State static var codexNeedsRelogin = false
    @StateObject static var refreshState = RefreshState()
    @State static var hasUpdate = false
    @State static var shouldShowBadge = false

    static var previews: some View {
        UsageDetailView(
            usageData: $sampleData,
            codexUsageData: $codexData,
            errorMessage: $errorMsg,
            codexErrorMessage: $codexErrorMsg,
            codexNeedsRelogin: $codexNeedsRelogin,
            refreshState: refreshState,
            hasAvailableUpdate: $hasUpdate,
            shouldShowUpdateBadge: $shouldShowBadge
        )
    }
}
