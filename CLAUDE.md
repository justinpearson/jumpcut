# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

- **Build the project**: Open `Jumpcut/Jumpcut.xcodeproj` in Xcode and build with Cmd+B
- **Run the app**: Use Xcode's Run button (Cmd+R) or Product > Run
- **Run tests**: Use Xcode's Test navigator or Cmd+U for unit tests and UI tests
- **Clean build**: Product > Clean Build Folder (Shift+Cmd+K)
- **Archive for distribution**: Product > Archive
- **CLI build**: `cd Jumpcut && xcodebuild build -scheme Jumpcut -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=10.15`

The project uses Xcode's built-in build system with no external dependencies or build tools.

## Project Architecture

### Core Data Flow
Jumpcut follows a clipboard monitoring → storage → menu/bezel display architecture:

1. **Pasteboard monitoring**: `Pasteboard.swift` polls the system clipboard every 0.5 seconds using NSPasteboard
2. **Storage layer**: `Clippings.swift` contains the `ClippingStack` (UI interface) and `ClippingStore` (persistence) 
3. **Display layer**: Two main UI modes - menu bar menu via `MenuManager.swift` and keyboard-driven bezel via `Bezel.swift`
4. **User interactions**: `Interactions.swift` coordinates responses to user actions across all UI components

### Key Classes and Responsibilities

- **AppDelegate**: Main coordinator, manages app lifecycle, hotkey setup, and component initialization
- **ClippingStack**: Positional interface over clipping store with navigation (up/down/position tracking)
- **ClippingStore**: Handles persistence to ~/Library/Application Support/Jumpcut/JCEngine.save as PropertyList
- **Pasteboard**: Monitors system clipboard, filters transient/sensitive content, triggers callbacks on changes
- **MenuManager**: Builds two menu types (standard for selection, alt for copy/paste/delete actions)
- **Bezel**: Keyboard-driven overlay interface showing current clipboard position with navigation
- **Interactions**: Centralized handler for user actions from menus, bezel, and hotkeys
- **HotkeyListeners**: Manages global hotkey registration and keyboard event handling

### Dependencies

This fork has **zero external dependencies**. All functionality previously provided by third-party SPM packages has been replaced with inline implementations:

- **KeyboardLayout.swift**: Keyboard layout abstraction (replaces Sauce) and global hotkey registration via Carbon API (replaces HotKey). Also contains `ShortcutData` for hotkey dictionary parsing.
- **ShortcutRecorderView.swift**: Hotkey recording UI component (replaces ShortcutRecorder).
- **PreferenceWindow.swift**: Settings window using NSTabViewController (replaces sindresorhus/Preferences).
- Launch-at-login uses direct `SMLoginItemSetEnabled` calls (replaces LaunchAtLogin).
- Auto-update (Sparkle) was removed entirely — not needed for a personal fork.

### Settings System

Settings are managed through UserDefaults with enum-based keys in `Settings.swift`. The `SettingsPath` enum defines all preference keys. Preference panes in the `Preferences/` directory handle UI binding to these settings.

### Menu Behavior System

The app supports two menu modes:
- **Standard menu**: Direct selection copies item to clipboard
- **Alt menu**: Shows submenu with copy/paste/delete options

Menu switching is controlled by `MenuBehaviorFlags` and can be triggered by right-click or shift-click depending on user preferences.