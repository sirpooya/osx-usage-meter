//
//  LocalizationHelper.swift
//  UsageMeter
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Localized string accessors
/// Type safe access to localized strings
/// Supports switching languages at runtime, returning the string for the user's setting
enum L {
    
    // MARK: - Menu Items
    enum Menu {
        static var settings: String { localized("menu.settings") }
        static var generalSettings: String { localized("menu.general_settings") }
        static var authSettings: String { localized("menu.auth_settings") }
        static var checkUpdates: String { localized("menu.check_updates") }
        static var about: String { localized("menu.about") }
        static var claudeStatus: String { localized("menu.claude_status") }
        static var codexStatus: String { localized("menu.codex_status") }
        static var coffee: String { localized("menu.coffee") }
        static var githubSponsor: String { localized("menu.github_sponsor") }
        static var quit: String { localized("menu.quit") }
        static var account: String { localized("menu.account") }
        static var accountPrefix: String { localized("menu.account_prefix") }
    }

    // MARK: - Account Management
    enum Account {
        static var listTitle: String { localized("account.list_title") }
        static var noAccounts: String { localized("account.no_accounts") }
        static var addAccount: String { localized("account.add_account") }
        static var addNewAccount: String { localized("account.add_new_account") }
        static var currentAccount: String { localized("account.current_account") }
        static var switchTo: String { localized("account.switch_to") }
        static var alias: String { localized("account.alias") }
        static var aliasOptional: String { localized("account.alias_optional") }
        static var aliasPlaceholder: String { localized("account.alias_placeholder") }
        static var clearAlias: String { localized("account.clear_alias") }
        static var organizationId: String { localized("account.organization_id") }
        static var copyOrgId: String { localized("account.copy_org_id") }
        static var deleteAccount: String { localized("account.delete_account") }
        static var deleteConfirmTitle: String { localized("account.delete_confirm_title") }
        static var deleteConfirmMessage: String { localized("account.delete_confirm_message") }
        static var delete: String { localized("account.delete") }
        static var cancel: String { localized("account.cancel") }
        static var validateAndAdd: String { localized("account.validate_and_add") }
        static var multiOrgAdded: String { localized("account.multi_org_added") }
        static var claudeAccounts: String { localized("account.claude_accounts") }
        static var codexAccounts: String { localized("account.codex_accounts") }
        static var addCodexAccount: String { localized("account.add_codex_account") }
        static var codexCurrentAccount: String { localized("account.codex_current_account") }
    }
    
    // MARK: - Usage Detail View
    enum Usage {
        static var title: String { localized("usage.title") }
        static var notStarted: String { localized("usage.not_started") }
        static var resetIn: String { localized("usage.reset_in") }
        static var remaining: String { localized("usage.remaining") }
        static var available: String { localized("usage.available") }
        static var loading: String { localized("usage.loading") }
        static var notConfigured: String { localized("usage.not_configured") }
        static var signInPrompt: String { localized("usage.sign_in_prompt") }
        static var goToSettings: String { localized("usage.go_to_settings") }
        static var resetTime: String { localized("usage.reset_time") }
        static var used: String { localized("usage.used") }
        static var fiveHourLimit: String { localized("usage.five_hour_limit") }
        static var sevenDayLimit: String { localized("usage.seven_day_limit") }
        static var fiveHourLimitShort: String { localized("usage.five_hour_limit_short") }
        static var sevenDayLimitShort: String { localized("usage.seven_day_limit_short") }
        static var resetDate: String { localized("usage.reset_date") }
        static var refresh: String { localized("usage.refresh") }
        static var refreshCooldown: String { localized("usage.refresh_cooldown") }
        static var runDiagnostic: String { localized("usage.run_diagnostic") }
        static var codexTitle: String { localized("usage.codex_title") }
        static var codexRelogin: String { localized("usage.codex_relogin") }
        /// Note under the bars when a refresh failed and cached numbers are still shown
        static func staleNotice(_ time: String) -> String {
            String(format: localized("usage.stale_notice"), time)
        }
        static var staleNoticeUnknown: String { localized("usage.stale_notice_unknown") }
    }
    
    // MARK: - Settings Tabs
    enum SettingsTab {
        static var general: String { localized("settings.tab.general") }
        static var auth: String { localized("settings.tab.auth") }
        static var history: String { localized("settings.tab.history") }
        static var about: String { localized("settings.tab.about") }
    }

