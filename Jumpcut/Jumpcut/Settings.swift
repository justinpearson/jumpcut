//
//  Settings.swift
//  Jumpcut
//
//  Created by Steve Cook on 6/26/21.
//

import Cocoa
import ServiceManagement

/* A set of user interface elements bound to our user defaults. */

// NB: We dropped bezelAlpha, menuIcon, and savePreference in the transition to 0.80;
// menuIcon was restored in 0.81, as was the boolean skipSave (replacing savePreference).
// Note that skipSave is, as of 0.81, not exposed in the UI.
enum SettingsPath: String {
    case allowWhitespaceClippings
    case askForAccessibility
    case askBeforeClearingClippings
    case bezelAlignment
    case bezelSelectionPastes
    case bezelToTop
    case displayNum
    case hideStatusItem
    case ignoreLargeClippings
    case ignoreSensitiveClippingTypes
    case launchOnStartup
    case mainHotkey
    case menuBehaviorFlags
    case menuIcon
    case menuSelectionPastes
    case moveClippingsAfterUse
    case rememberNum
    case skipSave
    case stickyBezel
    case wraparoundBezel
}

enum BezelAlignment: String {
    case center
    case left
    case right
    case smartAlign
}

public enum MenuBehaviorFlags: String {
    case none
    case rightAlt
    case rightAltShiftToggle
    case shiftAlt
    case shiftAltRightToggle
}

private let settingsDefaults: [String: Any] = [
    SettingsPath.allowWhitespaceClippings.rawValue: false,
    SettingsPath.askForAccessibility.rawValue: true,
    SettingsPath.askBeforeClearingClippings.rawValue: true,
    SettingsPath.bezelAlignment.rawValue: BezelAlignment.center.rawValue,
    SettingsPath.bezelSelectionPastes.rawValue: true,
    SettingsPath.bezelToTop.rawValue: 1,
    SettingsPath.displayNum.rawValue: 10,
    SettingsPath.hideStatusItem.rawValue: false,
    SettingsPath.ignoreLargeClippings.rawValue: true,
    SettingsPath.ignoreSensitiveClippingTypes.rawValue: true,
    SettingsPath.launchOnStartup.rawValue: false,
    // Control-Option-V
    SettingsPath.mainHotkey.rawValue: [
        "charactersIgnoringModifiers": "v",
        "keyCode": 9,
        "modifierFlags": 786432
    ],
    SettingsPath.menuBehaviorFlags.rawValue: MenuBehaviorFlags.none.rawValue,
    SettingsPath.menuSelectionPastes.rawValue: true,
    SettingsPath.moveClippingsAfterUse.rawValue: false,
    SettingsPath.menuIcon.rawValue: 0,
    SettingsPath.rememberNum.rawValue: 99,
    SettingsPath.skipSave.rawValue: false,
    SettingsPath.stickyBezel.rawValue: false,
    SettingsPath.wraparoundBezel.rawValue: false
]

/*
 A switch button that doesn't change when clicked; instead,
 the action handles all its behavior.
 */
class FixedButton: NSButton {
    override class var cellClass: AnyClass? {
        get {
            return Cell.classForCoder()
        }
        set(newValue) {
            super.cellClass = newValue
        }
    }

    class Cell: NSButtonCell {
        override var nextState: Int {
            // We don't allow clicks to alter the state, nor
            // do we allow mixed state.
            let currentState = self.state == .on ? 1 : 0
            return currentState
        }
    }
}


public class PreferencePopupButton: NSPopUpButton {
    var key: SettingsPath
    var options: [(title: String, value: AnyHashable)] = []

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(forKey: SettingsPath, withOptions: [(title: String, value: AnyHashable)]) {
        self.key = forKey
        super.init(frame: .zero, pullsDown: false)
        self.autoenablesItems = false
        self.setOptions(withOptions)
    }

    override public func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        if self.selectedItem != nil {
            for tuple in options where self.selectedItem!.title == tuple.title {
                UserDefaults.standard.setValue(tuple.value, forKey: key.rawValue)
            }
        }
        return super.sendAction(action, to: target)
    }

    public func setOptions(_ newOptions: [(title: String, value: AnyHashable)]) {
        let prefVal = UserDefaults.standard.object(forKey: self.key.rawValue) as? AnyHashable
        options = newOptions
        for (index, tuple) in newOptions.enumerated() {
            self.addItem(withTitle: tuple.title)
            if prefVal != nil && tuple.value as AnyHashable == prefVal! {
                self.selectItem(at: index)
            }
        }
    }
}

