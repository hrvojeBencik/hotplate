import Carbon
import Foundation

/// System-wide keyboard shortcuts via Carbon hot keys (no accessibility permission needed).
/// ⌃⌥R = hot reload, ⌃⌥⇧R = hot restart.
final class HotKeyManager {
    static let shared = HotKeyManager()
    enum Action: UInt32 { case hotReload = 1, hotRestart = 2 }

    var onAction: ((Action) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let signature = OSType(0x4652_5552)   // "FRUR"

    func register() {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let action = Action(rawValue: id.id) { manager.onAction?(action) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let base = UInt32(controlKey | optionKey)
        add(.hotReload, key: UInt32(kVK_ANSI_R), modifiers: base)
        add(.hotRestart, key: UInt32(kVK_ANSI_R), modifiers: base | UInt32(shiftKey))
    }

    private func add(_ action: Action, key: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: action.rawValue)
        if RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}
