import ApplicationServices
import CoreGraphics
import Foundation

/// Accessibility window management errors.
enum AccessibilityWindowError: Error, Equatable {
    case focusedWindowUnavailable(String)
    case attributeReadFailed(String)
    case attributeWriteFailed(String)
    case observerCreateFailed(String)
    case observerAddFailed(String)
    case windowNotFound(Int)
}

/// Protocol for registered AX observer tokens.
protocol AccessibilityObservationToken {
    func invalidate()
}

/// Token representing a registered AX observer.
final class AccessibilityObserverToken: AccessibilityObservationToken {
    private let observer: AXObserver
    private let element: AXUIElement
    private let notifications: [CFString]
    private let runLoopSource: CFRunLoopSource
    private var refcon: UnsafeMutableRawPointer?
    private var isActive: Bool = true

    init(
        observer: AXObserver,
        element: AXUIElement,
        notifications: [CFString],
        runLoopSource: CFRunLoopSource,
        refcon: UnsafeMutableRawPointer
    ) {
        self.observer = observer
        self.element = element
        self.notifications = notifications
        self.runLoopSource = runLoopSource
        self.refcon = refcon
    }

    deinit {
        invalidate()
    }

    /// Removes notifications and releases underlying resources.
    func invalidate() {
        guard isActive else { return }
        isActive = false
        for notification in notifications {
            AXObserverRemoveNotification(observer, element, notification)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        if let refcon {
            Unmanaged<ObserverHandlerBox>.fromOpaque(refcon).release()
            self.refcon = nil
        }
    }
}

/// Defines AX window interaction capabilities.
protocol AccessibilityWindowManaging {
    /// Returns the currently focused window element.
    func focusedWindowElement() -> Result<AXUIElement, AccessibilityWindowError>

    /// Returns the accessibility element for a specific window by ID.
    func element(for windowId: Int) -> Result<AXUIElement, AccessibilityWindowError>

    /// Reads the window frame as an AppKit coordinate CGRect.
    func frame(of element: AXUIElement, mainDisplayHeightPoints: CGFloat) -> Result<CGRect, AccessibilityWindowError>

    /// Sets the window frame using AppKit coordinates.
    func setFrame(
        _ frame: CGRect,
        for element: AXUIElement,
        mainDisplayHeightPoints: CGFloat
    ) -> Result<Void, AccessibilityWindowError>

    /// Adds observers for window move/resize notifications.
    func addObserver(
        for element: AXUIElement,
        notifications: [CFString],
        handler: @escaping () -> Void
    ) -> Result<AccessibilityObservationToken, AccessibilityWindowError>

    /// Removes an observer token.
    func removeObserver(_ token: AccessibilityObservationToken)
}

/// Default implementation backed by AX APIs.
struct AccessibilityWindowManager: AccessibilityWindowManaging {
    func focusedWindowElement() -> Result<AXUIElement, AccessibilityWindowError> {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedWindowAttribute as CFString, &value)
        guard error == .success, let element = value else {
            return .failure(.focusedWindowUnavailable("AXError \(error.rawValue)"))
        }
        return .success((element as! AXUIElement))
    }

    func element(for windowId: Int) -> Result<AXUIElement, AccessibilityWindowError> {
        // Use Core Graphics to get the window info and find the owning app
        let windowIdRef = CGWindowID(windowId)
        guard let cgWindows = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowIdRef) as? [[String: AnyObject]] else {
            return .failure(.windowNotFound(windowId))
        }

        guard let windowInfo = cgWindows.first else {
            return .failure(.windowNotFound(windowId))
        }

        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? Int32 else {
            return .failure(.windowNotFound(windowId))
        }

        // Get the window bounds from Core Graphics for matching
        guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
              let cgX = boundsDict["X"],
              let cgY = boundsDict["Y"],
              let cgWidth = boundsDict["Width"],
              let cgHeight = boundsDict["Height"] else {
            return .failure(.windowNotFound(windowId))
        }
        let cgBounds = CGRect(x: cgX, y: cgY, width: cgWidth, height: cgHeight)

        // Create AX element for the app
        let appElement = AXUIElementCreateApplication(pid)

        // Get the windows from the app
        var windowsRef: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard windowsError == .success, let axWindows = windowsRef as? [AXUIElement] else {
            return .failure(.windowNotFound(windowId))
        }

