import AppKit
import ApplicationServices
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

struct DoubleShiftDetector {
    private enum Phase {
        case idle
        case firstPress(keyCode: UInt16, at: TimeInterval)
        case firstRelease(keyCode: UInt16, at: TimeInterval)
        case secondPress(keyCode: UInt16, at: TimeInterval)
    }

    private static let maximumTapDuration: TimeInterval = 0.35
    private static let maximumGap: TimeInterval = 0.45
    private var phase: Phase = .idle

    mutating func reset() {
        phase = .idle
    }

    mutating func accept(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> Bool {
        guard type == .flagsChanged, keyCode == 56 || keyCode == 60 else {
            reset()
            return false
        }

        let relevantModifiers = modifiers.intersection([.shift, .control, .option, .command])
        if relevantModifiers == .shift {
            switch phase {
            case .firstRelease(let firstKey, let releasedAt)
                where firstKey == keyCode && timestamp - releasedAt <= Self.maximumGap && timestamp >= releasedAt:
                phase = .secondPress(keyCode: keyCode, at: timestamp)
            case .idle, .firstRelease:
                phase = .firstPress(keyCode: keyCode, at: timestamp)
            default:
                reset()
            }
        } else if relevantModifiers.isEmpty {
            switch phase {
            case .firstPress(let firstKey, let pressedAt)
                where firstKey == keyCode && timestamp - pressedAt <= Self.maximumTapDuration && timestamp >= pressedAt:
                phase = .firstRelease(keyCode: keyCode, at: timestamp)
            case .secondPress(let secondKey, let pressedAt)
                where secondKey == keyCode && timestamp - pressedAt <= Self.maximumTapDuration && timestamp >= pressedAt:
                reset()
                return true
            default:
                reset()
            }
        } else {
            reset()
        }
        return false
    }
}

final class GlobalHotKeyManager {
    private static let defaultsKey = "WeeklyFlow.globalShortcut"
    private static let doubleShiftDefaultsKey = "WeeklyFlow.doubleShiftEnabled"
    private let onPress: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var globalShiftMonitor: Any?
    private var localShiftMonitor: Any?
    private var doubleShiftDetector = DoubleShiftDetector()
    private var doubleShiftSuspended = false
    private(set) var shortcut: GlobalShortcut?
    private(set) var registrationError: String?
    private(set) var doubleShiftEnabled: Bool

    var doubleShiftNeedsPermission: Bool {
        doubleShiftEnabled && !AXIsProcessTrusted()
    }

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        doubleShiftEnabled = UserDefaults.standard.bool(forKey: Self.doubleShiftDefaultsKey)
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
        refreshDoubleShiftMonitoring()
    }

    deinit {
        suspend()
        stopDoubleShiftMonitoring()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func setDoubleShiftEnabled(_ enabled: Bool) {
        doubleShiftEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.doubleShiftDefaultsKey)
        if enabled && !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        refreshDoubleShiftMonitoring()
    }

    func refreshDoubleShiftMonitoring() {
        stopDoubleShiftMonitoring()
        guard doubleShiftEnabled, !doubleShiftSuspended, AXIsProcessTrusted() else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalShiftMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.acceptDoubleShiftEvent(event)
        }
        localShiftMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.acceptDoubleShiftEvent(event)
            return event
        }
    }

    func suspendDoubleShift() {
        doubleShiftSuspended = true
        stopDoubleShiftMonitoring()
    }

    func resumeDoubleShift() {
        doubleShiftSuspended = false
        refreshDoubleShiftMonitoring()
    }

    private func stopDoubleShiftMonitoring() {
        if let globalShiftMonitor { NSEvent.removeMonitor(globalShiftMonitor) }
        if let localShiftMonitor { NSEvent.removeMonitor(localShiftMonitor) }
        globalShiftMonitor = nil
        localShiftMonitor = nil
        doubleShiftDetector.reset()
    }

    private func acceptDoubleShiftEvent(_ event: NSEvent) {
        if Thread.isMainThread {
            handleDoubleShiftEvent(event)
        } else {
            DispatchQueue.main.async { [weak self] in self?.handleDoubleShiftEvent(event) }
        }
    }

    private func handleDoubleShiftEvent(_ event: NSEvent) {
        guard doubleShiftEnabled, !doubleShiftSuspended else { return }
        if doubleShiftDetector.accept(
            type: event.type,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            timestamp: event.timestamp
        ) {
            DispatchQueue.main.async { [weak self] in self?.onPress() }
        }
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
