import Carbon.HIToolbox
import MouldCore

/// A system-wide hotkey via Carbon's RegisterEventHotKey: works from any app and, unlike
/// an NSEvent global monitor, needs no Accessibility permission.
@MainActor
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void
    let combo: KeyCombo

    init?(combo: KeyCombo, action: @escaping @MainActor () -> Void) {
        self.combo = combo
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, me, &handlerRef) == noErr else {
            return nil
        }
        let id = EventHotKeyID(signature: OSType(0x4D4F_4C44) /* 'MOLD' */, id: 1)
        guard RegisterEventHotKey(combo.keyCode, combo.modifiers.rawValue, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
