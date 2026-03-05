import XCTest

@testable import AgentPanel
@testable import AgentPanelAppKit
@testable import AgentPanelCore

// MARK: - Test Infrastructure (duplicated from SwitcherFocusFlowTests, as those are private)

struct CoordinatorTestLogEntryRecord: Equatable {
    let event: String
    let level: LogLevel
    let message: String?
    let context: [String: String]?
}

final class CoordinatorTestRecordingLogger: AgentPanelLogging {
    private let queue = DispatchQueue(label: "com.agentpanel.tests.coordinator.logger")
    private var entries: [CoordinatorTestLogEntryRecord] = []
    var onLog: ((CoordinatorTestLogEntryRecord) -> Void)?

    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
        let entry = CoordinatorTestLogEntryRecord(event: event, level: level, message: message, context: context)
        queue.sync {
            entries.append(entry)
        }
        onLog?(entry)
        return .success(())
    }

    func entriesSnapshot() -> [CoordinatorTestLogEntryRecord] {
        queue.sync { entries }
    }
}

final class CoordinatorTestAeroSpaceStub: AeroSpaceProviding {
    static let defaultListWorkspacesWithFocusWaitTimeoutSeconds: TimeInterval = 5.0

    var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(message: "stub"))
    var focusWindowSuccessIds: Set<Int> = []
    var workspacesWithFocusResult: Result<[ApWorkspaceSummary], ApCoreError> = .success([])
    var onListWorkspacesWithFocus: (() -> Void)?
    var onListWorkspacesWithFocusReturn: (() -> Void)?
    var listWorkspacesWithFocusWaitSemaphore: DispatchSemaphore?
    var listWorkspacesWithFocusWaitTimeoutSeconds: TimeInterval = defaultListWorkspacesWithFocusWaitTimeoutSeconds
    var focusWorkspaceResult: Result<Void, ApCoreError> = .success(())
    var windowsByBundleId: [String: [ApWindow]] = [:]
    var windowsByWorkspace: [String: [ApWindow]] = [:]
    var allWindows: [ApWindow] = []
    private(set) var focusedWindowIds: [Int] = []
    private(set) var focusedWorkspaces: [String] = []

    func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> {
        onListWorkspacesWithFocus?()
        if let waitSemaphore = listWorkspacesWithFocusWaitSemaphore {
            let waitResult = waitSemaphore.wait(timeout: .now() + listWorkspacesWithFocusWaitTimeoutSeconds)
            if waitResult == .timedOut {
                let message = "Timed out waiting \(listWorkspacesWithFocusWaitTimeoutSeconds)s for listWorkspacesWithFocusWaitSemaphore signal"
                XCTFail(message)
                onListWorkspacesWithFocusReturn?()
                return .failure(ApCoreError(message: message))
            }
        }
        onListWorkspacesWithFocusReturn?()
        return workspacesWithFocusResult
    }
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

struct CoordinatorTestIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> {
        .success(())
    }
}

struct CoordinatorTestChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> {
        .success(())
    }
}

struct CoordinatorTestTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> { .success([]) }
}

struct CoordinatorTestGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? { nil }
}

final class CoordinatorTestInMemoryFileSystem: FileSystem {
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
}
