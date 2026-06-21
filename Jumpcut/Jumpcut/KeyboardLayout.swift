//
//  KeyboardLayout.swift
//  Jumpcut
//
//  Replaces the Sauce and HotKey SPM dependencies with direct Carbon/CoreServices calls.
//

import Carbon
import Cocoa

// MARK: - KeyboardKey enum (replaces Sauce's Key)

/// Virtual key codes matching the QWERTY keyboard layout (same codes as kVK_ANSI_* constants).
enum KeyboardKey: Int {
    // Letters
    case v = 9

    // Number row
    case zero = 29
    case one = 18
    case two = 19
    case three = 20
    case four = 21
    case five = 23
    case six = 22
    case seven = 26
    case eight = 28
    case nine = 25

    // Keypad numbers
    case keypadZero = 82
    case keypadOne = 83
    case keypadTwo = 84
    case keypadThree = 85
    case keypadFour = 86
    case keypadFive = 87
    case keypadSix = 88
    case keypadSeven = 89
    case keypadEight = 91
    case keypadNine = 92
    case keypadEnter = 76

    // Navigation
    case upArrow = 126
    case downArrow = 125
    case leftArrow = 123
    case rightArrow = 124
    case pageUp = 116
    case pageDown = 121
    case home = 115
    case end = 119

    // Actions
    case escape = 53
    case `return` = 36
    case delete = 51
    case forwardDelete = 117

    init?(QWERTYKeyCode code: Int) {
        self.init(rawValue: code)
    }

    /// Map a character string to a KeyboardKey by finding which QWERTY key produces that character.
    init?(character: String, virtualKeyCode: CGKeyCode?) {
        if let code = virtualKeyCode {
            self.init(rawValue: Int(code))
            return
        }
        guard let target = character.lowercased().unicodeScalars.first else { return nil }
        // Try all character-producing key codes (0-50 covers the main keyboard area)
        for code: UInt16 in 0..<128 {
            if let ch = KeyboardLayout.characterForKeyCode(code, layout: KeyboardLayout.qwertyLayout),
               ch == target {
                self.init(rawValue: Int(code))
                return
            }
        }
        return nil
    }
}

// MARK: - KeyboardLayout singleton (replaces Sauce.shared)

class KeyboardLayout {
    static let shared = KeyboardLayout()

    /// Notification posted when the active keyboard input source changes.
    static let inputSourceChangedNotification = Notification.Name("KeyboardLayoutInputSourceChanged")

    /// Cached QWERTY layout pointer for character lookups.
    static let qwertyLayout: UnsafePointer<UCKeyboardLayout>? = {
        // Get the current layout as a fallback; the QWERTY mapping uses key codes directly
        // so this is only needed for character-based init.
        guard let source = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        return unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
    }()

    private init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }

    @objc private func inputSourceChanged() {
        NotificationCenter.default.post(name: KeyboardLayout.inputSourceChangedNotification, object: nil)
    }

    /// Returns the virtual key code for a KeyboardKey in the current keyboard layout.
    /// For non-character keys (arrows, function keys, etc.), this is always the raw value.
    func keyCode(for key: KeyboardKey) -> CGKeyCode {
        return CGKeyCode(key.rawValue)
    }

    /// Maps a KeyboardKey (identified by its QWERTY position) to the key code that produces
    /// the same character in the currently active keyboard layout. Returns nil if the character
    /// cannot be found in the current layout.
    func currentKeyCode(for key: KeyboardKey) -> CGKeyCode? {
        // For non-character keys, the code is layout-independent.
        guard let qwertyChar = KeyboardLayout.characterForKeyCode(UInt16(key.rawValue),
                                                                   layout: KeyboardLayout.qwertyLayout) else {
            return CGKeyCode(key.rawValue)
        }
        // Find which key code in the current layout produces this character.
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        for code: UInt16 in 0..<128 {
            if let ch = KeyboardLayout.characterForKeyCode(code, layout: layout), ch == qwertyChar {
                return CGKeyCode(code)
            }
        }
        return nil
    }

    /// Translates a virtual key code to a Unicode character using the given keyboard layout.
    static func characterForKeyCode(_ keyCode: UInt16, layout: UnsafePointer<UCKeyboardLayout>?) -> Unicode.Scalar? {
        guard let layout = layout else { return nil }
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0, // no modifiers
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &chars
        )
        guard status == noErr, length > 0 else { return nil }
        return Unicode.Scalar(chars[0])
    }
}

// MARK: - HotKeyManager (replaces soffes/HotKey)

/// Manages a single global hotkey using the Carbon RegisterEventHotKey API.
class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private static var eventHandler: EventHandlerRef?
    private static var instances: [UInt32: HotKeyManager] = [:]
    private static var nextID: UInt32 = 1

    private let hotkeyID: UInt32
    var keyDownHandler: (() -> Void)?

    init(carbonKeyCode: UInt32, carbonModifiers: UInt32) {
        hotkeyID = HotKeyManager.nextID
        HotKeyManager.nextID += 1
        HotKeyManager.instances[hotkeyID] = self

        // Install the shared event handler if needed.
        if HotKeyManager.eventHandler == nil {
            var eventSpec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, _) -> OSStatus in
                    var hotKeyID = EventHotKeyID()
                    GetEventParameter(
                        event,
                        UInt32(kEventParamDirectObject),
                        UInt32(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    HotKeyManager.instances[hotKeyID.id]?.keyDownHandler?()
                    return noErr
                },
                1,
                &eventSpec,
                nil,
                &HotKeyManager.eventHandler
            )
        }

        var hotKeyIDStruct = EventHotKeyID(
            signature: OSType(0x4A435554), // "JCUT"
            id: hotkeyID
        )
        RegisterEventHotKey(
            carbonKeyCode,
            carbonModifiers,
            hotKeyIDStruct,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        HotKeyManager.instances.removeValue(forKey: hotkeyID)
    }
}

// MARK: - ShortcutData (replaces ShortcutRecorder's Shortcut)

/// A keyboard shortcut stored as a dictionary, compatible with the existing UserDefaults format.
struct ShortcutData {
    let keyCode: Int
    let modifierFlags: Int
    let charactersIgnoringModifiers: String?

    init?(dictionary: [AnyHashable: Any]) {
        guard let kc = dictionary["keyCode"] as? Int else { return nil }
        self.keyCode = kc
        self.modifierFlags = dictionary["modifierFlags"] as? Int ?? 0
        self.charactersIgnoringModifiers = dictionary["charactersIgnoringModifiers"] as? String
    }

    /// Carbon key code for use with RegisterEventHotKey.
    var carbonKeyCode: UInt32 {
        return UInt32(keyCode)
    }

    /// Carbon modifier flags for use with RegisterEventHotKey.
    var carbonModifierFlags: UInt32 {
        var carbon: UInt32 = 0
        let cocoa = NSEvent.ModifierFlags(rawValue: UInt(modifierFlags))
        if cocoa.contains(.control) { carbon |= UInt32(controlKey) }
        if cocoa.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoa.contains(.shift) { carbon |= UInt32(shiftKey) }
        if cocoa.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
}
