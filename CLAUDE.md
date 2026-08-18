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
  - `Insertion/` — `SnippetInsertionService`, `AccessibilityInserter`, `ClipboardInserter`, `FocusSnapshotResolver`, `AccessibilityPermission`, `SelectionClipboardReader`, `PasteboardSnapshot`, `KeyEventSender`
  - `Placeholder/` — `PlaceholderCatalog`, `PlaceholderParser`, `PlaceholderContext`, `PlaceholderExpander` (see "Placeholders" below)
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

### Selection text recovery for Electron/Chromium apps

Electron/Chromium apps (VS Code, Slack, etc.) don't build an accessibility tree unless requested by assistive technology, so `FocusSnapshotResolver`'s plain `kAXSelectedTextAttribute` read always comes back empty in them. `FocusSnapshotResolver.resolveTarget(for:recovery:)` takes a `SelectionRecoveryBudget` (`.none` / `.immediate` / `.brief(maxWaitMs:)`) that governs how much blocking is acceptable on each call site: setting the `AXManualAccessibility` attribute on the app element asks Chromium to build its tree, but that build happens asynchronously in the target process, so the budget controls whether/how long to poll for it to finish. `SnippetInsertionService`'s pre-insert re-resolve doesn't need `selectedText` and stays at the default `.none`. `SnippetPanelPresenter.present()` uses `.immediate` (no blocking allowed before showing the panel) — first-time `{{selection}}` in VS Code can come back empty, but the tree stays built for the app's lifetime so later panel opens succeed. The `.brief` polling only runs once per pid (`FocusSnapshotResolver.manualAccessibilityEnabledPIDs`) since a second attempt after the tree exists is already fast.

`AppSharedState.handleQuickRegisterShortcut()` is the only call site using `.brief()`, and it's also the only one allowed to fall back further to `SelectionClipboardReader.readSelectedText()` (Cmd+C sent via `KeyEventSender`, clipboard captured/restored via `PasteboardSnapshot` — the same retire/restore primitives `ClipboardInserter` uses for Cmd+V). This Cmd+C fallback is deliberately quick-register-only, not wired into the panel path: firing it on every panel presentation would add latency and, in apps like VS Code where Cmd+C with no selection copies the current line, could silently populate `{{selection}}` with unintended text. Known limitation: a clipboard history app will record two entries when the fallback fires (the copied selection, then the restored original) since the target app itself performs the copy.

### Placeholders

Snippet bodies can contain `{{keyword}}` / `{{keyword:argument}}` tokens (see `docs/macos_snippet_menu_app_plan.md` §14 "プレースホルダ" for the original design). `PlaceholderParser.scan(_:)` is the single tokenizer both the editor's syntax highlighting (`SnippetBodyTextView.Coordinator.applyHighlight`) and the expansion engine (`PlaceholderExpander.expand(_:context:)`) share — never re-implement `{{ }}` scanning elsewhere. `PlaceholderCatalog.all` is the single source of truth for which keywords are recognized; adding a new placeholder means adding a `PlaceholderDefinition` there, a case to resolve in `PlaceholderExpander.resolvedValue(for:argument:context:)`, and matching `placeholder.<keyword>.name` / `.description` keys in **both** `Localizable.strings` files (a Swift Testing case in `PlaceholderTests` fails the build if either is missing). Expansion happens exactly once, in `SnippetPanelPresenter.insertAndClose`, right before `SnippetInsertionService.insert` — that is also where `PlaceholderContext.capture(from:)` reads the clipboard, so it must run before `ClipboardInserter` has a chance to overwrite it. Unknown `{{ }}` text is left verbatim rather than stripped, so a body pasted from code containing stray braces is never silently mangled.

