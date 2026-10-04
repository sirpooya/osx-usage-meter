//
//  WelcomeDocLinks.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-08-21.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

// MARK: - Welcome Doc Links

/// Build the anchor link into this repo's README for the current language.
/// It points at sirpooya/osx-usage-meter's own docs, no longer at upstream f-is-h/Usage4Claude.
/// Every language's anchor matches a section heading that really exists in the README, so renaming a heading means changing this too.
enum WelcomeDocLinks {
    private static let baseURL = "https://github.com/sirpooya/osx-usage-meter/blob/main"

    /// The "initial setup" section
    static func initialSetupURL(for language: AppLanguage) -> String {
        switch language {
        case .english:
            return "\(baseURL)/README.md#initial-setup"
        case .german:
            return "\(baseURL)/docs/README.de.md#erste-konfiguration"
        case .chinese:
            return "\(baseURL)/docs/README.zh-CN.md#首次配置"
        case .chineseTraditional:
            return "\(baseURL)/docs/README.zh-TW.md#首次設定"
        case .japanese:
            return "\(baseURL)/docs/README.ja.md#初期設定"
        case .korean:
            return "\(baseURL)/docs/README.ko.md#초기-설정"
        case .french:
            return "\(baseURL)/docs/README.fr.md#configuration-initiale"
        }
    }
}
