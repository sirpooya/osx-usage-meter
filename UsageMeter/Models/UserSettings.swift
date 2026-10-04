//
//  UserSettings.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import ServiceManagement
import OSLog

// MARK: - Display Modes

/// Menu bar icon display mode
enum IconDisplayMode: String, CaseIterable, Codable {
    /// Percentage ring only
    case percentageOnly = "percentage_only"
    /// App icon only
    case iconOnly = "icon_only"
    /// Both the icon and the percentage
    case both = "both"
    /// No icon (a pointed separator in dual provider mode)
    case none = "no_display"

    var localizedName: String {
        switch self {
        case .percentageOnly:
            return L.Display.percentageOnly
        case .iconOnly:
            return L.Display.iconOnly
        case .both:
            return L.Display.both
        case .none:
            return L.Display.none
        }
    }
}

/// Menu bar icon style mode
enum IconStyleMode: String, CaseIterable, Codable {
    /// Colored and translucent (default, color with no background)
    case colorTranslucent = "color_translucent"
    /// Colored with a background
    case colorWithBackground = "color_with_background"
    /// Monochrome (template mode, follows the system theme)
    case monochrome = "monochrome"
    
    var localizedName: String {
        switch self {
        case .colorTranslucent:
            return L.IconStyle.colorTranslucent
        case .colorWithBackground:
            return L.IconStyle.colorWithBackground
        case .monochrome:
            return L.IconStyle.monochrome
        }
    }
    
    var description: String {
        switch self {
        case .colorTranslucent:
            return L.IconStyle.colorTranslucentDesc
        case .colorWithBackground:
            return L.IconStyle.colorWithBackgroundDesc
        case .monochrome:
            return L.IconStyle.monochromeDesc
        }
    }
}

// MARK: - Refresh Modes

/// Refresh mode
enum RefreshMode: String, CaseIterable, Codable {
    /// Smart interval (adjusts automatically to usage)
    case smart = "smart"
    /// Fixed interval (set by the user)
    case fixed = "fixed"
    
    var localizedName: String {
        switch self {
        case .smart:
            return L.Refresh.smartMode
        case .fixed:
            return L.Refresh.fixedMode
        }
    }
}

/// Data refresh interval
enum RefreshInterval: Int, CaseIterable, Codable {
    /// Refresh once a minute
    case oneMinute = 60
    /// Refresh every 3 minutes
    case threeMinutes = 180
    /// Refresh every 5 minutes
    case fiveMinutes = 300
    /// Refresh every 10 minutes
    case tenMinutes = 600
    
    var localizedName: String {
        switch self {
        case .oneMinute:
            return L.Refresh.oneMinute
        case .threeMinutes:
            return L.Refresh.threeMinutes
        case .fiveMinutes:
            return L.Refresh.fiveMinutes
        case .tenMinutes:
            return L.Refresh.tenMinutes
        }
    }
}

// MARK: - Limit Types

/// Limit type
enum LimitType: String, CaseIterable, Codable {
    /// 5 hour limit
    case fiveHour = "five_hour"
    /// 7 day limit
    case sevenDay = "seven_day"
    /// Extra Usage, the extra paid allowance
    case extraUsage = "extra_usage"
    /// Opus weekly limit
    case opusWeekly = "seven_day_opus"
    /// Sonnet weekly limit
    case sonnetWeekly = "seven_day_sonnet"
    /// Codex 5 hour window (primary)
    case codexPrimary = "codex_primary"
    /// Codex 7 day window (secondary)
    case codexSecondary = "codex_secondary"
    /// Codex Extra Usage / credits
    case codexExtraUsage = "codex_extra_usage"

    /// Owning provider
    var provider: ProviderType {
        switch self {
        case .fiveHour, .sevenDay, .extraUsage, .opusWeekly, .sonnetWeekly:
            return .claude
        case .codexPrimary, .codexSecondary, .codexExtraUsage:
            return .codex
        }
    }

    /// Whether the icon is a circle (5 hour, 7 day and both Codex entries)
    var isCircular: Bool {
        return self == .fiveHour || self == .sevenDay || self == .codexPrimary || self == .codexSecondary
    }

    /// Whether the icon is a rectangle (Opus and Sonnet)
    var isRectangular: Bool {
        return self == .opusWeekly || self == .sonnetWeekly
    }

    /// Whether the icon is a hexagon (Extra Usage)
    var isHexagonal: Bool {
        return self == .extraUsage || self == .codexExtraUsage
    }

    /// Whether it uses a dashed style (the 7 day type)
    var usesDashedStyle: Bool {
        return self == .sevenDay || self == .codexSecondary
    }

    /// Display name
    var displayName: String {
        switch self {
        case .fiveHour:
            return L.LimitTypes.fiveHour
        case .sevenDay:
            return L.LimitTypes.sevenDay
        case .opusWeekly:
            return L.LimitTypes.opusWeekly
        case .sonnetWeekly:
            return L.LimitTypes.sonnetWeekly
        case .extraUsage:
            return L.LimitTypes.extraUsage
        case .codexPrimary:
            return L.LimitTypes.codexPrimary
        case .codexSecondary:
            return L.LimitTypes.codexSecondary
        case .codexExtraUsage:
            return L.LimitTypes.codexExtraUsage
        }
    }

