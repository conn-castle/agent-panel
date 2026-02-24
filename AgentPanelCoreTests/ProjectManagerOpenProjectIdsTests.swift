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
        let focusHistoryFilePath = tempDir
            .appendingPathComponent("pm-workspace-focus-\(UUID().uuidString).json")
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
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath
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

private struct WorkspaceStateIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> {
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
                    ConfigLoadSuccess(config: Config(projects: [
                        ProjectConfig(
                            id: "a",
                            name: "Alpha",
                            path: "/tmp/a",
                            color: "blue",
                            useAgentLayer: false
                        )
                    ]))
                )
            }
        )

        switch manager.loadConfig() {
        case .failure(let error):
            XCTFail("Expected loadConfig to succeed, got: \(error)")
        case .success(let success):
            XCTAssertEqual(success.config.projects.map(\.id), ["a"])
        }

        XCTAssertEqual(manager.projects.map(\.id), ["a"])
    }

    func testLoadConfigFailureClearsProjectsAndReturnsFailure() {
        let manager = makeManager(
            configLoader: { .failure(.parseFailed(detail: "bad toml")) }
        )

        switch manager.loadConfig() {
        case .success(let success):
            XCTFail("Expected failure, got config: \(success)")
        case .failure(let error):
            XCTAssertEqual(error, .parseFailed(detail: "bad toml"))
        }

        XCTAssertEqual(manager.projects, [])
    }

    func testLoadConfigStoresWarningsFromConfigLoadSuccess() {
        let warning = ConfigFinding(severity: .warn, title: "Deprecated field: foo")
        let manager = makeManager(
            configLoader: {
                .success(
                    ConfigLoadSuccess(
                        config: Config(projects: []),
                        warnings: [warning]
                    )
                )
            }
        )

        switch manager.loadConfig() {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let success):
            XCTAssertEqual(success.warnings.count, 1)
            XCTAssertEqual(success.warnings[0].title, "Deprecated field: foo")
        }

        XCTAssertEqual(manager.configWarnings.count, 1)
        XCTAssertEqual(manager.configWarnings[0].title, "Deprecated field: foo")
    }

    func testLoadConfigClearsWarningsOnNoWarnings() {
        var loadCount = 0
        let warning = ConfigFinding(severity: .warn, title: "Deprecated field: foo")
        let manager = makeManager(
            configLoader: {
                loadCount += 1
                if loadCount == 1 {
                    return .success(
                        ConfigLoadSuccess(
                            config: Config(projects: []),
                            warnings: [warning]
                        )
                    )
                } else {
                    return .success(
                        ConfigLoadSuccess(
                            config: Config(projects: []),
                            warnings: []
                        )
                    )
                }
            }
        )

        // First load — has warnings
        _ = manager.loadConfig()
        XCTAssertEqual(manager.configWarnings.count, 1)

        // Second load — no warnings, should clear
        _ = manager.loadConfig()
        XCTAssertTrue(manager.configWarnings.isEmpty)
    }

    func testLoadConfigClearsWarningsOnFailure() {
        var shouldSucceed = true
        let warning = ConfigFinding(severity: .warn, title: "Deprecated field: foo")
        let manager = makeManager(
            configLoader: {
                if shouldSucceed {
                    return .success(ConfigLoadSuccess(config: Config(projects: []), warnings: [warning]))
                } else {
                    return .failure(.parseFailed(detail: "bad"))
                }
            }
        )

        // First load — has warnings
        _ = manager.loadConfig()
        XCTAssertEqual(manager.configWarnings.count, 1)

        // Second load — failure clears warnings
        shouldSucceed = false
        _ = manager.loadConfig()
        XCTAssertTrue(manager.configWarnings.isEmpty)
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

    func testSortedProjectsFiltersAndSortsByScoreThenRecency() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir.appendingPathComponent("pm-sorted-match-\(UUID().uuidString).json")
        try? JSONEncoder().encode(["calico", "foo", "alpine", "alpha"]).write(to: recencyFilePath, options: .atomic)

        let manager = makeManager(recencyFilePath: recencyFilePath)
        manager.loadTestConfig(
            Config(projects: [
                // Fuzzy scores for query "al":
                // - "Alpha" name prefix → ~1000 (highest tier)
                // - "alpine" id prefix → ~1000 (highest tier)
                // - "Bald" name substring at pos 1 → ~600 tier
                // - "calico" id substring at pos 1 → ~600 tier
                ProjectConfig(id: "alpha", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "alpine", name: "Zzz", path: "/tmp/b", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "foo", name: "Bald", path: "/tmp/c", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "calico", name: "Zzz", path: "/tmp/d", color: "blue", useAgentLayer: false)
            ])
        )

        let sorted = manager.sortedProjects(query: " al ")
        // Prefix matches first: alpha (name "Alpha" len 5 → 1095) > alpine (id "alpine" len 6 → 1094).
        // Substring matches next: calico and foo both ~649, recency breaks tie: calico(0) before foo(1).
        XCTAssertEqual(sorted.map(\.id), ["alpha", "alpine", "calico", "foo"])
    }

    func testSortedProjectsWhenScoreSameUsesRecencyRankBeforeConfigOrder() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir.appendingPathComponent("pm-sorted-recency-tie-\(UUID().uuidString).json")
        try? JSONEncoder().encode(["alice", "alfie"]).write(to: recencyFilePath, options: .atomic)

        let manager = makeManager(recencyFilePath: recencyFilePath)
        manager.loadTestConfig(
            Config(projects: [
                // Both names are 5 chars and match prefix for query "al" → equal scores.
                // Recency breaks tie: alice(0) before alfie(1).
                ProjectConfig(id: "alfie", name: "Alfie", path: "/tmp/a", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "alice", name: "Alice", path: "/tmp/b", color: "blue", useAgentLayer: false)
            ])
        )

        let sorted = manager.sortedProjects(query: "al")
        XCTAssertEqual(sorted.map(\.id), ["alice", "alfie"])
    }

    func testSortedProjectsWhenScoreSameFallsBackToConfigOrderWhenNoRecency() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir.appendingPathComponent("pm-sorted-config-tie-\(UUID().uuidString).json")
        try? JSONEncoder().encode(["unrelated"]).write(to: recencyFilePath, options: .atomic)

        let manager = makeManager(recencyFilePath: recencyFilePath)
        manager.loadTestConfig(
            Config(projects: [
                // Both names are 5 chars and match prefix for query "al" → equal scores.
                // Neither appears in recency, so config order is used: alfie first.
                ProjectConfig(id: "alfie", name: "Alfie", path: "/tmp/a", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "alice", name: "Alice", path: "/tmp/b", color: "blue", useAgentLayer: false)
            ])
        )

        let sorted = manager.sortedProjects(query: "al")
        XCTAssertEqual(sorted.map(\.id), ["alfie", "alice"])
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
        configLoader: @escaping () -> Result<ConfigLoadSuccess, ConfigLoadError> = { .success(ConfigLoadSuccess(config: Config(projects: []))) }
    ) -> ProjectManager {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let effectiveRecencyFilePath = recencyFilePath
            ?? tempDir.appendingPathComponent("pm-sorting-recency-\(UUID().uuidString).json")
        let focusHistoryFilePath = tempDir.appendingPathComponent("pm-sorting-focus-\(UUID().uuidString).json")
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
            focusHistoryFilePath: focusHistoryFilePath,
            configLoader: configLoader
        )
    }
}

