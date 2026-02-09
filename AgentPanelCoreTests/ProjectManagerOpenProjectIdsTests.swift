import Foundation
import XCTest
@testable import AgentPanelCore

final class ProjectManagerWorkspaceStateTests: XCTestCase {

    func testWorkspaceStateReturnsOpenProjectIdsAndActiveProjectId() {
        let aerospace = WorkspaceStateAeroSpaceStub(
            listWorkspacesWithFocusResult: .success([
                ApWorkspaceSummary(workspace: "main", isFocused: false),
                ApWorkspaceSummary(workspace: "ap-alpha", isFocused: false),
                ApWorkspaceSummary(workspace: "ap-beta", isFocused: true),
                ApWorkspaceSummary(workspace: "ap-alpha", isFocused: false)
            ])
        )
        let manager = makeManager(aerospace: aerospace)

        switch manager.workspaceState() {
        case .success(let state):
            XCTAssertEqual(state.activeProjectId, "beta")
            XCTAssertEqual(state.openProjectIds, Set(["alpha", "beta"]))
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWorkspaceStateIgnoresFocusedNonProjectWorkspace() {
        let aerospace = WorkspaceStateAeroSpaceStub(
            listWorkspacesWithFocusResult: .success([
                ApWorkspaceSummary(workspace: "main", isFocused: true),
                ApWorkspaceSummary(workspace: "ap-alpha", isFocused: false)
            ])
        )
        let manager = makeManager(aerospace: aerospace)

        switch manager.workspaceState() {
        case .success(let state):
            XCTAssertNil(state.activeProjectId)
            XCTAssertEqual(state.openProjectIds, Set(["alpha"]))
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWorkspaceStateReturnsAeroSpaceFailureWhenWorkspaceQueryFails() {
        let aerospace = WorkspaceStateAeroSpaceStub(
            listWorkspacesWithFocusResult: .failure(ApCoreError(message: "workspace query failed"))
        )
        let manager = makeManager(aerospace: aerospace)

        switch manager.workspaceState() {
        case .success(let state):
            XCTFail("Expected failure, got state: \(state)")
        case .failure(let error):
            XCTAssertEqual(error, .aeroSpaceError(detail: "workspace query failed"))
        }
    }

    private func makeManager(aerospace: WorkspaceStateAeroSpaceStub) -> ProjectManager {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir
            .appendingPathComponent("pm-workspace-state-\(UUID().uuidString).json")
        let chromeTabsDir = tempDir.appendingPathComponent("chrome-tabs-\(UUID().uuidString)", isDirectory: true)
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: WorkspaceStateIdeLauncherStub(),
            chromeLauncher: WorkspaceStateChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: WorkspaceStateTabCaptureStub(),
            gitRemoteResolver: WorkspaceStateGitRemoteStub(),
            logger: WorkspaceStateLoggerStub(),
            recencyFilePath: recencyFilePath
        )
    }
}

private final class WorkspaceStateAeroSpaceStub: AeroSpaceProviding {
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

private struct WorkspaceStateIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?) -> Result<Void, ApCoreError> {
        .success(())
    }
}

private struct WorkspaceStateChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> {
        .success(())
    }
}

private struct WorkspaceStateTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> {
        .success([])
    }
}

private struct WorkspaceStateGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? {
        nil
    }
}

private struct WorkspaceStateLoggerStub: AgentPanelLogging {
    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError> {
        .success(())
    }
}
