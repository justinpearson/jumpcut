//
//  KeyboardLayout.swift
//  Jumpcut
//
//  Replaces the third-party Sauce library.
//  Provides KeyCode enum and KeyboardLayoutManager for keyboard-layout-aware key mapping.
//

import Carbon
import Cocoa

// MARK: - KeyCode Enum

/// Virtual key codes for the standard US (QWERTY) keyboard layout.
/// These are hardware key codes and are layout-independent.
enum KeyCode: UInt16, CaseIterable {
    // Letters (used by the app)
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

    // Navigation
    case escape = 53
    case `return` = 36
    case delete = 51
    case forwardDelete = 117
    case upArrow = 126
    case downArrow = 125
    case leftArrow = 123
    case rightArrow = 124
    case pageUp = 116
    case pageDown = 121
    case home = 115
    case end = 119

    // Keypad
    case keypadEnter = 76
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

    /// Initialize from a QWERTY key code (same as raw value since our enum IS QWERTY codes).
    init?(QWERTYKeyCode: Int) {
        self.init(rawValue: UInt16(QWERTYKeyCode))
    }

    /// Try to initialize from a character string by reverse-mapping through QWERTY layout.
    init?(character: String, virtualKeyCode: Int?) {
        if let vk = virtualKeyCode, let kc = KeyCode(rawValue: UInt16(vk)) {
            self = kc
            return
        }
        // Reverse lookup: find key code that produces this character in QWERTY
        if let kc = KeyboardLayoutManager.shared.keyCodeForCharacter(character, inQWERTY: true) {
            self = kc
            return
        }
        return nil
    }
}

// MARK: - KeyboardLayoutManager

class KeyboardLayoutManager {
    static let shared = KeyboardLayoutManager()
    static let keyboardDidChangeNotification = Notification.Name("KeyboardLayoutDidChange")

    private var cachedQWERTYMapping: [String: KeyCode] = [:]

    private init() {
        buildQWERTYMapping()
        // Listen for keyboard layout changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    @objc private func inputSourceChanged() {
        NotificationCenter.default.post(name: KeyboardLayoutManager.keyboardDidChangeNotification, object: nil)
    }

    /// Get the virtual key code for a KeyCode (identity mapping — key codes are hardware codes).
    func keyCode(for key: KeyCode) -> CGKeyCode {
        CGKeyCode(key.rawValue)
    }

    /// Get the current keyboard layout's key code for a given character.
    /// Returns the virtual key code that produces this character in the current layout.
    func currentKeyCode(for character: KeyCode) -> CGKeyCode? {
        // For non-character keys (arrows, escape, etc.), the key code is the same in all layouts
        switch character {
        case .escape, .return, .delete, .forwardDelete,
             .upArrow, .downArrow, .leftArrow, .rightArrow,
             .pageUp, .pageDown, .home, .end,
             .keypadEnter, .keypadZero, .keypadOne, .keypadTwo, .keypadThree,
             .keypadFour, .keypadFive, .keypadSix, .keypadSeven, .keypadEight, .keypadNine:
            return CGKeyCode(character.rawValue)
        default:
            break
        }

        // For character-producing keys, we need to find what key code produces the
        // same character as this QWERTY key code would in QWERTY.
        // First, figure out what character this key produces in QWERTY
        guard let qwertyChar = characterForKeyCode(CGKeyCode(character.rawValue), inQWERTY: true) else {
            return CGKeyCode(character.rawValue)
        }

        // Now find what key code produces that character in the current layout
        if let currentCode = keyCodeForCharacterInCurrentLayout(qwertyChar) {
            return CGKeyCode(currentCode)
        }

        // Fallback: same key code
        return CGKeyCode(character.rawValue)
    }

    /// Get the current keyboard layout's key code for a character string.
    func currentKeyCode(for character: String) -> CGKeyCode? {
        if let code = keyCodeForCharacterInCurrentLayout(character) {
            return CGKeyCode(code)
        }
        return nil
    }

    // MARK: - Private

    /// Build a mapping from characters to KeyCode values for QWERTY layout.
    private func buildQWERTYMapping() {
        for kc in KeyCode.allCases {
            if let char = characterForKeyCode(CGKeyCode(kc.rawValue), inQWERTY: true) {
                cachedQWERTYMapping[char.lowercased()] = kc
            }
        }
    }

    /// Find a KeyCode for a character in QWERTY.
    func keyCodeForCharacter(_ character: String, inQWERTY: Bool) -> KeyCode? {
        if inQWERTY {
            return cachedQWERTYMapping[character.lowercased()]
        }
        // For current layout, scan all key codes
        for kc in KeyCode.allCases {
            if let char = characterForKeyCode(CGKeyCode(kc.rawValue), inQWERTY: false),
               char.lowercased() == character.lowercased() {
                return kc
            }
        }
        return nil
    }

    /// Get the character produced by a key code in either QWERTY or the current layout.
    private func characterForKeyCode(_ keyCode: CGKeyCode, inQWERTY: Bool) -> String? {
        let inputSource: TISInputSource
        if inQWERTY {
            // Get ASCII-capable input source (QWERTY)
            guard let source = TISCopyInputSourceForLanguage("en" as CFString)?.takeRetainedValue() else {
                return nil
            }
            inputSource = source
        } else {
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
                return nil
            }
            inputSource = source
        }

        guard let layoutDataPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataPtr, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0, // no modifiers
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    /// Find the key code that produces a given character in the current keyboard layout.
    private func keyCodeForCharacterInCurrentLayout(_ character: String) -> UInt16? {
        // Scan key codes 0-127 to find one that produces the target character
        for code: UInt16 in 0..<128 {
            if let char = characterForKeyCode(CGKeyCode(code), inQWERTY: false),
               char.lowercased() == character.lowercased() {
                return code
            }
        }
        return nil
    }
}
