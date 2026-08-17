# CLAUDE.md

Development conventions and context for working on PopSnip, a macOS menu bar app for text-snippet management and insertion.

## Project Overview

PopSnip is an `LSUIElement` (menu-bar-only, no Dock icon) macOS app. A global shortcut opens a Raycast-style search panel (`SnippetPanel`, an `NSPanel`) that lets the user search, browse-by-tag, and insert snippets into whatever app previously had focus, via the Accessibility API with a clipboard fallback.

See `docs/macos_snippet_menu_app_plan.md` for the original feature roadmap and `docs/PopSnip_UI_plan.md` / `docs/UI_fix.md` for UI design decisions. `handoff.md` at the repo root logs session-by-session implementation history — read it (or run `python3 ~/.claude/skills/handoff/scripts/summarize.py` if available) before starting new work to pick up recent context.

## Architecture

The project is split into three targets, defined in `project.yml` (XcodeGen):

- **`PopSnipCore`** (`Sources/PopSnipCore`) — platform-agnostic-ish models, settings persistence, search, and insertion services. No SwiftUI. Everything here is `public` so `PopSnipApp` can consume it.
  - `Models/` — `Snippet`, `SnippetTag`, `SnippetLibrary`, `InsertionTarget`
  - `Storage/` — `SnippetStore` (JSON persistence, `@Published` for SwiftUI), `TagColorAssigner`
  - `Settings/` — `PanelPreferences`, `UserDefaultsKeys`, `AppSettingsResolver`, `AppFontSize`, `PanelSection`, `LaunchAtLoginManager`
  - `Shortcut/` — `PopSnipShortcutAction`, `PanelShortcutConfiguration`/`PanelShortcutResolver`, `GlobalShortcutService`
  - `Search/` — `SnippetSearchEngine`, `HighlightRange`
  - `Insertion/` — `SnippetInsertionService`, `AccessibilityInserter`, `ClipboardInserter`, `FocusSnapshotResolver`, `AccessibilityPermission`
- **`PopSnipApp`** (`Sources/PopSnipApp`) — the SwiftUI/AppKit UI layer: `Panel/`, `Editor/`, `Settings/`, `MenuBar/`, `Update/`, plus `DesignTokens.swift`, `Localization.swift`, `AppSharedState.swift` (wires every controller together), `PopSnipApp.swift` (entry point / `NSApplicationDelegate`).
- **`PopSnipTests`** (`PopSnipTests`) — Swift Testing (`import Testing`) unit tests for `PopSnipCore` only (store, search engine, Codable round-trip, tag color assignment). There are no UI tests; UI changes must be verified manually.

`AppSharedState` is the composition root: it owns `SnippetStore`, `GlobalShortcutService`, `SnippetPanelPresenter`, `StatusBarController`, and the window controllers (`SettingsWindowController`, `SnippetEditorWindowController`, `SnippetListWindowController`), and wires their callback closures together in `wireHandlers()`.

## Build & Test

The Xcode project is generated, not committed by hand — **run `xcodegen generate` after adding, removing, or renaming any Swift file**, or after editing `project.yml` (e.g. adding a package dependency). Builds can silently fail to see new files otherwise.

