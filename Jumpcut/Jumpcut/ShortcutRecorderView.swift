//
//  ShortcutRecorderView.swift
//  Jumpcut
//
//  Replaces the ShortcutRecorder SPM dependency with a minimal inline implementation.
//

import Cocoa

/// A view that captures a keyboard shortcut from the user.
/// Displays the current shortcut (e.g. "⌃⌥V") and enters recording mode on click.
class ShortcutRecorderView: NSView {
    private var isRecording = false
    private var shortcutValue: [String: Any]?
    private let label = NSTextField(labelWithString: "")
    private var boundKeyPath: String?
    private var boundObject: AnyObject?

    // Notification support (matches existing NotifyingRecorderControl pattern)
    var settingsKey: SettingsPath?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 4
        updateAppearance()
    }

    private func updateAppearance() {
        if isRecording {
            layer?.borderColor = NSColor.selectedControlColor.cgColor
            layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.1).cgColor
            label.stringValue = "Type shortcut…"
        } else {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            label.stringValue = shortcutValue != nil ? displayString(for: shortcutValue!) : "Click to record"
        }
    }

    // MARK: - Display formatting

    private func displayString(for shortcut: [String: Any]) -> String {
        var parts = ""
        if let flags = shortcut["modifierFlags"] as? Int {
            let mods = NSEvent.ModifierFlags(rawValue: UInt(flags))
            if mods.contains(.control) { parts += "⌃" }
            if mods.contains(.option) { parts += "⌥" }
            if mods.contains(.shift) { parts += "⇧" }
            if mods.contains(.command) { parts += "⌘" }
        }
        if let chars = shortcut["charactersIgnoringModifiers"] as? String {
            parts += chars.uppercased()
        }
        return parts.isEmpty ? "None" : parts
    }

    // MARK: - Mouse/keyboard handling

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        updateAppearance()
        if let key = settingsKey {
            NotificationCenter.default.post(
                name: NSNotification.Name("recorderBeganRecording.\(key)"),
                object: nil
            )
        }
    }

    private func stopRecording() {
        isRecording = false
        updateAppearance()
        if let key = settingsKey {
            NotificationCenter.default.post(
                name: NSNotification.Name("recorderEndedRecording.\(key)"),
                object: nil
            )
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        // Require at least one modifier key for the shortcut.
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !modifiers.isEmpty else {
            if event.keyCode == 53 { // Escape cancels recording
                stopRecording()
            }
            return
        }
        let shortcut: [String: Any] = [
            "keyCode": Int(event.keyCode),
            "modifierFlags": Int(modifiers.rawValue),
            "charactersIgnoringModifiers": event.charactersIgnoringModifiers ?? ""
        ]
        shortcutValue = shortcut
        // Write to bound UserDefaults
        if let obj = boundObject as? UserDefaults, let keyPath = boundKeyPath {
            obj.set(shortcut, forKey: keyPath)
        }
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording()
        }
        return super.resignFirstResponder()
    }

    // MARK: - Cocoa Bindings support

    override func bind(_ binding: NSBindingName, to observable: Any, withKeyPath keyPath: String, options: [NSBindingOption: Any]? = nil) {
        if binding == .value {
            boundObject = observable as AnyObject
            boundKeyPath = keyPath
            // Load current value
            if let defaults = observable as? UserDefaults,
               let dict = defaults.dictionary(forKey: keyPath) as? [String: Any] {
                shortcutValue = dict
                updateAppearance()
            }
        } else {
            super.bind(binding, to: observable, withKeyPath: keyPath, options: options)
        }
    }

    override func unbind(_ binding: NSBindingName) {
        if binding == .value {
            boundObject = nil
            boundKeyPath = nil
        } else {
            super.unbind(binding)
        }
    }
}
