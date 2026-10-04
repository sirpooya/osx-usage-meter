# Usage Meter

[English](README.md) | [日本語](docs/README.ja.md) | [简体中文](docs/README.zh-CN.md) | [繁體中文](docs/README.zh-TW.md) | [한국어](docs/README.ko.md) | [Français](docs/README.fr.md) | [Deutsch](docs/README.de.md)

<div align="center">

<img src="docs/images/icon@2x.png" width="256" alt="icon">

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?style=flat-square)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange?style=flat-square)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-✓-green?style=flat-square)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-MIT-purple?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/sirpooya/osx-usage-meter?style=flat-square)](https://github.com/sirpooya/osx-usage-meter/releases)
[![Downloads (all assets, all releases)](https://img.shields.io/github/downloads/sirpooya/osx-usage-meter/total)](https://github.com/sirpooya/osx-usage-meter/releases)

**Track your Claude (and Codex) subscription quota, beautifully, in your menu bar.**

✨ **Monitors all Claude platforms: Web • Claude Code • Desktop • Mobile App • Cowork** ✨

[Features](#-features) • [Installation](#-installation) • [User Guide](#-user-guide) • [FAQ](#-faq) • [Support](#-support)

</div>

---

## ✨ Features

### 🎯 Core Features

- **📊 Real-time Monitoring** - Display Claude subscription (Free/Pro/Team/Max) usage quota in menu bar, with optional Codex monitoring
- **🔑 Authoritative Data** - Talks to Claude's own `/api/oauth/usage` endpoint, the same source Claude Code itself uses, so numbers are accurate across every device, not scraped from a cookie
- **⚡️ Zero-Setup CLI Sync** - Already signed in to Claude Code? The app signs itself in from its Keychain entry automatically, no pasted session key and no browser login needed
- **📈 Usage History** - Session and weekly usage charted over 5h / 24h / 7d / 30d windows, plus API billing spend, so trends are visible instead of a single live number
- **🎯 Multi-Limit Support** - Claude supports 5-hour, 7-day, and Extra Usage limits plus weekly per-model usage for any number of models (e.g. Opus, Sonnet, Fable), while Codex supports 5-hour, 7-day, and Extra Usage/credits
- **🎨 Smart Display Mode** - Auto-detect and display all limit types with available data
- **⚙️ Custom Display** - Manually select which limit types to display, supports any combination
- **🎨 Color By: Limit / Usage / Monochrome** - Color bars and menu bar icons by which limit they are, by how fast usage is pacing toward the reset (burn-rate aware), or drop to one brand color entirely
- **⏱️ Time Marker** - An optional tick on each bar showing how much of the window has elapsed, so usage can be read against time, not just against the cap
- **🔔 Usage Notifications** - Warning notification at 90% usage, reset notification when quota resets
- **👥 Multi-Account Management** - Support multiple Claude accounts / multiple organizations per account, plus independent Codex account management and quick switching
- **🧩 Codex Support** - Optional Codex quota monitoring; use Codex alone or show it alongside Claude in a dual-column view (add a Codex account in settings to enable)
- **🕐 Time Format** - Follows the system 12/24-hour format
- **⏰ Precise Timing** - Quota reset time displayed with minute precision, or as remaining time (like the macOS battery indicator)
- **🔄 Smart Refresh System** - Intelligent adaptive refresh or fixed intervals (1/3/5/10 min)
- **⚡ Manual Refresh** - Click refresh button to update data instantly (10-second debounce protection)
- **💻 Native Experience** - Pure native macOS app, lightweight and elegant, no Dock icon

### 🌐 Cross-Platform Support

Works seamlessly with all Claude products:
- 🌐 **Claude.ai** (Web interface)
- 💻 **Claude Code** (CLI tool for developers)
- 🖥️ **Desktop App** (macOS/Windows)
- 📱 **Mobile App** (iOS/Android)
- 🤝 **Cowork** (AI Agent)

All platforms share the same usage quota, monitored in one place!

### 🧩 Codex Support

- Monitor Codex alone or together with Claude
- Supports Codex 5-hour, 7-day, and Extra Usage/credits information
- Add a Codex account by logging in to ChatGPT with the built-in browser
- Claude-only users need no extra setup; the existing experience stays unchanged until a Codex account is added

### 🔑 Authentication

- **CLI Account Sync (recommended)** - Already signed in with `claude` on this Mac? The app reads Claude Code's own Keychain entry and signs itself in automatically, no browser and no pasted key
- **Browser Login** - Sign in to your claude.ai account in the built-in browser
- **Manual Session Key** - Paste a session key directly, as a fallback
- **Codex** - Built-in browser login to ChatGPT (Codex has no manual key option)
- Credentials never leave the Keychain; the app never displays, logs, or copies a raw token

### 🎨 Personalization

- **🕓 Multiple Display Modes**
  - Percentage Only - Clean and intuitive, view at a glance
  - Icon Only - Subtle and elegant, detailed info on click
  - Icon + Percentage - Complete information, quick visual identification

- **🌍 Multilingual Support**
  - English
  - 日本語
  - 简体中文
  - 繁体中文
  - 한국어
  - Français (contributed by [@mtreize](https://github.com/mtreize))
  - Deutsch (contributed by [@schaitl](https://github.com/schaitl))
  - More languages coming soon... (Localization PRs are welcome!)

### 🔧 Convenient Features

- **⚙️ Visual Settings** - No code modification needed, GUI configuration for all options
- **🆕 Smart Update Alerts** - Menu bar badge and rainbow animation notify new versions
- **🚀 Launch at Login** - Optional automatic startup when system boots
- **⌨️ Keyboard Shortcuts** - Common operations support shortcuts (⌘R | ⌘, | ⌘⇧A | ⌘U | ⌘Q)
- **👋 Zero-Friction Onboarding** - One sign-in window; already logged into Claude Code and it can skip onboarding entirely
- **⚙️ Gear Menu** - Popover header gear opens Settings directly; account switching, updates, About and Quit live on the right-click menu bar menu
- **🔔 Usage Notifications** - Claude usage warning and reset notifications, configurable in settings

### 🔒 Security & Privacy

- 🏠 **Local Storage Only** - All data stored locally only, never collect or upload any personal information
- 🔐 **Keychain Protection** - Claude Session Key and Codex authentication token secured in Keychain, no plain text keys
- 📖 **Open Source Transparency** - Code fully public, anyone can audit
- 🚫 **No Telemetry** - No analytics, no accounts, no network calls except to `api.anthropic.com` and ChatGPT/Codex endpoints
- ⚠️ **App Sandbox is off, deliberately** - CLI Account Sync needs to read Claude Code's own Keychain entry, which the sandbox would block regardless of entitlements. This trades Mac App Store distribution for zero-setup login.

---

## 📸 Screenshots

### Menu Bar Display

- Claude and Codex menu bar icons and limit indicators are shown below
- Dual indicators through shape and color ensure easy identification even in monochrome themes

| Icon | 5-Hour | 7-Day | Extra | 7-Day Opus | 7-Day Sonnet | Monochrome (Adaptive) |
|:---:|:---:|:---:|:---:|:---:|:---:|-----|
| <img src="docs/images/bar.icon@2x.png" width="40" height="40" alt="icon"> | <img src="docs/images/bar.5h@2x.png" width="45" height="45" alt="5h ring"> | <img src="docs/images/bar.7d@2x.png" width="45" height="45" alt="7d ring"> | <img src="docs/images/bar.ex@2x.png" width="45" height="45" alt="extra ring"> | <img src="docs/images/bar.7do@2x.png" width="45" height="45" alt="7d opus ring"> | <img src="docs/images/bar.7ds@2x.png" width="45" height="45" alt="7d sonnet ring"> | <img src="docs/images/bar.mono.b@2x.png" width="auto" height="35" alt="mono black"></br> <img src="docs/images/bar.mono.w@2x.png" width="auto" height="35" alt="mono white"> |
| <img src="docs/images/bar.icon.codex@2x.png" width="40" height="40" alt="codex icon"> | <img src="docs/images/bar.5h.codex@2x.png" width="45" height="45" alt="codex 5h ring"> | <img src="docs/images/bar.7d.codex@2x.png" width="45" height="45" alt="codex 7d ring"> | <img src="docs/images/bar.ex.codex@2x.png" width="45" height="45" alt="codex extra ring"> | — | — | <img src="docs/images/bar.mono.b.codex@2x.png" width="auto" height="35" alt="codex mono black"></br> <img src="docs/images/bar.mono.w.codex@2x.png" width="auto" height="35" alt="codex mono white"> |

**Color Indicators**:

Claude current colors:

- **5-Hour Limit (incl. detail window)**: ![macOS Green](https://img.shields.io/badge/macOS_Green-34C759) → ![macOS Orange](https://img.shields.io/badge/macOS_Orange-FF9500) → ![macOS Red](https://img.shields.io/badge/macOS_Red-FF3B30)
- **7-Day Limit (incl. detail window)**: ![Light Purple](https://img.shields.io/badge/Light_Purple-C084FC) → ![Purple](https://img.shields.io/badge/Purple-B450F0) → ![Deep Purple](https://img.shields.io/badge/Deep_Purple-B41EA0)
- **Extra Usage**: ![Pink](https://img.shields.io/badge/Pink-FF9ECD) → ![Rose](https://img.shields.io/badge/Rose-EC4899) → ![Magenta](https://img.shields.io/badge/Magenta-D946EF)
- **7-Day Opus Limit**: ![Light Orange](https://img.shields.io/badge/Light_Orange-FFC864) → ![Amber](https://img.shields.io/badge/Amber-FBBF24) → ![Orange Red](https://img.shields.io/badge/Orange_Red-FF6432)
- **7-Day Sonnet Limit**: ![Light Blue](https://img.shields.io/badge/Light_Blue-64C8FF) → ![Blue](https://img.shields.io/badge/Blue-007AFF) → ![Indigo](https://img.shields.io/badge/Indigo-4F46E5)

Codex current colors:

- **Codex 5-Hour Limit**: ![Bright Teal](https://img.shields.io/badge/Bright_Teal-2DD4BF) → ![Deep Teal](https://img.shields.io/badge/Deep_Teal-0D9488) → ![Darkest Teal](https://img.shields.io/badge/Darkest_Teal-134E4A)
- **Codex 7-Day Limit**: ![Sky Blue](https://img.shields.io/badge/Sky_Blue-60A5FA) → ![Blue](https://img.shields.io/badge/Blue-2563EB) → ![Deep Blue](https://img.shields.io/badge/Deep_Blue-1E3A8A)
- **Codex Extra Usage / credits**: ![Gold](https://img.shields.io/badge/Gold-F59E0B) → ![Deep Gold](https://img.shields.io/badge/Deep_Gold-D97706) → ![Darkest Amber](https://img.shields.io/badge/Darkest_Amber-78350F)

### Detail Window

<table border="0">
<tr>
<td align="top" valign="top">
<img src="docs/images/detail.claude.en@2x.png" width="280" alt="Claude-only mode">
<br/>
<sub><i>Claude-only mode</i></sub>
</td>
<td align="center" valign="top">
<img src="docs/images/detail.codex.en@2x.png" width="280" alt="Codex-only mode">
<br/>
<sub><i>Codex-only mode</i></sub>
</td>
</tr>
<tr>
<td align="center" valign="top" colspan="2">
<img src="docs/images/detail.both.en@2x.png" width="560" alt="Claude and Codex mode">
<br/>
<sub><i>Claude + Codex mode</i></sub>
</td>
</tr>
<tr>
<td align="center" valign="top" colspan="2">
<img src="docs/images/detail@2x.gif" width="280" alt="Time Remaining Toggle Animation">
<br/>
<sub><i>Time Remaining Toggle Animation</i></sub>
</td>
</tr>
</table>

### Settings

**General** - Display options, color by (limit/usage/monochrome), time marker, remaining-time display, notification settings, refresh mode, language options, launch at login
**Account** - Claude/Codex credentials in a sidebar grouped by provider: Claude.ai, API Console, CLI Account (sync status, masked token, re-sync), Codex, and Diagnostics
**History** - Session and weekly usage charted over 5h / 24h / 7d / 30d, plus API billing spend
**About** - Version info and related links

### Welcome Screen

A single sign-in window. Claude Code users already logged in via `claude` are signed in automatically and never see this screen; everyone else gets one button for built-in browser login (auto-detects Organization ID and multiple organizations under the same account) or a manual Session Key fallback. Codex and display options are configured later in Settings, there is no separate setup wizard.

---

## 💾 Installation

> **No prebuilt DMG yet.** The current release ([v1.1.0](https://github.com/sirpooya/osx-usage-meter/releases/tag/v1.1.0)) is source only. Build from source below until a DMG is published.

### Build from Source

#### Requirements
- macOS 13.0 or later
- Xcode 15.0 or later
- Git

#### Build Steps

```bash
# Clone repository
git clone https://github.com/sirpooya/osx-usage-meter.git
cd osx-usage-meter

# Open in Xcode
open UsageMeter.xcodeproj

# Press Cmd + R to run in Xcode
```

Once a signed DMG is published, updates after the first install will be in-app: Sparkle checks for new versions automatically (and on demand via Settings gear → Check for Updates once re-enabled), downloads, verifies the EdDSA signature, and installs with one click.

---

## 📖 User Guide

### Initial Setup

1. **Launch App**
   If Claude Code is already signed in on this Mac (`claude` has a valid Keychain entry), the app syncs from it automatically and the welcome screen never appears.

2. **Configure Authentication** (only if CLI Sync didn't find anything)
   - **Browser Login (Recommended)** - Click the sign-in button and log in to your Claude account in the built-in browser
   - **Manual Session Key** - Paste a session key directly, as a fallback
   - **Codex Account (Optional)** - Open Settings → Account → Codex, click Browser Login, and sign in to ChatGPT; Codex does not support manual key input

### Daily Usage

- **Default Display** - Menu bar icon shows usage percentage
- **View Details** - Click the menu bar icon to view the popover; when only Claude/Codex is configured it shows a single column, and when both are configured it shows a dual-column view
- **Manual Refresh** - Click refresh in the popover or use ⌘R; in dual-column mode, Claude and Codex can also be refreshed separately
- **Switch Account** - Right-click the menu bar icon to select a Claude / Codex account
- **Open Settings** - Click the gear in the popover header, or ⌘,
- **Keyboard Shortcuts**
  - ⌘R - Manual refresh data
  - ⌘, - Open Settings
  - ⌘Q - Quit app
- **Update Alerts** - When a new version is available, the popover gear and menu bar menu show a badge

### Refresh Mode

**Smart Frequency (Recommended)**
- Automatically adjusts refresh rate based on usage patterns
- Active mode (1 min) - Fast refresh when actively using Claude or Codex
- Idle modes (3/5/10 min) - Progressively slower refresh when idle
- Significantly reduces API calls during idle periods (up to 10x)
- Instantly returns to 1-minute refresh when usage detected
- Automatically refreshes after system wake to avoid stale data

**Fixed Frequency**
- **1 minute** - Recommended for consistent monitoring
- **3 minutes** - Balanced monitoring
- **5 minutes** - Low frequency monitoring
- **10 minutes** - Minimal API calls

---

## ❓ FAQ

<details>
<summary><b>Q: What if the app shows "Session Expired"?</b></summary>

A: Claude Session Keys or Codex authentication tokens expire periodically (usually weeks to months), and you need to log in again:
1. Open Settings → Account
2. For Claude, use CLI Account Sync if `claude` is still logged in on this Mac, click "Browser Login" to sign in again, or manually re-obtain a Session Key
3. For Codex, click Codex "Browser Login" and log in to ChatGPT in the built-in browser
4. Done, monitoring will resume

</details>

<details>
<summary><b>Q: How to enable auto-launch on startup?</b></summary>

A: Two methods:

**Method 1: Using built-in option (Recommended)**
1. Open Settings → General
2. Check "Launch at Login" option

**Method 2: Via System Settings**
1. Open System Settings → General → Login Items
2. Click "+" to add Usage Meter

</details>

<details>
<summary><b>Q: How much system resources does it use?</b></summary>

A: Very lightweight:
- CPU Usage: < 0.1% (idle)
- Memory: ~20MB
- Network: Refreshes at the configured smart frequency; when both Claude and Codex are configured, each service is requested separately

</details>

<details>
<summary><b>Q: Which macOS versions are supported?</b></summary>

A: Requires macOS 13.0 (Ventura) or later. Supports both Intel and Apple Silicon (M1/M2/M3/M4/M5) chips.

</details>

<details>
<summary><b>Q: Why does it need Keychain permission?</b></summary>

A:
- Keychain is macOS's system-level password manager
- Claude Session Key and Codex authentication token are encrypted in Keychain
- Claude Organization ID is stored in local config (non-sensitive identifier)
- This is Apple's recommended secure storage method
- Only this app can access the information, other apps cannot view it

</details>

<details>
<summary><b>Q: Is my data safe? How is privacy protected?</b></summary>

**Completely safe!** 

**Data Storage:**
- All data stored **only** on your local Mac
- No collection, no tracking, no statistics of any information
- No network requests except Claude and Codex usage-related API calls
- No third-party services used

**Authentication Security:**
- Claude Session Key and Codex authentication token encrypted via macOS Keychain (system-level encryption)
- Keychain uses AES-256 encryption + hardware protection (T2 / Secure Enclave)
- Only this app can access your credentials, other apps cannot read them
- You can revoke access anytime via "Keychain Access" app

**Code Transparency:**
- 100% open source
- No obfuscation or hidden features
- Community can audit and verify

**Additional Protection:**
- App Sandbox is off, deliberately, so CLI Account Sync can read Claude Code's own Keychain entry (the sandbox would block that no matter what entitlements are granted)
- No access to your files, contacts, or other apps beyond that one Keychain entry
- Minimal permissions (only network + Keychain)

You can verify all of this by reviewing the source code on GitHub!

</details>

<details>
<summary><b>Q: Does it work with Claude Code / Desktop App / Mobile App?</b></summary>

A: **Yes, it works with all Claude platforms!**

Since all Claude products (Web, Claude Code, Desktop App, Mobile App, Cowork) share the same usage quota, Usage Meter monitors your combined usage across all platforms.

Whether you're:
- Coding in terminal with `claude code`
- Chatting on claude.ai
- Using the desktop app
- Using mobile apps
- Using Cowork agents

You'll see your real-time total usage in the menu bar. No platform-specific configuration needed!

</details>

<details>
<summary><b>Q: How do I enable Codex support? Can I use Codex only?</b></summary>

A: Yes. Open Settings → Account → Codex, click "Browser Login", and log in to ChatGPT in the built-in browser.

- Codex only: the menu bar and detail window show Codex usage
- Claude + Codex: the detail window shows both providers side by side
- Codex currently supports browser login only, not manual Session Key input

</details>

<details>
<summary><b>Q: Can't see the icon in menu bar?</b></summary>

A: macOS system or third-party software (like Bartender, Hidden Bar, etc.) may automatically hide menu bar icons.

**Solution:**
1. Hold **Command (⌘) key**
2. Drag icons in the menu bar with mouse
3. Drag Usage Meter icon to the visible area on the right side of menu bar
4. Release mouse

**Note:**
- macOS Sonoma (14.0+) automatically hides infrequently used icons to "Control Center"
- You can adjust menu bar icon display in "System Settings" → "Control Center"

</details>

<details>
<summary><b>Q: How to manage multiple accounts?</b></summary>

A: Usage Meter supports multiple Claude accounts, multiple organizations under the same Claude account, and independent Codex account management:
- **Add Account** - Add via CLI Account Sync, Claude browser login, Claude manual input, or Codex browser login in Settings → Account
- **Switch Account** - Right-click the menu bar icon, select the Claude / Codex account to switch to
- **Edit Alias** - Set easily recognizable aliases for each account
- **Delete Account** - Remove unwanted accounts from the Account settings pane

</details>

<details>
<summary><b>Q: How to enable usage notifications?</b></summary>

A: Toggle Claude usage notifications in Settings → General → Notifications:
- **Usage Warning** - System notification when Claude usage reaches 90%
- **Reset Notification** - Notification when Claude quota resets
- macOS notification permission required on first enable

</details>

---

## 🛠 Tech Stack

Built with modern macOS native technologies:

- **Language**: Swift 6
- **UI Framework**: SwiftUI + AppKit hybrid (`NSStatusItem` menu bar, SwiftUI popover and settings)
- **Charts**: Swift Charts (History tab)
- **Architecture**: MVVM
- **Networking**: URLSession, direct to `api.anthropic.com` (no cookie scraping)
- **Reactive**: Combine Framework
- **Updates**: Sparkle
- **Localization**: Built-in i18n support, 7 locales
- **Platform**: macOS 13.0+ deployment target

---

## 🗺 Roadmap

### ✅ Completed
- [x] Basic monitoring features
- [x] Menu bar real-time display
- [x] Authoritative OAuth usage endpoint (no cookie scraping)
- [x] Zero-setup CLI Account Sync from Claude Code's own Keychain entry
- [x] Bar-row popover, replacing the progress ring
- [x] Color By: Limit / Usage (pace-aware) / Monochrome
- [x] Time marker tick on bars and menu bar icons
- [x] Remaining-time display mode (like the macOS battery indicator)
- [x] Usage History tab (session, weekly, and API billing charts)
- [x] Real-time countdown
- [x] Multiple menu bar display modes
- [x] Visual settings interface, restyled sidebar for Account
- [x] Multilingual support (7 locales)
- [x] Zero-friction onboarding (skips entirely when CLI Sync succeeds)
- [x] Keychain authentication storage
- [x] Settings interface display optimization
- [x] Launch at login option
- [x] Keyboard shortcuts support
- [x] Manual refresh feature
- [x] Dual limit mode support (5-hour + 7-day)
- [x] Unified color scheme management
- [x] Multi-limit type support (5+ types, including per-model weekly)
- [x] Smart/custom display mode
- [x] Auto-retrieve Organization ID
- [x] Korean language support
- [x] Built-in browser auto-authentication
- [x] Automatic credential configuration
- [x] Usage notifications
- [x] Multi-account management
- [x] Settings interface dark mode adaptation
- [x] Codex usage monitoring support
- [x] Codex-only mode
- [x] Claude + Codex dual-column popover
- [x] Codex account management and browser login
- [x] French and German localization
- [x] Automatic refresh after system wake
- [x] Resilient refresh: transient errors never blank the popover, last good data is cached

### Mid-term Plans
1. **Feature Addition**
    - Ship a signed DMG and re-enable Sparkle auto-updates
    - More language localizations

### Long-term Vision
2. **Differentiators**
   - Burn-rate forecast ("weekly cap Thursday ~3pm at this pace")
   - Cost/token attribution per project, repo, and branch from local session logs

3. **More Display Methods**
   - Desktop widgets
   - Browser extension icon usage display

4. **Multi-platform Support**
   - iOS / iPadOS version
   - Apple Watch version
   - Windows version

---

## 🤝 Contributing

All contributions are welcome! Whether it's new features, bug fixes, or documentation improvements.

For detailed contribution guidelines, please see [CONTRIBUTING.md](CONTRIBUTING.md).

### How to Contribute

1. Fork this repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Contributors

Thanks to all who have contributed to this project!

<!-- ALL-CONTRIBUTORS-LIST:START -->
<!-- Contributor list will be auto-generated here -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

---

## 📝 Changelog

For detailed version history and updates, please see [CHANGELOG.md](CHANGELOG.md).

---

## 💖 Support

If this project helps you, please support in the following ways:

### ⭐ Star the Project
Giving a star is the biggest encouragement!

### ☕ Buy Me a Coffee

<!-- GitHub Sponsors -->
<a href="https://github.com/sponsors/f-is-h?frequency=one-time">
  <img src="https://img.shields.io/badge/GitHub-Sponsor-EA4AAA?style=for-the-badge&logo=github" alt="GitHub Sponsor">
</a>

<!-- Ko-fi -->
<a href="https://ko-fi.com/1attle">
  <img src="https://img.shields.io/badge/Ko--fi-Support-FF5E5B?style=for-the-badge&logo=ko-fi" alt="Ko-fi">
</a>

<!-- Buy Me A Coffee -->
<!-- <a href="https://buymeacoffee.com/fish_">
  <img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee">
</a> -->

### 📢 Share the Project
If you like this project, please share it with more people!

---

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details

```
MIT License

Copyright (c) 2026 Pooya Kamel
Copyright (c) 2025-2026 f-is-h (original Usage4Claude)

You are free to use, copy, modify, merge, publish, distribute, sublicense, 
and/or sell copies of the Software.
```

---

## 🙏 Acknowledgments

- Thanks to Claude/Codex - Most code written by AI
- Thanks to all contributors and users for their support
- Icon design inspired by Claude/Codex official branding

---

## 📞 Contact

- **Issues**: [Submit issues or suggestions](https://github.com/sirpooya/osx-usage-meter/issues)
- **GitHub**: [@f-is-h](https://github.com/f-is-h) (original Usage4Claude author)

---

## ⚖️ Disclaimer

This project is an independent third-party tool with no official affiliation with Anthropic, Claude AI, OpenAI, or Codex. Please comply with the relevant Terms of Service when using this software.

---

<div align="center">

**If this project helps you, please give it a ⭐ Star!**

Made with ❤️ by [f-is-h](https://github.com/f-is-h)

[⬆ Back to Top](#usage-meter)

</div>
