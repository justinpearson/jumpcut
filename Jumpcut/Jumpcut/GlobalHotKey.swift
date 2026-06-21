//
//  GlobalHotKey.swift
//  Jumpcut
//
//  Replaces the third-party HotKey library with direct Carbon Event API calls.
//

import Carbon
import Foundation

class GlobalHotKey {
    var keyDownHandler: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID: EventHotKeyID

    private static var instances: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandler: EventHandlerRef?

    init(carbonKeyCode: UInt32, carbonModifiers: UInt32) {
        let id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        hotKeyID = EventHotKeyID(signature: OSType(0x4A43), id: id) // "JC"

        GlobalHotKey.installHandlerIfNeeded()
        GlobalHotKey.instances[id] = self

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            carbonKeyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        GlobalHotKey.instances.removeValue(forKey: hotKeyID.id)
    }

    private static func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    UInt32(kEventParamDirectObject),
                    UInt32(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                if let instance = GlobalHotKey.instances[hotKeyID.id] {
                    instance.keyDownHandler?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }
}