    // MARK: - History
    enum History {
        static var title: String { localized("history.title") }
        static var subtitle: String { localized("history.subtitle") }
        static var usageOverview: String { localized("history.usage_overview") }
        static var sessionUsage: String { localized("history.session_usage") }
        static var weeklyUsage: String { localized("history.weekly_usage") }
        static var apiBilling: String { localized("history.api_billing") }
        static var noData: String { localized("history.no_data") }
        static var now: String { localized("history.now") }
        static var range5h: String { localized("history.range.5h") }
        static var range24h: String { localized("history.range.24h") }
        static var range7d: String { localized("history.range.7d") }
        static var range30d: String { localized("history.range.30d") }
        /// "%1$@ to %2$@", the visible window's start and end
        static var rangeFormat: String { localized("history.range_format") }
    }
    
    // MARK: - Settings General
    enum SettingsGeneral {
        static var launchSection: String { localized("settings.general.launch_section") }
        static var launchAtLogin: String { localized("settings.general.launch_at_login") }
        static var launchHint: String { localized("settings.general.launch_hint") }
        static var displaySection: String { localized("settings.general.display_section") }
        static var menubarIcon: String { localized("settings.general.menubar_icon") }
        static var menubarHint: String { localized("settings.general.menubar_hint") }
        static var menubarTheme: String { localized("settings.general.menubar_theme") }
        static var displayContent: String { localized("settings.general.display_content") }
        static var monochromeNoIconHint: String { localized("settings.general.monochrome_no_icon_hint") }
        static var refreshSection: String { localized("settings.general.refresh_section") }
        static var refreshMode: String { localized("settings.general.refresh_mode") }
        static var refreshInterval: String { localized("settings.general.refresh_interval") }
        static var refreshHintSmart: String { localized("settings.general.refresh_hint_smart") }
        static var refreshHintFixed: String { localized("settings.general.refresh_hint_fixed") }
        static var languageSection: String { localized("settings.general.language_section") }
        static var interfaceLanguage: String { localized("settings.general.interface_language") }
        static var languageHint: String { localized("settings.general.language_hint") }
        static var resetButton: String { localized("settings.general.reset_button") }
    }
    
    // MARK: - Settings Authentication
    enum SettingsAuth {
        static var howToTitle: String { localized("settings.auth.how_to_title") }
        static var step1: String { localized("settings.auth.step1") }
        static var step2: String { localized("settings.auth.step2") }
        static var step3: String { localized("settings.auth.step3") }
        static var step4: String { localized("settings.auth.step4") }
        static var step5: String { localized("settings.auth.step5") }
        static var step6: String { localized("settings.auth.step6") }
        static var openBrowser: String { localized("settings.auth.open_browser") }
        static var sessionKeyLabel: String { localized("settings.auth.session_key_label") }
        static var sessionKeyPlaceholder: String { localized("settings.auth.session_key_placeholder") }
        static var sessionKeyHint: String { localized("settings.auth.session_key_hint") }
        static var configured: String { localized("settings.auth.configured") }
        static var notConfigured: String { localized("settings.auth.not_configured") }
        static var credentialsTitle: String { localized("settings.auth.credentials_title") }
        static var readyToUse: String { localized("settings.auth.ready_to_use") }
        static var needCredentials: String { localized("settings.auth.need_credentials") }
        static var showPassword: String { localized("settings.auth.show_password") }
        static var hidePassword: String { localized("settings.auth.hide_password") }
        static var manualInputClaudeOnlyHelp: String { localized("settings.auth.manual_input_claude_only_help") }
    }
    
    // MARK: - Settings About
    enum SettingsAbout {
        static func version(_ version: String) -> String {
            String(format: localized("settings.about.version"), version)
        }
        static var description: String { localized("settings.about.description") }
        static var developer: String { localized("settings.about.developer") }
        static var license: String { localized("settings.about.license") }
        static var licenseValue: String { localized("settings.about.license_value") }
        static var github: String { localized("settings.about.github") }
        static var coffee: String { localized("settings.about.coffee") }
        static var reportIssue: String { localized("settings.about.report_issue") }
        static var githubSponsor: String { localized("settings.about.github_sponsor") }
        static var copyright: String { localized("settings.about.copyright") }
    }
    
    // MARK: - Welcome View
    enum Welcome {
        static var title: String { localized("welcome.title") }
        static var subtitle: String { localized("welcome.subtitle") }
        static var tagline: String { localized("welcome.tagline") }
        static var signInNote: String { localized("welcome.sign_in_note") }
        static var setupButton: String { localized("welcome.setup_button") }
        static var laterButton: String { localized("welcome.later_button") }

