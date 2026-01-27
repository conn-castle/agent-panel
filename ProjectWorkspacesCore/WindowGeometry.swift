import ApplicationServices
import Foundation

/// Errors emitted when applying window geometry.
public enum WindowGeometryError: Error, Equatable, Sendable {
    case aeroSpaceFailed(AeroSpaceCommandError)
    case axError(detail: String)
}

/// Result of attempting to apply window geometry.
public enum WindowGeometryOutcome: Equatable, Sendable {
    case applied
    case skipped(reason: LayoutSkipReason)
    case failed(error: WindowGeometryError)
}

/// Applies geometry to a window id.
public protocol WindowGeometryApplying {
    /// Applies geometry to the target window.
    /// - Parameters:
    ///   - frame: Frame in screen points.
    ///   - windowId: Target window id.
    ///   - workspaceName: Expected workspace name for focus verification.
    /// - Returns: Outcome describing whether geometry was applied.
    func apply(frame: CGRect, toWindowId windowId: Int, inWorkspace workspaceName: String) -> WindowGeometryOutcome
}

/// Focuses a window by id.
protocol WindowFocusing {
    /// Focuses the provided window id.
    /// - Parameter windowId: AeroSpace window id to focus.
    /// - Returns: Command result or a structured error.
    func focus(windowId: Int) -> Result<CommandResult, AeroSpaceCommandError>
}

extension AeroSpaceClient: WindowFocusing {
    /// Focuses a window by id using AeroSpace.
    func focus(windowId: Int) -> Result<CommandResult, AeroSpaceCommandError> {
        focusWindow(windowId: windowId)
    }
}

/// Verifies focus before applying geometry.
protocol FocusVerifying {
    /// Verifies that the focused window matches the expected window id and workspace.
    /// - Parameters:
    ///   - windowId: Expected window id.
    ///   - workspaceName: Expected workspace name.
    /// - Returns: Verification result with the last observed focus state.
    func verify(windowId: Int, workspaceName: String) -> FocusVerificationResult
}

struct FocusVerificationResult: Equatable {
    let matches: Bool
    let actualWindowId: Int?
    let actualWorkspace: String?
}

/// Queries focused window information.
protocol FocusedWindowQuerying {
    /// Lists the currently focused window as decoded models.
    /// - Returns: Decoded windows (typically one) or a structured error.
    func listWindowsFocusedDecoded() -> Result<[AeroSpaceWindow], AeroSpaceCommandError>
}

extension AeroSpaceClient: FocusedWindowQuerying {}

/// Focus verifier backed by AeroSpace focused window queries.
struct AeroSpaceFocusVerifier: FocusVerifying {
    private let focusedWindowQuery: FocusedWindowQuerying
    private let sleeper: AeroSpaceSleeping
    private let attempts: Int
    private let delayMs: Int

    /// Creates a focus verifier.
    /// - Parameters:
    ///   - focusedWindowQuery: Query interface for focused window information.
    ///   - sleeper: Sleeper used between verification attempts.
    ///   - attempts: Number of verification attempts.
    ///   - delayMs: Delay in milliseconds between attempts.
    init(
        focusedWindowQuery: FocusedWindowQuerying,
        sleeper: AeroSpaceSleeping,
        attempts: Int,
        delayMs: Int
    ) {
        self.focusedWindowQuery = focusedWindowQuery
        self.sleeper = sleeper
        self.attempts = attempts
        self.delayMs = delayMs
    }

    /// Convenience initializer for AeroSpaceClient.
    /// - Parameters:
    ///   - aeroSpaceClient: AeroSpace client used to query focused windows.
    ///   - sleeper: Sleeper used between verification attempts.
    ///   - attempts: Number of verification attempts.
    ///   - delayMs: Delay in milliseconds between attempts.
    init(
        aeroSpaceClient: AeroSpaceClient,
        sleeper: AeroSpaceSleeping,
        attempts: Int,
        delayMs: Int
    ) {
        self.init(
            focusedWindowQuery: aeroSpaceClient,
            sleeper: sleeper,
            attempts: attempts,
            delayMs: delayMs
        )
    }

