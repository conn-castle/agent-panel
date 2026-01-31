import Foundation

/// Snapshot of the previously focused window/workspace for restoration.
public struct WorkspaceFocusSnapshot: Equatable, Sendable {
    public let windowId: Int?
    public let workspaceName: String?

    /// Creates a focus snapshot.
    /// - Parameters:
    ///   - windowId: Focused window id, if available.
    ///   - workspaceName: Focused workspace name, if available.
    public init(windowId: Int?, workspaceName: String?) {
        self.windowId = windowId
        self.workspaceName = workspaceName
    }
}

/// Facade for workspace lifecycle operations used by the App layer.
public protocol WorkspaceManaging {
    /// Activates the project workspace for the given project id.
    /// - Parameters:
    ///   - projectId: Project identifier to activate.
    ///   - focusIdeWindow: Whether to focus the IDE window at the end of activation.
    ///   - switchWorkspace: Whether to switch to the project workspace during activation.
    ///   - progress: Optional progress sink for activation milestones.
    ///   - cancellationToken: Optional token used to cancel activation.
    /// - Returns: Activation outcome with warnings or failure.
    func activate(
        projectId: String,
        focusIdeWindow: Bool,
        switchWorkspace: Bool,
        progress: ((ActivationProgress) -> Void)?,
        cancellationToken: ActivationCancellationToken?
    ) -> ActivationOutcome

    /// Focuses the provided workspace and IDE window id after activation.
    /// - Parameter report: Activation report that includes workspace and IDE window information.
    /// - Returns: Success or a structured activation error.
    func focusWorkspaceAndWindow(report: ActivationReport) -> Result<Void, ActivationError>

    /// Captures the current focused window/workspace (best effort).
    /// - Returns: Snapshot with the focused window and/or workspace.
    func captureFocusSnapshot() -> WorkspaceFocusSnapshot?

    /// Restores focus to a previously captured window/workspace (best effort).
    /// - Parameter snapshot: Snapshot captured earlier.
    func restoreFocusSnapshot(_ snapshot: WorkspaceFocusSnapshot)

    /// Checks whether a workspace exists (best effort).
    /// - Parameter name: Workspace name to look up.
    /// - Returns: True if the workspace exists.
    func workspaceExists(name: String) -> Bool
}

/// Default Core facade used by the App layer.
public struct DefaultWorkspaceManager: WorkspaceManaging {
    private let activationService: ActivationService
    private let focusProvider: WorkspaceFocusProviding

    /// Creates the default workspace manager.
    /// - Parameters:
    ///   - activationService: Activation service implementation.
    ///   - logger: Logger used for focus provider diagnostics.
    ///   - focusTimeoutSeconds: Timeout for focus provider commands.
    public init(
        activationService: ActivationService = ActivationService(),
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger(),
        focusTimeoutSeconds: TimeInterval = 2
    ) {
        self.activationService = activationService
        self.focusProvider = AeroSpaceWorkspaceFocusProvider(
            logger: logger,
            timeoutSeconds: focusTimeoutSeconds
        )
    }

    init(
        activationService: ActivationService,
        focusProvider: WorkspaceFocusProviding
    ) {
        self.activationService = activationService
        self.focusProvider = focusProvider
    }

    public func activate(
        projectId: String,
        focusIdeWindow: Bool,
        switchWorkspace: Bool,
        progress: ((ActivationProgress) -> Void)?,
        cancellationToken: ActivationCancellationToken?
    ) -> ActivationOutcome {
        activationService.activate(
            projectId: projectId,
            focusIdeWindow: focusIdeWindow,
            switchWorkspace: switchWorkspace,
            progress: progress,
            cancellationToken: cancellationToken
        )
    }

    public func focusWorkspaceAndWindow(report: ActivationReport) -> Result<Void, ActivationError> {
        activationService.focusWorkspaceAndWindow(report: report)
    }

    public func captureFocusSnapshot() -> WorkspaceFocusSnapshot? {
        focusProvider.captureSnapshot()
    }

    public func restoreFocusSnapshot(_ snapshot: WorkspaceFocusSnapshot) {
        focusProvider.restore(snapshot: snapshot)
    }

    public func workspaceExists(name: String) -> Bool {
        focusProvider.workspaceExists(workspaceName: name)
    }
}

/// Provides focused window/workspace snapshots using AeroSpace.
protocol WorkspaceFocusProviding {
    /// Captures the currently focused window and/or workspace (best effort).
    func captureSnapshot() -> WorkspaceFocusSnapshot?
    /// Restores focus to a previously captured snapshot (best effort).
    func restore(snapshot: WorkspaceFocusSnapshot)
    /// Checks whether a workspace exists (best effort).
    func workspaceExists(workspaceName: String) -> Bool
}

private final class AeroSpaceWorkspaceFocusProvider: WorkspaceFocusProviding {
    private let logger: ProjectWorkspacesLogging
    private let timeoutSeconds: TimeInterval
    private let clientLock = NSLock()
    private var cachedClient: AeroSpaceClient?

    init(logger: ProjectWorkspacesLogging, timeoutSeconds: TimeInterval) {
        self.logger = logger
        self.timeoutSeconds = timeoutSeconds
    }

    func captureSnapshot() -> WorkspaceFocusSnapshot? {
        guard let client = makeClient() else { return nil }

        if case .success(let windows) = client.listWindowsFocusedDecoded(),
           let focused = windows.first {
            return WorkspaceFocusSnapshot(windowId: focused.windowId, workspaceName: focused.workspace)
        }

        if case .success(let workspace) = client.focusedWorkspace() {
            return WorkspaceFocusSnapshot(windowId: nil, workspaceName: workspace)
        }

        return nil
    }

    func restore(snapshot: WorkspaceFocusSnapshot) {
        guard let client = makeClient() else { return }
        if let windowId = snapshot.windowId {
            if case .success = client.focusWindow(windowId: windowId) {
                return
            }
        }
        if let workspaceName = snapshot.workspaceName {
            _ = client.switchWorkspace(workspaceName)
        }
    }

    func workspaceExists(workspaceName: String) -> Bool {
        guard let client = makeClient() else { return false }
        switch client.workspaceExists(workspaceName) {
        case .success(let exists):
            return exists
        case .failure(let error):
            _ = logger.log(
                event: "switcher.workspace.exists.failed",
                level: .warn,
                message: "\(error)",
                context: ["workspace": workspaceName]
            )
            return false
        }
    }

    private func makeClient() -> AeroSpaceClient? {
        do {
            clientLock.lock()
            if let cachedClient {
                clientLock.unlock()
                return cachedClient
            }
            let client = try AeroSpaceClient(
                resolver: DefaultAeroSpaceBinaryResolver(),
                commandRunner: DefaultAeroSpaceCommandRunner(),
                timeoutSeconds: timeoutSeconds
            )
            cachedClient = client
            clientLock.unlock()
            return client
        } catch {
            clientLock.unlock()
            _ = logger.log(
                event: "switcher.aerospace.client.failed",
                level: .warn,
                message: "\(error)",
                context: nil
            )
            return nil
        }
    }
}
