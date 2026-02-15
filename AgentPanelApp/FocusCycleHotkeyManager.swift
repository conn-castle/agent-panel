import AppKit
import Carbon

import AgentPanelCore

/// Manages global hotkeys for Option-Tab / Option-Shift-Tab window cycling.
///
/// Separate from `HotkeyManager` to isolate risk from the switcher hotkey.
/// Registers two Carbon hotkeys and dispatches to callbacks.
/// Registration is atomic: both hotkeys must succeed or both are rolled back.
final class FocusCycleHotkeyManager: FocusCycleStatusProviding {
    private let logger: AgentPanelLogging
    private var nextHotKeyRef: EventHotKeyRef?
    private var prevHotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handlerUPP: EventHandlerUPP?
    private(set) var registrationStatus: FocusCycleRegistrationStatus?

    /// Called when Option-Tab is pressed.
    var onCycleNext: (() -> Void)?
    /// Called when Option-Shift-Tab is pressed.
    var onCyclePrevious: (() -> Void)?

    init(logger: AgentPanelLogging = AgentPanelLogger()) {
        self.logger = logger
    }

    deinit {
        unregisterAll()
    }

    /// Registers Option-Tab and Option-Shift-Tab global hotkeys.
    /// Registration is atomic: if either hotkey fails, both are unregistered.
    func registerHotkeys() {
        unregisterAll()

        let statusHandler = installEventHandler()
        guard statusHandler == noErr else {
            _ = logger.log(
                event: "focus_cycle.handler_failed",
                level: .error,
                message: "Failed to install focus cycle event handler",
                context: ["osStatus": "\(statusHandler)"]
            )
            registrationStatus = .failed(osStatus: statusHandler)
            return
        }

        // Option-Tab → cycle next (ID 10)
        let nextResult = registerSingleHotkey(
            keyCode: UInt32(kVK_Tab),
            modifiers: UInt32(optionKey),
            id: nextHotkeyId,
            label: "Option-Tab"
        )

        // Option-Shift-Tab → cycle previous (ID 11)
        let prevResult = registerSingleHotkey(
            keyCode: UInt32(kVK_Tab),
            modifiers: UInt32(optionKey | shiftKey),
            id: prevHotkeyId,
            label: "Option-Shift-Tab"
        )

        // Atomic: both must succeed
        switch (nextResult.ref, nextResult.status, prevResult.ref, prevResult.status) {
        case (let nextRef?, noErr, let prevRef?, noErr):
            nextHotKeyRef = nextRef
            prevHotKeyRef = prevRef
            registrationStatus = .registered
        default:
            // Roll back any successful registration
            if let ref = nextResult.ref { UnregisterEventHotKey(ref) }
            if let ref = prevResult.ref { UnregisterEventHotKey(ref) }
            if let handler = handlerRef {
                RemoveEventHandler(handler)
                handlerRef = nil
            }
            handlerUPP = nil
            let failedStatus = nextResult.status != noErr ? nextResult.status : prevResult.status
            registrationStatus = .failed(osStatus: failedStatus)
            _ = logger.log(
                event: "focus_cycle.registration_failed",
                level: .error,
                message: "Focus cycle hotkey registration failed (atomic rollback)",
                context: ["nextStatus": "\(nextResult.status)", "prevStatus": "\(prevResult.status)"]
            )
        }
    }

    /// Returns the current focus-cycle registration status for Doctor integration.
    func focusCycleRegistrationStatus() -> FocusCycleRegistrationStatus? {
        registrationStatus
    }

    private func registerSingleHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32,
        label: String
    ) -> (ref: EventHotKeyRef?, status: OSStatus) {
        let hotKeyId = EventHotKeyID(signature: hotkeySignature, id: id)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            _ = logger.log(
                event: "focus_cycle.registered",
                level: .info,
                message: "\(label) hotkey registered",
                context: ["hotkey": label]
            )
        } else {
            _ = logger.log(
                event: "focus_cycle.registration_failed",
                level: .error,
                message: "\(label) hotkey registration failed",
                context: ["hotkey": label, "osStatus": "\(status)"]
            )
        }

        return (ref, status)
    }

    private func installEventHandler() -> OSStatus {
        let handler: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<FocusCycleHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotkeyEvent(eventRef)
        }

        handlerUPP = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        return InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )
    }

    private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
        var eventHotKeyId = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyId
        )

        guard status == noErr, eventHotKeyId.signature == hotkeySignature else {
            return OSStatus(eventNotHandledErr)
        }

        switch eventHotKeyId.id {
        case nextHotkeyId:
            onCycleNext?()
            return noErr
        case prevHotkeyId:
            onCyclePrevious?()
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func unregisterAll() {
        if let nextHotKeyRef {
            UnregisterEventHotKey(nextHotKeyRef)
            self.nextHotKeyRef = nil
        }
        if let prevHotKeyRef {
            UnregisterEventHotKey(prevHotKeyRef)
            self.prevHotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        handlerUPP = nil
    }

    private var hotkeySignature: OSType {
        OSType(0x41504346) // "APCF"
    }

    private var nextHotkeyId: UInt32 { 10 }
    private var prevHotkeyId: UInt32 { 11 }
}
