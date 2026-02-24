import XCTest
@testable import AgentPanelCore

final class ProjectManagerFocusHistoryPersistenceTests: XCTestCase {
    func testFocusHistoryPersistsAcrossManagers() {
        let fileSystem = InMemoryFileSystem()
        let focusHistoryPath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)

        let manager1 = makeManager(
            aerospace: FocusHistoryAeroSpaceStub(),
            fileSystem: fileSystem,
            focusHistoryFilePath: focusHistoryPath
        )
        manager1.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager1.pushFocusForTest(CapturedFocus(
            windowId: 42,
            appBundleId: "com.apple.Terminal",
            workspace: "main"
        ))

        let aero2 = FocusHistoryAeroSpaceStub()
        let window = ApWindow(windowId: 42, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")
        aero2.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        aero2.allWindows = [window]
        aero2.focusWindowSuccessIds = [42]
        aero2.focusedWindowResult = .success(window)

        let manager2 = makeManager(
            aerospace: aero2,
            fileSystem: fileSystem,
            focusHistoryFilePath: focusHistoryPath
        )
        manager2.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        aero2.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        let result = manager2.exitToNonProjectWindow()
        if case .failure(let error) = result {
            XCTFail("Expected success, got \(error)")
        }
        XCTAssertTrue(aero2.focusedWindowIds.contains(42))
    }

    func testFocusHistoryPrunesStaleEntries() {
        let fileSystem = InMemoryFileSystem()
        let focusHistoryPath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)
        let store = FocusHistoryStore(
            fileURL: focusHistoryPath,
            fileSystem: fileSystem,
            maxAge: 7 * 24 * 60 * 60,
            maxEntries: 20
        )
        let staleDate = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let staleEntry = FocusHistoryEntry(
            windowId: 10,
            appBundleId: "com.apple.Safari",
            workspace: "main",
            capturedAt: staleDate
        )
        let state = FocusHistoryState(
            version: FocusHistoryStore.currentVersion,
            stack: [staleEntry],
            mostRecent: staleEntry
        )
        _ = store.save(state: state)

        let aero = FocusHistoryAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let manager = makeManager(
            aerospace: aero,
            fileSystem: fileSystem,
            focusHistoryFilePath: focusHistoryPath
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = manager.exitToNonProjectWindow()
        switch result {
        case .failure(.noPreviousWindow):
            break
        case .failure(let error):
            XCTFail("Expected noPreviousWindow, got \(error)")
        case .success:
            XCTFail("Expected noPreviousWindow, got success")
        }
    }

    private func makeManager(
        aerospace: FocusHistoryAeroSpaceStub,
        fileSystem: InMemoryFileSystem,
        focusHistoryFilePath: URL
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: "/recency-\(UUID().uuidString).json", isDirectory: false)
        let chromeTabsDir = URL(fileURLWithPath: "/chrome-tabs-\(UUID().uuidString)", isDirectory: true)

        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: NoopIdeLauncher(),
            agentLayerIdeLauncher: NoopIdeLauncher(),
            chromeLauncher: NoopChromeLauncher(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir, fileSystem: fileSystem),
            chromeTabCapture: NoopTabCapture(),
            gitRemoteResolver: NoopGitRemoteResolver(),
            logger: NoopLogger(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            fileSystem: fileSystem,
            windowPollTimeout: 0.3,
            windowPollInterval: 0.05
        )
    }
}

private final class FocusHistoryAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(message: "stub"))
    var focusWindowSuccessIds: Set<Int> = []
    var workspacesWithFocusResult: Result<[ApWorkspaceSummary], ApCoreError> = .success([])
    var windowsByWorkspace: [String: [ApWindow]] = [:]
    var allWindows: [ApWindow] = []
    private(set) var focusedWindowIds: [Int] = []

    func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { workspacesWithFocusResult }
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }

    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> { .success([]) }
    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        .success(windowsByWorkspace[workspace] ?? [])
    }
    func listAllWindows() -> Result<[ApWindow], ApCoreError> {
        .success(allWindows)
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
        if let match = allWindows.first(where: { $0.windowId == windowId }) {
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

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
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

private struct NoopLogger: AgentPanelLogging {
    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> { .success(()) }
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