public class Settings: NSObject {
    let standardDefaults = UserDefaults.standard
    let continuous = [NSBindingOption.continuouslyUpdatesValue: true]

    class func registerDefaults() {
        let userDefaults = UserDefaults.standard
        userDefaults.register(
            defaults: settingsDefaults
        )
     }

    class func reset() {
        _ = settingsDefaults.map {
            UserDefaults.standard.removeObject(forKey: $0.key)
        }
        registerDefaults()
        let helper = "net.sf.Jumpcut.JumpcutHelper"
        if !SMLoginItemSetEnabled(helper as CFString, false) {
            #if DEBUG
                print("SMLoginItemSetEnabled for \(helper) (false) failed")
            #endif
        }
     }

    private func setAttributedTitle(button: NSButton, title: String) {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes = [NSAttributedString.Key.font: font]
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    /*
     A fixed checkbox is not bound to standard defaults; instead, the action is in
     charge of checking the logic and switching the underlying variable. The caller is
     currently responsible for setting the initial state.
     */
    func fixedCheckbox(title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = FixedButton()
        button.setButtonType(NSButton.ButtonType.switch)
        button.action = action
        button.target = target
        setAttributedTitle(button: button, title: title)
        return button
    }

    func checkbox(title: String, key: SettingsPath, target: AnyObject?, action: Selector?) -> NSButton {
        var button: NSButton
        if #available(macOS 10.12, *) {
            button = NSButton(checkboxWithTitle: title, target: target, action: action)
        } else {
            button = NSButton()
            button.setButtonType(NSButton.ButtonType.switch)
            button.action = action
            button.target = target
            setAttributedTitle(button: button, title: title)
        }
        button.bind(.value, to: standardDefaults, withKeyPath: key.rawValue, options: continuous)
        return button
    }

    func checkbox(title: String, key: SettingsPath) -> NSButton {
        return checkbox(title: title, key: key, target: nil, action: nil)
    }

    func popup(
        title: String, key: SettingsPath, options: [(title: String, value: AnyHashable)]
    ) -> NSStackView {
        let button = PreferencePopupButton(forKey: key, withOptions: options)
        let label = makeLabel(title: title)
        var popupArray = [NSView]()
        popupArray.append(label)
        popupArray.append(button)
        return NSStackView(views: popupArray)
    }

    func smallText(_ text: String) -> NSTextField {
        let interim = makeLabel(title: text)
        interim.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return interim
    }

    private func makeLabel(title: String) -> NSTextField {
        var label: NSTextField
        if #available(macOS 10.12, *) {
            label = NSTextField(labelWithString: title)
        } else {
            label = NSTextField()
            label.stringValue = title
            label.textColor = NSColor.labelColor
            label.backgroundColor = .clear
            label.drawsBackground = false
            label.alignment = .natural
            label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: label.controlSize))
            label.lineBreakMode = .byClipping
        }
        return label
    }

    func shortcutRecorder(title: String, key: SettingsPath) -> NSStackView {
        let label = makeLabel(title: title)
        let recorder = ShortcutRecorderView(frame: .zero)
        recorder.settingsKey = key
        recorder.bind(.value, to: UserDefaults.standard, withKeyPath: key.rawValue, options: nil)
        return NSStackView(views: [label, recorder])
    }

    func rangeStepper(title: String = "", minValue: Int, maxValue: Int, key: SettingsPath) -> NSStackView {
        let stp = NSStepper()
        stp.minValue = Double(minValue)
        stp.maxValue = Double(maxValue)
        let stpLabel = makeLabel(title: title)
        stpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let stpDisplay = makeLabel(title: "")
        stpDisplay.preferredMaxLayoutWidth = CGFloat(15.0)
        stp.bind(.value,
                 to: UserDefaults.standard,
                 withKeyPath: key.rawValue,
                 options: [NSBindingOption.continuouslyUpdatesValue: true])
        stp.valueWraps = false
        stpDisplay.bind(.value,
                        to: UserDefaults.standard,
                        withKeyPath: key.rawValue,
                        options: [NSBindingOption.continuouslyUpdatesValue: true])
        var stepperArray = [NSView]()
        stepperArray.append(stpLabel)
        stepperArray.append(stp)
        stepperArray.append(stpDisplay)
        return NSStackView(views: stepperArray)
    }

}