        // v2.0.0 Welcome Flow
        static var credentialsTitle: String { localized("welcome_credentials_title") }
        static var credentialsSubtitle: String { localized("welcome_credentials_subtitle") }
        static var displayTitle: String { localized("welcome.display_title") }
        static var displaySubtitle: String { localized("welcome.display_subtitle") }
        static var preview: String { localized("welcome.preview") }
        static var back: String { localized("welcome.back") }
        static var continue_: String { localized("welcome.continue") }
        static var skip: String { localized("welcome.skip") }
        static var finish: String { localized("welcome.finish") }
        static var authenticationSetup: String { localized("welcome.authentication_setup") }
        static var sessionKey: String { localized("welcome.session_key") }
        static var manualSessionKey: String { localized("welcome.manual_session_key") }
        static var sessionKeyPlaceholder: String { localized("welcome.session_key_placeholder") }
        static var sessionKeyHint: String { localized("welcome.session_key_hint") }
        static var validFormat: String { localized("welcome.valid_format") }
        static var howToGetSessionKey: String { localized("welcome.how_to_get_session_key") }
        static var invalidFormat: String { localized("welcome.invalid_format") }
        static var selectLimits: String { localized("welcome.select_limits") }
        static var smartModeRecommended: String { localized("welcome.smart_mode_recommended") }
        static var customSelection: String { localized("welcome.custom_selection") }
        static var configuring: String { localized("welcome.configuring") }
        static var fetchOrgIdFailed: String { localized("welcome.fetch_org_id_failed") }
        static var menubarIconNotVisible: String { localized("welcome.menubar_icon_not_visible") }
        static var multiAccountHint: String { localized("welcome.multi_account_hint") }
    }
    
    // MARK: - Update
    enum Update {
        /// Shared "OK" button, reused by the diagnostics and settings UI
        static var okButton: String { localized("update.ok_button") }
        // Update hints: menu bar badge / rainbow text / popover banner
        enum Notification {
            static var available: String { localized("update.notification.available") }
            static var badgeMenu: String { localized("update.notification.badge_menu") }
            static var badgeShort: String { localized("update.notification.badge_short") }
        }
    }
    
    // MARK: - Icon Display Mode
    enum Display {
        static var percentageOnly: String { localized("display.percentage_only") }
        static var iconOnly: String { localized("display.icon_only") }
        static var both: String { localized("display.both") }
        static var none: String { localized("display.none") }
        static var showIcon: String { localized("display.show_icon") }
        static var showPercentage: String { localized("display.show_percentage") }
        static var showRemaining: String { localized("display.show_remaining") }
        static var showRemainingDesc: String { localized("display.show_remaining_desc") }
        static var paceAwareColors: String { localized("display.pace_aware_colors") }
        static var paceAwareColorsDesc: String { localized("display.pace_aware_colors_desc") }
        static var showTimeMarker: String { localized("display.show_time_marker") }
        static var showTimeMarkerDesc: String { localized("display.show_time_marker_desc") }
        // The three mutually exclusive bar / icon colouring modes, one picker
        static var colorMode: String { localized("display.color_mode") }
        static var colorModeType: String { localized("display.color_mode_type") }
        static var colorModeUsage: String { localized("display.color_mode_usage") }
        static var colorModeMonochrome: String { localized("display.color_mode_monochrome") }
        static var colorModeTypeDesc: String { localized("display.color_mode_type_desc") }
        static var colorModeUsageDesc: String { localized("display.color_mode_usage_desc") }
        static var colorModeMonochromeDesc: String { localized("display.color_mode_monochrome_desc") }
    }
    
    // MARK: - Icon Style Mode
    enum IconStyle {
        static var colorTranslucent: String { localized("icon_style.color_translucent") }
        static var colorWithBackground: String { localized("icon_style.color_with_background") }
        static var monochrome: String { localized("icon_style.monochrome") }
        static var colorTranslucentDesc: String { localized("icon_style.color_translucent_desc") }
        static var colorWithBackgroundDesc: String { localized("icon_style.color_with_background_desc") }
        static var monochromeDesc: String { localized("icon_style.monochrome_desc") }
        static var monochromeToggleHint: String { localized("icon_style.monochrome_toggle_hint") }
    }
    
    // MARK: - Refresh Interval
    enum Refresh {
        static var smartMode: String { localized("refresh.smart_mode") }
        static var fixedMode: String { localized("refresh.fixed_mode") }
        static var oneMinute: String { localized("refresh.1_minute") }
        static var threeMinutes: String { localized("refresh.3_minutes") }
        static var fiveMinutes: String { localized("refresh.5_minutes") }
        static var tenMinutes: String { localized("refresh.10_minutes") }
    }
    
    // MARK: - Language Names
    enum Language {
        static var english: String { localized("language.english") }
        static var japanese: String { localized("language.japanese") }
        static var chinese: String { localized("language.chinese") }
        static var chineseTraditional: String { localized("language.chinese_traditional") }
        static var korean: String { localized("language.korean") }
        static var french: String { localized("language.french") }
        static var german: String { localized("language.german") }
    }
    
