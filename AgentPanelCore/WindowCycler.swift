//
//  WindowCycler.swift
//  AgentPanelCore
//
//  Cycles focus between windows in the focused workspace.
//  Uses AeroSpace to enumerate windows and focus the next/previous window
//  in list order, wrapping at boundaries.
//

import Foundation

/// Direction for window cycling.
public enum CycleDirection: Sendable {
    case next
    case previous
}

/// Cycles focus between windows in the focused AeroSpace workspace.
public struct WindowCycler {
    private let aerospace: AeroSpaceProviding

    /// Creates a window cycler with default dependencies.
    public init() {
        self.aerospace = ApAeroSpace()
    }

    /// Creates a window cycler with injected dependencies (for testing).
    init(aerospace: AeroSpaceProviding) {
        self.aerospace = aerospace
    }

    /// Cycles focus to the next or previous window in the focused workspace.
    ///
    /// - Parameter direction: `.next` for forward cycling, `.previous` for backward.
    /// - Returns: `.success(())` if focus was cycled or no action was needed,
    ///   `.failure` if AeroSpace returned an error.
    public func cycleFocus(direction: CycleDirection) -> Result<Void, ApCoreError> {
        // Get the currently focused window (includes workspace name)
        let focused: ApWindow
        switch aerospace.focusedWindow() {
        case .success(let w):
            focused = w
        case .failure(let error):
            return .failure(error)
        }

        // List all windows in the focused window's workspace
        let windows: [ApWindow]
        switch aerospace.listWindowsWorkspace(workspace: focused.workspace) {
        case .success(let w):
            windows = w
        case .failure(let error):
            return .failure(error)
        }

        // Nothing to cycle if 0 or 1 windows
        guard windows.count > 1 else {
            return .success(())
        }

        // Find the focused window in the list
        guard let currentIndex = windows.firstIndex(where: { $0.windowId == focused.windowId }) else {
            return .success(())
        }

        // Compute target index with wrapping
        let count = windows.count
        let targetIndex: Int
        switch direction {
        case .next:
            targetIndex = (currentIndex + 1) % count
        case .previous:
            targetIndex = (currentIndex - 1 + count) % count
        }

        return aerospace.focusWindow(windowId: windows[targetIndex].windowId)
    }
}
