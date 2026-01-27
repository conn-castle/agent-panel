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
    /// 1. Check workspace for existing windows matching bundle ID
    /// 2. If managed ID exists, look globally and move if found elsewhere
    /// 3. If not found, call the creation closure
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
        kind: ActivationWindowKind,
        managedWindowId: Int?,
        projectId: String,
        warnings: inout [ActivationWarning],
        recordWarning: (ActivationWarning, String, String, inout [ActivationWarning]) -> Void,
        createWindow: (inout [ActivationWarning]) -> Result<WindowResolution, ActivationError>
    ) -> Result<WindowResolution, ActivationError> {
        // Step 1: Check workspace for existing windows
        let workspaceResult = aeroSpaceClient.listWindowsDecoded(workspace: workspaceName)
        let workspaceWindows: [AeroSpaceWindow]
        switch workspaceResult {
        case .failure(let error):
            return .failure(.aeroSpaceFailed(error))
        case .success(let windows):
            workspaceWindows = windows
        }

        let matchingWindows = workspaceWindows.filter { $0.appBundleId == bundleId }
        if let selection = selectWindow(from: matchingWindows, managedWindowId: managedWindowId, kind: kind, workspaceName: workspaceName) {
            if let warning = selection.warning {
                recordWarning(warning, projectId, workspaceName, &warnings)
            }
            return .success(WindowResolution(windowId: selection.windowId, created: false, moved: false))
        }

        // Step 2: Check if managed window exists elsewhere and move it
        if let managedWindowId {
            switch aeroSpaceClient.listWindowsAllDecoded() {
            case .failure(let error):
                return .failure(.aeroSpaceFailed(error))
            case .success(let windows):
                if let managedWindow = windows.first(where: { $0.windowId == managedWindowId }) {
                    if managedWindow.workspace == workspaceName {
                        return .success(WindowResolution(windowId: managedWindowId, created: false, moved: false))
                    }
                    let moveOutcome = aeroSpaceClient.moveWindow(windowId: managedWindowId, to: workspaceName)
                    switch moveOutcome {
                    case .success:
                        return .success(WindowResolution(windowId: managedWindowId, created: false, moved: true))
                    case .failure(let error):
                        let warning = ActivationWarning.moveFailed(
                            kind: kind,
                            windowId: managedWindowId,
                            workspace: workspaceName,
                            error: error
                        )
                        recordWarning(warning, projectId, workspaceName, &warnings)
                    }
                }
            }
        }

        // Step 3: Create new window
        return createWindow(&warnings)
    }

    /// Selects a window ID from the workspace list using deterministic rules.
    private func selectWindow(
        from windows: [AeroSpaceWindow],
        managedWindowId: Int?,
        kind: ActivationWindowKind,
        workspaceName: String
    ) -> WindowSelection? {
        let ids = windows.map { $0.windowId }
        guard !ids.isEmpty else {
            return nil
        }
        let sortedIds = ids.sorted()
        return selectFromIds(sortedIds, managedWindowId: managedWindowId, kind: kind, workspaceName: workspaceName)
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