    // MARK: - Window Titles
    enum Window {
        static var settingsTitle: String { localized("window.settings_title") }
        static var welcomeTitle: String { localized("window.welcome_title") }
        static var loginTitle: String { localized("window.login_title") }
    }

    // MARK: - Limit Types
    enum Limit {
        static var fiveHour: String { localized("five_hour_limit") }
        static var sevenDay: String { localized("seven_day_limit") }
        static var opusWeekly: String { localized("opus_weekly_limit") }
        static var sonnetWeekly: String { localized("sonnet_weekly_limit") }
        static var extraUsage: String { localized("extra_usage") }
        static var codexPrimary: String { localized("codex_primary_limit") }
        static var codexSecondary: String { localized("codex_secondary_limit") }
        static var codexExtraUsage: String { localized("codex_extra_usage") }
    }

    // MARK: - Detail Rows
    enum DetailRow {
        static var fiveHour: String { localized("detail_row.five_hour_limit") }
        static var sevenDay: String { localized("detail_row.seven_day_limit") }
        static var opusWeekly: String { localized("detail_row.opus_weekly_limit") }
        static var sonnetWeekly: String { localized("detail_row.sonnet_weekly_limit") }

        /// Weekly limit scoped to one model, e.g. "Weekly Fable".
        ///
        /// The API names the model live, so the label is composed rather than hardcoded.
        /// `detail_row.opus_weekly_limit` is only the fallback when no name arrives.
        static func weeklyModel(_ modelName: String) -> String {
            return String(format: localized("detail_row.weekly_model"), modelName)
        }
        static var extraUsage: String { localized("detail_row.extra_usage") }
        static var today: String { localized("usage_data.detail_today") }

        static func creditsBalance(_ balance: Double) -> String {
            return String(format: localized("extra_usage.detail_credits_balance"), displayCredits(balance))
        }

        static func creditsRemaining(_ balance: Double) -> String {
            return String(format: localized("extra_usage.detail_credits_remaining"), displayCredits(balance))
        }

        private static func displayCredits(_ balance: Double) -> Int {
            max(0, Int(balance.rounded(.down)))
        }
    }

    // MARK: - Usage Data Formatting
    enum UsageData {
        static var notStartedReset: String { localized("usage_data.not_started_reset") }
        static var resettingSoon: String { localized("usage_data.resetting_soon") }
        static func resetsInHours(_ hours: Int, _ minutes: Int) -> String {
            String(format: localized("usage_data.resets_in_hours"), hours, minutes)
        }
        static func resetsInMinutes(_ minutes: Int) -> String {
            String(format: localized("usage_data.resets_in_minutes"), minutes)
        }
        static func resetsInDays(_ days: Int, _ hours: Int) -> String {
            String(format: localized("usage_data.resets_in_days"), days, hours)
        }
        static var unknown: String { localized("usage_data.unknown") }
        static var today: String { localized("usage_data.today") }
        static var tomorrow: String { localized("usage_data.tomorrow") }

        // Compact remaining formats
        static var compactResettingSoon: String { localized("usage_data.compact_resetting_soon") }
        static func compactRemainingMinutes(_ minutes: Int) -> String {
            String(format: localized("usage_data.compact_remaining_minutes"), minutes)
        }
        static func compactRemainingHours(_ hours: Int, _ minutes: Int) -> String {
            String(format: localized("usage_data.compact_remaining_hours"), hours, minutes)
        }
        static func compactRemainingDays(_ days: Int, _ hours: Int) -> String {
            String(format: localized("usage_data.compact_remaining_days"), days, hours)
        }
        /// Days only, for a countdown over a day: once days are on the clock the hours are noise
        static func compactRemainingHoursOnly(_ hours: Int) -> String {
            String(format: localized("usage_data.compact_remaining_hours_only"), hours)
        }
        static func compactRemainingDaysOnly(_ days: Int) -> String {
            String(format: localized("usage_data.compact_remaining_days_only"), days)
        }
        static func compactRemainingDaysWithMinutes(_ days: Int, _ hours: Int, _ minutes: Int) -> String {
            String(format: localized("usage_data.compact_remaining_days_with_minutes"), days, hours, minutes)
        }
    }
    
    // MARK: - Error Messages
    enum Error {
        static var invalidUrl: String { localized("error.invalid_url") }
        static var noData: String { localized("error.no_data") }
        static var sessionExpired: String { localized("error.session_expired") }
        static var cloudflareBlocked: String { localized("error.cloudflare_blocked") }
        static var noCredentials: String { localized("error.no_credentials") }
        static var networkFailed: String { localized("error.network_failed") }
        static var decodingFailed: String { localized("error.decoding_failed") }
        static var noOrganizationsFound: String { localized("error.no_organizations_found") }
        static var unauthorized: String { localized("error.unauthorized") }
        static var rateLimited: String { localized("error.rate_limited") }
    }