    /// Name for a list already grouped under a provider heading, so Codex rows drop the
    /// "Codex" prefix the heading already says. Reuses the Claude labels, which is what the
    /// popover shows for the same Codex rows. Notifications keep `displayName`.
    var groupedName: String {
        switch self {
        case .codexPrimary:
            return LimitType.fiveHour.displayName
        case .codexSecondary:
            return LimitType.sevenDay.displayName
        case .codexExtraUsage:
            return LimitType.extraUsage.displayName
        default:
            return displayName
        }
    }
}

// MARK: - Display Mode

/// Display mode (smart or custom)
enum DisplayMode: String, CaseIterable, Codable {
    /// Smart display, shows every limit type that has data
    case smart = "smart"
    /// Custom display, the user picks which limit types to show
    case custom = "custom"

    var localizedName: String {
        switch self {
        case .smart:
            return L.DisplayOptions.smartDisplay
        case .custom:
            return L.DisplayOptions.customDisplay
        }
    }
}

/// Time format preference
enum TimeFormatPreference: String, CaseIterable, Codable {
    /// Follow the system
    case system = "system"
    /// 12 hour clock
    case twelveHour = "twelve_hour"
    /// 24 hour clock
    case twentyFourHour = "twenty_four_hour"

    var localizedName: String {
        switch self {
        case .system:
            return L.TimeFormat.system
        case .twelveHour:
            return L.TimeFormat.twelveHour
        case .twentyFourHour:
            return L.TimeFormat.twentyFourHour
        }
    }
}

/// App appearance mode
enum AppAppearance: String, CaseIterable, Codable {
    /// Follow the system
    case system = "system"
    /// Light
    case light = "light"
    /// Dark
    case dark = "dark"

    var localizedName: String {
        switch self {
        case .system:
            return L.Appearance.system
        case .light:
            return L.Appearance.light
        case .dark:
            return L.Appearance.dark
        }
    }

    /// The matching SwiftUI ColorScheme (system returns nil, meaning follow the system)
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

/// App language options
enum AppLanguage: String, CaseIterable, Codable {
    /// English
    case english = "en"
    /// Japanese
    case japanese = "ja"
    /// Simplified Chinese
    case chinese = "zh-Hans"
    /// Traditional Chinese
    case chineseTraditional = "zh-Hant"
    /// Korean
    case korean = "ko"
    /// French
    case french = "fr"
    /// German
    case german = "de"

    var localizedName: String {
        switch self {
        case .english:
            return L.Language.english
        case .japanese:
            return L.Language.japanese
        case .chinese:
            return L.Language.chinese
        case .chineseTraditional:
            return L.Language.chineseTraditional
        case .korean:
            return L.Language.korean
        case .french:
            return L.Language.french
        case .german:
            return L.Language.german
        }
    }
}

extension AppLanguage {
    /// Convert the app language to its Locale
    var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US")
        case .japanese:
            return Locale(identifier: "ja_JP")
        case .chinese:
            return Locale(identifier: "zh_CN")
        case .chineseTraditional:
            return Locale(identifier: "zh_TW")
        case .korean:
            return Locale(identifier: "ko_KR")
        case .french:
            return Locale(identifier: "fr_FR")
        case .german:
            return Locale(identifier: "de_DE")
        }
    }
}

// MARK: - User Settings

/// User settings
/// Owns every user setting: authentication, display options, language and the rest
/// Sensitive data (organization ID and session key) is stored in the Keychain
/// Non sensitive settings are stored in UserDefaults
class UserSettings: ObservableObject {
    // MARK: - Singleton

    /// Shared instance
    static let shared = UserSettings()

    /// Default value for customDisplayTypes, shared by init() and resetToDefaults() so the two cannot drift apart
    static let defaultCustomDisplayTypes: Set<LimitType> = [.fiveHour, .sevenDay]

    // MARK: - Properties

    private let defaults = UserDefaults.standard
    private let keychain = KeychainManager.shared

    /// Combine subscriptions: forwards accountStore's objectWillChange, so SwiftUI views bound to UserSettings
    /// also update when account data changes (see the subscription in init())
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Multi account support (v2.1.0, split into AccountStore, see audit report 4.1)

    /// Account CRUD, persistence and the current account ID all moved to AccountStore, so this is only a facade
    /// that forwards, keeping every call site (settings.accounts, settings.addAccount(...) and so on) unchanged.
    let accountStore = AccountStore()

    var accounts: [Account] { accountStore.accounts }
    var currentAccountId: UUID? { accountStore.currentAccountId }
    var currentAccount: Account? { accountStore.currentAccount }

    var sessionKey: String {
        get { accountStore.sessionKey }
        set { accountStore.sessionKey = newValue }
    }

    var organizationId: String {
        get { accountStore.organizationId }
        set { accountStore.organizationId = newValue }
    }

    /// Semantic alias for the Claude account list (same as accounts, keeps provider aware code symmetric)
    var claudeAccounts: [Account] { accountStore.claudeAccounts }

    // MARK: - Codex account support

