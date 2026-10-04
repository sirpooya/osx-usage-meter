# osx-usage-meter

**Usage Meter** (`UsageMeter.app`, bundle id `in.pooya.usagemeter`): macOS menu bar app showing
Claude usage (session window, weekly, per-model) at a glance.

**Not greenfield.** The codebase is [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude)
(MIT, ~22k LOC Swift), taken as-is on 2026-08-21, renamed throughout to `ClaudeUsage`, then renamed again to Usage Meter
on 2026-10-04 (see "Renamed to Usage Meter" under Fork status). The
goal is to improve that app in place, not to rewrite it. See "Fork status" below.

## Build and run loop (do this after every change)

Non-negotiable. A build that only exists in DerivedData is useless.

1. Rebuild (`xcodebuild` ad hoc signs it for us).
2. Replace `/Applications/UsageMeter.app`, then verify the signature rather than re-signing.
3. Launch from `/Applications`, never from DerivedData or a temp path.
4. Update this file with what changed.

```bash
pkill -f "UsageMeter.app/Contents/MacOS/UsageMeter"
xcodebuild -project UsageMeter.xcodeproj -scheme UsageMeter -configuration Debug \
  -derivedDataPath <scratch>/dd build \
  CODE_SIGN_IDENTITY="Apple Development: pooyak@live.com (FTQDQPMU3H)" \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER="" DEVELOPMENT_TEAM=""
rm -rf /Applications/UsageMeter.app
cp -R <scratch>/dd/Build/Products/Debug/UsageMeter.app /Applications/UsageMeter.app
codesign -v --strict /Applications/UsageMeter.app      # do NOT re-sign, see gotchas
codesign -d --entitlements - /Applications/UsageMeter.app | grep -A2 app-sandbox   # expect false
open -a /Applications/UsageMeter.app
pgrep -lf "/Applications/UsageMeter.app"   # confirm it actually came up
```

Gotchas that cost time already:
- **Sign with the Apple Development identity, not ad hoc**, or the Keychain prompt
  ("UsageMeter wants to use your confidential information stored in Claude Code-credentials")
  comes back after every single build. Ad hoc signing makes the app's designated requirement a
  raw `cdhash H"..."`, and that is what Keychain Access stores in the item's ACL when you click
  Always Allow. A rebuild is a new cdhash, so the grant no longer matches anything and macOS asks
  again. Signing with the identity gives an identity-based requirement instead
  (`identifier "in.pooya.usagemeter" and anchor apple generic and certificate
  leaf[subject.CN] = "Apple Development: ..."`), which survives rebuilds, so Always Allow sticks.
  Verify with `codesign -d -r- /Applications/UsageMeter.app`: if the last line says `cdhash`, the
  prompt will be back next build. `CODE_SIGN_STYLE=Manual` plus the two empty overrides is what
  keeps Xcode from demanding a provisioning profile. Entitlements are unaffected, still
  `app-sandbox = false`.
- The prompt also appears **while you are doing nothing**, which is not a second bug:
  `ClaudeAPIService.fetchCLISyncedUsage` deliberately re-reads the Keychain on every poll (60s
  active, up to 5-10 min idle), so any lost grant is re-asked on the poll timer rather than on
  your next click. Claude Code rotating its own entry can also reset the ACL mid-session.
- Do not launch the binary directly from a backgrounded shell. The process dies when that
  shell exits, which looks exactly like a crash in the log.
- To screenshot a window, get its id from `CGWindowListCopyWindowInfo` and use
  `screencapture -l <id>`. Region captures (`-R`) get occluded by whatever is in front.
- `defaults delete in.pooya.usagemeter` resets first-launch onboarding state, but **not**
  the accounts: those live in our own Keychain item via `AccountStore`/`KeychainManager`, so the
  app still has credentials after a defaults wipe.
- Entitlements do not come from `Config/UsageMeter.entitlements` alone. Xcode 26 merges
  build-setting-derived keys over that file, so `ENABLE_APP_SANDBOX` in `project.pbxproj` wins.
  Editing only the plist left `app-sandbox = true` in the signature (the giveaway was a
  `files.user-selected.read-write` key that appears in no file we own). Both configs are now `NO`.
- The `codesign --force --deep --sign -` step in the loop above **strips all entitlements**.
  `xcodebuild` with `CODE_SIGN_IDENTITY="-"` already ad hoc signs the product correctly, so
  prefer `cp -R` plus `codesign -v --strict` to verify, and re-sign only if verification fails.
  Every `/Applications` build installed before this was discovered had therefore been running
  with no entitlements at all, which is why its data sits outside `~/Library/Containers`.
- `sips -c H W --cropOffset Y X` measures the offset **from the image centre**, not the top left,
  which makes menu bar crops land in the middle of the screen. `screencapture -x -R x,y,w,h`
  against the real menu bar strip is the reliable way to photograph the status items.
- Changing the bundle id can make Control Center hide the menu bar icon. See the
  `menubar-fix` skill.

## Goal

Beat the existing crowd of ~20 menu bar usage trackers on the two things they all get wrong:
authoritative data and history. Native, menu-bar-only, no telemetry, no account.

## Data sources (all three verified working on this machine, 2026-08-21)

