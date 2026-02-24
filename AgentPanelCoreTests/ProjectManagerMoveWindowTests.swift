import Foundation
import XCTest
@testable import AgentPanelCore

/// Tests for ProjectManager.moveWindowToProject().
final class ProjectManagerMoveWindowTests: XCTestCase {

    // MARK: - Test Doubles

    private struct NoopLogger: AgentPanelLogging {
        func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
            .success(())
        }
    }

    private struct NoopIdeLauncher: IdeLauncherProviding {
        func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> { .success(()) }
    }

    private struct NoopChromeLauncher: ChromeLauncherProviding {
        func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> { .success(()) }
    }

    private struct NoopTabCapture: ChromeTabCapturing {
        func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> { .success([]) }
    }

    private struct NoopGitRemoteResolver: GitRemoteResolving {
        func resolve(projectPath: String) -> String? { nil }
    }

    private final class MoveAeroSpaceStub: AeroSpaceProviding {
        var moveResult: Result<Void, ApCoreError> = .success(())
        var moveWindowCalls: [(workspace: String, windowId: Int, focusFollows: Bool)] = []
        var workspaces: [String] = []
        var windowsByWorkspace: [String: [ApWindow]] = [:]
        var failingWorkspaces: Set<String> = []
        var listAllWindowsResultOverride: Result<[ApWindow], ApCoreError>?

        func getWorkspaces() -> Result<[String], ApCoreError> { .success(workspaces) }
        func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(true) }
        func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
        func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { .success([]) }
        func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
        func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
        func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> { .success([]) }
        func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
            if failingWorkspaces.contains(workspace) {
                return .failure(ApCoreError(message: "listing failed for \(workspace)"))
            }
            return .success(windowsByWorkspace[workspace] ?? [])
        }
        func listAllWindows() -> Result<[ApWindow], ApCoreError> {
            if let result = listAllWindowsResultOverride {
                return result
            }
            var windows: [ApWindow] = []
            var seenWindowIds: Set<Int> = []
            for list in windowsByWorkspace.values {
                for window in list where !seenWindowIds.contains(window.windowId) {
                    seenWindowIds.insert(window.windowId)
                    windows.append(window)
                }
            }
            return .success(windows)
        }
        func focusedWindow() -> Result<ApWindow, ApCoreError> { .failure(ApCoreError(message: "no focus")) }
        func focusWindow(windowId: Int) -> Result<Void, ApCoreError> { .success(()) }
        func focusWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }

        func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> {
            moveWindowCalls.append((workspace, windowId, focusFollows))
            return moveResult
        }
    }

    // MARK: - Helpers

    private func makeProjectManager(aerospace: MoveAeroSpaceStub = MoveAeroSpaceStub()) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-move-recency-\(UUID().uuidString).json")
        let focusHistoryFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-move-focus-\(UUID().uuidString).json")
        let chromeTabsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-move-tabs-\(UUID().uuidString)", isDirectory: true)
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: NoopIdeLauncher(),
            agentLayerIdeLauncher: NoopIdeLauncher(),
            chromeLauncher: NoopChromeLauncher(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: NoopTabCapture(),
            gitRemoteResolver: NoopGitRemoteResolver(),
            logger: NoopLogger(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath
        )
    }

    private func makeTestConfig(projectIds: [String] = ["myproject"]) -> Config {
        let projects = projectIds.map { id in
            ProjectConfig(
                id: id,
                name: id.capitalized,
                path: "/tmp/\(id)",
                color: "#FF0000",
                useAgentLayer: false
            )
        }
        return Config(projects: projects)
    }

    // MARK: - Tests

    func testMoveWindowToProject_success() {
        let aerospace = MoveAeroSpaceStub()
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig(projectIds: ["myproject"]))

        let result = pm.moveWindowToProject(windowId: 42, projectId: "myproject")

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls.count, 1)
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "ap-myproject")
        XCTAssertEqual(aerospace.moveWindowCalls[0].windowId, 42)
        XCTAssertFalse(aerospace.moveWindowCalls[0].focusFollows)
    }

    func testMoveWindowToProject_configNotLoaded() {
        let pm = makeProjectManager()
        // Don't load config

        let result = pm.moveWindowToProject(windowId: 42, projectId: "myproject")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .configNotLoaded)
    }

    func testMoveWindowToProject_projectNotFound() {
        let pm = makeProjectManager()
        pm.loadTestConfig(makeTestConfig(projectIds: ["other"]))

        let result = pm.moveWindowToProject(windowId: 42, projectId: "nonexistent")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .projectNotFound(projectId: "nonexistent"))
    }

    func testMoveWindowToProject_aeroSpaceError() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.moveResult = .failure(ApCoreError(message: "move rejected"))
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig(projectIds: ["myproject"]))

        let result = pm.moveWindowToProject(windowId: 42, projectId: "myproject")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .aeroSpaceError(detail: "move rejected"))
    }

    func testMoveWindowToProject_correctWorkspacePrefix() {
        let aerospace = MoveAeroSpaceStub()
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig(projectIds: ["my-fancy-project"]))

        _ = pm.moveWindowToProject(windowId: 1, projectId: "my-fancy-project")

        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "ap-my-fancy-project")
    }

    // MARK: - moveWindowFromProject Tests

    func testMoveWindowFromProject_noWorkspaces_fallsBackToDefault() {
        let aerospace = MoveAeroSpaceStub()
        // No workspaces configured — should fall back to WorkspaceRouting.fallbackWorkspace
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls.count, 1)
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, WorkspaceRouting.fallbackWorkspace)
        XCTAssertEqual(aerospace.moveWindowCalls[0].windowId, 99)
        XCTAssertFalse(aerospace.moveWindowCalls[0].focusFollows)
    }

    func testMoveWindowFromProject_prefersNonProjectWorkspaceWithWindows() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.workspaces = ["ap-myproject", "main", "empty-ws"]
        aerospace.windowsByWorkspace["main"] = [
            ApWindow(windowId: 50, appBundleId: "com.test.app", workspace: "main", windowTitle: "Existing Window")
        ]
        // "empty-ws" has no windows

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "main",
                       "Should target non-project workspace with windows")
    }

    func testMoveWindowFromProject_onlyProjectWorkspaces_fallsBackToDefault() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.workspaces = ["ap-proj1", "ap-proj2"]
        aerospace.windowsByWorkspace["ap-proj1"] = [
            ApWindow(windowId: 50, appBundleId: "com.test.app", workspace: "ap-proj1", windowTitle: "W")
        ]

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, WorkspaceRouting.fallbackWorkspace,
                       "Should fall back to default when only project workspaces exist")
    }

    func testMoveWindowFromProject_failedListingExcludesWorkspaceFromCandidates() {
        let aerospace = MoveAeroSpaceStub()
        // "broken-ws" is listed but its window listing fails; "healthy-ws" succeeds
        aerospace.workspaces = ["broken-ws", "healthy-ws"]
        aerospace.failingWorkspaces = ["broken-ws"]
        aerospace.windowsByWorkspace["healthy-ws"] = [
            ApWindow(windowId: 50, appBundleId: "com.test.app", workspace: "healthy-ws", windowTitle: "W")
        ]

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "healthy-ws",
                       "Should skip workspace with failed listing and use healthy candidate")
    }

    func testMoveWindowFromProject_listAllWindowsFailureFallsBackToPerWorkspaceSelection() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.workspaces = ["broken-ws", "healthy-ws"]
        aerospace.failingWorkspaces = ["broken-ws"]
        aerospace.listAllWindowsResultOverride = .failure(ApCoreError(message: "listAllWindows unavailable"))
        aerospace.windowsByWorkspace["healthy-ws"] = [
            ApWindow(windowId: 50, appBundleId: "com.test.app", workspace: "healthy-ws", windowTitle: "W")
        ]

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(
            aerospace.moveWindowCalls[0].workspace,
            "healthy-ws",
            "Should fall back to per-workspace selection when listAllWindows fails"
        )
    }

    func testMoveWindowFromProject_allNonProjectListingsFail_fallsBackToDefault() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.workspaces = ["broken-ws"]
        aerospace.failingWorkspaces = ["broken-ws"]

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, WorkspaceRouting.fallbackWorkspace,
                       "Should fall back to default when all non-project workspace listings fail")
    }

    func testMoveWindowFromProject_configNotLoaded() {
        let pm = makeProjectManager()

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .configNotLoaded)
    }

    func testMoveWindowFromProject_aeroSpaceError() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.moveResult = .failure(ApCoreError(message: "move failed"))
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .aeroSpaceError(detail: "move failed"))
    }
}
