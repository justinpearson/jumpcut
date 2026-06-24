# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Jumpcut is a macOS menu-bar clipboard manager written in Swift against AppKit/Cocoa. It records text you cut or copy and lets you retrieve earlier clippings via a keyboard-driven HUD ("the bezel") or the status-bar menu. The app is "nibless" — there is no storyboard or main nib; `main.swift` instantiates the `AppDelegate` and the entire UI is built in code.

## Build, test, lint

The Xcode project lives in the `Jumpcut/` subdirectory. There is no `xcworkspace`; use the `.xcodeproj`. Swift 5.0; all targets deploy to macOS 26.0 (this fork targets only current macOS — see the deployment-target note below). Signing uses `CODE_SIGN_STYLE = Automatic` with `DEVELOPMENT_TEAM = AMXKCKJQUB` (the maintainer's Apple Development team); command-line builds therefore need `-allowProvisioningUpdates`.

```sh
# Build the app (Debug)
xcodebuild -project Jumpcut/Jumpcut.xcodeproj -scheme Jumpcut -configuration Debug \
  -allowProvisioningUpdates build

# Run all tests
xcodebuild -project Jumpcut/Jumpcut.xcodeproj -scheme Jumpcut -allowProvisioningUpdates test

# Run a single test (target/class/method)
xcodebuild -project Jumpcut/Jumpcut.xcodeproj -scheme Jumpcut -allowProvisioningUpdates test \
  -only-testing:JumpcutTests/JumpcutTests/testExample

# Lint (config: .swiftlint.yml and Jumpcut/.swiftlint.yml; `todo` rule disabled,
# cyclomatic_complexity ignores case statements)
swiftlint
```

Deployment target: upstream set the app to macOS 10.12, which no longer builds under Xcode 26 (the `Sauce` dependency requires ≥10.13, and 10.12 is below Xcode 26's floor). This fork raised every target to 26.0 to match its single-machine, current-macOS-only stance. If you ever see a `module 'Sauce' has a minimum deployment target` error, a target's deployment floor has drifted back below 10.13.

Targets: `Jumpcut` (the app), `JumpcutHelper` (login-item helper), `JumpcutTests` (unit), `JumpcutUITests` (UI). Schemes: `Jumpcut`, `JumpcutHelper`.

`JumpcutUITests` is still scaffold-only. `JumpcutTests/JumpcutTests.swift` holds characterization tests for the domain core (`Clipping`, `ClippingStack`, and the `JCEngine` persistence format) — they pin *current* behavior, quirks included and noted inline, as a safety net for refactoring. Two things make them hermetic: the test target hosts the app, so `AppDelegate.applicationDidFinishLaunching` early-returns under XCTest (detected via the `XCTestConfigurationFilePath` env var) to avoid starting the pasteboard poller or hotkeys; and `ClippingStack` tests set `skipSave = true` in `UserDefaults` before constructing the stack so `ClippingStore` never reads or writes the real `JCEngine.save`. New test files must be registered in the `JumpcutTests` target inside the `.xcodeproj` (the project uses explicit file references, not folder-synced groups), so the simplest path is to add cases to the existing `JumpcutTests.swift`.

Dependencies are Swift Package Manager remote packages (resolved automatically by `xcodebuild`): `HotKey` (global hotkey registration), `Sauce` (keyboard-layout-independent key codes), `ShortcutRecorder` (the hotkey-recording UI control), `Preferences` (sindresorhus; the preference-window framework), `LaunchAtLogin` (login-item toggle), and `Sparkle` (auto-update).

## Architecture

`AppDelegate` is the central coordinator. In `applicationDidFinishLaunching` it constructs and wires together every major object and holds the global hotkey. Most other classes reach back to it via `NSApplication.shared.delegate as? AppDelegate` and keep a `weak` reference, so the delegate is effectively a service locator. There is an explicit `// NB:` comment in `AppDelegate.setHotkey` noting that hotkey handling is over-coupled to the delegate and is intended to be refactored out — keep that direction in mind rather than adding more coupling.

The clipboard data flow is a three-layer stack in `Clippings.swift`:
- `Clipping` is one snippet: the `fullText` plus a `shortenedText` (first line, trimmed, truncated to 40 chars) used for menu display.
- `ClippingStore` (private) owns the `[Clipping]` array, enforces `maxLength`, and persists to disk.
- `ClippingStack` is a positional overlay over the store, adding a `position` cursor that the bezel moves with `up()`/`down()`/`move()`. UI code talks to `ClippingStack`, not the store.

Persistence is an XML property list at `~/Library/Application Support/Jumpcut/JCEngine.save`. The `JCEngine`/`JCListItem` Codable structs (with capitalized field names like `Contents`, `Position`, `Type`) are an inherited on-disk format from the original Objective-C Jumpcut and must stay compatible. Several `// TK:` comments mark the intended future migration to SQLite — the store rewrites the whole plist on every mutation today. When `skipSave` is set the stack is in-memory only and nothing is written.

`Pasteboard` watches the system clipboard by polling `NSPasteboard.general` on a 0.5s `Timer` (comparing `changeCount`). It filters out clippings that are transient (macro expanders like TextExpander), sensitive (password managers), too large, whitespace-only, or that Jumpcut itself just wrote (tagged with the private `net.sf.jumpcut.internal` pasteboard type). When a new clipping passes the filters it calls back into `AppDelegate.pasteboardChangeClosure`, which adds it to the stack and rebuilds the menu. `Pasteboard.fakeCommandV()` synthesizes a Command-V `CGEvent` to paste into the frontmost app.

`Interactions` holds all user-action logic — bezel key handling, menu-item handlers, clear-all — separated from the views themselves. A key distinction throughout the code: **place** puts a clipping on the pasteboard only, while **paste** does `place` and then 0.2s later fires `fakeCommandV()` to paste it into the active app. Whether a selection pastes or merely places is a per-context preference (`bezelSelectionPastes`, `menuSelectionPastes`), and an alt/modifier toggle can invert it at click time.

The view layer: `Bezel` is the floating keyboard-navigable HUD window (its `KeyCaptureWindow` captures arrow/number/escape/return keys); `StatusItem` manages the menu-bar icon and its visibility (the app can run "headless" with no icon); `MenuManager` rebuilds two parallel `NSMenu`s — a `standard` menu and an `alt` menu (the latter exposing per-clipping Copy/Paste/Delete submenus). Both menus are regenerated wholesale by `rebuild(stack:)` whenever the stack changes.

`Settings.swift` is the configuration backbone. `SettingsPath` is a string enum whose cases **are** the `UserDefaults` keys; `settingsDefaults` registers their defaults at launch. Preferences propagate by a deliberately coarse mechanism: the app observes `UserDefaults.didChangeNotification` and, on any change, re-runs `statusItem.setVisibility()` and `menu.rebuild(stack:)` rather than diffing what actually changed. The factory methods (`checkbox`, `popup`, `shortcutRecorder`, `rangeStepper`) build AppKit controls already bound to a `SettingsPath`. The four panes in `Preferences/` (General, Clippings, Hotkey, Appearance) are assembled from these.

Keyboard handling is layout-independent: hotkeys are stored on disk as QWERTY key codes and re-mapped to the user's current layout (e.g. Dvorak) through `Sauce` at registration time. `Types.swift` defines `typealias SauceKey = Key` to resolve a `Key` name collision between the `Sauce` and `HotKey` packages — use `SauceKey` in app code.

## Conventions

`#if DEBUG` blocks guard development-only behavior — notably, accessibility-permission and double-click flows differ under Xcode's debugger, and debug builds auto-open Preferences when headless. The `CHANGELOG` is maintained by hand and uses pre-1.0 `0.XX` version numbers (the project predates semantic versioning); update it for user-facing changes.
