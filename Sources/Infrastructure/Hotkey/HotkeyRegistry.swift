import AppKit
import Carbon.HIToolbox
import ConsolepilotDomain
import Foundation

@MainActor
final class HotkeyRegistry {
    private static let signature: OSType = 0x4350_4C54  // "CPLT"
    private let systemRegistrationEnabled: Bool
    private var registrations: [String: HotkeySpec] = [:]
    private var handlers: [String: @MainActor () -> Void] = [:]
    private var namesByID: [UInt32: String] = [:]
    private var systemHotkeys: [String: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private var pendingPresses: [String: (count: Int, lastPress: ContinuousClock.Instant)] = [:]
    private let doublePressWindow: Duration = .milliseconds(420)
    private var lastExternalProcessID: pid_t?
    private var workspaceObserver: NSObjectProtocol?

    init(systemRegistrationEnabled: Bool = false) {
        self.systemRegistrationEnabled = systemRegistrationEnabled
        if systemRegistrationEnabled {
            installEventHandler()
            trackExternalFrontmostApplication()
        }
    }

    func register(name: String, spec: HotkeySpec, handler: @escaping @MainActor () -> Void) -> Bool {
        guard registrations[name] == nil else { return false }
        if systemRegistrationEnabled {
            guard let keyCode = Self.keyCode(for: spec.key) else { return false }
            let id = nextID
            nextID &+= 1
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode, Self.carbonModifiers(spec.modifiers),
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else { return false }
            systemHotkeys[name] = reference
            namesByID[id] = name
        }
        registrations[name] = spec
        handlers[name] = handler
        pendingPresses.removeValue(forKey: name)
        return true
    }

    func unregister(name: String) {
        if let reference = systemHotkeys.removeValue(forKey: name) {
            UnregisterEventHotKey(reference)
        }
        namesByID = namesByID.filter { $0.value != name }
        registrations.removeValue(forKey: name)
        handlers.removeValue(forKey: name)
        pendingPresses.removeValue(forKey: name)
    }

    func replaceAll(_ values: [String: (HotkeySpec, @MainActor () -> Void)]) {
        for name in registrations.keys { unregister(name: name) }
        for (name, value) in values { _ = register(name: name, spec: value.0, handler: value.1) }
    }

    func removeAll() {
        for name in Array(registrations.keys) { unregister(name: name) }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    /// Test and internal hook that follows the same single/double-press
    /// semantics as a Carbon event.
    func trigger(name: String) { handlePress(name: name) }
    var registeredNames: Set<String> { Set(registrations.keys) }

    private func installEventHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
                guard status == noErr, hotkeyID.signature == HotkeyRegistry.signature else { return status }
                let registry = Unmanaged<HotkeyRegistry>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { registry.handleSystemHotkey(id: hotkeyID.id) }
                return noErr
            },
            1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func handleSystemHotkey(id: UInt32) {
        guard let name = namesByID[id] else { return }
        if let spec = registrations[name], spec.key == "c", spec.modifiers == ["cmd"] {
            // RegisterEventHotKey consumes the physical event. Replay the
            // native Command+C to the original foreground app so ordinary
            // copy continues to work while the double-press detector runs.
            relayCommandC()
        }
        handlePress(name: name)
    }

    private func handlePress(name: String) {
        guard let spec = registrations[name], spec.pressCount == 2 else {
            handlers[name]?()
            return
        }
        let now = ContinuousClock.now
        if let pending = pendingPresses[name], now - pending.lastPress <= doublePressWindow {
            pendingPresses.removeValue(forKey: name)
            handlers[name]?()
        } else {
            pendingPresses[name] = (count: 1, lastPress: now)
        }
    }

    private func relayCommandC() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Carbon consumes the registered key event. When Consolepilot itself
        // is frontmost, invoke AppKit's normal copy responder chain directly
        // so a single Command+C still copies selected transcript/config text.
        if frontmostPID == ownPID {
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            return
        }
        guard let targetPID = lastExternalProcessID ?? frontmostPID,
            targetPID != ownPID
        else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(targetPID)
        up.postToPid(targetPID)
    }

    private func trackExternalFrontmostApplication() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID {
            lastExternalProcessID = app.processIdentifier
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                app.processIdentifier != ownPID
            else { return }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in self?.lastExternalProcessID = pid }
        }
    }

    private static func carbonModifiers(_ values: Set<String>) -> UInt32 {
        values.reduce(0) { result, value in
            switch value {
            case "cmd": return result | UInt32(cmdKey)
            case "ctrl": return result | UInt32(controlKey)
            case "alt": return result | UInt32(optionKey)
            case "shift": return result | UInt32(shiftKey)
            default: return result
            }
        }
    }

    private static func keyCode(for key: String) -> UInt32? {
        let codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9, "`": kVK_ANSI_Grave,
        ]
        return codes[key.lowercased()].map(UInt32.init)
    }
}
