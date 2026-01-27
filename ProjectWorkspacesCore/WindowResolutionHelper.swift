import Foundation

/// Helper for resolving and ensuring windows exist in a workspace.
struct WindowResolutionHelper {
    private let aeroSpaceClient: AeroSpaceClient

    /// Creates a window resolution helper.
    /// - Parameter aeroSpaceClient: AeroSpace client for window queries and moves.
    init(aeroSpaceClient: AeroSpaceClient) {
        self.aeroSpaceClient = aeroSpaceClient
    }

    /// Ensures a window of the given bundle ID exists in the workspace.
    ///
    /// Resolution order:
    /// 1. If managed ID exists and is already in the workspace, reuse it.
    /// 2. If not found, call the creation closure.
    ///
    /// - Parameters:
    ///   - bundleId: Bundle identifier to filter windows.
    ///   - workspaceName: Target workspace name.
    ///   - kind: Window kind for warnings.
    ///   - managedWindowId: Previously managed window ID if any.
    ///   - projectId: Project identifier for warning context.
    ///   - warnings: Warning accumulator.
    ///   - recordWarning: Callback to record warnings.
    ///   - createWindow: Closure to create a new window if needed.
    /// - Returns: Window resolution with ID and creation/move status, or error.
    func ensureWindow(
        bundleId: String,
        workspaceName: String,
        kind _: ActivationWindowKind,
        managedWindowId: Int?,
        projectId _: String,
        warnings: inout [ActivationWarning],
        recordWarning _: (ActivationWarning, String, String, inout [ActivationWarning]) -> Void,
        createWindow: (inout [ActivationWarning]) -> Result<WindowResolution, ActivationError>
    ) -> Result<WindowResolution, ActivationError> {
        // Step 1: Check if managed window exists in the workspace
        if let managedWindowId {
            switch aeroSpaceClient.listWindowsDecoded(workspace: workspaceName) {
            case .failure(let error):
                return .failure(.aeroSpaceFailed(error))
            case .success(let windows):
                if windows.contains(where: { $0.windowId == managedWindowId }) {
                    return .success(WindowResolution(windowId: managedWindowId, created: false, moved: false))
                }
            }
        }

        // Step 2: Create new window
        return createWindow(&warnings)
    }

    /// Selects a window ID from sorted IDs, emitting warnings for multiples.
    func selectFromIds(
        _ sortedIds: [Int],
        managedWindowId: Int?,
        kind: ActivationWindowKind,
        workspaceName: String
    ) -> WindowSelection {
        let chosenId: Int
        if let managedWindowId, sortedIds.contains(managedWindowId) {
            chosenId = managedWindowId
        } else {
            chosenId = sortedIds[0]
        }

        let extras = sortedIds.filter { $0 != chosenId }
        let warning: ActivationWarning?
        if sortedIds.count > 1 {
            warning = ActivationWarning.multipleWindows(
                kind: kind,
                workspace: workspaceName,
                chosenId: chosenId,
                extraIds: extras
            )
        } else {
            warning = nil
        }

        return WindowSelection(windowId: chosenId, warning: warning)
    }
}

/// Result of window selection from a list.
struct WindowSelection {
    let windowId: Int
    let warning: ActivationWarning?
}

/// Result of window resolution (ID, whether created, whether moved).
struct WindowResolution {
    let windowId: Int
    let created: Bool
    let moved: Bool
}
