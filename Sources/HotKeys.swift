import AppKit
import Carbon.HIToolbox

/// 全局快捷键（Carbon RegisterEventHotKey，无需辅助功能权限）
final class HotKeys {
    static let shared = HotKeys()
    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false

    private init() {}

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers,
                                         EventHotKeyID(signature: OSType(0x544E4154) /* "TNAT" */, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            handlers[id] = handler
        } else {
            log("快捷键注册失败 id=\(id) status=\(status)")
        }
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKeys.shared.dispatch(id: id.id)
            return noErr
        }, 1, &eventType, nil, nil)
    }

    private func dispatch(id: UInt32) {
        DispatchQueue.main.async { self.handlers[id]?() }
    }
}

/// Carbon 修饰键与键码常量
enum HK {
    static let opt = UInt32(optionKey)
    static let shift = UInt32(shiftKey)
    static let q = UInt32(kVK_ANSI_Q)
    static let w = UInt32(kVK_ANSI_W)
    static let e = UInt32(kVK_ANSI_E)
}