The editor's body field (`Sources/PopSnipApp/Editor/SnippetBodyTextView.swift`) wraps `NSTextView` instead of SwiftUI's `TextEditor` — click-to-insert from the placeholder palette needs direct `NSTextView` access to the current selection, and `TextEditor` only gains cursor/selection support via `init(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>)`, which requires **macOS 26+** (confirmed via Apple's docs; do not assume macOS 15 is enough here — `TextSelection`, macOS 15+, pairs with `TextField`, not `TextEditor`). Migrating to that API was considered and deliberately deferred: it would drop this whole file, but at the cost of the app's minimum OS version, which is a call for the user to make, not something to do as a side effect of a bug fix. Drag-and-drop from the palette relies on the default `NSTextView` (`isEditable`, `isRichText = false`) behavior, which tracks the mouse with a visible insertion caret and inserts at the correct character index. `DragReadyTextView.viewDidMoveToWindow()` refreshes the standard drag-type registration. Its `draggingEntered` override only makes the text view first responder before returning `super.draggingEntered(sender)`; this is required because an untouched body field otherwise ignores the first drop until normal typing activates it. Never replace `performDragOperation`, and never return from `draggingEntered` without calling `super` — doing so suppresses AppKit's built-in insertion caret. Any code that touches `textStorage` (highlighting, programmatic insertion) must guard on `hasMarkedText() == false` first, same as the IME guard in `SnippetPanelPresenter`'s key monitor — mutating `textStorage` mid-composition corrupts the IME's marked text.

`SnippetBodyTextView` uses the standard representable synchronization pattern: `textDidChange` copies the current string to the binding, while `updateNSView` writes an externally changed binding only when the strings differ and no IME marked text exists. Placeholder highlighting likewise skips `textStorage` mutations while marked text exists. Do not add composition-state machinery without first reproducing behavior that differs from TextEdit: macOS Japanese IME live conversion normally converts and visually settles earlier segments while the user continues typing, which can look like premature confirmation even though it is standard IME behavior.

`NSViewRepresentable.makeNSView` must not synchronously invoke a callback that mutates SwiftUI `@State`; defer reference handoff such as `onTextViewCreated` to the next main run-loop turn. AppKit coordinators that read or mutate `NSTextView` must be explicitly `@MainActor`. For `NotificationCenter` block observers registered with `queue: .main`, use `MainActor.assumeIsolated` before calling actor-isolated UI methods so the compiler and runtime contract stay aligned.

### Sibling project: timeSlice

`/Users/nihondo/Library/CloudStorage/Dropbox/Projects.localized/timeSlice` is a sibling macOS menu bar app by the same author. Several PopSnip subsystems are intentionally ported from it (with credit in file-header comments) to keep the two apps' UX consistent: the settings window's sidebar `NavigationSplitView` layout, the About panel (`NSApp.orderFrontStandardAboutPanel`), and `AppUpdateController` (Sparkle wrapper). When extending these areas, check timeSlice's equivalent file first rather than inventing a new pattern.

### Sparkle updates

`AppUpdateController` (`Sources/PopSnipApp/Update/AppUpdateController.swift`) wraps `SPUStandardUpdaterController` as a singleton (`.shared`), touched once at `AppSharedState.init()` so scheduled checks run from launch. Update-related keys live in `Sources/Resources/Info.plist` (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`, `SUAutomaticallyUpdate`, `SUAllowsAutomaticUpdates`).

`SUPublicEDKey` holds the real EdDSA public key. The matching **private key lives in the login keychain** (item `Private key for signing Sparkle updates`, created by `Sparkle/bin/generate_keys` from the resolved Sparkle package) and is never committed. Every release archive must be signed with `Sparkle/bin/sign_update <archive>`, and the resulting `sparkle:edSignature` / `length` pasted into the appcast at `SUFeedURL`; an unsigned or mismatched entry is rejected by the updater at download time. If `SUPublicEDKey` is ever blanked out, update checks log `Fatal updater error (1): The EdDSA public key is not valid`.

## Testing Notes

- `PopSnipTests` covers core logic and testable panel view-model behavior. Add Swift Testing coverage for `SnippetStore`, `SnippetSearchEngine`, `TagColorAssigner`, Codable models, settings resolution, and panel selection/search logic as applicable.
- There is no automated UI rendering target. For SwiftUI/AppKit changes (panel layout, settings screens, menu bar), build and run the app manually and exercise the golden path plus edge cases (IME composition, empty states, resize) before calling a change done.
