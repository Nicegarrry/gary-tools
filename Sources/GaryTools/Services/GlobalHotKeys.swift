import Carbon
import Foundation
import GaryCore

/// Single Carbon hotkey dispatcher shared by Clipboard and Menu Bar modules.
@MainActor
final class GlobalHotKeys {
    private static let signature: OSType = 0x47544F4C // 'GTOL'
    private var handler: EventHandlerRef?
    private var references: [UInt32: EventHotKeyRef] = [:]

    var onToggleClipboard: (() -> Void)?
    var onPasteStack: (() -> Void)?
    var onRevealMenuBar: (() -> Void)?
    var onContextGrab: (() -> Void)?

    private(set) var clipboardRegistered = false
    private(set) var stackRegistered = false
    private(set) var revealRegistered = false
    private(set) var contextGrabRegistered = false

    func register(clipboardPrefs: ClipboardPreferences, enableRevealShortcut: Bool) -> Bool {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            )
            guard status == noErr, id.signature == GlobalHotKeys.signature else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
                switch id.id {
                case 1: owner.onToggleClipboard?()
                case 2: owner.onPasteStack?()
                case 3: owner.onRevealMenuBar?()
                case 4: owner.onContextGrab?()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, pointer, &handler)
        guard installed == noErr else { return false }

        let keys: [String: UInt32] = ["V": 9, "Space": 49, "B": 11]
        let modifiers: UInt32
        switch clipboardPrefs.shortcutModifiers {
        case "commandShift": modifiers = UInt32(cmdKey | shiftKey)
        case "commandOption": modifiers = UInt32(cmdKey | optionKey)
        default: modifiers = UInt32(controlKey | optionKey)
        }

        var clipRef: EventHotKeyRef?
        let clipStatus = RegisterEventHotKey(
            keys[clipboardPrefs.shortcutKey] ?? 9,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &clipRef
        )
        if let clipRef { references[1] = clipRef }
        clipboardRegistered = (clipStatus == noErr)

        var stackRef: EventHotKeyRef?
        let stackStatus = RegisterEventHotKey(
            35, // P
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: Self.signature, id: 2),
            GetApplicationEventTarget(),
            0,
            &stackRef
        )
        if let stackRef { references[2] = stackRef }
        stackRegistered = (stackStatus == noErr)

        if enableRevealShortcut {
            var revealRef: EventHotKeyRef?
            let revealStatus = RegisterEventHotKey(
                UInt32(kVK_Space),
                UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: Self.signature, id: 3),
                GetApplicationEventTarget(),
                0,
                &revealRef
            )
            if let revealRef { references[3] = revealRef }
            revealRegistered = (revealStatus == noErr)
        } else {
            revealRegistered = false
        }

        var grabRef: EventHotKeyRef?
        let grabStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_G),
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: Self.signature, id: 4),
            GetApplicationEventTarget(),
            0,
            &grabRef
        )
        if let grabRef { references[4] = grabRef }
        contextGrabRegistered = (grabStatus == noErr)

        return clipboardRegistered && stackRegistered
    }

    func unregister() {
        for (_, ref) in references { UnregisterEventHotKey(ref) }
        references.removeAll()
        clipboardRegistered = false
        stackRegistered = false
        revealRegistered = false
        contextGrabRegistered = false
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