    // MARK: - Diagnostics
    enum Diagnostic {
        static var sectionTitle: String { localized("diagnostic.section_title") }
        static var sectionDescription: String { localized("diagnostic.section_description") }
        static var testButton: String { localized("diagnostic.test_button") }
        static var viewDetailsButton: String { localized("diagnostic.view_details_button") }
        static var exportButton: String { localized("diagnostic.export_button") }
        static var testingConnection: String { localized("diagnostic.testing_connection") }
        static var testCompleted: String { localized("diagnostic.test_completed") }
        static var testSuccess: String { localized("diagnostic.test_success") }
        static var testFailed: String { localized("diagnostic.test_failed") }
        static var resultSuccess: String { localized("diagnostic.result_success") }
        static var resultFailed: String { localized("diagnostic.result_failed") }
        static var httpStatus: String { localized("diagnostic.http_status") }
        static var responseTime: String { localized("diagnostic.response_time") }
        static var responseType: String { localized("diagnostic.response_type") }
        static var cloudflareDetected: String { localized("diagnostic.cloudflare_detected") }
        static var diagnosis: String { localized("diagnostic.diagnosis") }
        static var suggestions: String { localized("diagnostic.suggestions") }
        static var privacyNotice: String { localized("diagnostic.privacy_notice") }
        static var detailedReportTitle: String { localized("diagnostic.detailed_report_title") }
        static var noReportAvailable: String { localized("diagnostic.no_report_available") }
        static var copyToClipboard: String { localized("diagnostic.copy_to_clipboard") }
        static var exportTitle: String { localized("diagnostic.export_title") }
        static var exportMessage: String { localized("diagnostic.export_message") }
        static var exportSuccessTitle: String { localized("diagnostic.export_success_title") }
        static var exportSuccessMessage: String { localized("diagnostic.export_success_message") }
        static var exportErrorTitle: String { localized("diagnostic.export_error_title") }

        // Diagnosis messages
        static var diagnosisSuccess: String { localized("diagnostic.diagnosis_success") }
        static var diagnosisCloudflare: String { localized("diagnostic.diagnosis_cloudflare") }
        static var diagnosisDecoding: String { localized("diagnostic.diagnosis_decoding") }
        static var diagnosisNetwork: String { localized("diagnostic.diagnosis_network") }
        static var diagnosisNoCredentials: String { localized("diagnostic.diagnosis_no_credentials") }
        static var diagnosisInvalidUrl: String { localized("diagnostic.diagnosis_invalid_url") }
        static var diagnosisUnknown: String { localized("diagnostic.diagnosis_unknown") }

        // Suggestion messages
        static var suggestionSuccess: String { localized("diagnostic.suggestion_success") }
        static var suggestionVisitBrowser: String { localized("diagnostic.suggestion_visit_browser") }
        static var suggestionWaitAndRetry: String { localized("diagnostic.suggestion_wait_and_retry") }
        static var suggestionCheckVPN: String { localized("diagnostic.suggestion_check_vpn") }
        static var suggestionUseSmartMode: String { localized("diagnostic.suggestion_use_smart_mode") }
        static var suggestionVerifyCredentials: String { localized("diagnostic.suggestion_verify_credentials") }
        static var suggestionUpdateSessionKey: String { localized("diagnostic.suggestion_update_session_key") }
        static var suggestionCheckBrowser: String { localized("diagnostic.suggestion_check_browser") }
        static var suggestionCheckInternet: String { localized("diagnostic.suggestion_check_internet") }
        static var suggestionCheckFirewall: String { localized("diagnostic.suggestion_check_firewall") }
        static var suggestionRetryLater: String { localized("diagnostic.suggestion_retry_later") }
        static var suggestionConfigureAuth: String { localized("diagnostic.suggestion_configure_auth") }
        static var suggestionCheckOrgId: String { localized("diagnostic.suggestion_check_org_id") }
        static var suggestionExportAndShare: String { localized("diagnostic.suggestion_export_and_share") }
        static var suggestionContactSupport: String { localized("diagnostic.suggestion_contact_support") }

        // Log folder access
        static var openLogFolder: String { localized("diagnostic.open_log_folder") }
    }

    // MARK: - Limit Types (v2.0.0)
    enum LimitTypes {
        static var fiveHour: String { localized("five_hour_limit") }
        static var sevenDay: String { localized("seven_day_limit") }
        static var opusWeekly: String { localized("opus_weekly_limit") }
        static var sonnetWeekly: String { localized("sonnet_weekly_limit") }
        static var extraUsage: String { localized("extra_usage") }
        static var codexPrimary: String { localized("codex_primary_limit") }
        static var codexSecondary: String { localized("codex_secondary_limit") }
        static var codexExtraUsage: String { localized("codex_extra_usage") }
    }

