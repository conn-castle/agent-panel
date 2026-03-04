import Foundation
@testable import AgentPanelCore

final class WorkspaceStateAeroSpaceStub: AeroSpaceProviding {
    let listWorkspacesWithFocusResult: Result<[ApWorkspaceSummary], ApCoreError>

    init(listWorkspacesWithFocusResult: Result<[ApWorkspaceSummary], ApCoreError>) {
        self.listWorkspacesWithFocusResult = listWorkspacesWithFocusResult
    }

    func getWorkspaces() -> Result<[String], ApCoreError> {
        .success([])
    }

    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> {
        .success(false)
    }

    func listWorkspacesFocused() -> Result<[String], ApCoreError> {
        .success([])
    }

    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> {
        listWorkspacesWithFocusResult
    }

    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> {
        .success(())
    }

    func closeWorkspace(name: String) -> Result<Void, ApCoreError> {
        .success(())
    }

    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> {
        .success([])
    }

    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        .success([])
    }
    func listAllWindows() -> Result<[ApWindow], ApCoreError> { .success([]) }

    func focusedWindow() -> Result<ApWindow, ApCoreError> {
        .failure(ApCoreError(message: "not used in this test"))
    }

    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        .success(())
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> {
        .success(())
    }

    func focusWorkspace(name: String) -> Result<Void, ApCoreError> {
        .success(())
    }
}

struct WorkspaceStateIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> {
        .success(())
    }
}

struct WorkspaceStateChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> {
        .success(())
    }
}

struct WorkspaceStateTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> {
        .success([])
    }
}

struct WorkspaceStateGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? {
        nil
    }
}

struct WorkspaceStateLoggerStub: AgentPanelLogging {
    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError> {
        .success(())
    }
}


final class RecordingFocusAeroSpaceStub: AeroSpaceProviding {
    var focusWindowSuccessIds: Set<Int> = []
    private(set) var focusedWindowIds: [Int] = []

    func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { .success([]) }
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> { .success([]) }
    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> { .success([]) }
    func listAllWindows() -> Result<[ApWindow], ApCoreError> { .success([]) }
    func focusedWindow() -> Result<ApWindow, ApCoreError> { .failure(ApCoreError(message: "not used")) }

    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        focusedWindowIds.append(windowId)
        if focusWindowSuccessIds.contains(windowId) {
            return .success(())
        }
        return .failure(ApCoreError(message: "window not found"))
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
}

final class AlwaysDifferentFocusAeroSpaceStub: AeroSpaceProviding {
    var focusWindowSuccessIds: Set<Int> = []
    private(set) var focusedWindowIds: [Int] = []

    func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { .success([]) }
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> { .success([]) }
    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> { .success([]) }
    func listAllWindows() -> Result<[ApWindow], ApCoreError> { .success([]) }

    func focusedWindow() -> Result<ApWindow, ApCoreError> {
        .success(ApWindow(windowId: 999, appBundleId: "other", workspace: "main", windowTitle: "Other"))
    }

    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        focusedWindowIds.append(windowId)
        if focusWindowSuccessIds.contains(windowId) {
            return .success(())
        }
        return .failure(ApCoreError(message: "window not found"))
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
}