        // Find the AX window with matching bounds (position + size)
        for axWindow in axWindows {
            guard let position = readPointAttribute(axWindow, attribute: kAXPositionAttribute),
                  let size = readSizeAttribute(axWindow, attribute: kAXSizeAttribute) else {
                continue
            }

            // Core Graphics uses top-left origin, AX uses top-left origin too
            let axBounds = CGRect(origin: position, size: size)

            // A small tolerance is necessary because Core Graphics and Accessibility APIs may have
            // minor rounding differences in frame geometry, especially on scaled displays.
            let boundsMatchingTolerance: CGFloat = 2.0
            if abs(axBounds.origin.x - cgBounds.origin.x) < boundsMatchingTolerance &&
               abs(axBounds.origin.y - cgBounds.origin.y) < boundsMatchingTolerance &&
               abs(axBounds.width - cgBounds.width) < boundsMatchingTolerance &&
               abs(axBounds.height - cgBounds.height) < boundsMatchingTolerance {
                return .success(axWindow)
            }
        }

        // Fallback: if only one window, return it (common case)
        if axWindows.count == 1 {
            return .success(axWindows[0])
        }

        return .failure(.windowNotFound(windowId))
    }

    func frame(
        of element: AXUIElement,
        mainDisplayHeightPoints: CGFloat
    ) -> Result<CGRect, AccessibilityWindowError> {
        guard let position = readPointAttribute(element, attribute: kAXPositionAttribute) else {
            return .failure(.attributeReadFailed("Failed to read AX position"))
        }
        guard let size = readSizeAttribute(element, attribute: kAXSizeAttribute) else {
            return .failure(.attributeReadFailed("Failed to read AX size"))
        }
        let frame = axPositionTopLeftToAppKitFrame(
            position: position,
            size: size,
            mainDisplayHeightPoints: mainDisplayHeightPoints
        )
        return .success(frame)
    }

    func setFrame(
        _ frame: CGRect,
        for element: AXUIElement,
        mainDisplayHeightPoints: CGFloat
    ) -> Result<Void, AccessibilityWindowError> {
        let position = appKitFrameToAXPositionTopLeft(
            frame: frame,
            mainDisplayHeightPoints: mainDisplayHeightPoints
        )
        var positionPoint = CGPoint(x: position.x, y: position.y)
        var sizeValuePoint = CGSize(width: frame.width, height: frame.height)
        let positionValue = AXValueCreate(.cgPoint, &positionPoint)
        let sizeValue = AXValueCreate(.cgSize, &sizeValuePoint)

        guard let positionValue, let sizeValue else {
            return .failure(.attributeWriteFailed("Failed to create AX values"))
        }

        let positionError = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        if positionError != AXError.success {
            return .failure(.attributeWriteFailed("AX position set failed: \(positionError.rawValue)"))
        }

        let sizeError = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        if sizeError != AXError.success {
            return .failure(.attributeWriteFailed("AX size set failed: \(sizeError.rawValue)"))
        }

        return .success(())
    }

    func addObserver(
        for element: AXUIElement,
        notifications: [CFString],
        handler: @escaping () -> Void
    ) -> Result<AccessibilityObservationToken, AccessibilityWindowError> {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        let handlerBox = ObserverHandlerBox(handler: handler)
        let refcon = Unmanaged.passRetained(handlerBox).toOpaque()

        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let box = Unmanaged<ObserverHandlerBox>.fromOpaque(refcon).takeUnretainedValue()
            box.handler()
        }, &observer)

        guard result == .success, let observer else {
            Unmanaged<ObserverHandlerBox>.fromOpaque(refcon).release()
            return .failure(.observerCreateFailed("AXObserverCreate failed: \(result.rawValue)"))
        }

        for notification in notifications {
            let addResult = AXObserverAddNotification(observer, element, notification, refcon)
            if addResult != .success {
                for existing in notifications {
                    if existing == notification { break }
                    AXObserverRemoveNotification(observer, element, existing)
                }
                Unmanaged<ObserverHandlerBox>.fromOpaque(refcon).release()
                return .failure(.observerAddFailed("AXObserverAddNotification failed: \(addResult.rawValue)"))
            }
        }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        let token = AccessibilityObserverToken(
            observer: observer,
            element: element,
            notifications: notifications,
            runLoopSource: source,
            refcon: refcon
        )
        return .success(token)
    }

    func removeObserver(_ token: AccessibilityObservationToken) {
        token.invalidate()
    }

    private func readPointAttribute(_ element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else {
            return nil
        }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func readSizeAttribute(_ element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else {
            return nil
        }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}

private final class ObserverHandlerBox {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
}