```bash
xcodegen generate
xcodebuild -project PopSnip.xcodeproj -scheme PopSnip -configuration Debug build
xcodebuild -project PopSnip.xcodeproj -scheme PopSnip -destination 'platform=macOS' test
```

Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete` is enabled — most UI types are `@MainActor`-isolated; watch for actor-isolation errors in `deinit` (nonisolated by default) and in `@Sendable` closures such as `NotificationCenter` block observers.

## Conventions

### Settings are always type-safe and go through `AppSettingsResolver`

Never read/write `UserDefaults` directly from a View. The pattern, consistently used across every setting:

1. Add the raw key to `PopSnipCore/Settings/UserDefaultsKeys.swift`.
2. Add a typed field to the relevant model (`PanelPreferences`, or a dedicated enum like `AppFontSize`, `InsertionStrategy`).
3. Add read/write logic to `AppSettingsResolver` (`resolve...` / `save...`).
4. Views call `AppSettingsResolver.resolvePanelPreferences()` on load and `AppSettingsResolver.savePanelPreferences(_:)` in an `.onChange` handler.

This keeps `PanelPreferences` the single source of truth that both the panel and the settings UI read from.

### Design tokens, not magic numbers

`Sources/PopSnipApp/DesignTokens.swift` centralizes spacing, corner radius, window sizes, and base typography sizes (`DesignTokens.Typography`). Use these instead of literal `CGFloat` values in new SwiftUI code.

### Font size scaling

`AppFontSize` (small/medium/large) lives in `PanelPreferences.fontSize`. It's applied via `EnvironmentValues.appFontSize` (`AppFontSizeEnvironment.swift`): inject it once near the root of a window (`.environment(\.appFontSize, ...)`) and read it with `@Environment(\.appFontSize)` in leaf views, using `appFontSize.font(_:weight:)` for `Font` values or `.scaledFont(_:weight:)` as a view modifier. The panel re-injects on every `present()` (reads fresh preferences); the snippet list window binds directly to `@AppStorage(UserDefaultsKeys.panelFontSize)` so an already-open window reacts immediately to a settings change.

### Localization

All user-facing strings go through `L10n.string(_:)` / `L10n.format(_:_:)`, backed by `Sources/Resources/{ja,en}.lproj/Localizable.strings`. **Every new key must be added to both files** — ja is the primary/default language for this app's users, en is the secondary. Keep the section comments (`/* ... */`) in both files aligned so the two are easy to diff.

### Panel key handling

Arrow keys, Tab/Shift+Tab, Enter, Backspace, Esc, and `⌘1`–`⌘9` inside the search panel are handled by a single `NSEvent` local monitor in `SnippetPanelPresenter`, not by SwiftUI `onKeyPress` or `NSTextFieldDelegate.doCommandBy`. This is deliberate: SwiftUI's `TextField` + `onKeyPress` and the field editor's `doCommandBy` both have known issues intercepting keys during Japanese (IME) text composition. The monitor checks `hasMarkedText()` on the field editor and passes the event through untouched while IME composition is active. Don't move this logic back into SwiftUI without re-testing IME behavior end to end.

### Panel tag navigation

`SnippetPanelViewModel` stores panel focus as a stable `PanelSelection` (back row, tag ID, or snippet ID plus section context), rather than a raw row index. `listItems` is the shared logical ordering for rendering and keyboard actions. In the default `.horizontalStrip` layout, all visible tags occupy one vertical navigation row while Tab/Shift+Tab and left/right cycle individual tags; `.verticalList` keeps one tag per vertical row. Search filters tag suggestions and snippets within the current selected-tag scope, but `⌘1`–`⌘9` always counts snippet results only.

Tag ordering is controlled by `PanelPreferences.tagSortOrder`. The `.recentlyUsed` option is derived from the greatest `Snippet.lastUsedAt` among snippets carrying each tag, so it does not add state to `SnippetTag` or require a JSON migration. At the top level it uses the whole library; during tag drill-down it uses only the currently scoped snippets. Tags with equal dates, including never-used tags, retain registration order.

### Sibling project: timeSlice

`/Users/nihondo/Library/CloudStorage/Dropbox/Projects.localized/timeSlice` is a sibling macOS menu bar app by the same author. Several PopSnip subsystems are intentionally ported from it (with credit in file-header comments) to keep the two apps' UX consistent: the settings window's sidebar `NavigationSplitView` layout, the About panel (`NSApp.orderFrontStandardAboutPanel`), and `AppUpdateController` (Sparkle wrapper). When extending these areas, check timeSlice's equivalent file first rather than inventing a new pattern.

### Sparkle updates

`AppUpdateController` (`Sources/PopSnipApp/Update/AppUpdateController.swift`) wraps `SPUStandardUpdaterController` as a singleton (`.shared`), touched once at `AppSharedState.init()` so scheduled checks run from launch. Update-related keys live in `Sources/Resources/Info.plist` (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`, `SUAutomaticallyUpdate`, `SUAllowsAutomaticUpdates`).

**`SUPublicEDKey` is currently a placeholder empty string.** Until a real EdDSA key pair is generated (`Sparkle/bin/generate_keys` from the resolved Sparkle package) and the public half is filled in, update checks will log `Fatal updater error (1): The EdDSA public key is not valid` — this is expected and non-fatal to the app itself, but real update delivery won't work until the key and the appcast feed at `SUFeedURL` are both live.

## Testing Notes

- `PopSnipTests` covers core logic and testable panel view-model behavior. Add Swift Testing coverage for `SnippetStore`, `SnippetSearchEngine`, `TagColorAssigner`, Codable models, settings resolution, and panel selection/search logic as applicable.
- There is no automated UI rendering target. For SwiftUI/AppKit changes (panel layout, settings screens, menu bar), build and run the app manually and exercise the golden path plus edge cases (IME composition, empty states, resize) before calling a change done.
