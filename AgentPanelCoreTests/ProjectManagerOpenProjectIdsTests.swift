import Foundation
import XCTest
@testable import AgentPanelCore

final class ProjectManagerOpenProjectIdsTests: XCTestCase {

    func testOpenProjectIdsReturnsPrefixedWorkspaceIds() {
        let aerospace = OpenProjectIdsAeroSpaceStub(
            getWorkspacesResult: .success(["ap-alpha", "main", "ap-beta", "ap-alpha"])
        )
        let manager = makeManager(aerospace: aerospace)

        switch manager.openProjectIds() {
        case .success(let ids):
            XCTAssertEqual(ids, Set(["alpha", "beta"]))
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenProjectIdsReturnsAeroSpaceFailureWhenWorkspaceQueryFails() {
        let aerospace = OpenProjectIdsAeroSpaceStub(
            getWorkspacesResult: .failure(ApCoreError(message: "workspace query failed"))
        )
        let manager = makeManager(aerospace: aerospace)

        switch manager.openProjectIds() {
        case .success(let ids):
            XCTFail("Expected failure, got ids: \(ids)")
        case .failure(let error):
            XCTAssertEqual(error, .aeroSpaceError(detail: "workspace query failed"))
        }
    }

    private func makeManager(aerospace: OpenProjectIdsAeroSpaceStub) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-open-ids-\(UUID().uuidString).json")
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: OpenProjectIdsIdeLauncherStub(),
            chromeLauncher: OpenProjectIdsChromeLauncherStub(),
            logger: OpenProjectIdsLoggerStub(),
            recencyFilePath: recencyFilePath
        )
    }
}

private final class OpenProjectIdsAeroSpaceStub: AeroSpaceProviding {
    let getWorkspacesResult: Result<[String], ApCoreError>

    init(getWorkspacesResult: Result<[String], ApCoreError>) {
        self.getWorkspacesResult = getWorkspacesResult
    }

    func getWorkspaces() -> Result<[String], ApCoreError> {
        getWorkspacesResult
    }

    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> {
        .success(false)
    }

    func listWorkspacesFocused() -> Result<[String], ApCoreError> {
        .success([])
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

private struct OpenProjectIdsIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?) -> Result<Void, ApCoreError> {
        .success(())
    }
}

private struct OpenProjectIdsChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String) -> Result<Void, ApCoreError> {
        .success(())
    }
}

private struct OpenProjectIdsLoggerStub: AgentPanelLogging {
    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError> {
        .success(())
    }
}
