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
            agentLayerIdeLauncher: WorkspaceStateIdeLauncherStub(),
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
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?) -> Result<Void, ApCoreError> {
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

// MARK: - Sorting + Load Config Tests

final class ProjectManagerSortingTests: XCTestCase {

    func testDefaultInitializerDoesNotCrash() {
        _ = ProjectManager()
    }

    func testLoadConfigSuccessPopulatesProjectsAndReturnsSuccess() {
        let manager = makeManager(
            configLoader: {
                .success(
                    Config(projects: [
                        ProjectConfig(
                            id: "a",
                            name: "Alpha",
                            path: "/tmp/a",
                            color: "blue",
                            useAgentLayer: false
                        )
                    ])
                )
            }
        )

        switch manager.loadConfig() {
        case .failure(let error):
            XCTFail("Expected loadConfig to succeed, got: \(error)")
        case .success(let config):
            XCTAssertEqual(config.projects.map(\.id), ["a"])
        }

        XCTAssertEqual(manager.projects.map(\.id), ["a"])
    }

    func testLoadConfigFailureClearsProjectsAndReturnsFailure() {
        let manager = makeManager(
            configLoader: { .failure(.parseFailed(detail: "bad toml")) }
        )

        switch manager.loadConfig() {
        case .success(let config):
            XCTFail("Expected failure, got config: \(config)")
        case .failure(let error):
            XCTAssertEqual(error, .parseFailed(detail: "bad toml"))
        }

        XCTAssertEqual(manager.projects, [])
    }

    func testSortedProjectsUsesRecencyWhenQueryEmpty() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir.appendingPathComponent("pm-sorted-recency-\(UUID().uuidString).json")
        try? JSONEncoder().encode(["b", "a"]).write(to: recencyFilePath, options: .atomic)

        let manager = makeManager(recencyFilePath: recencyFilePath)
        manager.loadTestConfig(
            Config(projects: [
                ProjectConfig(id: "a", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "b", name: "Beta", path: "/tmp/b", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "c", name: "Gamma", path: "/tmp/c", color: "blue", useAgentLayer: false)
            ])
        )

        let sorted = manager.sortedProjects(query: "")
        XCTAssertEqual(sorted.map(\.id), ["b", "a", "c"])
    }

    func testSortedProjectsFallsBackToConfigOrderWhenRecencyFileInvalid() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir.appendingPathComponent("pm-sorted-invalid-\(UUID().uuidString).json")
        try? "not json".write(to: recencyFilePath, atomically: true, encoding: .utf8)

        let manager = makeManager(recencyFilePath: recencyFilePath)
        manager.loadTestConfig(
            Config(projects: [
                ProjectConfig(id: "a", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "b", name: "Beta", path: "/tmp/b", color: "blue", useAgentLayer: false)
            ])
        )

        let sorted = manager.sortedProjects(query: "")
        XCTAssertEqual(sorted.map(\.id), ["a", "b"])
    }

    func testSortedProjectsFiltersAndSortsByMatchTypeThenRecency() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir.appendingPathComponent("pm-sorted-match-\(UUID().uuidString).json")
        try? JSONEncoder().encode(["calico", "foo", "alpine", "alpha"]).write(to: recencyFilePath, options: .atomic)

        let manager = makeManager(recencyFilePath: recencyFilePath)
        manager.loadTestConfig(
            Config(projects: [
                // Match types for query \"al\":
                // - name prefix (0)
                // - id prefix (1)
                // - name infix (2)
                // - id infix (3)
                ProjectConfig(id: "alpha", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "alpine", name: "Zzz", path: "/tmp/b", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "foo", name: "Bald", path: "/tmp/c", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "calico", name: "Zzz", path: "/tmp/d", color: "blue", useAgentLayer: false)
            ])
        )

        let sorted = manager.sortedProjects(query: " al ")
        XCTAssertEqual(sorted.map(\.id), ["alpha", "alpine", "foo", "calico"])
    }

    func testSortedProjectsWhenMatchTypeSameUsesRecencyRankBeforeConfigOrder() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir.appendingPathComponent("pm-sorted-recency-tie-\(UUID().uuidString).json")
        try? JSONEncoder().encode(["alpine", "alpha"]).write(to: recencyFilePath, options: .atomic)

        let manager = makeManager(recencyFilePath: recencyFilePath)
        manager.loadTestConfig(
            Config(projects: [
                // Both projects match name prefix for query "al" (matchType 0),
                // so ordering should be determined by recency rank first.
                ProjectConfig(id: "alpha", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "alpine", name: "Alpine", path: "/tmp/b", color: "blue", useAgentLayer: false)
            ])
        )

        let sorted = manager.sortedProjects(query: "al")
        XCTAssertEqual(sorted.map(\.id), ["alpine", "alpha"])
    }

    func testSortedProjectsWhenMatchTypeSameFallsBackToConfigOrderWhenNoRecency() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir.appendingPathComponent("pm-sorted-config-tie-\(UUID().uuidString).json")
        try? JSONEncoder().encode(["unrelated"]).write(to: recencyFilePath, options: .atomic)

        let manager = makeManager(recencyFilePath: recencyFilePath)
        manager.loadTestConfig(
            Config(projects: [
                // Both projects match name prefix for query "al" (matchType 0),
                // but neither appears in recency, so config order should be used.
                ProjectConfig(id: "alpha", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "alpine", name: "Alpine", path: "/tmp/b", color: "blue", useAgentLayer: false)
            ])
        )

        let sorted = manager.sortedProjects(query: "al")
        XCTAssertEqual(sorted.map(\.id), ["alpha", "alpine"])
    }

    func testRestoreFocusFocusesWindowAndReturnsTrueOnSuccess() {
        let aerospace = RecordingFocusAeroSpaceStub()
        aerospace.focusWindowSuccessIds = [123]
        let manager = makeManager(aerospace: aerospace)

        let ok = manager.restoreFocus(CapturedFocus(windowId: 123, appBundleId: "test", workspace: "main"))

        XCTAssertTrue(ok)
        XCTAssertEqual(aerospace.focusedWindowIds, [123])
    }

    func testFocusWindowStableReturnsFalseWhenFocusNeverStabilizes() async {
        let aerospace = AlwaysDifferentFocusAeroSpaceStub()
        aerospace.focusWindowSuccessIds = [123]
        let manager = makeManager(aerospace: aerospace)

        let ok = await manager.focusWindowStable(windowId: 123, timeout: 0.01, pollInterval: 0.001)

        XCTAssertFalse(ok)
        XCTAssertFalse(aerospace.focusedWindowIds.isEmpty, "Should attempt to focus during stabilization")
    }

    private func makeManager(
        aerospace: AeroSpaceProviding = RecordingFocusAeroSpaceStub(),
        recencyFilePath: URL? = nil,
        configLoader: @escaping () -> Result<Config, ConfigLoadError> = { .success(Config(projects: [])) }
    ) -> ProjectManager {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let effectiveRecencyFilePath = recencyFilePath
            ?? tempDir.appendingPathComponent("pm-sorting-recency-\(UUID().uuidString).json")
        let chromeTabsDir = tempDir.appendingPathComponent("pm-sorting-tabs-\(UUID().uuidString)", isDirectory: true)

        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: WorkspaceStateIdeLauncherStub(),
            agentLayerIdeLauncher: WorkspaceStateIdeLauncherStub(),
            chromeLauncher: WorkspaceStateChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: WorkspaceStateTabCaptureStub(),
            gitRemoteResolver: WorkspaceStateGitRemoteStub(),
            logger: WorkspaceStateLoggerStub(),
            recencyFilePath: effectiveRecencyFilePath,
            configLoader: configLoader
        )
    }
}

private final class RecordingFocusAeroSpaceStub: AeroSpaceProviding {
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

private final class AlwaysDifferentFocusAeroSpaceStub: AeroSpaceProviding {
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