    var codexAccounts: [Account] { accountStore.codexAccounts }
    var currentCodexAccountId: UUID? { accountStore.currentCodexAccountId }
    var currentCodexAccount: Account? { accountStore.currentCodexAccount }
    var codexSessionToken: String { accountStore.codexSessionToken }
    var hasValidCodexCredentials: Bool { accountStore.hasValidCodexCredentials }

    /// Whether both a Claude and a Codex account exist (which puts the UI into multi provider form)
    var isMultiProviderActive: Bool {
        #if DEBUG
        if debugModeEnabled {
            if displayMode == .custom {
                let hasClaudeDisplayTypes = customDisplayTypes.contains { $0.provider == .claude }
                let hasCodexDisplayTypes = customDisplayTypes.contains { $0.provider == .codex }
                return hasClaudeDisplayTypes && hasCodexDisplayTypes
            }
            return true
        }
        #endif
        return !accounts.isEmpty && !codexAccounts.isEmpty
    }

    // MARK: - Non sensitive settings (stored in UserDefaults)

    /// Menu bar icon display mode
    @Published var iconDisplayMode: IconDisplayMode {
        didSet {
            defaults.set(iconDisplayMode.rawValue, forKey: "iconDisplayMode")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    
    /// Menu bar icon style mode
    @Published var iconStyleMode: IconStyleMode {
        didSet {
            defaults.set(iconStyleMode.rawValue, forKey: "iconStyleMode")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// The account's subscription tier, cached for display next to the popover title ("Claude Team").
    /// Cached rather than fetched on demand: the only free sources are read on a background queue
    /// (Claude Code's Keychain entry on every CLI synced poll, the OAuth profile at login), and the
    /// header cannot touch the Keychain while rendering. Empty means unknown, and the header then
    /// shows the plain title.
    @Published var claudeSubscriptionTier: String {
        didSet {
            guard claudeSubscriptionTier != oldValue else { return }
            defaults.set(claudeSubscriptionTier, forKey: "claude.subscriptionTier")
        }
    }

    /// The tier as it reads next to the popover title, so "team" and "claude_team" both give "Team".
    /// Normalized generically rather than matched against a fixed list: the raw value comes from the
    /// server, so a tier this build has never heard of still prints instead of vanishing.
    /// Empty for the tiers not worth a badge (no subscription, or nothing known yet).
    var claudeSubscriptionTierLabel: String {
        Self.planLabel(claudeSubscriptionTier, dropPrefix: "claude_")
    }

    /// The Codex account's plan (`plan_type` from the wham/usage response: plus, pro, team...),
    /// cached for the popover title ("Codex Plus") the same way as `claudeSubscriptionTier`.
    @Published var codexPlanType: String {
        didSet {
            guard codexPlanType != oldValue else { return }
            defaults.set(codexPlanType, forKey: "codex.planType")
        }
    }

    /// The plan as it reads next to the Codex title. Same normalization as the Claude tier.
    var codexPlanLabel: String {
        // The API's internal SKU names carry billing qualifiers the user never sees on
        // chatgpt.com, e.g. "self_serve_business_prolite" is just the Business plan
        let plan = codexPlanType.lowercased()
            .replacingOccurrences(of: "self_serve_", with: "")
            .replacingOccurrences(of: "_prolite", with: "")
        return Self.planLabel(plan, dropPrefix: "chatgpt_")
    }

    /// Shared plan name formatting: lowercase, drop a provider prefix, title case each word.
    /// Empty for plans not worth a badge (free, none, unknown).
    private static func planLabel(_ raw: String, dropPrefix prefix: String) -> String {
        var value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        guard !["", "free", "none", "unknown"].contains(value) else { return "" }
        return value
            .split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Time marker: a tick on the progress bars at the point the current period has reached,
    /// so usage can be read against how much of the window is gone.
    @Published var showTimeMarker: Bool {
        didSet {
            defaults.set(showTimeMarker, forKey: "showTimeMarker")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Pace-aware bar colours: escalate on the projected end-of-window figure rather than on
    /// current usage, so the colour answers "will I hit the cap" instead of "where am I now".
    @Published var paceAwareBarColors: Bool {
        didSet {
            defaults.set(paceAwareBarColors, forKey: "paceAwareBarColors")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Battery style display: show remaining capacity instead of used percentage.
    /// Flips the displayed number and the ring/bar fill everywhere; status colors stay keyed off used.
    @Published var showRemainingPercentage: Bool {
        didSet {
            defaults.set(showRemainingPercentage, forKey: "showRemainingPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Refresh mode (smart or fixed)
    @Published var refreshMode: RefreshMode {
        didSet {
            defaults.set(refreshMode.rawValue, forKey: "refreshMode")
            NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
        }
    }
    
    /// Data refresh interval (seconds), used in fixed mode only
    @Published var refreshInterval: Int {
        didSet {
            defaults.set(refreshInterval, forKey: "refreshInterval")
            NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
        }
    }
    
    /// App interface language
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    /// Appearance persistence, applying it to NSApp and watching the system theme all live in AppearanceManager, so this is only a forwarding facade.
    /// A computed property still forms a ReferenceWritableKeyPath, so the $settings.appearance two way binding is unaffected.
    let appearanceManager = AppearanceManager()

    var appearance: AppAppearance {
        get { appearanceManager.appearance }
        set { appearanceManager.appearance = newValue }
    }

    /// Time format preference
    @Published var timeFormatPreference: TimeFormatPreference {
        didSet {
            defaults.set(timeFormatPreference.rawValue, forKey: "timeFormatPreference")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Display mode (smart or custom)
    @Published var displayMode: DisplayMode {
        didSet {
            defaults.set(displayMode.rawValue, forKey: "displayMode")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// The custom set of limit types (used in custom mode only)
    @Published var customDisplayTypes: Set<LimitType> {
        didSet {
            let rawValues = customDisplayTypes.map { $0.rawValue }
            defaults.set(rawValues, forKey: "customDisplayTypes")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Whether the custom display applies to the menu bar only (when on, the popover uses the smart display)
    @Published var customDisplayMenuBarOnly: Bool {
        didSet {
            defaults.set(customDisplayMenuBarOnly, forKey: "customDisplayMenuBarOnly")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Whether the popover should show custom mode placeholders (0% shells)
    /// True only when the display mode is custom and "menu bar only" is off
    var shouldShowCustomPlaceholderInPopover: Bool {
        displayMode == .custom && !customDisplayMenuBarOnly
    }

    /// First launch flag
    @Published var isFirstLaunch: Bool {
        didSet {
            defaults.set(isFirstLaunch, forKey: "isFirstLaunch")
        }
    }
    
    /// Whether usage notifications are enabled
    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }

    /// Registering, unregistering and status syncing for launch at login all live in LaunchAtLoginManager, so this is only a forwarding facade.
    /// isEnabled is derived straight from SMAppService.mainApp.status (the single source of truth),
    /// so there is no stored Bool plus flag to prevent recursion, and on failure the Toggle snaps back as status stays put.
    let launchAtLoginManager = LaunchAtLoginManager()

    var launchAtLogin: Bool {
        get { launchAtLoginManager.isEnabled }
        set { launchAtLoginManager.isEnabled = newValue }
    }

    /// Launch at login state (for the UI)
    var launchAtLoginStatus: SMAppService.Status { launchAtLoginManager.status }

    // MARK: - Debug Mode (Debug builds only)

    #if DEBUG
    /// Whether debug mode is on (simulating different data scenarios)
    @Published var debugModeEnabled: Bool {
        didSet {
            defaults.set(debugModeEnabled, forKey: "debugModeEnabled")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug scenario type
    @Published var debugScenario: DebugScenario {
        didSet {
            defaults.set(debugScenario.rawValue, forKey: "debugScenario")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug 5 hour limit percentage (0-100)
    @Published var debugFiveHourPercentage: Double {
        didSet {
            defaults.set(debugFiveHourPercentage, forKey: "debugFiveHourPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug 7 day limit percentage (0-100)
    @Published var debugSevenDayPercentage: Double {
        didSet {
            defaults.set(debugSevenDayPercentage, forKey: "debugSevenDayPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug Opus limit percentage (0-100)
    @Published var debugOpusPercentage: Double {
        didSet {
            defaults.set(debugOpusPercentage, forKey: "debugOpusPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug Sonnet limit percentage (0-100)
    @Published var debugSonnetPercentage: Double {
        didSet {
            defaults.set(debugSonnetPercentage, forKey: "debugSonnetPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug Codex 5 hour window percentage (0-100)
    @Published var debugCodexPrimaryPercentage: Double {
        didSet {
            defaults.set(debugCodexPrimaryPercentage, forKey: "debugCodexPrimaryPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug Codex 7 day window percentage (0-100)
    @Published var debugCodexSecondaryPercentage: Double {
        didSet {
            defaults.set(debugCodexSecondaryPercentage, forKey: "debugCodexSecondaryPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug Codex Extra Usage percentage (0-100)
    @Published var debugCodexExtraUsagePercentage: Double {
        didSet {
            defaults.set(debugCodexExtraUsagePercentage, forKey: "debugCodexExtraUsagePercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Debug flag for whether Extra Usage is enabled
    @Published var debugExtraUsageEnabled: Bool {
        didSet {
            defaults.set(debugExtraUsageEnabled, forKey: "debugExtraUsageEnabled")
        }
    }

    /// Debug Extra Usage amount used (cents), the same unit as the real API's used_credits
    @Published var debugExtraUsageUsed: Double {
        didSet {
            defaults.set(debugExtraUsageUsed, forKey: "debugExtraUsageUsed")
        }
    }

    /// Debug Extra Usage total limit (cents), the same unit as the real API's monthly_limit, integers only
    @Published var debugExtraUsageLimit: Int {
        didSet {
            defaults.set(debugExtraUsageLimit, forKey: "debugExtraUsageLimit")
        }
    }

    /// Debug Extra Usage percentage (0-100), which also updates the used value
    @Published var debugExtraUsagePercentage: Double {
        didSet {
            defaults.set(debugExtraUsagePercentage, forKey: "debugExtraUsagePercentage")
            // Also update the used value (cents)
            debugExtraUsageUsed = Double(debugExtraUsageLimit) * (debugExtraUsagePercentage / 100.0)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Whether to simulate an available update (for debugging)
    @Published var simulateUpdateAvailable: Bool {
        didSet {
            defaults.set(simulateUpdateAvailable, forKey: "simulateUpdateAvailable")
            // Post a notification so MenuBarManager rechecks the update state
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Whether to show every shape icon separately in the menu bar (for debugging, handy for screenshots)
    @Published var debugShowAllShapesIndividually: Bool {
        didSet {
            defaults.set(debugShowAllShapesIndividually, forKey: "debugShowAllShapesIndividually")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// Whether to keep the detail window open at all times (for debugging, handy for recording animations)
    @Published var debugKeepDetailWindowOpen: Bool {
        didSet {
            defaults.set(debugKeepDetailWindowOpen, forKey: "debugKeepDetailWindowOpen")
        }
    }

    /// Debug scenarios
    enum DebugScenario: String, CaseIterable {
        case realData = "real"              // Real API data
        case fiveHourOnly = "five_hour"     // 5 hour limit only
        case sevenDayOnly = "seven_day"     // 7 day limit only
        case both = "both"                  // Both kinds of limit
        case allFive = "all_five"           // All 5 limits (v2.0 test)

        var displayName: String {
            switch self {
            case .realData:
                return "Real data"
            case .fiveHourOnly:
                return "5 hour limit only"
            case .sevenDayOnly:
                return "7 day limit only"
            case .both:
                return "Both limits"
            case .allFive:
                return "All five limits"
            }
        }
    }
    #endif

    // MARK: - Smart mode internal state (not persisted, delegated to the pure SmartRefreshPolicy state machine)

    /// The 4 level monitoring mode state machine behind smart refresh (pure logic, unit testable on its own, see Helpers/SmartRefreshPolicy.swift)
    private let smartRefreshPolicy = SmartRefreshPolicy()

    /// The percentage from the last check (used to detect changes)
    var lastUtilization: Double? {
        get { smartRefreshPolicy.lastUtilization }
        set { smartRefreshPolicy.lastUtilization = newValue }
    }

    /// Number of consecutive unchanged polls
    var unchangedCount: Int {
        get { smartRefreshPolicy.unchangedCount }
        set { smartRefreshPolicy.unchangedCount = newValue }
    }

    /// Current monitoring mode (used in smart mode)
    var currentMonitoringMode: MonitoringMode {
        get { smartRefreshPolicy.currentMode }
        set { smartRefreshPolicy.currentMode = newValue }
    }

    // MARK: - Initialization
    
    /// Detect the system language and map it onto a language the app supports
    /// - Returns: the AppLanguage closest to the system language
    private static func detectSystemLanguage() -> AppLanguage {
        let systemLanguage = Locale.preferredLanguages.first ?? "en"

        // Match the system language prefix against the languages the app supports
        if systemLanguage.hasPrefix("zh-Hans") {
            return .chinese
        } else if systemLanguage.hasPrefix("zh-Hant") || systemLanguage.hasPrefix("zh-HK") || systemLanguage.hasPrefix("zh-TW") {
            return .chineseTraditional
        } else if systemLanguage.hasPrefix("ja") {
            return .japanese
        } else if systemLanguage.hasPrefix("ko") {
            return .korean
        } else if systemLanguage.hasPrefix("fr") {
            return .french
        } else if systemLanguage.hasPrefix("de") {
            return .german
        } else {
            return .english  // English by default
        }
    }
    
    /// Private initializer (singleton)
    /// Loads sensitive data from the Keychain and everything else from UserDefaults
    private init() {
        // MARK: - Load non sensitive settings from UserDefaults

        if let modeString = defaults.string(forKey: "iconDisplayMode"),
           let mode = IconDisplayMode(rawValue: modeString) {
            self.iconDisplayMode = mode
        } else {
            self.iconDisplayMode = .percentageOnly
        }
        
        if let styleString = defaults.string(forKey: "iconStyleMode"),
           let style = IconStyleMode(rawValue: styleString) {
            self.iconStyleMode = style
        } else {
            // Color by default: the status colors carry the information, monochrome is the opt-in
            self.iconStyleMode = .colorTranslucent
        }

        self.claudeSubscriptionTier = defaults.string(forKey: "claude.subscriptionTier") ?? ""
        self.codexPlanType = defaults.string(forKey: "codex.planType") ?? ""
        
        // Load the refresh mode, smart by default
        if let modeString = defaults.string(forKey: "refreshMode"),
           let mode = RefreshMode(rawValue: modeString) {
            self.refreshMode = mode
        } else {
            self.refreshMode = .smart
        }
        
        let savedRefreshInterval = defaults.integer(forKey: "refreshInterval")
        self.refreshInterval = savedRefreshInterval > 0 ? savedRefreshInterval : 180 // 3 minutes by default
        
        if let langString = defaults.string(forKey: "language"),
           let lang = AppLanguage(rawValue: langString) {
            self.language = lang
        } else {
            // Use the system language on first launch
            self.language = Self.detectSystemLanguage()
        }

        // Appearance loading moved into AppearanceManager.init()

        // Always follow the system. The Time Format card was removed from the General tab, so a
        // stored 12 or 24 hour choice would be stuck with no way to change it; ignoring the key
        // means everyone follows the system rather than only new installs.
        self.timeFormatPreference = .system

        // Load the display mode, smart by default
        if let modeString = defaults.string(forKey: "displayMode"),
           let mode = DisplayMode(rawValue: modeString) {
            self.displayMode = mode
        } else {
            self.displayMode = .smart
        }

        // Load the custom display types, the 5 hour and 7 day limits by default
        if let rawValues = defaults.array(forKey: "customDisplayTypes") as? [String] {
            self.customDisplayTypes = Set(rawValues.compactMap { LimitType(rawValue: $0) })
        } else {
            self.customDisplayTypes = Self.defaultCustomDisplayTypes
        }

        // Load the "custom display applies to the menu bar only" switch, off by default (backward compatible)
        self.customDisplayMenuBarOnly = defaults.bool(forKey: "customDisplayMenuBarOnly")

        // Check for a first launch (no saved authentication means this is the first launch)
        if !defaults.bool(forKey: "hasLaunched") {
            self.isFirstLaunch = true
            defaults.set(true, forKey: "hasLaunched")
        } else {
            self.isFirstLaunch = false
        }
        
        // Load the notification setting, on by default
        self.notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true

        // Load the remaining percentage display, off (show used) by default
        self.showRemainingPercentage = defaults.bool(forKey: "showRemainingPercentage")

        // Load the pace-aware bar colors, off (color on current usage) by default
        self.paceAwareBarColors = defaults.bool(forKey: "paceAwareBarColors")

        // Load the time marker, off by default
        self.showTimeMarker = defaults.bool(forKey: "showTimeMarker")

        // Launch at login loading moved into LaunchAtLoginManager.init()

        // MARK: - Initialize the debug mode settings

        #if DEBUG
        self.debugModeEnabled = defaults.bool(forKey: "debugModeEnabled")
        self.debugScenario = DebugScenario(
            rawValue: defaults.string(forKey: "debugScenario") ?? "real"
        ) ?? .realData
        self.debugFiveHourPercentage = defaults.object(forKey: "debugFiveHourPercentage") as? Double ?? 55.0
        self.debugSevenDayPercentage = defaults.object(forKey: "debugSevenDayPercentage") as? Double ?? 66.0
        self.debugOpusPercentage = defaults.object(forKey: "debugOpusPercentage") as? Double ?? 77.0
        self.debugSonnetPercentage = defaults.object(forKey: "debugSonnetPercentage") as? Double ?? 88.0
        self.debugCodexPrimaryPercentage = defaults.object(forKey: "debugCodexPrimaryPercentage") as? Double ?? 42.0
        self.debugCodexSecondaryPercentage = defaults.object(forKey: "debugCodexSecondaryPercentage") as? Double ?? 58.0
        self.debugCodexExtraUsagePercentage = defaults.object(forKey: "debugCodexExtraUsagePercentage") as? Double ?? 35.0
        self.debugExtraUsageEnabled = defaults.object(forKey: "debugExtraUsageEnabled") as? Bool ?? true
        self.debugExtraUsageUsed = defaults.object(forKey: "debugExtraUsageUsed") as? Double ?? 3050.0
        self.debugExtraUsageLimit = defaults.object(forKey: "debugExtraUsageLimit") as? Int ?? 5000
        self.debugExtraUsagePercentage = defaults.object(forKey: "debugExtraUsagePercentage") as? Double ?? 61.0
        self.simulateUpdateAvailable = defaults.bool(forKey: "simulateUpdateAvailable")
        self.debugShowAllShapesIndividually = defaults.bool(forKey: "debugShowAllShapesIndividually")
        self.debugKeepDetailWindowOpen = defaults.bool(forKey: "debugKeepDetailWindowOpen")
        #endif

        // Account loading and migration, launch at login registration state, applying the appearance and watching the system theme
        // each moved into the init() of AccountStore / LaunchAtLoginManager / AppearanceManager;
        // all that is left here is forwarding their objectWillChange, so the SwiftUI views using
        // @ObservedObject var settings = UserSettings.shared refresh when those child objects change.
        for publisher in [accountStore.objectWillChange, launchAtLoginManager.objectWillChange, appearanceManager.objectWillChange] {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        // Sync the system's real launch at login state (LaunchAtLoginManager.init only read one snapshot,
        // so refresh once here in case the user changed it in System Settings before the app started)
        syncLaunchAtLoginStatus()
    }
    
    // MARK: - Computed Properties

    /// The Locale the app currently uses (from the language the user chose)
    var appLocale: Locale {
        return language.locale
    }

    /// Check whether authentication is configured
    /// An OAuth account counts as valid on its refresh_token alone (the sk-ant-ort01- prefix);
    /// a session cookie account still needs both organizationId and sessionKey to be non empty.
    var hasValidCredentials: Bool {
        guard !sessionKey.isEmpty else { return false }
        if sessionKey.hasPrefix("sk-ant-ort01-") { return true }
        return !organizationId.isEmpty
    }

    /// Check whether authentication is configured for either provider
    var hasAnyValidCredentials: Bool {
        return hasValidCredentials || hasValidCodexCredentials
    }

    /// Validate the organization ID format
    /// - Parameter id: the organization ID to validate
    /// - Returns: true when the format is valid (a UUID)
    func isValidOrganizationId(_ id: String) -> Bool {
        // An organization ID should be a UUID
        let uuidRegex = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", uuidRegex)
        return predicate.evaluate(with: id)
    }

    /// Validate the session key format
    /// - Parameter key: the session key to validate
    /// - Returns: true when the format is valid
    func isValidSessionKey(_ key: String) -> Bool {
        // A session key should be non empty and of a plausible length
        // A typical session key is 20 to 200 characters
        return !key.isEmpty && key.count >= 20 && key.count <= 500
    }
    
    /// Get the refresh interval currently in effect (seconds)
    /// - Returns: in smart mode the current monitoring mode's interval, in fixed mode the interval the user set
    var effectiveRefreshInterval: Int {
        switch refreshMode {
        case .smart:
            return currentMonitoringMode.interval
        case .fixed:
            return refreshInterval
        }
    }
    
    // MARK: - Public Methods

    /// Reset to the default settings
    /// Resets only the non sensitive settings, authentication is untouched
    func resetToDefaults() {
        appearance = .system
        iconDisplayMode = .percentageOnly
        iconStyleMode = .colorTranslucent
        showRemainingPercentage = false
        paceAwareBarColors = false
        showTimeMarker = false
        refreshMode = .smart
        refreshInterval = 180  // 3 minutes by default in fixed mode
        language = Self.detectSystemLanguage()
        timeFormatPreference = .system
        displayMode = .smart
        customDisplayTypes = Self.defaultCustomDisplayTypes
        customDisplayMenuBarOnly = false
        notificationsEnabled = true

        // Reset the smart mode state
        lastUtilization = nil
        unchangedCount = 0
        currentMonitoringMode = .active
    }
    
    /// Clear all authentication data
    /// Deletes the organization ID and session key from the Keychain
    func clearCredentials() {
        keychain.deleteCredentials()
        organizationId = ""
        sessionKey = ""
        Logger.settings.notice("Cleared all credentials")
    }
    
    /// Update the smart monitoring mode
    /// Adjust the refresh interval from how the usage percentage moves
    /// - Parameter currentUtilization: the current usage percentage
    func updateSmartMonitoringMode(currentUtilization: Double) {
        updateSmartMonitoringMode(providerUtilizations: [.claude: currentUtilization])
    }

    /// Update the smart monitoring mode
    /// Any provider whose usage changed switches back to active mode; only when nothing changed does the quiet count build up.
    /// The state machine itself lives in SmartRefreshPolicy (pure logic, unit testable); this only handles the two side effects, logging and notifications.
    /// - Parameter providerUtilizations: provider usage percentages fetched successfully this round
    func updateSmartMonitoringMode(providerUtilizations: [ProviderType: Double]) {
        // Only does anything in smart mode
        guard refreshMode == .smart else { return }

        let previousMode = smartRefreshPolicy.currentMode
        let modeChanged = smartRefreshPolicy.update(providerUtilizations: providerUtilizations)

        if modeChanged {
            logModeTransition(from: previousMode, to: smartRefreshPolicy.currentMode)
            NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
        }
    }

    /// Log a mode switch
    /// - Parameters:
    ///   - from: the old mode
    ///   - to: the new mode
    private func logModeTransition(from: MonitoringMode, to: MonitoringMode) {
        let modeNames: [MonitoringMode: String] = [
            .active: "active (1 min)",
            .idleShort: "short idle (3 min)",
            .idleMedium: "medium idle (5 min)",
            .idleLong: "long idle (10 min)"
        ]
        Logger.settings.debug("Monitoring mode change: \(modeNames[from] ?? "") -> \(modeNames[to] ?? "")")
    }

    /// Reset the smart monitoring mode state
    /// Called when switching to fixed mode, or on a manual refresh
    func resetSmartMonitoringState() {
        smartRefreshPolicy.reset()
    }

    // MARK: - Account Management (v2.1.0)
    // The real storage and persistence lives in AccountStore (Models/AccountStore.swift), this is only a forwarding facade
    // that keeps the call sites unchanged. addCodexAccount also initializes the display types for a "first Codex account",
    // because that part reads displayMode and customDisplayTypes, which are UserSettings' own business.

    /// Add a new account
    /// - Parameter account: the account to add
    func addAccount(_ account: Account) {
        accountStore.addAccount(account)
    }

    /// Delete an account
    /// - Parameter account: the account to delete
    func removeAccount(_ account: Account) {
        accountStore.removeAccount(account)
    }

    /// Switch to the given account
    /// - Parameter account: the account to switch to
    func switchToAccount(_ account: Account) {
        accountStore.switchToAccount(account)
    }

    /// Update account information
    /// - Parameters:
    ///   - account: the account to update
    ///   - alias: new alias (optional)
    func updateAccount(_ account: Account, alias: String?) {
        accountStore.updateAccount(account, alias: alias)
    }

    /// Account list used for display
    var displayAccounts: [Account] { accountStore.displayAccounts }

    /// Display name of the current account
    var currentAccountName: String? { accountStore.currentAccountName }

    // MARK: - Codex Account Management

    @discardableResult
    func addCodexAccount(_ account: Account) -> Account {
        let (stored, wasFirstCodexAccount) = accountStore.addCodexAccount(account)
        if wasFirstCodexAccount {
            ensureDefaultCodexDisplayTypesForCustomMode()
        }
        return stored
    }

    func removeCodexAccount(_ account: Account) {
        accountStore.removeCodexAccount(account)
    }

    func switchToCodexAccount(_ account: Account) {
        accountStore.switchToCodexAccount(account)
    }

    func updateCodexAccount(_ account: Account, alias: String?) {
        accountStore.updateCodexAccount(account, alias: alias)
    }

    /// Silently update the current Codex account's session token (does not post accountChanged)
    /// For the auto renewal case: only the persisted data changes, no refetch loop is triggered
    func silentlyUpdateCurrentCodexSessionToken(_ token: String) {
        accountStore.silentlyUpdateCurrentCodexSessionToken(token)
    }

    /// Silently update the current Claude account's session token (does not post accountChanged)
    /// For the OAuth refresh_token rotation case: only the persisted data changes, no refetch loop is triggered
    func silentlyUpdateCurrentClaudeSessionToken(_ token: String) {
        accountStore.silentlyUpdateCurrentClaudeSessionToken(token)
    }

    private func ensureDefaultCodexDisplayTypesForCustomMode() {
        guard displayMode == .custom else { return }
        let codexTypes: Set<LimitType> = [.codexPrimary, .codexSecondary, .codexExtraUsage]
        guard customDisplayTypes.isDisjoint(with: codexTypes) else { return }
        customDisplayTypes.formUnion([.codexPrimary, .codexSecondary])
    }

    // MARK: - Launch at Login Management
    // Registering, unregistering and status syncing all live in LaunchAtLoginManager, so only one forwarding method is left here,
    // for UsageMeterApp (didBecomeActive) and the settings page (onAppear).

    /// Read the real launch at login state from the system and update the UI
    func syncLaunchAtLoginStatus() {
        launchAtLoginManager.refreshStatus()
    }

    // MARK: - Display Logic Helper Methods (v2.0)

    /// Get the list of limit types to show right now
    /// - Parameters:
    ///   - usageData: Claude usage data
    ///   - codexUsageData: Codex usage data (optional, passed in when there is a Codex account)
    ///   - forMenuBar: whether this is for menu bar rendering. When customDisplayMenuBarOnly is on,
    ///                 only the menu bar takes the custom branch and the popover falls back to the smart branch
    /// - Returns: the limit types to show, in display order
    func getActiveDisplayTypes(usageData: UsageData?, codexUsageData: CodexUsageData? = nil, forMenuBar: Bool = false) -> [LimitType] {
        // When "menu bar only" is on and this render is for the popover, force the smart branch
        let effectiveMode: DisplayMode = {
            if displayMode == .custom && customDisplayMenuBarOnly && !forMenuBar {
                return .smart
            }
            return displayMode
        }()
        switch effectiveMode {
        case .smart:
            // Smart mode: show every type that has data
            var types: [LimitType] = []

            // Claude types, in the canonical order fiveHour, sevenDay, extraUsage, opus, sonnet
            if let data = usageData {
                // The 5 hour and 7 day limits always show, because every account is bound by those two
                types.append(.fiveHour)
                types.append(.sevenDay)
                if data.extraUsage?.enabled == true {
                    types.append(.extraUsage)
                }
                if data.opus != nil {
                    types.append(.opusWeekly)
                }
                if data.sonnet != nil {
                    types.append(.sonnetWeekly)
                }
            }

            // Codex types are appended only when their window actually has data
            // (Codex once dropped the 5 hour window temporarily, leaving the API returning only the 7 day window,
            //  so unlike Claude's fiveHour/sevenDay we cannot assume primary always exists)
            if let codex = codexUsageData {
                if codex.primary != nil {
                    types.append(.codexPrimary)
                }
                if codex.secondary != nil {
                    types.append(.codexSecondary)
                }
                if codex.extraUsage?.enabled == true {
                    types.append(.codexExtraUsage)
                }
            }

            return types

        case .custom:
            // Custom mode: the user's order, shown whether the data exists or not
            // Codex types are candidates only when a Codex account exists; the debug mock mode is the exception
            var orderedTypes: [LimitType] = [.fiveHour, .sevenDay, .extraUsage, .opusWeekly, .sonnetWeekly]
            var shouldIncludeCodexTypes = !codexAccounts.isEmpty
            #if DEBUG
            if debugModeEnabled {
                shouldIncludeCodexTypes = true
            }
            #endif
            if shouldIncludeCodexTypes {
                orderedTypes.append(contentsOf: [.codexPrimary, .codexSecondary, .codexExtraUsage])
            }
            return orderedTypes.filter { customDisplayTypes.contains($0) }
        }
    }

    /// Decide whether the current configuration can use a color theme
    /// - Returns: true when a color theme is available
    func canUseColoredTheme(usageData: UsageData?) -> Bool {
        let activeTypes = getActiveDisplayTypes(usageData: usageData)

        // Every limit type supports colored display now
        // A color theme works as long as there is an icon
        return !activeTypes.isEmpty
    }
}

// MARK: - Notification Names

/// Settings notification name extensions
// Note: the notification names now live in NotificationNames.swift
// Imported here for backward compatibility