// MARK: - onProjectsChanged Tests

final class ProjectManagerOnProjectsChangedTests: XCTestCase {

    func testOnProjectsChangedFiresOnFirstLoad() {
        var received: [ProjectConfig]?
        let project = ProjectConfig(id: "a", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false)
        let manager = makeManager(configLoader: {
            .success(ConfigLoadSuccess(config: Config(projects: [project])))
        })

        manager.onProjectsChanged = { projects in
            received = projects
        }

        _ = manager.loadConfig()

        XCTAssertEqual(received?.map(\.id), ["a"])
    }

    func testOnProjectsChangedFiresWhenProjectsChange() {
        var callCount = 0
        var loadCount = 0
        let projectA = ProjectConfig(id: "a", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false)
        let projectB = ProjectConfig(id: "b", name: "Beta", path: "/tmp/b", color: "red", useAgentLayer: false)
        let manager = makeManager(configLoader: {
            loadCount += 1
            if loadCount == 1 {
                return .success(ConfigLoadSuccess(config: Config(projects: [projectA])))
            } else {
                return .success(ConfigLoadSuccess(config: Config(projects: [projectA, projectB])))
            }
        })

        manager.onProjectsChanged = { _ in callCount += 1 }

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 1)

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 2)
    }

    func testOnProjectsChangedDoesNotFireWhenProjectsUnchanged() {
        var callCount = 0
        let project = ProjectConfig(id: "a", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false)
        let manager = makeManager(configLoader: {
            .success(ConfigLoadSuccess(config: Config(projects: [project])))
        })

        manager.onProjectsChanged = { _ in callCount += 1 }

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 1, "Should fire on first load (nil → projects)")

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 1, "Should NOT fire again when projects are the same")
    }

    func testOnProjectsChangedDoesNotFireOnLoadFailure() {
        var received: [ProjectConfig]?
        let manager = makeManager(configLoader: {
            .failure(.parseFailed(detail: "bad toml"))
        })

        manager.onProjectsChanged = { projects in
            received = projects
        }

        _ = manager.loadConfig()

        XCTAssertNil(received, "Should not fire callback on config load failure")
    }

    func testOnProjectsChangedDoesNotFireForEmptyToEmpty() {
        var callCount = 0
        let manager = makeManager(configLoader: {
            .success(ConfigLoadSuccess(config: Config(projects: [])))
        })

        manager.onProjectsChanged = { _ in callCount += 1 }

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 0, "Empty to empty is not a change")

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 0, "Still empty to empty")
    }

    private func makeManager(
        configLoader: @escaping () -> Result<ConfigLoadSuccess, ConfigLoadError>
    ) -> ProjectManager {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyPath = tempDir.appendingPathComponent("pm-callback-recency-\(UUID().uuidString).json")
        let focusHistoryPath = tempDir.appendingPathComponent("pm-callback-focus-\(UUID().uuidString).json")
        let chromeTabsDir = tempDir.appendingPathComponent("pm-callback-tabs-\(UUID().uuidString)", isDirectory: true)

        return ProjectManager(
            aerospace: RecordingFocusAeroSpaceStub(),
            ideLauncher: WorkspaceStateIdeLauncherStub(),
            agentLayerIdeLauncher: WorkspaceStateIdeLauncherStub(),
            chromeLauncher: WorkspaceStateChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: WorkspaceStateTabCaptureStub(),
            gitRemoteResolver: WorkspaceStateGitRemoteStub(),
            logger: WorkspaceStateLoggerStub(),
            recencyFilePath: recencyPath,
            focusHistoryFilePath: focusHistoryPath,
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