    // MARK: - Display Options (v2.0.0)
    enum DisplayOptions {
        static var title: String { localized("display_options") }
        static var smartDisplay: String { localized("smart_display") }
        static var smartDisplayDescription: String { localized("smart_display_description") }
        static var customDisplay: String { localized("custom_display") }
        static var customDisplayDescription: String { localized("custom_display_description") }
        static var displayModeLabel: String { localized("display_mode_label") }
        static var selectLimitTypes: String { localized("select_limit_types") }
        static var circularIconConstraint: String { localized("circular_icon_constraint") }
        static var coloredThemeUnavailable: String { localized("colored_theme_unavailable") }
        static var menuBarOnlyToggle: String { localized("custom_display.menu_bar_only_toggle") }
        static var menuBarOnlyDescription: String { localized("custom_display.menu_bar_only_description") }
    }

    // MARK: - Launch at Login
    enum LaunchAtLogin {
        static var statusEnabled: String { localized("launch.status.enabled") }
        static var statusDisabled: String { localized("launch.status.disabled") }
        static var statusRequiresApproval: String { localized("launch.status.requires_approval") }
        static var statusNotFound: String { localized("launch.status.not_found") }
        static var errorTitle: String { localized("launch.error.title") }
        static var errorEnable: String { localized("launch.error.enable") }
        static var errorDisable: String { localized("launch.error.disable") }
    }

    // MARK: - Extra Usage
    enum ExtraUsage {
        static var notEnabled: String { localized("extra_usage.not_enabled") }
        static var unlimited: String { localized("extra_usage.unlimited") }
        static var limitReached: String { localized("extra_usage.limit_reached") }
        static func usageAmount(_ used: Double, _ limit: Double, symbol: String = "$") -> String {
            String(format: localized("extra_usage.usage_amount"), symbol, used, symbol, limit)
        }
        static func remainingAmount(_ remaining: Double, symbol: String = "$") -> String {
            String(format: localized("extra_usage.remaining_amount"), symbol, remaining)
        }
        static func creditsBalance(_ balance: Double) -> String {
            return String(format: localized("extra_usage.credits_balance"), displayCredits(balance))
        }
        static func creditsRemaining(_ balance: Double) -> String {
            return String(format: localized("extra_usage.credits_remaining"), displayCredits(balance))
        }

        private static func displayCredits(_ balance: Double) -> Int {
            max(0, Int(balance.rounded(.down)))
        }
    }

    // MARK: - Loading Animation
    enum LoadingAnimation {
        static var rainbow: String { localized("loading_animation.rainbow") }
        static var dashed: String { localized("loading_animation.dashed") }
        static var pulse: String { localized("loading_animation.pulse") }
        static func current(_ name: String) -> String {
            String(format: localized("loading_animation.current"), name)
        }
    }

    // MARK: - Time Format
    enum TimeFormat {
        static var system: String { localized("time_format.system") }
        static var twelveHour: String { localized("time_format.twelve_hour") }
        static var twentyFourHour: String { localized("time_format.twenty_four_hour") }
    }

    // MARK: - Appearance
    enum Appearance {
        static var system: String { localized("appearance.system") }
        static var light: String { localized("appearance.light") }
        static var dark: String { localized("appearance.dark") }
    }

    // MARK: - Settings General (Appearance)
    enum SettingsGeneralAppearance {
        static var section: String { localized("settings.general.appearance_section") }
        static var hint: String { localized("settings.general.appearance_hint") }
    }

    // MARK: - Web Login
    enum WebLogin {
        static var windowTitle: String { localized("weblogin.window_title") }
        static var codexWindowTitle: String { localized("weblogin.codex_window_title") }
        static var browserLogin: String { localized("weblogin.browser_login") }
        static var browserLoginRecommended: String { localized("weblogin.browser_login_recommended") }
        static var manualInput: String { localized("weblogin.manual_input") }
        static var orManualInput: String { localized("weblogin.or_manual_input") }
        static var loading: String { localized("weblogin.loading") }
        static var waitingForLogin: String { localized("weblogin.waiting_for_login") }
        static var codexWaitingForLogin: String { localized("weblogin.codex_waiting_for_login") }
        static var validating: String { localized("weblogin.validating") }
        static func success(_ name: String) -> String {
            String(format: localized("weblogin.success"), name)
        }
        static var cloudflareBlocked: String { localized("weblogin.cloudflare_blocked") }
        static var privacyNotice: String { localized("weblogin.privacy_notice") }

