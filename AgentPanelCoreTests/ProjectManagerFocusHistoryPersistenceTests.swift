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

    func testLoadFocusHistoryFailureFallsBackToEmptyHistory() {
        let fileSystem = FocusHistoryStoreFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readError = NSError(domain: "ProjectManagerFocusHistoryPersistenceTests", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "read failed"
        ])

        let focusHistoryPath = URL(fileURLWithPath: "/focus-history-load-fail.json", isDirectory: false)
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
        if case .failure(.noPreviousWindow) = result {
            return
        }
        XCTFail("Expected noPreviousWindow when persisted history cannot be loaded")
    }

    func testPersistFocusHistoryFailureDoesNotBreakInMemoryRestore() {
        let fileSystem = FocusHistoryStoreFailingFileSystem()
        fileSystem.writeError = NSError(domain: "ProjectManagerFocusHistoryPersistenceTests", code: 11, userInfo: [
            NSLocalizedDescriptionKey: "write failed"
        ])
        let focusHistoryPath = URL(fileURLWithPath: "/focus-history-save-fail.json", isDirectory: false)

        let aero = FocusHistoryAeroSpaceStub()
        let window = ApWindow(windowId: 42, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        aero.allWindows = [window]
        aero.focusWindowSuccessIds = [42]
        aero.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        let manager = makeManager(
            aerospace: aero,
            fileSystem: fileSystem,
            focusHistoryFilePath: focusHistoryPath
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager.pushFocusForTest(CapturedFocus(
            windowId: 42,
            appBundleId: "com.apple.Terminal",
            workspace: "main"
        ))

        let result = manager.exitToNonProjectWindow()
        if case .failure(let error) = result {
            XCTFail("Expected success with in-memory focus despite save failure, got \(error)")
        }
        XCTAssertGreaterThan(fileSystem.writeCallCount, 0)
        XCTAssertTrue(aero.focusedWindowIds.contains(42))
    }

    private func makeManager(
        aerospace: FocusHistoryAeroSpaceStub,
        fileSystem: FileSystem,
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

final class FocusHistoryStoreCoverageTests: XCTestCase {
    private let focusHistoryFile = URL(fileURLWithPath: "/focus-history-coverage.json", isDirectory: false)

    func testLoadReturnsFailureWhenReadFails() {
        let fileSystem = FocusHistoryStoreFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readError = NSError(domain: "FocusHistoryStoreCoverageTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "read failed"
        ])
        let store = makeStore(fileSystem: fileSystem)

        let result = store.load(now: Date())

        switch result {
        case .success:
            XCTFail("Expected read failure")
        case .failure(let error):
            XCTAssertEqual(error.message, "Failed to read focus history")
            XCTAssertEqual(error.detail, "read failed")
        }
    }

    func testLoadReturnsFailureWhenDecodeFails() {
        let fileSystem = FocusHistoryStoreFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readData = Data("not-json".utf8)
        let store = makeStore(fileSystem: fileSystem)

        let result = store.load(now: Date())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Failed to decode focus history")
            return
        }
        XCTFail("Expected decode failure")
    }

    func testLoadReturnsFailureWhenVersionIsUnsupported() throws {
        let fileSystem = FocusHistoryStoreFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readData = try JSONSerialization.data(withJSONObject: [
            "version": FocusHistoryStore.currentVersion + 1,
            "stack": [],
            "mostRecent": NSNull()
        ])
        let store = makeStore(fileSystem: fileSystem)

        let result = store.load(now: Date())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Unsupported focus history version")
            return
        }
        XCTFail("Expected unsupported version failure")
    }

    func testLoadPrunesWhenStackExceedsMaxEntries() {
        let fileSystem = FocusHistoryStoreFailingFileSystem()
        let now = Date()
        let store = makeStore(fileSystem: fileSystem, maxAge: 60 * 60, maxEntries: 2)
        let state = FocusHistoryState(
            version: FocusHistoryStore.currentVersion,
            stack: [
                FocusHistoryEntry(windowId: 1, appBundleId: "com.apple.Terminal", workspace: "main", capturedAt: now),
                FocusHistoryEntry(windowId: 2, appBundleId: "com.apple.Safari", workspace: "main", capturedAt: now),
                FocusHistoryEntry(windowId: 3, appBundleId: "com.apple.TextEdit", workspace: "main", capturedAt: now)
            ],
            mostRecent: nil
        )
        _ = store.save(state: state)
        fileSystem.fileExistsValue = true
        fileSystem.readData = fileSystem.lastWrittenData

        let result = store.load(now: now)

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        case .success(let outcome):
            guard let outcome else {
                XCTFail("Expected pruned outcome")
                return
            }
            XCTAssertEqual(outcome.prunedCount, 1)
            XCTAssertEqual(outcome.state.stack.map(\.windowId), [2, 3])
        }
    }

    func testLoadReturnsFailureWhenTimestampIsInvalid() {
        let fileSystem = FocusHistoryStoreFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readData = Data(
            """
            {
              "version": 1,
              "stack": [
                {
                  "windowId": 1,
                  "appBundleId": "com.apple.Terminal",
                  "workspace": "main",
                  "capturedAt": "invalid-date"
                }
              ],
              "mostRecent": null
            }
            """.utf8
        )
        let store = makeStore(fileSystem: fileSystem)

        let result = store.load(now: Date())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Failed to decode focus history")
            return
        }
        XCTFail("Expected timestamp parse failure")
    }

    func testSaveReturnsFailureWhenCreateDirectoryFails() {
        let fileSystem = FocusHistoryStoreFailingFileSystem()
        fileSystem.createDirectoryError = NSError(domain: "FocusHistoryStoreCoverageTests", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "mkdir failed"
        ])
        let store = makeStore(fileSystem: fileSystem)

        let result = store.save(state: sampleState())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Failed to create focus history directory")
            XCTAssertEqual(error.detail, "mkdir failed")
            return
        }
        XCTFail("Expected create-directory failure")
    }

    func testSaveReturnsFailureWhenWriteFails() {
        let fileSystem = FocusHistoryStoreFailingFileSystem()
        fileSystem.writeError = NSError(domain: "FocusHistoryStoreCoverageTests", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "write failed"
        ])
        let store = makeStore(fileSystem: fileSystem)

        let result = store.save(state: sampleState())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Failed to write focus history")
            XCTAssertEqual(error.detail, "write failed")
            return
        }
        XCTFail("Expected write failure")
    }

    private func makeStore(
        fileSystem: FocusHistoryStoreFailingFileSystem,
        maxAge: TimeInterval = 60,
        maxEntries: Int = 20
    ) -> FocusHistoryStore {
        FocusHistoryStore(
            fileURL: focusHistoryFile,
            fileSystem: fileSystem,
            maxAge: maxAge,
            maxEntries: maxEntries
        )
    }

    private func sampleState() -> FocusHistoryState {
        FocusHistoryState(
            version: FocusHistoryStore.currentVersion,
            stack: [
                FocusHistoryEntry(
                    windowId: 42,
                    appBundleId: "com.apple.Terminal",
                    workspace: "main",
                    capturedAt: Date()
                )
            ],
            mostRecent: nil
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

private final class FocusHistoryStoreFailingFileSystem: FileSystem {
    var fileExistsValue = false
    var readData: Data?
    var readError: Error?
    var createDirectoryError: Error?
    var writeError: Error?
    var lastWrittenData: Data?
    var writeCallCount = 0

    func fileExists(at url: URL) -> Bool { fileExistsValue }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }

    func readFile(at url: URL) throws -> Data {
        if let readError {
            throw readError
        }
        if let readData {
            return readData
        }
        throw NSError(domain: "FocusHistoryStoreFailingFileSystem", code: 99, userInfo: nil)
    }

    func createDirectory(at url: URL) throws {
        if let createDirectoryError {
            throw createDirectoryError
        }
    }

    func fileSize(at url: URL) throws -> UInt64 { UInt64(lastWrittenData?.count ?? 0) }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}

    func writeFile(at url: URL, data: Data) throws {
        writeCallCount += 1
        if let writeError {
            throw writeError
        }
        lastWrittenData = data
        readData = data
    }
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
