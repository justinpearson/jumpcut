//
//  HotkeyPreferenceViewController.swift
//  Jumpcut
//
//  Created by Steve Cook on 4/16/22.
//

import Cocoa

final class HotkeyPreferenceViewController: NSViewController {

    // Dummy nib; we'll build the UI programatically
    override func loadView() {
        self.view = NSView()
    }
    override var nibName: NSNib.Name? { nil }

    override func viewDidLoad() {
        let settings = Settings()
        self.preferredContentSize = CGSize(width: 480, height: 180)
        super.viewDidLoad()
        let recorder = settings.shortcutRecorder(title: "Main hotkey", key: .mainHotkey)
        let grid = NSStackView(views: [ recorder ])
        grid.orientation = .vertical
        grid.alignment = .leading
        self.view.addSubview(grid)
        self.view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.leadingAnchor, constant: 24),
            grid.topAnchor.constraint(greaterThanOrEqualTo: self.view.topAnchor, constant: 24)
       ])
    }
}
