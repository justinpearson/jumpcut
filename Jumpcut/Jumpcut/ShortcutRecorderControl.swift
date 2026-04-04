//
//  ShortcutRecorderControl.swift
//  Jumpcut
//
//  Replaces the third-party ShortcutRecorder library.
//  Provides KeyboardShortcut (model) and ShortcutRecorderControl (UI).
//

import Carbon
import Cocoa

// MARK: - KeyboardShortcut Model

struct KeyboardShortcut {
    let keyCode: Int
    let modifierFlags: UInt
    let charactersIgnoringModifiers: String?

    var carbonKeyCode: UInt32 {
        UInt32(keyCode)
    }

    var carbonModifierFlags: UInt32 {
        var carbon: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    init?(dictionary: [AnyHashable: Any]) {
        guard let kc = dictionary["keyCode"] as? Int else { return nil }
        keyCode = kc
        modifierFlags = dictionary["modifierFlags"] as? UInt ?? 0
        charactersIgnoringModifiers = dictionary["charactersIgnoringModifiers"] as? String
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "keyCode": keyCode,
            "modifierFlags": modifierFlags
        ]
        if let chars = charactersIgnoringModifiers {
            dict["charactersIgnoringModifiers"] = chars
        }
        return dict
    }

    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        if flags.contains(.control) { parts.append("\u{2303}") }
        if flags.contains(.option) { parts.append("\u{2325}") }
        if flags.contains(.shift) { parts.append("\u{21E7}") }
        if flags.contains(.command) { parts.append("\u{2318}") }
        if let chars = charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            parts.append(chars)
        } else {
            parts.append("Key \(keyCode)")
        }
        return parts.joined()
    }
}

// MARK: - ShortcutRecorderControl

class ShortcutRecorderControl: NSView {
    var shortcutValue: [AnyHashable: Any]? {
        didSet {
            needsDisplay = true
        }
    }

    var settingsKey: SettingsPath?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 200, height: 25)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupDefaults()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDefaults()
    }

    private func setupDefaults() {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    // Binding support for UserDefaults
    func bind(toDefaultsKey key: SettingsPath) {
        settingsKey = key
        shortcutValue = UserDefaults.standard.value(forKey: key.rawValue) as? [AnyHashable: Any]
        // Observe changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func defaultsChanged() {
        guard let key = settingsKey else { return }
        if !isRecording {
            shortcutValue = UserDefaults.standard.value(forKey: key.rawValue) as? [AnyHashable: Any]
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bg = isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.1) : NSColor.controlBackgroundColor
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()

        let text: String
        if isRecording {
            text = "Type shortcut\u{2026}"
        } else if let dict = shortcutValue, let shortcut = KeyboardShortcut(dictionary: dict) {
            text = shortcut.displayString
        } else {
            text = "Click to record shortcut"
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let size = attrStr.size()
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        attrStr.draw(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            startRecording()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 { // Escape
            endRecording()
            return
        }

        // Require at least one modifier key
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else { return }

        let dict: [String: Any] = [
            "keyCode": Int(event.keyCode),
            "modifierFlags": modifiers.rawValue,
            "charactersIgnoringModifiers": event.charactersIgnoringModifiers ?? ""
        ]

        shortcutValue = dict
        if let key = settingsKey {
            UserDefaults.standard.set(dict, forKey: key.rawValue)
        }
        endRecording()
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't process modifier-only events as shortcuts
        if isRecording {
            needsDisplay = true
        }
    }

    private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
        if let key = settingsKey {
            NotificationCenter.default.post(
                name: NSNotification.Name("recorderBeganRecording.\(key)"),
                object: nil
            )
        }
    }

    private func endRecording() {
        isRecording = false
        needsDisplay = true
        if let key = settingsKey {
            NotificationCenter.default.post(
                name: NSNotification.Name("recorderEndedRecording.\(key)"),
                object: nil
            )
        }
    }
}
