import XCTest

@testable import AgentPanel
@testable import AgentPanelCore

@MainActor
final class SwitcherFocusFlowTests: XCTestCase {
    func testExitToPreviousRestoresFocusAndLogsSuccess() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "test"
        let nonProjectWindow = ApWindow(
            windowId: 42,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )
        aerospace.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-\(projectId)", isFocused: true)
        ])
        aerospace.allWindows = [nonProjectWindow]
        aerospace.focusWindowSuccessIds = [nonProjectWindow.windowId]
        aerospace.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager.pushFocusForTest(CapturedFocus(
            windowId: nonProjectWindow.windowId,
            appBundleId: nonProjectWindow.appBundleId,
            workspace: nonProjectWindow.workspace
        ))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_enableBackActionRow()

        let expectation = expectation(description: "exit succeeds")
        logger.onLog = { entry in
            if entry.event == "switcher.exit_to_previous.succeeded" {
                expectation.fulfill()
            }
        }

        controller.testing_handleExitToNonProject()
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertTrue(aerospace.focusedWindowIds.contains(nonProjectWindow.windowId))
    }

    func testCloseProjectRefreshesCapturedFocus() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "test"
        let refreshedWindow = ApWindow(
            windowId: 55,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )
        aerospace.focusedWindowResult = .success(refreshedWindow)
        aerospace.allWindows = [refreshedWindow]
        aerospace.focusWindowSuccessIds = [refreshedWindow.windowId]

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 1, appBundleId: "com.apple.Safari", workspace: "main"))

        let expectation = expectation(description: "close succeeds")
        logger.onLog = { entry in
            if entry.event == "switcher.close_project.succeeded" {
                expectation.fulfill()
            }
        }

        controller.testing_performCloseProject(
            projectId: projectId,
            projectName: "Test",
            source: "test",
            selectedRowAtRequestTime: 0
        )

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(controller.testing_capturedFocus?.windowId, refreshedWindow.windowId)
        XCTAssertEqual(controller.testing_capturedFocus?.appBundleId, refreshedWindow.appBundleId)
        XCTAssertEqual(controller.testing_capturedFocus?.workspace, refreshedWindow.workspace)
    }

    func testProjectSelectionFocusesIdeWindow() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "alpha"
        let workspace = "ap-\(projectId)"
        let chromeWindow = ApWindow(
            windowId: 100,
            appBundleId: ApChromeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "AP:\(projectId) - Chrome"
        )
        let ideWindow = ApWindow(
            windowId: 101,
            appBundleId: ApVSCodeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "AP:\(projectId) - VS Code"
        )

        aerospace.windowsByBundleId[ApChromeLauncher.bundleId] = [chromeWindow]
        aerospace.windowsByBundleId[ApVSCodeLauncher.bundleId] = [ideWindow]
        aerospace.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aerospace.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
        aerospace.focusedWindowResult = .success(ideWindow)
        aerospace.focusWindowSuccessIds = [ideWindow.windowId]
        aerospace.allWindows = [chromeWindow, ideWindow]

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 77, appBundleId: "com.apple.Terminal", workspace: "main"))

        let expectation = expectation(description: "project selection completes")
        logger.onLog = { entry in
            if entry.event == "project_manager.select.completed" {
                expectation.fulfill()
            }
        }

        controller.testing_handleProjectSelection(project)
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertTrue(aerospace.focusedWindowIds.contains(ideWindow.windowId))
    }

    func testRecoverProjectShortcutInvokesRecoverCallbackWithCapturedFocus() {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        let focus = CapturedFocus(windowId: 77, appBundleId: "com.apple.Terminal", workspace: "ap-test")
        controller.testing_setCapturedFocus(focus)

        var callbackFocus: CapturedFocus?
        controller.onRecoverProjectRequested = { capturedFocus, completion in
            callbackFocus = capturedFocus
            completion(.success(RecoveryResult(windowsProcessed: 2, windowsRecovered: 1, errors: [])))
        }

        controller.testing_handleRecoverProjectFromShortcut()

        XCTAssertEqual(callbackFocus, focus)
    }

    func testFooterHintsIncludeRecoverProjectWhenShortcutIsAvailable() {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ap-test"))
        controller.onRecoverProjectRequested = { _, completion in
            completion(.success(RecoveryResult(windowsProcessed: 0, windowsRecovered: 0, errors: [])))
        }

        controller.testing_updateFooterHints()

        XCTAssertTrue(controller.testing_footerHints.contains("⌘R Recover Project"))
    }

    func testRecoverProjectShortcutIsSingleFlight() {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ap-test"))

        var invocationCount = 0
        var pendingCompletion: ((Result<RecoveryResult, ApCoreError>) -> Void)?
        controller.onRecoverProjectRequested = { _, completion in
            invocationCount += 1
            pendingCompletion = completion
        }

        controller.testing_handleRecoverProjectFromShortcut()
        controller.testing_handleRecoverProjectFromShortcut()

        XCTAssertEqual(invocationCount, 1, "Recover Project should not run concurrently from repeated keybind presses")

        pendingCompletion?(.success(RecoveryResult(windowsProcessed: 1, windowsRecovered: 1, errors: [])))
    }

    private func makeProjectManager(
        aerospace: TestAeroSpaceStub,
        logger: RecordingLogger,
        fileSystem: InMemoryFileSystem
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: "/recency.json", isDirectory: false)
        let focusHistoryFilePath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)
        let chromeTabsDir = URL(fileURLWithPath: "/chrome-tabs", isDirectory: true)

        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: TestIdeLauncherStub(),
            agentLayerIdeLauncher: TestIdeLauncherStub(),
            chromeLauncher: TestChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir, fileSystem: fileSystem),
            chromeTabCapture: TestTabCaptureStub(),
            gitRemoteResolver: TestGitRemoteStub(),
            logger: logger,
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            fileSystem: fileSystem,
            windowPollTimeout: 0.5,
            windowPollInterval: 0.05
        )
    }
}

