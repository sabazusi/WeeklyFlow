import AppKit
import Carbon
import Foundation

struct GlobalShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let modifierCount = [NSEvent.ModifierFlags.control, .option, .shift, .command]
            .filter { flags.contains($0) }.count
        guard modifierCount >= 2,
              let character = event.charactersIgnoringModifiers?.first,
              character.isASCII,
              character.isLetter || character.isNumber else { return nil }

        keyCode = UInt32(event.keyCode)
        keyLabel = String(character).uppercased()
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        modifiers = carbonModifiers
    }

    var displayName: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyLabel
    }
}

final class GlobalHotKeyManager {
    private static let defaultsKey = "WeeklyFlow.globalShortcut"
    private let onPress: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private(set) var shortcut: GlobalShortcut?
    private(set) var registrationError: String?

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onPress() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            registrationError = "ショートカットを監視できませんでした（\(status)）"
        } else if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
                  let saved = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            do {
                try register(saved)
                shortcut = saved
            } catch {
                registrationError = error.localizedDescription
                shortcut = saved
            }
        }
    }

    deinit {
        suspend()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func suspend() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    func resume() {
        guard hotKey == nil, let shortcut else { return }
        do {
            try register(shortcut)
            registrationError = nil
        } catch {
            registrationError = error.localizedDescription
        }
    }

    func update(_ candidate: GlobalShortcut?) throws {
        let previous = shortcut
        suspend()
        do {
            if let candidate { try register(candidate) }
            shortcut = candidate
            registrationError = nil
            if let candidate {
                UserDefaults.standard.set(try JSONEncoder().encode(candidate), forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
        } catch {
            if let previous { try? register(previous) }
            shortcut = previous
            registrationError = error.localizedDescription
            throw error
        }
    }

    private func register(_ shortcut: GlobalShortcut) throws {
        guard eventHandler != nil else {
            throw HotKeyError.unavailable
        }
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x57464C57, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw HotKeyError.conflict
        }
        hotKey = reference
    }
}

private enum HotKeyError: LocalizedError {
    case unavailable
    case conflict

    var errorDescription: String? {
        switch self {
        case .unavailable: "キーボードショートカットを利用できません。"
        case .conflict: "このショートカットは登録できません。別の組み合わせを試してください。"
        }
    }
}