    /// Verifies the focused window using AeroSpace list-windows --focused.
    func verify(windowId: Int, workspaceName: String) -> FocusVerificationResult {
        var lastActualId: Int?
        var lastActualWorkspace: String?
        let delaySeconds = TimeInterval(delayMs) / 1000.0

        for attempt in 0..<attempts {
            switch focusedWindowQuery.listWindowsFocusedDecoded() {
            case .failure:
                lastActualId = nil
                lastActualWorkspace = nil
            case .success(let windows):
                if let focused = windows.first {
                    lastActualId = focused.windowId
                    lastActualWorkspace = focused.workspace
                    if focused.windowId == windowId, focused.workspace == workspaceName {
                        return FocusVerificationResult(
                            matches: true,
                            actualWindowId: focused.windowId,
                            actualWorkspace: focused.workspace
                        )
                    }
                }
            }

            if attempt < attempts - 1 {
                sleeper.sleep(seconds: delaySeconds)
            }
        }

        return FocusVerificationResult(
            matches: false,
            actualWindowId: lastActualId,
            actualWorkspace: lastActualWorkspace
        )
    }
}

/// AX-backed geometry applier with focus verification.
struct AXWindowGeometryApplier: WindowGeometryApplying {
    private let focusController: WindowFocusing
    private let focusVerifier: FocusVerifying
    private let accessibilityApplier: WindowAccessibilityApplying

    /// Creates an AX geometry applier.
    /// - Parameters:
    ///   - focusVerifier: Focus verification helper.
    ///   - accessibilityApplier: AX applier for position/size updates.
    init(
        focusController: WindowFocusing,
        focusVerifier: FocusVerifying,
        accessibilityApplier: WindowAccessibilityApplying = AXWindowAccessibilityApplier()
    ) {
        self.focusController = focusController
        self.focusVerifier = focusVerifier
        self.accessibilityApplier = accessibilityApplier
    }

    /// Applies geometry to a window after verifying focus.
    func apply(frame: CGRect, toWindowId windowId: Int, inWorkspace workspaceName: String) -> WindowGeometryOutcome {
        switch focusController.focus(windowId: windowId) {
        case .success:
            break
        case .failure(let error):
            return .failed(error: .aeroSpaceFailed(error))
        }

        let verification = focusVerifier.verify(windowId: windowId, workspaceName: workspaceName)
        guard verification.matches else {
            return .skipped(
                reason: .focusNotVerified(
                    expectedWindowId: windowId,
                    expectedWorkspace: workspaceName,
                    actualWindowId: verification.actualWindowId,
                    actualWorkspace: verification.actualWorkspace
                )
            )
        }

        switch accessibilityApplier.apply(frame: frame) {
        case .success:
            return .applied
        case .failure(let error):
            return .failed(error: error)
        }
    }
}

/// Applies AX position and size updates to the focused window.
protocol WindowAccessibilityApplying {
    /// Applies position and size to the focused window.
    /// - Parameter frame: Frame in screen points.
    /// - Returns: Success or a structured geometry error.
    func apply(frame: CGRect) -> Result<Void, WindowGeometryError>
}

struct AXWindowAccessibilityApplier: WindowAccessibilityApplying {
    /// Applies AX position and size updates to the focused window.
    func apply(frame: CGRect) -> Result<Void, WindowGeometryError> {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(system, kAXFocusedWindowAttribute as CFString, &focused)
        guard focusedResult == .success, let focusedWindow = focused else {
            return .failure(.axError(detail: "Failed to read focused window (AX error \(focusedResult.rawValue))."))
        }
        guard CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else {
            return .failure(.axError(detail: "Focused window attribute was not an AXUIElement."))
        }
        let focusedElement = unsafeBitCast(focusedWindow, to: AXUIElement.self)

        var point = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.size.width, height: frame.size.height)

        guard let positionValue = AXValueCreate(.cgPoint, &point) else {
            return .failure(.axError(detail: "Failed to create AXValue for position."))
        }
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            return .failure(.axError(detail: "Failed to create AXValue for size."))
        }

        let positionResult = AXUIElementSetAttributeValue(focusedElement, kAXPositionAttribute as CFString, positionValue)
        guard positionResult == .success else {
            return .failure(.axError(detail: "Failed to set AX position (AX error \(positionResult.rawValue))."))
        }

        let sizeResult = AXUIElementSetAttributeValue(focusedElement, kAXSizeAttribute as CFString, sizeValue)
        guard sizeResult == .success else {
            return .failure(.axError(detail: "Failed to set AX size (AX error \(sizeResult.rawValue))."))
        }

        return .success(())
    }
}