private struct LogEntryRecord: Equatable {
    let event: String
    let level: LogLevel
    let message: String?
    let context: [String: String]?
}

private final class RecordingLogger: AgentPanelLogging {
    private let queue = DispatchQueue(label: "com.agentpanel.tests.logger")
    private(set) var entries: [LogEntryRecord] = []
    var onLog: ((LogEntryRecord) -> Void)?

    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
        let entry = LogEntryRecord(event: event, level: level, message: message, context: context)
        queue.sync {
            entries.append(entry)
        }
        onLog?(entry)
        return .success(())
    }
}

private final class TestAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(message: "stub"))
    var focusWindowSuccessIds: Set<Int> = []
    var workspacesWithFocusResult: Result<[ApWorkspaceSummary], ApCoreError> = .success([])
    var focusWorkspaceResult: Result<Void, ApCoreError> = .success(())
    var windowsByBundleId: [String: [ApWindow]] = [:]
    var windowsByWorkspace: [String: [ApWindow]] = [:]
    var allWindows: [ApWindow] = []
    private(set) var focusedWindowIds: [Int] = []
    private(set) var focusedWorkspaces: [String] = []

    func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { workspacesWithFocusResult }
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }

    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> {
        .success(windowsByBundleId[bundleId] ?? [])
    }

    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        .success(windowsByWorkspace[workspace] ?? [])
    }

    func listAllWindows() -> Result<[ApWindow], ApCoreError> {
        if !allWindows.isEmpty {
            return .success(allWindows)
        }
        var windows: [ApWindow] = []
        var seen: Set<Int> = []
        for list in windowsByWorkspace.values {
            for window in list where !seen.contains(window.windowId) {
                seen.insert(window.windowId)
                windows.append(window)
            }
        }
        for list in windowsByBundleId.values {
            for window in list where !seen.contains(window.windowId) {
                seen.insert(window.windowId)
                windows.append(window)
            }
        }
        return .success(windows)
    }

    func focusedWindow() -> Result<ApWindow, ApCoreError> { focusedWindowResult }

    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        focusedWindowIds.append(windowId)
        guard focusWindowSuccessIds.contains(windowId) else {
            return .failure(ApCoreError(message: "window not found"))
        }
        if case .success(let focused) = focusedWindowResult, focused.windowId == windowId {
            return .success(())
        }
        if let match = windowById(windowId) {
            focusedWindowResult = .success(match)
        } else {
            focusedWindowResult = .success(ApWindow(
                windowId: windowId,
                appBundleId: "com.stub.app",
                workspace: "main",
                windowTitle: "Stub"
            ))
        }
        return .success(())
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> {
        updateWindowWorkspace(windowId: windowId, workspace: workspace)
        return .success(())
    }

    func focusWorkspace(name: String) -> Result<Void, ApCoreError> {
        focusedWorkspaces.append(name)
        return focusWorkspaceResult
    }

    private func windowById(_ windowId: Int) -> ApWindow? {
        if !allWindows.isEmpty {
            return allWindows.first(where: { $0.windowId == windowId })
        }
        for list in windowsByWorkspace.values {
            if let match = list.first(where: { $0.windowId == windowId }) {
                return match
            }
        }
        for list in windowsByBundleId.values {
            if let match = list.first(where: { $0.windowId == windowId }) {
                return match
            }
        }
        return nil
    }

    private func updateWindowWorkspace(windowId: Int, workspace: String) {
        if !allWindows.isEmpty {
            for (index, window) in allWindows.enumerated() where window.windowId == windowId {
                allWindows[index] = ApWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                )
            }
            return
        }

        for (bundleId, list) in windowsByBundleId {
            for (index, window) in list.enumerated() where window.windowId == windowId {
                var updated = list
                updated[index] = ApWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                )
                windowsByBundleId[bundleId] = updated
            }
        }

        for (workspaceName, list) in windowsByWorkspace {
            if let index = list.firstIndex(where: { $0.windowId == windowId }) {
                var updated = list
                let window = updated.remove(at: index)
                windowsByWorkspace[workspaceName] = updated
                var targetList = windowsByWorkspace[workspace] ?? []
                targetList.append(ApWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                ))
                windowsByWorkspace[workspace] = targetList
                return
            }
        }
    }
}

