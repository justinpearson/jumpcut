//
//  PreferenceWindow.swift
//  Jumpcut
//
//  Created by Steve Cook on 7/21/22.
//

import Cocoa

class PreferencesWindowController: NSWindowController {
    private let tabVC = NSTabViewController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Jumpcut Preferences"
        self.init(window: window)

        tabVC.tabStyle = .toolbar

        let panes: [(NSViewController, String, String)] = [
            (GeneralPreferenceViewController(), "General", "gearshape"),
            (HotkeyPreferenceViewController(), "Hotkey", "command.square"),
            (ClippingsPreferenceViewController(), "Clippings", "paperclip"),
            (AppearancePreferenceViewController(), "Appearance", "paintpalette")
        ]

        for (vc, title, imageName) in panes {
            let item = NSTabViewItem(viewController: vc)
            item.label = title
            let icon = NSImage(named: imageName)
            icon?.isTemplate = true
            item.image = icon
            tabVC.addTabViewItem(item)
        }

        window.contentViewController = tabVC
    }

    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

var preferencesWindowController = PreferencesWindowController()
