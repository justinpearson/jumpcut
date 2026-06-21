//
//  PreferenceWindow.swift
//  Jumpcut
//
//  Created by Steve Cook on 7/21/22.
//

import Cocoa

protocol PreferencePane: NSViewController {
    var preferencePaneTitle: String { get }
    var toolbarItemIcon: NSImage { get }
}

class PreferencesWindowController: NSWindowController {
    private let tabViewController = NSTabViewController()

    convenience init(preferencePanes: [PreferencePane]) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Jumpcut Preferences"
        self.init(window: window)
        tabViewController.tabStyle = .toolbar
        for pane in preferencePanes {
            let tabItem = NSTabViewItem(viewController: pane)
            tabItem.label = pane.preferencePaneTitle
            tabItem.image = pane.toolbarItemIcon
            tabViewController.addTabViewItem(tabItem)
        }
        window.contentViewController = tabViewController
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

var preferencesWindowController = PreferencesWindowController(
    preferencePanes: [
        GeneralPreferenceViewController(),
        HotkeyPreferenceViewController(),
        ClippingsPreferenceViewController(),
        AppearancePreferenceViewController()
    ]
)
