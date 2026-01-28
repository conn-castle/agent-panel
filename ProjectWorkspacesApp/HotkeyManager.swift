import AppKit
import Carbon

import ProjectWorkspacesCore

/// Manages global hotkey registration for the switcher.
final class HotkeyManager: HotkeyRegistrationStatusProviding {
    private let logger: ProjectWorkspacesLogging
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handlerUPP: EventHandlerUPP?
    private(set) var registrationStatus: HotkeyRegistrationStatus? {
        didSet {
            onStatusChange?(registrationStatus)
        }
    }

    /// Called when the hotkey is triggered.
    var onHotkey: (() -> Void)?

    /// Called whenever the registration status changes.
    var onStatusChange: ((HotkeyRegistrationStatus?) -> Void)?

    /// Creates a hotkey manager.
    /// - Parameter logger: Logger used to record registration failures.
    init(logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger()) {
        self.logger = logger
    }

    deinit {
        unregisterHotkey()
    }

    /// Registers the Cmd+Shift+Space global hotkey.
    func registerHotkey() {
        unregisterHotkey()

        let statusHandler = installEventHandler()
        guard statusHandler == noErr else {
            recordFailure(osStatus: statusHandler)
            return
        }

        let signature = hotkeySignature
        let hotKeyId = EventHotKeyID(signature: signature, id: hotkeyId)
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_Space)
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
            hotKeyRef = ref
            registrationStatus = .registered
        } else {
            recordFailure(osStatus: status)
            unregisterHotkey()
        }
    }

    /// Returns the last known registration status for Doctor integration.
    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus? {
        registrationStatus
    }

    private func installEventHandler() -> OSStatus {
        let handler: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else {
                return noErr
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotkeyEvent(eventRef)
            return noErr
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

    private func handleHotkeyEvent(_ event: EventRef) {
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

        guard status == noErr else {
            return
        }

        guard eventHotKeyId.signature == hotkeySignature, eventHotKeyId.id == hotkeyId else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onHotkey?()
        }
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }

        handlerUPP = nil
    }

    private func recordFailure(osStatus: OSStatus) {
        registrationStatus = .failed(osStatus: osStatus)
        _ = logger.log(
            event: "hotkey.registration_failed",
            level: .error,
            message: "Cmd+Shift+Space hotkey registration failed",
            context: ["osStatus": "\(osStatus)"]
        )
    }

    private var hotkeySignature: OSType {
        OSType(0x50574354) // "PWCT"
    }

    private var hotkeyId: UInt32 {
        1
    }
}