        // MARK: Claude OAuth login (system browser)
        static var claudeOAuthPortBusy: String { localized("weblogin.claude_oauth_port_busy") }
        static var claudeOAuthManualHint: String { localized("weblogin.claude_oauth_manual_hint") }
        static var claudeOAuthManualPrompt: String { localized("weblogin.claude_oauth_manual_prompt") }
        static var claudeOAuthManualSubmit: String { localized("weblogin.claude_oauth_manual_submit") }
        static var claudeOAuthManualInvalid: String { localized("weblogin.claude_oauth_manual_invalid") }

        // MARK: Codex OAuth login (system browser)
        static var codexOAuthPreparing: String { localized("weblogin.codex_oauth_preparing") }
        static var codexOAuthWaitingBrowser: String { localized("weblogin.codex_oauth_waiting_browser") }
        static var codexOAuthWaitingHint: String { localized("weblogin.codex_oauth_waiting_hint") }
        static var codexOAuthExchanging: String { localized("weblogin.codex_oauth_exchanging") }
        static var codexOAuthFailed: String { localized("weblogin.codex_oauth_failed") }
        static var codexOAuthTimeout: String { localized("weblogin.codex_oauth_timeout") }
        static var codexOAuthPortBusy: String { localized("weblogin.codex_oauth_port_busy") }
        static var codexOAuthReopenBrowser: String { localized("weblogin.codex_oauth_reopen_browser") }
        static var codexOAuthRetry: String { localized("weblogin.codex_oauth_retry") }
    }

    // MARK: - Settings Notification
    enum SettingsNotification {
        static var section: String { localized("notification.section") }
        static var hint: String { localized("notification.hint") }
        static var enable: String { localized("notification.enable") }
        static var description: String { localized("notification.description") }
    }

    // MARK: - Usage Notification
    enum UsageNotification {
        static var warningTitle: String { localized("notification.warning_title") }
        static func warningBody(_ type: String, _ percentage: Int) -> String {
            String(format: localized("notification.warning_body"), type, percentage)
        }
        static var resetTitle: String { localized("notification.reset_title") }
        static func resetBody(_ type: String) -> String {
            String(format: localized("notification.reset_body"), type)
        }
        static var codexSessionExpiredTitle: String { localized("notification.codex_session_expired_title") }
        static var codexSessionExpiredBody: String { localized("notification.codex_session_expired_body") }
    }

    // MARK: - Settings General (Time Format)
    enum SettingsGeneralTimeFormat {
        static var section: String { localized("settings.general.time_format_section") }
        static var hint: String { localized("settings.general.time_format_hint") }
        static var preview: String { localized("settings.general.time_format_preview") }
    }

    // MARK: - Helper Methods
    
    /// Localized string helpers
    /// Returns the localized string for the language the user chose
    /// - Parameter key: the localized string key
    /// - Returns: the localized string in the selected language
    // MARK: - API Console
    enum APIConsole {
        static var paneTitle: String { localized("api_console.pane_title") }
        static var paneSubtitle: String { localized("api_console.pane_subtitle") }
        static var configuration: String { localized("api_console.configuration") }
        static var stepEnterKey: String { localized("api_console.step_enter_key") }
        static var stepSelectOrg: String { localized("api_console.step_select_org") }
        static var stepConfirm: String { localized("api_console.step_confirm") }
        static var signInHint: String { localized("api_console.sign_in_hint") }
        static var openConsole: String { localized("api_console.open_console") }
        static var or: String { localized("api_console.or") }
        static var manualKeyTitle: String { localized("api_console.manual_key_title") }
        static var manualKeyHint: String { localized("api_console.manual_key_hint") }
        static var fetchOrganizations: String { localized("api_console.fetch_organizations") }
        static var selectOrgHint: String { localized("api_console.select_org_hint") }
        static var organization: String { localized("api_console.organization") }
        static var back: String { localized("api_console.back") }
        static var connect: String { localized("api_console.connect") }
        static var currentPeriod: String { localized("api_console.current_period") }
        static var currentPeriodSubtitle: String { localized("api_console.current_period_subtitle") }
        static var currentSpend: String { localized("api_console.current_spend") }
        static var prepaidCredits: String { localized("api_console.prepaid_credits") }
        static var errorInvalidKey: String { localized("api_console.error_invalid_key") }
        static var errorNoOrganizations: String { localized("api_console.error_no_organizations") }
        static var aboutTitle: String { localized("api_console.about_title") }
        static var aboutPoint1: String { localized("api_console.about_point_1") }
        static var aboutPoint2: String { localized("api_console.about_point_2") }
        static var aboutPoint3: String { localized("api_console.about_point_3") }
    }