private struct TestIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> {
        .success(())
    }
}

private struct TestChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> {
        .success(())
    }
}

private struct TestTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> { .success([]) }
}

private struct TestGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? { nil }
}

private final class InMemoryFileSystem: FileSystem {
    private var storage: [URL: Data] = [:]
    private var directories: Set<URL> = []

    func fileExists(at url: URL) -> Bool { storage[url] != nil }
    func directoryExists(at url: URL) -> Bool { directories.contains(url) }
    func isExecutableFile(at url: URL) -> Bool { false }

    func readFile(at url: URL) throws -> Data {
        guard let data = storage[url] else {
            throw NSError(domain: "InMemoryFileSystem", code: 1, userInfo: nil)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = storage[url] else {
            throw NSError(domain: "InMemoryFileSystem", code: 2, userInfo: nil)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        storage.removeValue(forKey: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        storage[destinationURL] = storage[sourceURL]
        storage.removeValue(forKey: sourceURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        let existing = storage[url] ?? Data()
        var updated = existing
        updated.append(data)
        storage[url] = updated
    }

    func writeFile(at url: URL, data: Data) throws {
        storage[url] = data
    }

    func contentsOfDirectory(at url: URL) throws -> [String] {
        storage.keys
            .filter { $0.deletingLastPathComponent() == url }
            .map { $0.lastPathComponent }
    }
}