### 1. Primary: OAuth usage endpoint (authoritative, server-side, cross-device)

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
Content-Type: application/json
User-Agent: claude-cli/2.0.0 (external, cli)
```

**The User-Agent header is mandatory.** Without it the endpoint returns an instant, persistent
429 `rate_limit_error` even with a valid token. This is the single blocker that
[anthropics/claude-code#31021](https://github.com/anthropics/claude-code/issues/31021) hit and
that made most competing apps fall back to fragile cookie scraping. Verified HTTP 200 with it.

Token comes from the macOS Keychain, not a file:

```
security find-generic-password -s "Claude Code-credentials" -w
```

Returns JSON; the token is at `.claudeAiOauth.accessToken` (also `refreshToken`, `expiresAt`).
`~/.claude/.credentials.json` does **not** exist on macOS (that path is Linux/Windows only).
Access tokens expire ~60 min; refresh via the OAuth refresh token, and expect Claude Code itself
to rotate the Keychain entry underneath us. **Do not read Claude Code's entry on the poll path**:
that read is what raises the authorization prompt. Mirror it once into our own Keychain item and
serve polls from there. See "Keychain prompt on every poll" below.

Response shape (verified):

```jsonc
{
  "five_hour": { "utilization": 44.0, "resets_at": "...", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
  "seven_day": { "utilization": 52.0, "resets_at": "..." },
  "seven_day_opus": null, "seven_day_sonnet": null, "seven_day_cowork": null,
  "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null, "daily": null, "weekly": null },
  "limits": [                       // <- PREFER THIS. Flat, stable, self-describing.
    { "kind": "session",       "group": "session", "percent": 44, "severity": "normal", "resets_at": "...", "scope": null, "is_active": false },
    { "kind": "weekly_all",    "group": "weekly",  "percent": 52, "severity": "normal", "resets_at": "...", "scope": null, "is_active": true },
    { "kind": "weekly_scoped", "group": "weekly",  "percent": 38, "severity": "normal", "resets_at": "...",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": false }
  ],
  "spend": { "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 }, "limit": null, "percent": 0, "enabled": false },
  "member_dashboard_available": false
}
```

Parsing rules:
- Drive the UI off `limits[]`, not the top-level `five_hour`/`seven_day` blocks. It is flat,
  carries `severity` and `is_active`, and new limit kinds appear there without a schema change.
- The top level contains codenamed keys (`nimbus_quill`, `tangelo`, `iguana_necktie`,
  `cinder_cove`, `amber_ladder`, `omelette_promotional`). These are unreleased/internal limit
  buckets, usually null. **Never hardcode or display them.** Ignore unknown keys.
- `limit_dollars` / `used_dollars` are null on subscription plans. Do not render dollar figures
  from this endpoint unless non-null.
- Money is minor units: `amount_minor` with an `exponent`, so 0 USD exponent 2 means $0.00.
- `is_active: true` marks the limit currently binding. That is the one to show in the menu bar
  when collapsed to a single number.

### 2. Secondary: local session logs (offline, per-project, historical)

`~/.claude/projects/<url-encoded-cwd>/<sessionId>.jsonl` (488 files on this machine).
One JSON object per line. Records where `type == "assistant"` carry `message.model` and
`message.usage`:

```jsonc
{
  "model": "claude-opus-5",
  "usage": {
    "input_tokens": 2,
    "cache_creation_input_tokens": 12386,
    "cache_read_input_tokens": 21212,
    "output_tokens": 100,
    "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 },
    "service_tier": "standard",
    "cache_creation": { "ephemeral_1h_input_tokens": 12386, "ephemeral_5m_input_tokens": 0 },
    "iterations": [ /* per-turn breakdown, same fields */ ]
  }
}
```

Other line `type` values seen: `user`, `assistant`, `attachment`, `ai-title`, `last-prompt`,
`queue-operation`, `file-history-snapshot`, `file-history-delta`. Useful sibling fields on the
envelope: `cwd`, `gitBranch`, `sessionId`, `timestamp`, `version`, `requestId`, `model`, `effort`.

Parsing rules:
- Never sum `iterations[]` on top of the parent `usage` block. The parent is already the total.
- Cache reads are billed differently from fresh input. Keep the four token classes separate all
  the way to the UI; collapsing them makes cost estimates wrong by an order of magnitude.
- Dedupe by `requestId`. The same request can appear across resumed sessions.
- Tail incrementally (track file offset + inode). Never re-parse 488 files on a poll.
- The directory name is the cwd with `/` replaced by `-`, which is lossy. Prefer the `cwd` field
  inside the records for project attribution.

### 3. Fallback: PTY scrape of `claude` + `/usage`

`claude --help` exposes no usage/limits subcommand as of 2.1.220, so the only CLI route is
spawning a PTY and sending `/usage`, as [cc-usage-bar](https://github.com/lionhylra/cc-usage-bar)
does. Zero credential handling, but slow and brittle. Keep as last resort only.

## Architecture

Fuse source 1 and source 2. Nobody in the field does this well, and it is the whole differentiator.

- **Source 1 = truth.** Percentages, reset times, which limit binds. Cross-device accurate.
- **Source 2 = detail and history.** Per-model, per-project, per-branch tokens; cache hit rates;
  real-time movement between polls; unlimited retention.
- Source 1 has no history (the endpoint only reports now). Persist every poll locally so trends
  exist. Source 2 has no server truth (misses usage from other devices, web, mobile).
- Poll adaptively: ~60s while a session is active, back off to 5 to 10 min when idle. Respect
  429s with real backoff. Never poll faster than 30s.
- Menu bar collapsed state shows the `is_active` limit. Popover shows all limits plus history.

### Differentiators to build (ranked)

1. **History and trends.** Every competitor lists this as "planned" and none shipped it.
2. **Burn-rate forecast.** "Weekly cap Thursday ~3pm at this pace" beats a raw percentage.
   Only AIQuotaBar attempts it.
3. **Attribution.** Cost and tokens per project / repo / branch / model, from source 2's `cwd`
   and `gitBranch`. Zero apps do this.
4. **macOS 26 polish.** Liquid Glass popover, LSUIElement agent, Sparkle updates, Homebrew cask.

## Competitive landscape (researched 2026-08-21)

| Repo | Stars | Stack | Data source | Note |
|---|---|---|---|---|
| [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) | 3.3k | Swift, MIT | claude.ai `sessionKey` cookie + Console API key | Best UI. Dynamic Island, multi-profile. Cookie auth expires constantly |
| [tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar) | 1.4k | Swift 6.2, Tuist, Sparkle | per-provider CLIs + cookies + SQLite | 12 providers. Most active. No license file |
| [Iamshankhadeep/ccseva](https://github.com/Iamshankhadeep/ccseva) | 800 | TypeScript | local logs | Electron weight |
| [Nanako0129/TokenBar](https://github.com/Nanako0129/TokenBar) | 257 | Rust core + SwiftUI, MIT | local logs only | Best local-parsing design. No server truth. Apple Silicon only |
| [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude) | 364 | Swift, MVVM | browser OAuth + cookie | **This is now our base, see "Fork status".** Not cookie-only any more: it does call `/api/oauth/usage`, just without the User-Agent fix |
| [aqua5230/usage](https://github.com/aqua5230/usage) | 287 | Python, AGPL | local logs | Cross-platform. AGPL, so do not copy code |
| [lionhylra/cc-usage-bar](https://github.com/lionhylra/cc-usage-bar) | 16 | Swift, MIT | PTY scrape of `/usage` | Novel approach, cited above |
| [SessionWatcher](https://sessionwatcher.com/) | paid | native | mixed | $6.99 one-time. Only commercial one with traction |

Takeaway: the entire field splits into cookie-scrapers (fragile) and local-log-parsers
(incomplete). The OAuth endpoint plus the User-Agent fix skips both traps.

## Fork status

Base commit: `f-is-h/Usage4Claude` main, downloaded 2026-08-21 (never cloned, so no upstream git
history). MIT, so forking and renaming is fine, but `LICENSE` keeps f-is-h's copyright notice.

Layout: app source in `UsageMeter/`, Xcode project `UsageMeter.xcodeproj`, tests in
`Tests/UsageMeterCoreTests` (128 tests, `swift test`). `Package.swift` is a thin manifest that
points at a handful of pure-logic files in place so they can be unit tested without Xcode. The
Xcode project is the authoritative app build.

The target uses a `PBXFileSystemSynchronizedRootGroup` over the `UsageMeter/` folder, so new
files are compiled automatically with no `project.pbxproj` editing.

What has been changed from upstream so far:

- Renamed everything to `ClaudeUsage`, bundle id `com.claudeusage.ClaudeUsage`. Superseded by
  the Usage Meter rename, see the next entry.
- Every GitHub URL now points at this fork's own repo, `sirpooya/osx-usage-meter`. The rename
  pass had left two broken families behind: `f-is-h/ClaudeUsage`, a repo that never existed
  (203 references, all 404), and `f-is-h/Usage4Claude`, which resolved but documented upstream
  rather than this fork (15 references). Both are gone. Touched app code, all 7 locale files,
  `README.md`, the 6 localized `docs/README.*.md`, `CHANGELOG.md`, `CONTRIBUTING.md`,
  `appcast.xml`, `Config/Info.plist` (`SUFeedURL`), the whole `website/` tree,
  `.github/RELEASE_TEMPLATE.md`, `.agents/skills/release/SKILL.md`, `scripts/build.sh` and
  `docs/archive/`. Verified HTTP 200 for the repo root, `/issues`, `/releases`,
  `/releases/latest`, `/pulls`, `/blob/main/LICENSE`, both issue templates, the raw appcast
  feed, and all 7 localized `#initial-setup` anchors (the anchor headings are real in our own
  README copies, checked line by line).
  - The Sparkle appcast URL now resolves. Its `<enclosure>` entries still name upstream's DMG
    assets, which do not exist under this repo's releases, so the feed is reachable but not yet
    servable. Fix that before shipping any update.
  - `/discussions` returns 404 because Discussions is not enabled on the repo. It is linked from
    `README.md`, `CONTRIBUTING.md`, `website/`, and the localized READMEs. Enable the tab or
    drop those links.
  - Deliberately **not** rewritten, because they are attribution, not navigation: f-is-h's
    `LICENSE` copyright, the `Copyright (c) 2025-2026 f-is-h` and `Created by f-is-h` headers in
    the Swift and `.strings` files, `github.com/sponsors/f-is-h` (About window, menu bar menu,
    `website/`, READMEs), `.github/FUNDING.yml`, the `@f-is-h` profile links in the README
    Contact sections, and the two upstream-attribution rows near the top of this file.
  - `DiagnosticLogger.swift` used `com.f-is-h.ClaudeUsage` as its `Logger` subsystem and queue
    label; the Usage Meter rename fixed it to `in.pooya.usagemeter`.
- **Renamed to Usage Meter (2026-10-04).** App, project, repo and folder all moved off the
  ClaudeUsage name:
  - `UsageMeter.app`, `CFBundleDisplayName` "Usage Meter" (new key in `Config/Info.plist`), bundle
    id **`in.pooya.usagemeter`**, matching the `in.pooya.<name>` rule every other osx-* app uses.
    Target, schemes, source folder `UsageMeter/`, `UsageMeter.xcodeproj`, `Config/UsageMeter.entitlements`,
    SwiftPM `UsageMeterCore` / `Tests/UsageMeterCoreTests`, entry point `UsageMeterApp`.
  - User-visible copy says "Usage Meter" with a space (About, welcome title in all 7 locales,
    diagnostic report, OAuth callback page, README, website, appcast); paths and identifiers say
    `UsageMeter`. Prose like "your Claude usage" and the `cachedClaudeUsage` / `clearClaudeUsageState`
    family were left alone: they mean Claude's usage, not the app.
  - GitHub repo renamed to `sirpooya/osx-usage-meter` (GitHub redirects the old URL), every link,
    the git remote and `SUFeedURL` repointed. Local folder is `~/Documents/GitHub/osx-usage-meter`.
    The undeployed website domain placeholder is now `usagemeter.pages.dev`.
  - Other ids that moved: Keychain token mirror `in.pooya.usagemeter.tokens`, Application Support
    folder `UsageMeter/`, log files `usagemeter_*.log`, window autosave names `UsageMeter.*`.
  - **`Services/LegacyRenameMigration.swift`** carries the old install over once (gate key
    `legacyRename.migratedFromClaudeUsage`): copies every key from the `com.claudeusage.ClaudeUsage`
    defaults domain that the new domain lacks (Debug builds keep accounts there as `DEBUG_*`),
    remapping `ClaudeUsage.` window autosave keys; in Release, copies KeychainManager's items from
    the old service (each read may prompt once, the ACL names the old id); and moves
    `Application Support/ClaudeUsage` to `UsageMeter` if the new folder does not exist. Nothing old
    is deleted. It runs from **AppDelegate's first stored property**, because `UserSettings.shared`
    loads in a later stored property, before `applicationDidFinishLaunching` would ever run.
  - Verified live: 39 keys and the history folder migrated, the CLI account re-synced, icons up in
    the menu bar, Control Center lists `in.pooya.usagemeter` as allowed. The old token mirror item
    was not migrated on purpose: the app re-mirrors from Claude Code's item, one prompt either way.
  - Leftovers on this machine, harmless: the `com.claudeusage.ClaudeUsage` defaults domain, the
    `com.claudeusage.ClaudeUsage.tokens` Keychain item, and a ghost `com.claudeusage.ClaudeUsage`
    row in Control Center's menu bar list (`menubar-fix` skill, `prune`).
- Replaced both icon assets with our own artwork. See "App icon".
- Onboarding is now a single window with one path: sign in with a claude.ai account.
  - Removed upstream's first page, then the manual Session Key field, the Display Options
    block (theme, display content, smart/custom limits), the Skip button and the Finish bar.
    Display settings live in Settings; nothing here needs a "later" escape hatch.
  - Window is titled **Login** (new `window.login_title` key), 300x400, and shows app icon,
    app name, tagline and a note under the button (`welcome.tagline`, `welcome.sign_in_note`).
  - The CTA is brand-coloured via `UsageColorScheme.brand` (#D97757, display-p3, same value as
    the icon artwork).
  - `ClaudeOAuthCoordinator` already calls `addAccount` before its callback, so `WelcomeView`
    no longer re-fetches organizations. That removed the org-fetch spinner and error row.
  - With no Finish button, `willCloseNotification` sets `isFirstLaunch = false`, otherwise
    closing the window would reopen it on every launch.
- Fixed the welcome window not opening centred. See "Centring an NSWindow around SwiftUI".
- Default menu bar theme is now `.monochrome` (was `.colorTranslucent`), in `UserSettings`.
- Fixed colour-mode menu bar icons. See "Menu bar icon colour modes".
- Fixed `NSImage(named: "AppIcon")` always returning nil. See "App icon".
- Reworked the popover's no-credentials and error states, in `UsageDetailView`:
  - Upstream branched on `error.contains("Authentication") || error.contains("configured")`,
    but the actual string is "Please **configure** authentication information in settings
    first", so both tests failed and the Go to Settings button was suppressed.
  - Worse, both buttons called `onMenuAction?(.authSettings)` while one was labelled "Run
    Diagnostic". The same duplicated pair existed in the Codex block. Real diagnostics live in
    Settings > Auth > Help (`DiagnosticsView`), not here.
  - Now keyed off `UserSettings.shared.hasValidCredentials`, not string sniffing. Signed-out is
    an empty state (`usage.sign_in_prompt`) with one button that opens the login window and
    then refreshes; genuine errors get Refresh plus Go to Settings. Error text uses
    `fixedSize` so it wraps instead of truncating to "...information in...".
- Replaced the popover's ring with a list of full-width bars, one per limit, in
  `UsageDetailView` / `UsageRowComponents` / `CodexColumnView`:
  - A row is title plus countdown on the left, the percentage alone on the right, and a 5pt
    capsule bar under both. `UsageLimitBarRow` + `UsageLimitBar` are the new components;
    `UnifiedLimitRow` keeps all the per-type label / percentage / reset-time logic and now just
    feeds them.
    - The countdown used to sit on the right as one `NN% · <countdown>` string. It now sits with
      the title, so the row reads as one phrase ("5-Hour Limit  24m left") and the percentage
      stands alone at the right edge. `trailingText` became `percentageText`, which returns nil
      when the limit has no percentage so the row cannot print a bare "%"; the countdown keeps
      its own `TimelineView` and the title takes `layoutPriority(1)` so the countdown is what
      gives way when the row is tight.
    - All three labels share one size, `UsageLimitBarRow.labelSize` (12pt), so they sit on one
      optical line. Hierarchy is weight and colour only: the title is medium and primary, the
      countdown and percentage are regular and secondary. The countdown and percentage used to
      be 11pt. Keep the constant as the single source or the three drift apart again.
    - **No `minimumScaleFactor` on any of the three**, and do not reintroduce one. The title and
      countdown carried `0.85` while the percentage did not, and since the percentage always has
      room it never shrank: a tight row (`5-Hour Limit  4h 51m left  1%`) scaled the first two
      down to 10.2pt while the percentage stayed at 12, so a row that declared one size rendered
      two, and the percentage read as the largest label on the line. One shared constant is not
      enough on its own, the scaling behaviour has to match too. Overflow now truncates, and the
      title's `layoutPriority(1)` makes the countdown give way first.
    - The gap between the title and the countdown is 4pt (the row's `HStack` spacing, down from 6),
      tight enough that the two read as one phrase. Horizontal only, so it costs `PopoverMetrics`
      nothing; the 5pt label-to-bar gap and the 12pt row spacing are unchanged, and the row height
      that `PopoverMetrics` assumes still holds.
    - A middot separates the two ("5-Hour Limit · 1h left"). It is secondary at `labelSize`,
      the countdown's own colour, and sits inside the countdown's `TimelineView` rather than next
      to the title, so a limit with no countdown does not print a trailing dot.
  - Bar colour still comes from the per-limit palette in `UsageColorScheme` and still escalates
    with the percentage, so the colour says both which limit it is and how close it is.
  - `showRemainingMode` now defaults to **true**, so rows read "2d 7h left", not "Aug 24 2 AM".
    Read the default with `object(forKey:) as? Bool ?? true`; `UserDefaults.bool(forKey:)`
    returns false for a missing key and would silently flip it back. Tapping the list still
    toggles to absolute reset times. Percentages always read as used, never as remaining.
  - Countdowns run one unit coarser as the window gets longer: `45m left`, then `1h 11m left`
    under two hours, then **hours only** (`3h left`) up to a day, then **days only** (`2d left`)
    once a day is on the clock. Hours next to days were precision nobody acted on, and
    `1d 0h left` read worse than `1d left`.
    `formattedCompactRemaining` in `UsageData+Formatting.swift` is the single formatter; the
    days branch uses the new `usage_data.compact_remaining_days_only` key (all 7 locales, each
    matching that locale's existing phrasing, so de is `noch %dd` and ja is `残り%d日`).
    The old two-unit `usage_data.compact_remaining_days` key and its `compactRemainingDays`
    accessor are now unused but kept, as is the never-called
    `formattedCompactRemainingWithMinutes` (which printed a third unit, `3d 4h 48m left`).
    - The **under two hours** branch is the one exception to running coarser, added because
      `1h left` covered everything from 60 to 119 minutes. That is the range where the 5-hour
      window is actually being watched, so the minutes come back: the two-unit
      `usage_data.compact_remaining_hours` key (already present in all 7 locales) prints
      `1h 11m left`. At two hours and up the hours-only key takes over again.
    - The day count is **floored**, the same count the days-plus-hours version computed, so
      `1d left` means a full day really is left and the reset can only land later than the label
      implies. Rounding up would print `2d left` with 25h to go, promising time the user does not
      have.
    - No week unit: no limit window is longer than 7 days, so days is the largest useful one.
  - Both columns use the same rows, so Claude and Codex line up in two-provider mode.
  - Popover height is computed in `PopoverMetrics` (row 26, row spacing 14, chrome 18 + 20 + 10,
    empty states 210) plus `contentSpacing`, the fixed 16 between the title row and the bars.
    The bottom is deliberately the tightest of the three gaps: leftover slack lands there and
    reads as dead space, while the bars need air under the title. `contentSpacing` used to
    tighten to 10 for two or more limits, which only made sense while a 114pt ring sat under the
    title. `claudeRowCount` also counts the third-and-later model rows, which the old ring-era
    math left out, so a Fable + Opus + Sonnet account no longer gets its last row clipped.
  - Deleted with the ring: `MiniProgressIcon`, `DetailUsageRingCenterText`,
    `DetailUsageRingSweep`, `AnimationTypeHintView`, the ring trim helpers, every ring loading
    animation in `UsageDetailView+Helpers.swift` and `CodexColumnView`, and the long-press
    `LoadingAnimationType` switcher that only existed to pick between those animations. Bars
    breathe while refreshing instead. The `loading_animation.*` keys are now unused in all 7
    locale files.
  - `usage.title` is just "Claude" in all 7 locales, not "Claude Usage". The header already has
    the app icon next to it, so the word was redundant. `usage.codex_title` is still
    "Codex Usage".
- Trimmed the status item menu, in `MenuBarUI.createStandardMenu` and the matching SwiftUI
  `Menu` in `UsageDetailView`. Both have to change together or the right-click menu and the
  popover's three-dot menu disagree.
  - General Settings and Authentication Settings collapsed into one **Settings** item
    (new `menu.settings` key, all 7 locales) wired to `openSettings` / `.generalSettings`,
    which opens tab 0. The Auth tab is one click away inside the window, and the popover's
    "Go to Settings" buttons still deep-link to tab 1 via `.authSettings`, so both
    `L.Menu.generalSettings` and `L.Menu.authSettings` are now unused but their keys and the
    `MenuAction` cases stay.
  - Check for Updates is disabled (`isEnabled = false`, `.disabled(true)`) until the Sparkle
    appcast URL is repointed. This also required `menu.autoenablesItems = false`, otherwise
    AppKit re-enables any item that has a target and an action.
  - `menu.quit` is now just "Quit", not "Quit ClaudeUsage", and the item carries no icon.
- A failed refresh can no longer blank the popover. This is the "Too many requests, please try
  again later" screen that replaced perfectly good numbers on any transient 429:
  - Root cause of the errors themselves: `ClaudeOAuthService.post` (the token endpoint at
    `console.anthropic.com/v1/oauth/token`, used by both the initial exchange and every refresh)
    was the one request in the app **not** sending `User-Agent`. The usage and profile calls both
    set it. Without it this endpoint family answers a valid token with an instant 429, so once an
    access token expired (~60 min) every fetch failed. Fixed; see "Data sources" above.
  - The 429 actually observed on 2026-08-21 was a genuine server side limit from restarting the
    app in a tight loop (two agent sessions doing install-and-run at once), not the header bug.
    Verified by probing `/api/oauth/usage` directly with the app's exact headers: HTTP 200 while
    the popover was showing the error. Both causes are now handled the same way.
  - What the UI does now, which is what [hamed-elfayome/Claude-Usage-Tracker] does structurally:
    its `UsageRefreshCoordinator` only ever calls `dataStore.saveUsage(...)` on success and its
    `catch` blocks just log, so its views render the last saved snapshot and a failed request
    cannot produce a visible state. Ours had `errorMessage` as a UI state that took priority over
    the data, which is the whole difference.
  - So: `usageData` is never cleared on failure (it already was not, but `claudeMainContent`
    checked `errorMessage` **first**, so the error won anyway). Data now wins; the error branch is
    only reached with nothing cached at all.
  - Transient errors (429, network blip, 5xx, decode) never get a screen. `RefreshState`
    `claudeErrorIsTransient` gates that: transient means bars, or the loading state, never an
    error. Only actionable auth errors (no credentials, unauthorized, session expired, Cloudflare)
    still get the signed-out or error state, because the user has to do something about those.
  - The last good fetch is persisted (`cachedClaudeUsage` / `cachedClaudeUsageAt` in UserDefaults,
    which is why `UsageData` and friends are now `Codable`) and restored in `DataRefreshManager.init`,
    so a cold start shows real numbers instead of a spinner. Percentages and reset times only, no
    credentials.
  - When stale data is on screen, a one line note under the bars says so:
    "Couldn't refresh · showing 9:20 PM" (`usage.stale_notice`, 7 locales). `PopoverMetrics`
    `staleNoticeHeight` reserves its height (text 13 + row spacing + `staleNoticeTopGap` 8:
    it is not a limit row, so it does not sit at the same rhythm as one), and `claudeColumnHeight`
    is now the single place that decides the Claude column's height, so the height rule and the
    render rule cannot drift apart.
  - A 429 also arms a 10 minute backoff (`claudeBackoffUntil`): automatic polls sit it out, the
    Refresh button ignores it because the user asked. Skipping a poll never clears the cached data.
  - A Codex failure keeps its last data too (it used to call `clearCodexUsageState`).
- The popover header's ellipsis menu is now a gear that opens Settings directly. Everything that
  menu carried (account switching, check for updates, About, status pages, Buy me a coffee, Quit)
  is still on the status item's right click menu, `MenuBarUI.createStandardMenu`. The update dot
  moved onto the gear so the signal is not lost.
- **The popover header shows the subscription tier next to the title**, so it reads "Claude Team",
  the tier dimmed and regular weight because it names the plan rather than being a second title.
  Not localized: it is the plan's own name.
  - **Codex shows its plan too** ("Codex Plus"), and its title lost the word "Usage" in all 7
    locales (`usage.codex_title` is just "Codex", matching `usage.title`). The plan is
    `plan_type` from the wham/usage response, cached in `UserSettings.codexPlanType`
    (UserDefaults `codex.planType`) from `CodexAPIService` on every successful fetch.
    `codexPlanLabel` and `claudeSubscriptionTierLabel` share one private `planLabel` formatter
    (Codex drops a `chatgpt_` prefix, Claude a `claude_` one; free/none/unknown stay empty).
    Codex also strips `self_serve_` and `_prolite`: this account reports
    `self_serve_business_prolite`, which shows as "Business".
  - Both take `.font(.headline)`, the tier overriding only the weight with `.fontWeight(.regular)`,
    so the two cannot drift apart in size. The tier was 12pt against the title's 13pt headline.
  - Title and tier sit in their own `HStack(spacing: 4)` inside the header row. Tightening the gap
    between them directly would otherwise have pulled the app icon in too, since the icon shares
    the header row's default spacing.
  - Cached in `UserSettings.claudeSubscriptionTier` (UserDefaults `claude.subscriptionTier`)
    rather than fetched on demand. Both free sources are read on a background queue, and the
    header cannot touch the Keychain while rendering. Empty means unknown, and the header then
    shows the plain title, so a tier this build cannot resolve degrades to today's UI.
  - `claudeSubscriptionTierLabel` normalizes generically instead of matching a fixed list: lowercase,
    drop a leading `claude_`, split on `_`/`-`/space, capitalize each word. So both `team` (the
    Keychain spelling) and `claude_team` (the profile spelling) print "Team", and a tier this
    build has never heard of still prints instead of vanishing. `free` / `none` / `unknown` return
    empty, because "Claude Free" is not worth a badge.
  - Three write points, in order of how fresh they are:
    - `ClaudeAPIService.fetchCLISyncedUsage`, from `credentials.subscriptionType` on **every**
      CLI synced poll. The entry is already being read there, so this costs nothing. This is what
      makes an account that synced before the feature existed, or one whose plan changed, pick up
      the right tier without a re-sync.
    - `ClaudeCodeSyncService.upsertAccount` at sync time, preferring the profile's value and
      falling back to the Keychain's (the Keychain is readable even when the token has expired).
    - `ClaudeOAuthCoordinator.createAccount` for browser logins, which have no Keychain entry.
  - `ClaudeOAuthService.fetchProfile` now returns a 4th tuple member, `tier`, read from
    `organization.organization_type` (`claude_team` on a team or enterprise seat) and falling back
    to `account.has_claude_max` / `has_claude_pro`, which is where a personal account carries it.
    Verified live against the endpoint. The two call sites' tuple type annotations had to change
    with it, in `ClaudeCodeSyncService.fetchProfile`/`upsertAccount` and `createAccount`.
  - `UsageDetailView` now holds `@ObservedObject settings = UserSettings.shared`. It read
    `UserSettings.shared` directly in a dozen places without observing it, so without this the
    tier only appeared on whatever next rebuilt the popover.
- Translated all hardcoded Chinese in UI strings and the 148 logger messages to English.
- **CLI Account Sync**: the app now logs itself in from Claude Code's own Keychain entry, so a
  fresh install needs no pasted session key and no browser round trip. This is the login method
  the 3.3k-star `hamed-elfayome/Claude-Usage-Tracker` uses (its `CLI Account` credential row,
  alongside `Claude.ai` cookie and `API Console`), and the reason it feels zero-setup next to
  everything else in the field. New and changed pieces:
  - `Services/ClaudeCodeCredentials.swift` reads the entry with the Security framework, never by
    shelling out to `security(1)` (which would put the plaintext token in another process's
    pipe). It enumerates *attributes* first to find every `Claude Code-credentials*` service
    (suffixed variants exist per `CLAUDE_CONFIG_DIR`), and only reads secret data for the chosen
    one, so the authorization prompt happens once rather than per candidate.
  - `Services/ClaudeCodeSyncService.swift` turns that entry into a normal Claude account, pulling
    `/api/oauth/profile` for the display name. `pinnedService` (persisted at
    `cliSync.pinnedService`) lets a multi-config user nail the sync to one entry.
  - `Account` gained `credentialSource` (`.manual` / `.claudeCodeCLI`) and `keychainService`, both
    `decodeIfPresent` so existing stored accounts migrate untouched.
  - `ClaudeAPIService.fetchCLISyncedUsage` re-reads the Keychain on **every** poll and uses the
    CLI's `accessToken` directly while it is still valid, which costs zero extra requests and
    leaves the CLI's refresh token alone. Only when it has actually expired do we run the refresh
    grant ourselves, and then we **write the rotated pair back into Claude Code's Keychain entry**
    (preserving the entry's other fields). That write-back is not optional: refresh tokens are
    single use, so skipping it would silently log the user out of their own CLI on our next poll.
  - Startup gate in `UsageMeterApp.applicationDidFinishLaunching` tries the sync before
    deciding whether to show the welcome window, and marks first launch complete when it lands.
    It deliberately backs off when accounts already exist, so it never overrides a manual login.
  - `AuthSettingsView+CLIAccount.swift` is the settings card: sync status, masked access token,
    subscription type, scopes, Re-sync / Remove, plus the Keychain entry picker (shown only when
    more than one entry exists). Only the masked token is ever displayed.
- **App Sandbox is now off** (`ENABLE_APP_SANDBOX = NO` in both configs, and the entitlements
  file documents why). Inside the sandbox, Keychain access is confined to the app's own access
  group, so reading Claude Code's entry is impossible no matter what else is granted. The
  competitor ships unsandboxed for exactly this reason. Cost: no Mac App Store, which the
  Homebrew cask plan never wanted anyway.
- Added the mandatory `User-Agent: claude-cli/2.0.0 (external, cli)` header to both
  `/api/oauth/usage` and `/api/oauth/profile` (`ClaudeOAuthConfig.userAgent`). Upstream omitted
  it, which is the instant-persistent-429 trap documented under "Data sources" above.
- Dropped the "Advanced:" prefix from the manual session key label in all 7 locales
  (`welcome.manual_session_key`). It is a plain alternative input, not a hazardous setting.
- New `L.CLISync` localization namespace. The 21 keys carry English copy in all 7 locale files;
  de / fr / ja / ko / zh-Hans / zh-Hant still need real translations.
- **Credentials settings rebuilt as a two pane sidebar**, replacing the single scroll Auth tab.
  Sidebar rows are Claude.ai, API Console, CLI Account and Codex under CREDENTIALS, plus
  Diagnostics under TOOLS, each credential row carrying its own connected dot. Settings window
  went from 500x550 to 720x600 to fit it. `AuthSettingsView+Sidebar.swift` owns the shell;
  `legacyStackedBody` keeps the old layout around for reference only.
  - Width is now **556** (720 minus 164), so re-check this sidebar plus detail pane: the 720 was
    chosen to fit them side by side, and that was the one thing the narrower window put at risk.
  - **Grouped by provider now, not by "CREDENTIALS".** The sidebar heads each group with that
    provider's own icon: CLAUDE (`ImageHelper.createAppIcon`) over Claude.ai / API Console /
    CLI Account, then CODEX (`ImageHelper.createCodexIcon`) over Codex, then the unchanged
    text-only TOOLS over Diagnostics. One `sectionHeader(_:icon:topPadding:)` helper draws all
    three, icon 13pt (`sectionIconSize`) next to the same caption2 semibold secondary label,
    uppercased with `.textCase(.uppercase)`. "Claude" and "Codex" are brand names, so they are
    hardcoded rather than localized, the same call as the subscription tier label;
    `credentials_nav.section_credentials` is now unused but kept.
  - **Two new brand mark assets**, `ClaudeMark.imageset` and `CodexMark.imageset`, rendered at
    256px @2x from the SVGs kept in `Assets/marks/` (`codex-mark.png` and `download-unused.svg`
    are stashed there too, unused). `ImageHelper.createClaudeMark` / `createCodexMark` load them.
    They are the flat provider logos, deliberately separate from `AppIcon` (our pixel-glyph
    squircle) and `CodexIcon`: the sidebar group headers and the popover header both use the
    marks now, the menu bar renderers still use `AppIcon` / `CodexIcon` and their template
    siblings.
  - **The status card's text hierarchy was two headings stacked.** `CredentialStatusCard`'s
    title was 13pt semibold directly under the 17pt semibold `CredentialPageHeader`, and on the
    CLI pane it read "CLI Account Synced" over a bare "3m", so the pane name appeared twice and
    the second line named nothing. Now the card title is 13pt **medium** (a status, not a
    heading), its detail line wraps instead of truncating (`fixedSize(horizontal: false)`), and
    `CLIAccountPane` splits state from explanation: `statusTitle` is the state alone
    ("Synced" / "Syncing" / "Not Synced" / "Not Found" / "Sync Failed") and the new
    `statusDetail` carries the rest ("Last synced 3m ago", "Claude Code found on this Mac",
    "Sign in with the claude command, then try again", or the failure message).
    `cli_sync.status_synced` / `status_available` / `status_unavailable` were shortened and
    `status_available_detail`, `status_unavailable_detail`, `status_failed` and
    `last_synced` ("Last synced %@ ago") added, all translated in the 7 locales.
- **The settings window size lives in `SettingsView.contentSize`**, used by both the view's
  `.frame` and the window, the same single-source-of-truth shape as `WelcomeView.contentSize`.
  `MenuBarManager` re-applies it with `setContentSize` immediately after
  `setFrameAutosaveName("UsageMeter.SettingsWindow")`, and that ordering is the whole point:
  the autosave restore happens at that call and carries whatever size the window had when it
  last closed, so a stale saved width silently wins over any change to `contentSize`. Verified
  by reading the saved entry, which still held `571 313 720 632` after the source said 556.
  Only the position is meant to be restored; the size is fixed and owned by the view. A stale
  entry left on a machine can be cleared with
  `defaults delete in.pooya.usagemeter "NSWindow Frame UsageMeter.SettingsWindow"`.
- **Appearance card removed from the General tab.** The System / Light / Dark radio group and its
  hint are gone from `GeneralSettingsView`. Only the UI was removed: `UserSettings.appearance`,
  `AppearanceManager` and the `MenuBarUI` popover-appearance switch are all untouched, so the
  stored value (default `.system`) still applies. `L.SettingsGeneralAppearance.section` / `.hint`
  and `AppAppearance.localizedName` are now unused by this tab but kept, as is the enum itself.
- **The two Codex refresh probes are gone from the Debug Mode card**, in
  `GeneralSettingsDebugSection`: "Level 1: SSR refresh" and "Level 2: WebView refresh", plus
  their `tokenRefreshStatus` / `isTestingTokenRefresh` / `silentRefreshStatus` /
  `isTestingSilentRefresh` state and the divider above them. They were upstream's cookie-scraping
  probes, both `.disabled(!settings.hasValidCodexCredentials)` so they rendered permanently greyed
  out without a Codex account, and irrelevant now that auth is the OAuth endpoint plus CLI
  Keychain sync.
  - UI only, and this was checked before deleting: `CodexTokenRefreshCoordinator` is still called
    by `DataRefreshManager` (the real Codex refresh chain) and `DiagnosticRunner`, and
    `CodexSilentRefreshCoordinator` by `DataRefreshManager`. Neither coordinator became dead code.
  - Superseded: the whole card is now gone, see below.
- **The Debug Mode card is gone entirely**, and `GeneralSettingsDebugSection.swift` is deleted
  (it had exactly one call site, the `#if DEBUG` block at the bottom of `GeneralSettingsView`).
  That takes the four toggles (enable debug mode, simulate an update, show the shape icon on its
  own, keep the detail window open), the per-limit percentage sliders and the scenario picker.
  - The `debugModeEnabled` / `debugScenario` / `debug*Percentage` settings themselves are **kept**
    in `UserSettings`, because `DataRefreshManager`, `ClaudeAPIService`, `CodexAPIService` and
    `MenuBarManager` all still branch on them to serve mock data. With no UI they simply stay at
    their defaults, so that path is now unreachable at runtime: `debugModeEnabled` defaults false
    and nothing can flip it. Re-add a toggle (or set the key with `defaults write`) to use the
    mock-data path again.
  - It was `#if DEBUG`, so nothing about the shipped app changes.
- **Leading glyphs removed from the General tab's inline descriptions too**, matching the
  SettingCard lightbulb removal above so every description on the page is plain secondary text:
  the blue `info.circle.fill` on the notification description (`GeneralSettingsView`) and the
  blue one on the `circularIconConstraint` hint (`GeneralSettingsDisplayOptionsSection`). Each
  collapsed from an `HStack` to the bare `Text`, carrying the `padding(.leading, 20)` over where
  there was one. The orange `exclamationmark.circle.fill` on `coloredThemeUnavailable` is
  deliberately **kept**: it is a warning about an unavailable state, not a description, and its
  text is orange to match.
- **API Console is new functionality, not just a row.** `Services/ConsoleAPIService.swift` talks
  to `console.anthropic.com/api`: `/organizations` to validate a pasted console session key,
  `/organizations/<id>/current_spend` and `/organizations/<id>/prepaid/credits` for the figures.
  Money arrives in cents. The session key and chosen organization live in our Keychain item
  through three new named accessors on `KeychainManager` (`saveConsoleValue` and friends), so
  every credential in the app still enters through that class rather than touching `storage`.
- The three panes follow the competitor's design, which is deliberate and worth preserving:
  filled `.borderedProminent` for a card's primary action, bordered red tint for destructive,
  quiet bordered for Refresh and Back, title case card headers with a secondary subtitle line,
  hairline separated detail rows with accent colored icons, and a 1-2-3 stepper whose connectors
  stretch full width. All of it lives in `Views/Settings/Credentials/CredentialsChrome.swift`,
  which carries that contract as a comment so the panes cannot drift apart.
  - One intentional divergence: their label reads "Advanced: Manual Session Key", ours is just
    "Manual Session Key". It is a plain alternative input, not a hazardous setting.
- The CLI Account status card shows elapsed time since the last sync. `lastSyncedAt` persists in
  `UserDefaults` under `cliSync.lastSyncedAt`, and the pane re-renders on a 30s timer, otherwise
  the line sits frozen at whatever it said when the window opened.
- **Menu bar icon style is one switch now, not three radios.** `iconStyleMode` keeps all three
  cases for stored prefs, but the UI offers only Monochrome on or off (off maps to
  `.colorTranslucent`). The default flipped from `.monochrome` to `.colorTranslucent`, so the
  status colors carry the information and monochrome is the opt in. Per the
  `menubar-icon-theming` skill, which encodes this preference.
  New keys added by this fork are written in all 7 locales, not English-only.
  - **Monochrome now also recolors the popover bars.** With it on, every Claude limit bar in the
    popover drops its per-limit palette (green / purple / orange / blue / pink) and draws in
    `UsageColorScheme.brand` (#D97757), the same brand color as the login CTA and the app icon,
    so the whole app reads as one color rather than the menu bar alone going quiet. Handled in
    `UnifiedLimitRow.barColor` in `UsageRowComponents.swift`, ahead of the palette switch; the
    row observes `UserSettings.shared` so an open popover recolors the moment the switch flips.
    Codex bars keep their own teal / blue / amber palette: the setting is about Claude's brand
    color, and monochrome Codex rows would be indistinguishable from Claude's in two-provider
    mode. Percentages and reset times are unchanged, so how close a limit is to its cap is
    still legible from the text once the color stops escalating.
- Dead code left behind by the above: `MenuBarIconPreview` and `HorizontalRadioGroup` in
  `WelcomeSupportingViews.swift` now have no callers.
- About page: GitHub Sponsor button removed, and Buy Me A Coffee now opens `ko-fi.com/pooya`
  (was upstream's `ko-fi.com/1atte`) in both `AboutView.swift` and the two `MenuBarManager.swift`
  menu actions. The `website/` pages still carry the old ko-fi link.
- **Relicensed to Pooya Kamel.** `LICENSE` now leads with `Copyright (c) 2026 Pooya Kamel` and
  keeps f-is-h's line (MIT requires retaining it, annotated "original Usage4Claude"). About page
  Developer row reads "Pooya Kamel"; `settings.about.copyright` is "© 2026 Pooya Kamel" in all
  7 locales (a name, so not translated). The `Created by f-is-h` / `Copyright f-is-h` headers in
  Swift files stay, per the attribution rows above.
- **Version is 1.1.0** (`MARKETING_VERSION` in both configs; `CURRENT_PROJECT_VERSION` tracks it).
  This fork versions independently of upstream's 3.x line: it was reset to 1.0.0 at the fork, and
  1.1.0 is the first tagged release (`v1.1.0`, source only, no DMG or Sparkle feed entry yet).
- **Settings tab bar restyled** to the icon-toolbar shared by osx-download-manager /
  osx-launchpad: `ToolbarButton` is now glyph (18pt hierarchical, filled variants) over an 11pt
  caption, accent-tinted when selected over a 0.05 primary pill (0.035 on hover), intrinsic width
  with `minWidth: 52`, radius-9 continuous pill. Items sit centred with 2pt spacing instead of
  splitting the bar into thirds; `TabDivider.swift` deleted (no other callers). The divider under
  the bar is softened with `.overlay(Color.primary.opacity(0.03))`. The English
  `settings.tab.auth` label is now **"Account"** (was "Authentication", itself shortened from
  upstream's "Authentication Settings"), translated in all 7 locales (Konto / Compte /
  アカウント / 계정 / 账户 / 帳戶). The tab still opens the credentials sidebar; the key name
  stays `settings.tab.auth`. The settings window now carries no titlebar text at all,
  download-manager style: `titleVisibility = .hidden`, `titlebarAppearsTransparent`,
  `.fullSizeContentView` (tab bar at the very top, close button floating over its left end),
  miniaturize/zoom hidden, `isMovableByWindowBackground = true` so the window still drags. The
  `.languageChanged` observer that re-set the title is gone. `window.settings_title` says just
  "Settings" in all 7 locales but is currently unused. Tab items share one fixed 96pt width
  (fits fr "Authentification" at 11pt) so the pills line up evenly.
- **About tab rebuilt in the osx-launchpad layout** (icon 104pt, 22pt semibold name, version
  pill, grouped rounded cards of 36pt rows, tertiary copyright): an info card (Developer,
  License) and a links card (GitHub, Report Issue, Buy Me A Coffee; `settings.about.report_issue`
  is a new key, translated in all 7 locales, opening the repo's /issues) with fully tappable rows, accent arrow,
  hover underline and pointing-hand cursor. Content column capped at 420pt inside the 720pt
  window. The card/row/divider/pill pieces are private to `AboutView.swift` and copy launchpad's
  `SettingsComponents` metrics (radius 12 continuous, labelColor 0.05 fill, hairline 0.06,
  row padding 12). `AboutInfoRow.swift` in Components is now dead code.
- **SettingCard header glyphs removed** on the General tab: the card renders title only; the
  `icon`/`iconColor` parameters are still accepted but ignored so no call site changed, and the
  32pt content indent that existed to align under the glyph is gone.
- **SettingCard hint lightbulb removed.** The `hint` row was a `lightbulb.fill` glyph plus the
  text; it is now the text alone. That glyph prefixed every description on the General tab (one
  per card), so removing it in the one shared component covers all of them. The only other
  `lightbulb.fill` in the app is in `AuthSettingsView+AddAccount.swift`, which is a different
  page and deliberately untouched.
- **General tab regrouped in the osx-launchpad settings look**, via a new
  `Views/Settings/Components/SettingSection.swift`: a 13pt medium section header sitting *above*
  a rounded card (radius 12 continuous, `labelColor` 0.05 fill, no shadow), with the hint below
  it, all three aligned to one 12pt inset rather than to the card edge. Metrics copied from
  launchpad's `SettingsComponents` so this, `AboutView` and launchpad read as one system.
  `SettingSectionDivider` is the matching hairline (a plain `Rectangle` at primary 0.06, not
  `Divider()`, whose system separator draws under any overlay tint and cannot be lightened).
  - Deliberately a **new component rather than a restyle of `SettingCard`**. `SettingCard` is
    shared with the Authentication tab, whose panes follow the competitor-derived contract in
    `CredentialsChrome.swift` (in-card title plus a secondary subtitle line), so editing it would
    have dragged that layout along too. Only the four `GeneralSettings*.swift` files were
    repointed; `SettingCard` is unchanged and still used by the 5 Auth files.
  - `SettingSection` takes the same `(icon:iconColor:title:hint:content:)` signature and ignores
    `icon`/`iconColor` exactly as `SettingCard` does, so the repoint was a rename with no call
    site edits and no copy changes.
  - The in-card `Divider()` under the title is gone, because the title now sits outside the card.
  - **Controls sit at the row's trailing edge**, via `SettingRow` (title left, `Spacer`, a trailing
    ViewBuilder, optional description under the title) and `SettingToggleRow` on top of it, both in
    `SettingSection.swift`. Same shape as `SettingsRow` in osx-autoconnect and osx-launchpad, and
    what macOS System Settings does. Before this the switch sat immediately after its label, so
    four switches landed at four x positions depending on label length, leaving a ragged column
    and dead space to the right. `SettingToggleRow` owns the one switch style (`.switch`, `.small`,
    `labelsHidden`) so a screenful of toggles cannot drift into several sizes.
  - Verified on screen at the new 556 width: the four Display Settings switches line up in one
    right-hand column. This also confirmed the `SettingsView.contentSize` change actually reaches
    the window, which the earlier autosave note could not.
- **General tab content, trimmed and reordered.** All UI-only; every underlying setting is kept.
  - **Time Format card removed**, and `UserSettings` now loads `timeFormatPreference` as `.system`
    unconditionally, ignoring the stored key. Without that, an install that had 12 or 24 hour
    selected would be stuck there with no UI to change it; ignoring the key means everyone follows
    the system rather than only new installs. The enum, the property and `TimeFormatHelper` all
    stay, as do the CJK format patterns.
  - **Reset to Defaults button removed.** `UserSettings.resetToDefaults()` is kept.
  - **Launch at Login moved above Language**, and **Display Content moved to the bottom** of the
    Display Settings section. `Display Content`'s title now uses the same 13pt medium primary face
    as the toggle row titles instead of a secondary subheadline, so it reads as their peer.
    Its two checkboxes, **Show Icon** and **Show Percentage**, are 13pt **regular**, not medium:
    they are checkbox labels sitting under that heading, so at medium all three lines read as
    headings and nothing looked subordinate to anything.
  - **Removed copy**: the "Display Mode" label above the Smart/Custom radios, and the
    "Choose what to display in the menu bar" hint (`settings.general.menubar_hint`, now unused).
  - **Launch at Login's status badge only shows for `.requiresApproval`.** `.notFound` and
    `.notRegistered` are `SMAppService` registration states the switch itself already conveys, and
    a red "Not Found" next to an off switch reads as a failure rather than as "off". The other
    `statusIcon` / `statusColor` / `statusText` cases stay for that one state.
  - **The notification card's two lines are merged into one.** The card hint repeated what the row
    description said, so the specific line (`notification.description`) is now the card's hint and
    `notification.hint` is unused. That description also printed a literal **"90%%"**: the `.strings
    value carried an escaped percent for a `String(format:)` that never happens, since the row
    renders it directly. Fixed to a single `%` in the 6 locales that had it (de was already right).
  - **`opus_weekly_limit` and `detail_row.opus_weekly_limit` now read "Fable"** rather than "Opus",
    in all 7 locales, keeping each locale's own word order. ⚠️ That slot is *generic*: it carries
    whatever weekly scoped model the API returns, and the popover already prefers the live
    `opusModelName`. These two strings are only the fallback label, so hardcoding a model name will
    read wrong if the account's scoped model is ever not Fable.
    - Superseded by the "Weekly" rename below, which composes the live model name into the label
      instead of leaving a hardcoded one to go stale.
- **The weekly limit rows are named "Weekly" now, not "7-Day" or "7D Fable".** Taken from
  claude.ai's own usage panel, which reads "Weekly · all models" and "Weekly · Fable" where ours
  read "7-Day Limit" and "7D Fable Limit". The popover now shows `5-Hour Limit`,
  `Weekly All Models` and `Weekly Fable`.
  - The model row's label is **composed, not hardcoded**. New `detail_row.weekly_model` key
    ("Weekly %@" in en, real word order in the other 6) plus `L.DetailRow.weeklyModel(_:)`, fed
    the live `opusModelName` / `sonnetModelName` from the API. That is what fixes the stale-name
    trap flagged above: whatever weekly scoped model the account actually has prints correctly,
    so this does not have to be re-edited when the model changes again.
  - `seven_day_limit`, `opus_weekly_limit`, `sonnet_weekly_limit` and their three `detail_row.*`
    siblings were renamed in all 7 locales. Only the values changed; every key keeps its name, so
    no call site moved. The fallbacks now read "Weekly All Models" / "Weekly Fable" /
    "Weekly Sonnet".
  - `.sevenDay` and `.codexSecondary` share one `switch` arm in `UnifiedLimitRow.limitName`, so
    Codex's 7-day row is now "Weekly All Models" too. Its 7-day window is not model scoped
    either, so the label still holds. Split the arm if Codex ever grows a per model weekly limit.
  - `usage.seven_day_limit` and `usage.seven_day_limit_short` ("7d") are a different family
    (menu bar and settings) and deliberately still say 7-Day.
  - Verified live: the real popover reads `5-Hour Limit · 2h left  44%`,
    `Weekly All Models · 5d left  31%`, `Weekly Fable · 5d left  5%`, the third row coming
    through the composed path rather than the fallback.
  - **No middot inside a label**, which is where this diverges from claude.ai. Their row is
    "Weekly · all models"; ours already spends a middot separating the title from the countdown,
    so borrowing theirs would print "Weekly · all models · 5d left" and the two separators would
    read as one list. Title case for the same reason the other rows have it.
- **Pace-aware colours now reach the menu bar icons too.** They originally only affected the
  popover: `paceAwareBarColors` was read in exactly one render site (`UnifiedLimitRow`), so
  flipping the switch left every status icon unchanged, which looked like the setting doing nothing.
  - `MenuBarIconRenderer.colorPercentage(_:resetsAt:type:)` is the icon-side counterpart of
    `UnifiedLimitRow.colorPercentage`. Both circle renderers and both weekly shapes take a
    `colorPercentage:` parameter used **only** for the palette call (and for
    `monochromeOpacity(for:)`), so the sweep and the glyph still show actual usage.
  - `generateCacheKey` gained a `paceToken`, for the same reason as the tick below: the escalation
    figure moves with the clock rather than with the data, so a key built from percentages alone
    would serve a stale icon.
  - Worth knowing when this looks inert: the palette steps are coarse (green < 70, orange 70-90,
    red >= 90), so a projection only changes anything when it crosses one of those. And in
    Monochrome the popover bars use a fixed `UsageColorScheme.brand`, so pace cannot show there at
    all by design.
- **Time marker on the menu bar icons**, the second half of `showTimeMarker`.
  - `MenuBarIconRenderer.timeMarkerFraction(resetsAt:type:)` mirrors the popover's rule, including
    the `1 - elapsed` flip in remaining mode. nil for the Extra Usage buckets.
  - **One tick implementation for every shape**: `ShapeIconRenderer.drawRadialTimeMarker` draws a
    radial spoke crossing the border, and the circle path calls the same function.
    `ShapeIconRenderer.point(on:atFraction:)` finds where that is on a shape by walking the
    *flattened* path (it takes a fraction, not a distance, because flattening approximates the
    corner arcs and its total length is slightly under the analytic perimeter, so mixing the two
    drifts the tick). Use `path.flattened`; `bezierPathByFlatteningPath` no longer compiles.
    - The first attempt drew the tick *along* the outline with the same dash trick the progress
      stroke uses, which was tempting because the perimeter maths was already there. It gave the
      square a dash running **parallel** to its flat edge while the circles got a crossing spoke.
      Hence one shared radial implementation.
  - **Knockout, then mark.** Neither half works alone on a template icon, which keeps only alpha:
    a mark drawn over the solid sweep is invisible, and a bare gap punched in the faint 0.3-alpha
    track is invisible too. The first version punched only a gap and measured **2 differing pixels**
    against a marker-off capture, i.e. it rendered and could not be seen. Clearing a 2.6pt window
    and stroking a 1.0pt tick inside it reads against both.
  - `generateCacheKey` gained a `markerToken` per limit, quantised to whole percent (one step is
    about 3 minutes of a 5h window): the tick moves with the clock, so a key built from percentages
    alone froze it in place.
  - Verified against the countdown text on the real bar: a tick at ~3 o'clock for a 5h window a
    quarter gone, and at ~10-11 o'clock for a weekly limit reading "1d 1h left" (85%).
- **The weekly shape icons used a hardcoded `gray 0.5` track**, so on a dark menu bar their track
  read dark while the circle icons beside them resolved light. Fixed in all three shapes in
  `ShapeIconRenderer` to `UsageColorScheme.menuBarTrack(for: button)`, and their
  `NSColor.white.withAlphaComponent(0.5)` backing fill to
  `menuBarForeground(for: button).withAlphaComponent(0.10)`, matching `createCircleImage`. This is
  exactly the trap in "Menu bar icon colour modes" above: the earlier pass fixed the *glyph* in all
  four renderers but left the shapes' track and disc literal. The monochrome branches still use
  `controlTextColor` alphas, which is correct for a template.
- **Pace-aware bar colours: `paceAwareBarColors`.** New `UserSettings` flag (default off, key
  `paceAwareBarColors`, posts `.settingsChanged`), surfaced as a **Pace-Aware Bar Colors** switch
  in the Display Settings section. Ported from the competitor's `appearance.pace_coloring_*`.
  New keys `display.pace_aware_colors` / `_desc` in all 7 locales plus `L.Display.paceAwareColors`
  / `paceAwareColorsDesc`.
  - `Helpers/UsagePaceCalculator.swift` holds the maths, taking primitives rather than the app's
    models so it stays pure. `projectedPercentage = used / elapsedFraction`, clamped to 100.
    Window lengths: 5h for session and `codexPrimary`, 7d for `sevenDay` / `opusWeekly` /
    `sonnetWeekly` / `codexSecondary`, and **nil for both Extra Usage buckets**, which have no
    fixed window to project across and so keep colouring on current usage.
  - Returns nil (callers fall back to the current percentage) when there is nothing sane to
    project from: no usage yet, no reset time, the reset already in the past, a reset further out
    than one whole window, or **under 15% of the window elapsed**. That last gate is the
    important one: one request divided by a tiny elapsed fraction extrapolates to an absurd
    figure and would paint a fresh window red seconds in. Threshold matches the competitor's.
  - Wired through `UnifiedLimitRow.colorPercentage`, which feeds the existing per-limit palette
    functions the projected figure instead of the current one, so **only the colour changes
    meaning**: the displayed number and the bar fill still show actual usage. New
    `resetsAtValue` resolves the row's reset time per limit type (both Claude and Codex
    `LimitData` spell it `resetsAt`).
  - Verified by compiling the real helper against a stub `LimitType` and asserting 10 cases:
    40% used at 50% elapsed projects 80; the same 40% at 20% elapsed clamps to 100; 10% at 50%
    elapsed projects 20; a 7d limit at 3.5d remaining projects 60 (so the weekly window is not
    being measured with the 5h one); and the gated/nil cases above all return nil.
- **Time marker: `showTimeMarker`.** New `UserSettings` flag (default off, key `showTimeMarker`,
  posts `.settingsChanged`), surfaced as a **Show Time Marker** switch in the Display Settings
  section. Ported from the competitor's `appearance.show_time_marker_*`. New keys
  `display.show_time_marker` / `_desc` in all 7 locales plus `L.Display.showTimeMarker` /
  `showTimeMarkerDesc`. Popover only so far; the menu bar icons are the next step.
  - A tick drawn across the bar at the point the *period* has reached, so usage can be read
    against how much of the window is gone: 7% used at 17% elapsed is a very different story from
    7% used at 90%, and the bare percentage cannot tell them apart.
  - `UsageLimitBar` gained `markerFraction: CGFloat?` (nil hides it) and draws a 1.5pt
    `labelColor` 0.55 capsule the full height of the bar, over both the fill and the track:
    `labelColor` resolves near-black on a light backdrop and white on a dark one, so it stays
    legible against either and on top of the saturated fill. The x is inset by half the tick so
    it sits fully inside the capsule at 0% and 100% instead of half-hanging off the rounded ends.
  - `UnifiedLimitRow.markerFraction` computes it, reusing `UsagePaceCalculator.windowDuration`
    and `elapsedFraction` (which is why that helper's elapsed maths is separate from the
    projection). nil for the Extra Usage buckets, which have no window to measure.
  - **Mirrored to `1 - elapsed` when `showRemainingPercentage` is on**, because the fill is
    mirrored too. Leaving it un-mirrored would put the tick on the opposite side of the fill from
    where the comparison it exists to support actually lies. This is the one detail worth
    preserving if this code is ever reworked.
  - Verified live against the countdown text, which is the useful check because it ties the tick
    to something independently readable: with "4h 8m left" of a 5h window (17.3% elapsed) the
    tick measured at 17.2% of the bar, and with "1d 1h left" of 7d (85.1%) it measured at 84.5%.
- **Bar and icon colour is one three way choice now, not two overlapping switches.** New
  `Helpers/UsagePaceStatus.swift` carries the pace ramp; the General tab's Display Settings card
  offers a segmented **Color By** picker with **Type** / **Usage** / **Monochrome**.
  - The three are mutually exclusive (a bar has exactly one colour source) but used to be two
    independent toggles, and Monochrome silently won over Pace-Aware in every renderer, so a user
    could switch pace colours on, see nothing change, and have no way to tell why. A picker makes
    the exclusivity the control's own shape.
  - `ColorMode` in `GeneralSettingsDisplaySection` is **derived** from the two stored settings
    (`iconStyleMode` + `paceAwareBarColors`) rather than stored itself, so nothing had to migrate.
    Selecting Monochrome deliberately leaves `paceAwareBarColors` as it was: switching to
    Monochrome and back should not silently forget that the user wanted pace colours.
  - The card shows only the **selected** mode's description, not all three, so it explains the
    current choice instead of leaving the reader to work out which line applies.
  - Labels went through Status (rejected: describes all three), Limit Type and Type before landing
    on **Limit / Usage / Monochrome**. 7 new `display.color_mode*` keys, really translated in all 7
    locales. "Type" said nothing on its own next to "Usage": the axis is *which limit* a bar is
    versus *how fast* it is being spent, so the first segment names the limit. Only the
    `display.color_mode_type` value changed (Limit / Limit / Limite / 上限 / 한도 / 限额 / 限額);
    the key, `L.Display.colorModeType` and the `ColorMode.limitType` case all keep their names.
  - **The first segment is now Category** (Category / Kategorie / Catégorie / カテゴリ / 카테고리 /
    类别 / 類別), for the same reason "Type" was rejected: it names the axis rather than the thing.
    Key, `L.Display.colorModeType` and `ColorMode.limitType` still unchanged.
  - **Its description was stale and said the opposite of what the mode does.** It still read
    "Each limit keeps its own color, deepening as it approaches its cap", written before the
    per-limit palettes were flattened to `UsageColorScheme.flatPercentage`. Nothing deepens in
    this mode any more, so `display.color_mode_type_desc` now says the colour only names which
    limit a bar is, in all 7 locales.
- **The Usage mode's ramp: blue, amber, red on the percentage actually used.** Under 70%
  `systemBlue`, 70-90% **#F3B63F**, 90% or more **#C54A41**. The ramp only escalates.
  - **It reads the plain number, not a pace projection.** This is what claude.ai's own usage bars
    do (78% used is amber there, 93% used is red), and matching them is the whole point: the app
    and the web should not disagree about the colour of the same percentage.
  - **The projection it replaced coloured by rate, not amount**, `used / elapsedFraction`
    extrapolated to the end of the window. It read as a bug in exactly the case it was meant to
    help: 9% used a quarter hour into a five hour window projects to 180% of cap, so a barely
    started window went red. Raising the gate (3% to 15% elapsed) narrowed that but did not fix
    the mismatch with the web, so the projection came out of the colour path entirely.
  - `UsagePaceStatus.color(usedPercentage:resetsAt:type:)` is still the single entry point both
    the popover bars and the menu bar icons call, so the two cannot disagree. It now just forwards
    to `level(usedPercentage:)`. `resetsAt` and `type` stay in the signature (defaulted to nil)
    because every caller passes them and a window-aware mode may want them back.
  - Now dead in the colour path, kept because the time marker still uses the elapsed maths:
    `UsagePaceStatus.calculate`, `UsagePaceStatus.minimumElapsedFraction`, and
    `UsagePaceCalculator.projectedPercentage`. `UsagePaceCalculator.elapsedFraction` and
    `windowDuration` are still live, via `UnifiedLimitRow.rawElapsedFraction`.
  - The 70/90 breakpoints match what the per-limit palette functions already escalate on, so
    switching modes changes *which* colour a limit shows, not when it starts worrying.
  - Applies to the popover bars (`UnifiedLimitRow.barColor`, this beats the palette) **and the
    menu bar icons**. The icons were the whole point of the exercise and were missed on the first
    pass: `MenuBarIconRenderer.paceColor` plus a `paceColor:` override threaded through
    `createCircleImage` and both `ShapeIconRenderer` draw functions, so a limit that is orange in
    the popover is orange in the menu bar.
  - `MenuBarUI.generateCacheKey`'s pace token keys on the ramp **step**, not a figure.
  - **The time marker tick was deliberately left alone.** An earlier pass wired this ramp into the
    tick instead of the fill, which meant the setting did nothing unless `showTimeMarker` was
    also on. Wrong feature: the setting is about bar colours. The tick stays the neutral
    `labelColor` line it has always been.
  - **The amber and the red are sampled off claude.ai's own usage bars**, not chosen: #F3B63F at
    78% used and #C54A41 at 93% used, read pixel by pixel off two reference screenshots. The
    healthy step stays `systemBlue` because neither reference bar was under 70%, so there was
    nothing to sample. Swap it for a green only with a real sample.
  - **The track is tinted to match the fill in the popover**, the way claude.ai draws it: #F6DDAA
    behind amber, #F6D8D7 behind red, both sampled. They are their own tokens, **not** the fill
    composited over white at some alpha, which lands on #F6C8xx rather than #F6DDAA, so do not
    try to derive one from the other. `UsageLimitBar.trackColor` is the new optional; nil keeps
    the neutral `Color.primary.opacity(0.10)`, so Category and Monochrome are untouched.
    - Those samples are from a light background. On a dark popover they would read as near-white
      bars, so `UsagePaceStatus.trackNSColor` is a dynamic `NSColor` whose dark side is the fill
      at 0.28 alpha instead.
    - **The menu bar ring track deliberately stays the neutral adaptive grey**
      (`UsageColorScheme.menuBarTrack`). A pale cream ring on a light menu bar is invisible, and
      the bar's appearance is probed per display, which a colour sampled from one light web page
      cannot follow. The icon *fills* do take the sampled amber and red, via `paceColor`.
  - `MenuBarIconRenderer.colorPercentage` no longer projects either; in Usage mode it returns the
    figure itself, so the icon palette path and the ramp cannot disagree.
- **Limit colour mode is flat now: the per-limit palettes no longer escalate with usage.** A
  weekly limit crossing 70% used to darken its own identity colour on its own (light purple
  `#C084FC` to deep purple `#B450F0`, then `#B41EA0` at 90%), and the same step existed in all
  eight palettes. That escalation is upstream's, and the Color By picker was layered on top of it
  without removing it, so **Limit** and **Usage** both encoded usage and only the palette differed.
  Limit mode now says *which* limit a bar is and nothing else; the number, the fill and the
  countdown carry how full it is.
  - `UsageColorScheme.flatPercentage` (0) is the single knob. Every palette's safe step already
    *is* that limit's identity colour, so asking for 0 returns it without a second set of hex
    values that could drift from the first. Do not add one.
  - Render sites repointed: `UnifiedLimitRow.barColor` (popover), `createCircleImage`'s
    `escalationPercentage` and the Codex branches in `MenuBarIconRenderer`, and the three
    `ShapeIconRenderer` draws. `UnifiedLimitRow.colorPercentage` became dead and was deleted;
    `MenuBarIconRenderer.colorPercentage` stays and now returns `flatPercentage` when pace is off,
    which is what makes the icons and the bars flat-line together.
  - Escalation survives in the other two modes only, which is the whole point of the picker:
    the blue / orange / red pace ramp in **Usage**, and `ShapeIconRenderer.monochromeOpacity` in
    **Monochrome**.
  - Both Extra Usage buckets are hardcoded to `flatPercentage`. They have no fixed window, so the
    pace projection was never available to them and there is nothing to escalate on.
  - `monochromeOpacity` now reads the actual `percentage` in all three shapes. Two of them read
    `escalationPercentage`, so with Monochrome selected while `paceAwareBarColors` was still
    stored true (the picker deliberately preserves it) the projection leaked into the opacity of
    a mode that is not supposed to see it. The hexagon already did this correctly.
  - Verified live on the real bar: a 71% weekly reads light purple, the same colour it showed at
    69%, instead of stepping to deep purple.

- **Cmd+, opens the real settings window.** `UsageMeterApp`'s body is a placeholder
  `Settings { EmptyView() }` scene, and its default Cmd+, command opened that as a blank
  "Usage Meter Settings" window. `.commands { CommandGroup(replacing: .appSettings) }` now routes
  the shortcut to `AppDelegate.openSettingsWindow()` -> `MenuBarManager.openSettings()`.
  Verified: Cmd+, brings up only the 556x632 settings window.
- **No Codex brand icon between the groups in the menu bar.** With Show Icon on and both
  providers present, `createMultiProviderIcon` now separates Claude's and Codex's rings with the
  same divider that percentage only mode uses, instead of the `CodexIcon` clock artwork. The
  Claude app icon still leads the bar. The Codex brand still shows in the Codex only layout,
  where nothing else would say whose rings they are.
- **The limit type checkboxes are real checkboxes now.** `LimitTypeCheckbox` was a plain `Button`
  drawing `checkmark.square.fill` / `square` SF Symbols: recognisable but not an AppKit checkbox,
  so it had the wrong box size, corner radius and blue, no focus ring, no mixed state and none of
  the system's disabled or accent handling, while every other checkbox on the page was a real
  `Toggle(.checkbox)`. Now it is one too, with the limit's shape glyph and name as its label.
- **Display Options: the checkbox list keeps the recovered welcome screen placement, the labels
  around it are gone.** From upstream's setup step (`48850a8^`,
  `reference/Usage4Claude/.../SetupStepView.swift`), what survives is the list sitting indented
  under the radio that reveals it, behind its own caption-weight `welcome.select_limits` heading.
  - **Removed: the fixed 100pt "Display Mode:" label and the blue `info.circle.fill` description
    row.** Both were restored from the original and then cut: the card header already says Display
    Options, the two radios name themselves, and the description duplicated the card's `hint`.
    `L.DisplayOptions.displayModeLabel` is unused again but kept.
  - The constraint hints and the menu bar switch sit below, outside the radio block, so a long hint
    gets the card's full width.
  - The list stays **one checkbox per line**. A wrapped 3-per-row grid from the same original was
    tried and reverted: three to a row puts one column's checkbox right beside the previous
    column's *label*, so the boxes stop forming a single scannable edge and each row reads as one
    run-on line. Do not re-flow this.
- **The custom limit list is grouped by provider**, Claude then Codex, each under its brand mark
  (`ClaudeMark` / `CodexMark` at 12pt) and a caption-weight name, the same grouping as the Account
  sidebar. Grouping comes from `LimitType.provider`, so a new limit type lands in the right group
  with no list to maintain.
  The two groups sit **side by side as two columns** (Claude left, Codex right, top aligned,
  each column `maxWidth: .infinity` so Codex starts at a fixed x). Each column is still one
  checkbox per line, so the single-edge rule below holds within a column.
  Extra Usage sorts **last** in each column (`limitTypes(for:)`), after the windowed limits.
  Sorted in the view, not by reordering `LimitType`, so menu bar and popover order are unchanged.
  Codex rows drop the "Codex" prefix the heading already says: the checkbox uses the new
  `LimitType.groupedName`, which maps the three Codex types to Claude's labels (5-Hour Limit,
  Weekly All Models, Extra Usage, same as the popover). Notifications still use `displayName`. The two provider headings replace the single "Select Limits" caption;
  `L.Welcome.selectLimits` is now unused here but kept. Names are brands, so not localized.
- **The Color By picker sits in a `SettingRow`**, label left and segments right with the
  description underneath, the same shape as every switch in that card. Stacked full width under
  its own heading it read as a different kind of setting from its neighbours and left the row's
  right half empty. `.fixedSize()` on the picker, or the three segments stretch across that half.
- **The custom limit list lost its `Divider()` and its "Select Limit Types to Display" heading.**
  The list only ever appears directly under the radio that reveals it, so the radio already names
  it. That radio is now **Custom Limit Type Display** (was "Custom Display"), translated in all 7
  locales. `L.DisplayOptions.selectLimitTypes` and its key are now unused but kept.
- **Battery style display: `showRemainingPercentage`.** New `UserSettings` flag (default off,
  key `showRemainingPercentage`, posts `.settingsChanged`), surfaced as a **Show Remaining**
  switch in the Display Settings card with the description "Display remaining capacity instead
  of used percentage (like macOS battery)". Ported from the competitor's
  `appearance.show_remaining_*` setting. New keys `display.show_remaining` and
  `display.show_remaining_desc` in all 7 locales, plus `L.Display.showRemaining` /
  `showRemainingDesc`.
  - `UsagePercentDisplay.displayPercentage(_:)` / `displayFraction(_:)` in
    `UsageRowComponents.swift` are the single place the flip happens: they return `100 - used`
    when the flag is on. Every number and every fill routes through them, so there is one
    inversion point rather than one per renderer.
  - **Status colours deliberately stay keyed off the used percentage**, in all four renderers.
    Escalation has to keep meaning "close to the limit"; inverting the colour too would make a
    nearly exhausted limit render green. `monochromeOpacity(for:)` likewise still takes `used`.
  - Applied in the popover rows (`UsageLimitBarRow`: both the trailing "NN% · <countdown>" text
    and the bar fill) and in all four menu bar icon renderers: `createCircleImage` and
    `createCircleTemplateImage` in `MenuBarIconRenderer.swift`, and the rounded square, diamond
    and hexagon draws in `ShapeIconRenderer.swift`. Each shape's sweep length, its
    `>= 100` butt/round cap and font-size branches, its `> 0` draw guard and its glyph all read
    the display value; only the colour calls still read `used`.
  - `MenuBarUI.generateCacheKey` gained a `_rem` component. The flag changes the rendered image
    without changing any percentage in the data, so without it the cache would serve the old
    icon after a toggle.
  - `UsageLimitBarRow` observes `UserSettings.shared` so an open popover re-renders on toggle.
  - Verified live on the real menu bar: used mode drew 83 / 65 / 52, remaining mode drew
    17 / 35 / 48 (exact complements) with shorter sweeps and unchanged colours.
- The Display Settings card's hint (`menubarHint`, "Choose what to display in the menu bar") is
  now rendered inline under the Display Content checkboxes instead of in the card's `hint` slot.
  `SettingCard` always renders its hint last, so once Show Remaining was appended to the card
  that line fell underneath the new switch and read as if it described it.
- **Sparkle updates are live again.** `SUPublicEDKey` in `Config/Info.plist` is now this
  machine's own Sparkle keypair (public `XPeIzL4GHFXBMLCP+A/vxqQE4Bn8tGi7jkw9sRBHXSc=`, private
  key in the login Keychain, shared with the other osx-* apps; `generate_keys -p` prints it).
  `appcast.xml` dropped upstream's six 3.x items, whose DMGs do not exist under this repo and
  whose signatures were f-is-h's; the channel is valid but empty until the first v1.x release is
  cut per `docs/SPARKLE_SETUP.md` (sign_update lives in the SPM artifact,
  `SourcePackages/artifacts/sparkle/Sparkle/bin/`). Check for Updates re-enabled in
  `MenuBarUI.createStandardMenu`. ⚠️ Until the cleaned appcast is pushed to main, the raw
  feed URL still serves the old committed appcast listing v3.3.0, which the new public key
  would refuse anyway; push before testing an update check.
- **History tab in Settings** (tab index 2; About moved to 3 in `SettingsView` and both
  `MenuBarManager` deep links, `openAbout` and `.about`). First slice of differentiator #1.
  Ported from the competitor's Usage History (`_sample/`, MIT, user-approved):
  - `Views/Settings/Tabs/HistorySettingsView.swift` draws session (solid accent, gradient area)
    and weekly (dashed indigo) as Swift Charts step lines (`.stepEnd`) on one 0-100 axis over a
    5h / 24h / 7d / 30d window, pageable by half a window per chevron with a Now snap-back;
    below it an API Billing bar chart of Console spend samples. First `import Charts` in the
    app; fine on the macOS 13.0 deployment target.
  - `UsageHistoryStore` (Services) records a `UsageSnapshot` (Models/UsageHistory.swift:
    session, weekly and per-model percentages; per-model recorded but not charted yet) on every
    successful Claude fetch, hooked at both DataRefreshManager success paths, throttled inside
    the store to one per 5 min; and a `BillingSnapshot` after every successful Console
    `current_spend` fetch (hook in `ConsoleAPIService.refresh`), one per hour. Retention 90
    days, pruned on save.
  - Storage is `~/Library/Application Support/UsageMeter/usageHistory.json`, deliberately not
    UserDefaults: the competitor's issue #260 showed multi-MB history blobs blow the 4 MB
    CFPreferences domain limit and CFPreferences then silently drops ALL writes to the domain,
    credentials included.
  - `UsageHistoryStore.swift` needs `import Combine`. It declares `ObservableObject` plus an
    `@Published`, and `import Foundation` alone does not re-export those, so the file failed to
    compile with "does not conform to protocol 'ObservableObject'" and "initializer
    'init(wrappedValue:)' is not available due to missing import of defining module 'Combine'".
  - 14 new keys (`settings.tab.history`, `history.*`) with real translations in all 7 locales.
    The window range label is a localized "%1$@ to %2$@" format (bis/à/〜/~/至), not the
    competitor's spaced en dash.
  - Competitor bugs deliberately not carried over: zero-param `onChange` (macOS 14 only, we
    target 13, use the one-param form), duplicated billing chart title, hardcoded `$` on the
    billing y axis (non-USD now shows the ISO code), legend dashes knocked out with
    `controlBackgroundColor` (drawn as positive marks instead), and forward paging that could
    overshoot past "now" (clamped with `min(..., 0)`).
  - Verified live by seeding a synthetic 24 h `usageHistory.json`, driving the window open via
    lldb (`postNotificationName:@"openSettings" userInfo:@{@"tab": @2}`; the status item popover
    is invisible to AX scripting) and screenshotting. Synthetic file then deleted along with the
    `usageHistory.lastRecordedAt` / `lastBillingRecordedAt` throttle keys; on the clean
    relaunch the store recorded its first real snapshot within seconds.

Deliberately **not** translated, because doing so breaks non-English locales:

- CJK date format patterns in `TimeFormatHelper.swift` and `UsageData+Formatting.swift`
  (`"M月d日"`, `"H时"`, `"H時"`, `"M월d일"`). These are format strings, not copy.
- The zh/ja/ko AM/PM marker list used for parsing in `TimeFormatHelper.swift`.
- Localized documentation URL anchors in `SetupStepView.swift` (`#首次配置` and friends).
- ~~`error.contains("认证")` in `UsageDetailView.swift`~~ removed. Classifying by error string
  was the bug described above; the popover now checks `hasValidCredentials` instead.
- `zh-Hans.lproj` / `zh-Hant.lproj`, and the language endonyms (`日本語`, `中文（简体）`) that
  every locale file carries. Those are correct as they are.
- The doc-comment `- Returns:` / `- Examples:` lines in `TimeFormatHelper.swift` and
  `UsageData+Formatting.swift` that quote sample output of those CJK patterns (`"12月16日 15:42"`,
  `"15时"`). The prose around them is English; the quoted samples have to match what the formatter
  actually prints, so translating them would make the doc comment wrong.

All Chinese code comments and doc comments are now English: 2,573 line comments across 94 Swift
files (including the two tests-only files), plus the `/* */` block holding the alternative colour
schemes in `ColorScheme.swift`, the OSLog levels doc block in `LoggerExtension.swift`, and the one
Chinese `XCTAssert` message in `NotificationDecisionEngineTests.swift`. Translated by extracting
every unique comment payload (2,366 of them), translating each once, and rewriting only the comment
side of each line, so string literals could not be touched by accident. Verified with a CJK sweep
over `UsageMeter/` and `Tests/`: the only characters left are the ones listed above as deliberately
kept. `swift test` still passes 128/128.

Still upstream's, still Chinese: `scripts/build.sh` and parts of `README.md`, `CHANGELOG.md`,
`docs/`, and `website/`.

## Keychain prompt on every poll

Symptom: the Keychain password prompt appears while nobody is touching the app, sometimes hourly,
just to refresh a menu bar percentage.

Cause, in two halves:

1. Reading a Keychain item another app created needs an ACL grant, and `fetchCLISyncedUsage`
   read Claude Code's `Claude Code-credentials` item on **every poll** (60s active, 5-10 min idle).
2. Clicking "Always Allow" adds this app to that item's ACL, but the grant does not survive.
   Claude Code rewrites its own item whenever it rotates a token, and a rewrite resets the ACL.

Measured on this machine 2026-08-29: that item's ACL held **108 application entries, 102 of them
dead `cdhash` requirements** (`status -2147415734`, `errSecCSNoMatch`), one per ad hoc signed build
ever granted before the signing fix. The correct identity based entry was present but sat among
102 failing checks. Signing correctly (see "Gotchas") is necessary but was never sufficient: it
stops *new* debris, it does not stop the CLI's rewrites from clearing the grant.

Fix: **stop reading their item on the hot path.** `Services/ClaudeTokenMirror.swift` keeps our own
copy of the tokens in a Keychain item this app creates, service
`in.pooya.usagemeter.tokens`. An item we create has us in its ACL from birth and no other
process rewrites it, so reading it never prompts. Verified: its ACL has exactly **one** application
entry, `(OK)`, against Claude Code's 108.

The poll path in `ClaudeAPIService` is now:

- `ClaudeTokenMirror.load()` first. Usable access token, use it. This is the common case and it
  touches only our own item.
- Expired: refresh from the **mirror's own** refresh token, still without reading Claude Code's
  item, then update both our item and theirs.
- Only when that refresh fails do we fall back to `fetchUsingCLIKeychain`, which reads Claude
  Code's entry (and may prompt once) and re-mirrors. That means the user signed out and back in on
  the CLI, which is rare.

Things to keep, or the prompt comes back:

- **The write-back to Claude Code's item stays mandatory.** A refresh token is single use, so once
  we spend it their copy is dead and the user gets logged out of their own terminal. Writing does
  not prompt; only reading does. `writeBackByService` exists because the mirrored path holds only
  the origin service and account names, not a full `ClaudeCodeCredentials`.
- **`ClaudeTokenMirror` deliberately does not go through `KeychainManager`.** That class swaps in a
  plaintext `UserDefaults` backend under `#if DEBUG`, which is fine for an org id and not for a
  live OAuth token. The mirror writes to the real Keychain in every configuration.
- `removeSync()` calls `ClaudeTokenMirror.clear()`, or the mirror keeps serving polls for an
  account the user just removed.

Still worth doing by hand: the 102 stale `cdhash` entries on Claude Code's item are inert but
untidy. Pruning them needs the Keychain password (Keychain Access > that item > Access Control),
and nothing in the app depends on it now that the hot path avoids that item entirely.

## Menu bar icon colour modes

Two modes, and one rule that explains every bug here:

| Mode | Flag | What AppKit does |
|---|---|---|
| Monochrome | `image.isTemplate = true` | **Discards RGB, keeps alpha.** AppKit re-tints to match the bar. |
| Colour | `isTemplate = false` | **Every colour is literal.** You own all contrast. |

Upstream drew both modes with the same hardcoded colours, so monochrome looked correct by
accident while colour mode rendered the literal values: a black glyph (the unreadable dark "0"
on a dark bar), a `gray 0.5` track ring (the stray grey border) and a `white 0.5` backing disc
(the milky wash). Monochrome was not working, it was hiding the bug.

- `UsageColorScheme.menuBarForeground(for:)` / `menuBarTrack(for:)` resolve white on a dark bar
  and near-black on a light one. Use them for every glyph, track and disc in colour mode.
- Probe appearance from `button.effectiveAppearance.bestMatch(from:)`, never `NSApp`. The bar
  goes dark under a dark desktop picture even in light mode. `UsageColorScheme.isDarkMode(for:)`
  already does this; pass the `NSStatusBarButton` through.
- Dynamic colours (`labelColor`, `secondaryLabelColor`) resolve against whatever appearance is
  current inside `lockFocus()`, which is the app's, not the bar's. Resolve explicitly instead.
- The same glyph bug existed four times: `MenuBarIconRenderer.createCircleImage` plus the
  rounded-square, diamond and hexagon shapes in `ShapeIconRenderer`. Each adapted its stroke
  correctly and then drew its number in `NSColor.black`.
- `createCircleTemplateImage` still draws black on purpose. It is a template, so only alpha
  survives. Do not "fix" it.

The competing app (`HamedElfayome.Claude-Usage`, MIT) sidesteps the problem differently: it
fills the shape with the saturated status colour and knocks the glyph out in white, so contrast
comes from its own fill rather than the backdrop. Its setting is a single `Monochrome` toggle
subtitled "Use adaptive color instead of status colors (green/orange/red)". Full write-up in the
`menubar-icon-theming` skill.

### Per-display appearance (two monitors, opposite wallpapers)

Each display's menu bar picks its own appearance from the wallpaper behind it, so a colour icon
whose greys were resolved against one bar renders wrong on the other monitor. Template icons
never had the problem (AppKit re-tints and also dims them per bar); `button.effectiveAppearance`
is a single value, so probe-then-recolour can only ever match one display. Fixed 2026-08-21 and
verified live in both directions (light bar active with dark bar dimmed, and the reverse).

Everything lives in `MenuBarPerDisplayIcon.swift` plus the colour path of
`MenuBarUI.updateMenuBarIcon`:

- The icon is a dynamic image, `NSImage(size:flipped:drawingHandler:)`. The handler runs once
  per bar appearance (NSImage caches variants per appearance since 10.14), reads
  `NSAppearance.currentDrawing()` (the Swift spelling; `currentDrawingAppearance` does not
  compile), pins `UsageColorScheme.drawingIsDarkOverride` (Method 0 in `isDarkMode(for:)`, wins
  over the button probe) and re-renders, so tonal parts resolve per display while accent
  colours stay literal. The render closure passes `button: nil` and captures `iconRenderer`,
  not `self`. A probe render fixes the wrapper's size up front (geometry is
  appearance-independent).
- Inactive-bar dimming happens inside the same handler. macOS dims menu bar items on the
  inactive display's bar, but only through the template tint (measured live with lldb:
  `appearsDisabled` is NO on every button, every window's alpha is 1), so colour icons must
  dim themselves. The active display comes from private SkyLight,
  `SLSCopyActiveMenuBarDisplayIdentifier(SLSMainConnectionID())`, dlsym'd and runtime-guarded
  (unavailable = full brightness everywhere). The handler maps the appearance it is drawing
  for back to the bars that have it: when every such bar is inactive, the draw is dimmed to
  `inactiveDimAlpha` (0.45). When both bars share one appearance the mapping is ambiguous and
  nothing dims; full brightness is the safe wrong answer.
- The dim state is baked into the per-appearance cached variant, so `refreshDimIfNeeded()`
  rebuilds the wrapper (a new NSImage instance, one write to the main button) whenever the
  active-display UUID changes. Watchers: a 2s heartbeat (no event fires when focus moves
  between displays within one app; the check is one string compare), the undocumented
  `NSWorkspaceActiveDisplayDidChangeNotification`, `didActivateApplicationNotification`,
  `activeSpaceDidChangeNotification`, and `didChangeScreenParametersNotification`.
- Colour icons bypass the icon cache (wrapper creation is free, rendering is lazy per draw);
  only template icons are cached. Template mode needs none of this, AppKit tints and dims
  templates per bar natively.

Dim status as of 2026-08-21 night: colours per display are solid and verified in both focus
directions. The dim is solid on the bar hosting the real item; on the replicant bar it only
takes effect when macOS re-snapshots the item, because a replicant's bitmap refreshes ONLY at
item (re)creation. Verified immune to: image reassignment, length nudges,
contentView.setNeedsDisplay, pixel-changing beacons, 28s waits. Current levers: the dim
decision is anchored on the main window only (replicant windows lie: zero frames, nil screens
mid-lifecycle, a phantom third per-Space window), and `refreshDimIfNeeded` blips
`statusItem.isVisible` off/on (public API, rate-limited to one per 5s) on focus-display change
to force a re-snapshot. OPEN ISSUE: the launch-time snapshot of the secondary bar still
sometimes renders undimmed; if the blip proves insufficient, the next lever is blipping at
first-data rather than only on flips.

Hard-won negative knowledge. Do not retry these:

- **Writing images into the replicant status bar windows** (the private
  `NSStatusItemReplicant` machinery; the app hosts one `NSStatusBarWindow` per display and
  per Space, all in `NSApp.windows`) works briefly, then AppKit recreates and re-syncs those
  windows behind us, and repeated writes make Control Center pull the item from EVERY bar
  while `menubar-fix.sh list` still says allowed. `killall ControlCenter` brings it back
  instantly. The bar windows also report a bogus `windowNumber` (0x100000000), they are not
  really ours to drive.
- **`SLSSetWindowAlpha` on those windows**: same vanish, same heal.
- `nm -gU` on SkyLight finds nothing because the binary lives in the dyld shared cache; probe
  with `dlopen`/`dlsym` (that is how `SLSCopyActiveMenuBarDisplayIdentifier` was verified).
- Item exists with a valid image but invisible on every bar = Control Center suppression, not
  a rendering bug. Heal with `killall ControlCenter`; rule out the blocklist with the
  `menubar-fix` skill.

## Centring an NSWindow around SwiftUI

`welcomeWindow.center()` does not work here and neither does `setContentSize` before it. A
SwiftUI fixed `.frame` reaches the window through Auto Layout **after** the creating method
returns, so `center()` runs against the pre-layout intrinsic size (518x664 for this view), then
the window shrinks to its real size from the top-left and keeps the wrong origin. The result
was 146pt too high.

Things that did **not** fix it: `setContentSize` then `center()`, `hostingController.sizingOptions = []`,
and `contentView?.layoutSubtreeIfNeeded()` before `center()`.

What works is skipping `center()` and setting size and position in one `setFrame`, computed from
a size known up front:

- `WelcomeView.contentSize` is the single source of truth, used by both the view's `.frame` and
  the window. If those two disagree the centring is wrong again.
- `frameRect(forContentRect:)` converts content size to frame size (title bar included).
- Centre horizontally on `screen.frame` for true optical centre, vertically on
  `screen.visibleFrame` so the menu bar does not bias it upward.

Beware when verifying: with a right-hand Dock, centring a 518pt-wide window on the full screen
and centring a 460pt-wide one in `visibleFrame` land within 2pt of each other, so three
different wrong fixes all produced byte-identical coordinates. Measure with
`CGWindowListCopyWindowInfo` and compare against `(screen.width - window.width) / 2`.

## Conventions

- Swift 6 + SwiftUI, AppKit `NSStatusItem` for the menu bar. Deployment target is macOS 13.0
  (upstream's), project setting 26.0. The CLAUDE.md goal of "macOS 14 minimum" is not what the
  project file currently says.
- Upstream code comments are in Chinese. When editing their files, match the surrounding style.
- `LSUIElement` true. No Dock icon, no main window.
- App Sandbox off, deliberately, so CLI Account Sync can read Claude Code's Keychain entry.
  See "Fork status". Do not re-enable it without removing that feature first.
- MIT license.
- No telemetry, no analytics, no account, no network calls except `api.anthropic.com`.
- Never write, log, or display the access token. Read from Keychain at point of use only.
  Known violation to fix: the app persists the account's session key in plain UserDefaults
  under `DEBUG_accounts` (seen 2026-08-21 via `defaults read`). It belongs in the Keychain.
  The CLI Account settings card shows a masked token only (`ClaudeCodeCredentials.maskedAccessToken`),
  and there is deliberately no reveal or copy affordance for it.
- Never bundle an API key or ship credentials.
- No em dashes in any UI copy, comments, commits, or docs.

## App icon

An Icon Composer bundle (Xcode 26 native format). **Artwork replaced 2026-10-04 for the Usage
Meter rename**: a black speedometer gauge on a white squircle, glyph `Union.png` at scale 0.8,
white `fill-specializations` for dark and tinted. The bundle is Pooya's own Icon Composer export,
copied in as-is (the 2026-08-22 pixel invader and `Assets/appicon.svg` are superseded).
Re-imported the same day from a newer export; the only change was the layer name (`shape`),
and the regenerated `AppIcon.appiconset` and `AppIconReverse` came out pixel-identical.
The menu bar glyph (`AppIconReverse`, template) comes from `Assets/tray.svg`, the same gauge,
rendered with the recipe below. It only shows when Display Content has Show Icon ticked; this
machine was on percentage only. Note
`UsageColorScheme.brand` (#D97757) is unrelated code and still the login CTA / monochrome bar
colour.

Two distinct assets, and both have to be updated or the logo changes in half the app:

1. **`UsageMeter/Resources/appicon.icon`** is the real app icon: Finder, Get Info, Spotlight,
   notification banners, the DMG. `LSUIElement` is true so there is no Dock icon.
   - `icon.json` config: solid white fill, neutral shadow at 0.5, translucency 0.5. Glyph
     scaled 0.8, no translation.
     Squares shared across platforms, circles for watchOS. White solid `fill-specializations`
     for dark and tinted.
   - Wired via `ASSETCATALOG_COMPILER_APPICON_NAME = appicon` in both build configs. The name
     is lowercase `appicon`, **not** `AppIcon`, because the inherited asset catalog already has
     an `AppIcon` image set (see below) and two assets cannot share a name.
   - `actool` emits `CFBundleIconName` and `CFBundleIconFile` into the partial plist, so never
     hand-write those keys in `Info.plist`.
   - The `.icon` lives inside the `UsageMeter/` folder because the Xcode target uses a
     `PBXFileSystemSynchronizedRootGroup`, so anything dropped there is compiled automatically.

2. **`UsageMeter/Resources/Assets.xcassets/AppIcon.appiconset`** is the *in-app* logo. It
   appears in the login window, the popover header, About, account rows, and the colour menu
   bar theme. Changing only the `.icon` leaves this one stale, which is exactly the bug that
   shipped once already.
   - **`NSImage(named: "AppIcon")` always returns nil.** An `.appiconset` is compiled as icon
     data, never as a named image, so every call site silently fell back to a placeholder: a
     blue `chart.pie.fill` in the popover header, a plain circle for the colour menu bar theme,
     and nothing at all in the login window. Verified with
     `assetutil --info .../Assets.car`, which lists `AppIconReverse`, `CodexIcon` and
     `CodexIconReverse` but no `AppIcon`.
   - `ImageHelper.namedImage(_:)` is the single fallback: it tries `NSImage(named:)` first, then
     `NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)` for the `AppIcon` name only.
     `createAppIcon` and `createSquareIcon` both route through it, so do not reintroduce a bare
     `NSImage(named: "AppIcon")`.
   - Regenerate it from the composed system icon rather than from the raw SVG, so it matches the
     real app icon including Apple's squircle and material. Install the app, then extract with
     `NSWorkspace.shared.icon(forFile:)` drawn into a 1024 `NSBitmapImageRep`, and `sips -Z` that
     down to 16, 32, 64, 128, 256, 512, 1024.
   - `AppIconReverse.imageset` is the monochrome sibling used by the Monochrome menu bar theme.
     It is `template-rendering-intent: template`, so only alpha matters. Generate it as a tight
     square-cropped glyph: `rsvg-convert -w 1024 -h 1024`, then
     `magick ... -trim +repage -background none -gravity center -extent square -resize 512x512`.

## Verified environment

- `claude` 2.1.220 at `/opt/homebrew/bin/claude`
- Keychain service `Claude Code-credentials`, account = macOS username
- 488 session JSONL files under `~/.claude/projects/`
- Current account: subscription plan, `limit_dollars` null, `member_dashboard_available` false