    // MARK: - Claude.ai Pane
    enum ClaudeAIPane {
        static var signIn: String { localized("claude_ai_pane.sign_in") }
        static var signInHint: String { localized("claude_ai_pane.sign_in_hint") }
        static var manualKeyHint: String { localized("claude_ai_pane.manual_key_hint") }
        static var testConnection: String { localized("claude_ai_pane.test_connection") }
        static var errorInvalidKey: String { localized("claude_ai_pane.error_invalid_key") }
        static var accountsSubtitle: String { localized("claude_ai_pane.accounts_subtitle") }
    }

    // MARK: - Credentials Navigation
    enum CredentialsNav {
        static var sectionCredentials: String { localized("credentials_nav.section_credentials") }
        static var sectionTools: String { localized("credentials_nav.section_tools") }
        static var claudeAI: String { localized("credentials_nav.claude_ai") }
        static var codex: String { localized("credentials_nav.codex") }
        static var diagnostics: String { localized("credentials_nav.diagnostics") }
        static var connected: String { localized("credentials_nav.connected") }
        static var notConnected: String { localized("credentials_nav.not_connected") }
        static var cliPaneTitle: String { localized("credentials_nav.cli_pane_title") }
        static var cliPaneSubtitle: String { localized("credentials_nav.cli_pane_subtitle") }
        static var claudePaneTitle: String { localized("credentials_nav.claude_pane_title") }
        static var claudePaneSubtitle: String { localized("credentials_nav.claude_pane_subtitle") }
        static var codexPaneTitle: String { localized("credentials_nav.codex_pane_title") }
        static var codexPaneSubtitle: String { localized("credentials_nav.codex_pane_subtitle") }
        static var diagnosticsSubtitle: String { localized("credentials_nav.diagnostics_subtitle") }
        static var apiConsole: String { localized("credentials_nav.api_console") }
    }

    // MARK: - CLI Account Sync
    enum CLISync {
        static var title: String { localized("cli_sync.title") }
        static var hint: String { localized("cli_sync.hint") }
        static var statusSynced: String { localized("cli_sync.status_synced") }
        static var statusSyncing: String { localized("cli_sync.status_syncing") }
        static var statusAvailable: String { localized("cli_sync.status_available") }
        static var statusUnavailable: String { localized("cli_sync.status_unavailable") }
        static var statusAvailableDetail: String { localized("cli_sync.status_available_detail") }
        static var statusUnavailableDetail: String { localized("cli_sync.status_unavailable_detail") }
        static var statusFailed: String { localized("cli_sync.status_failed") }
        /// "Last synced 3m ago". The elapsed string comes from ClaudeCodeSyncService.timeSinceSync
        static func lastSynced(_ elapsed: String) -> String {
            String(format: localized("cli_sync.last_synced"), elapsed)
        }
        static var accessToken: String { localized("cli_sync.access_token") }
        static var subscription: String { localized("cli_sync.subscription") }
        static var scopes: String { localized("cli_sync.scopes") }
        static var resync: String { localized("cli_sync.resync") }
        static var remove: String { localized("cli_sync.remove") }
        static var syncNow: String { localized("cli_sync.sync_now") }
        static var refresh: String { localized("cli_sync.refresh") }
        static var advancedTitle: String { localized("cli_sync.advanced_title") }
        static var keychainEntry: String { localized("cli_sync.keychain_entry") }
        static var automatic: String { localized("cli_sync.automatic") }
        static var advancedHint: String { localized("cli_sync.advanced_hint") }
        static var advancedSubtitle: String { localized("cli_sync.advanced_subtitle") }
        static var errorNoCredentials: String { localized("cli_sync.error_no_credentials") }
        static var errorNoRefreshToken: String { localized("cli_sync.error_no_refresh_token") }
        static var defaultAccountName: String { localized("cli_sync.default_account_name") }
        static var accountDetails: String { localized("cli_sync.account_details") }
        static var accountDetailsSubtitle: String { localized("cli_sync.account_details_subtitle") }
        static var configuration: String { localized("cli_sync.configuration") }
        static var readyHint: String { localized("cli_sync.ready_hint") }
        static var notFoundHint: String { localized("cli_sync.not_found_hint") }
        static var aboutTitle: String { localized("cli_sync.about_title") }
        static var aboutPoint1: String { localized("cli_sync.about_point_1") }
        static var aboutPoint2: String { localized("cli_sync.about_point_2") }
        static var aboutPoint3: String { localized("cli_sync.about_point_3") }
    }

    private static func localized(_ key: String) -> String {
        // Read the language the user selected from UserSettings
        let language = UserSettings.shared.language.rawValue
        
        // Get the bundle for that language
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            // Fall back to the system default when that language is missing
            return NSLocalizedString(key, comment: "")
        }
        
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
