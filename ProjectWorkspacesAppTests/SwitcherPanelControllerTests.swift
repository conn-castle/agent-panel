import AppKit
import XCTest

import ProjectWorkspacesCore
@testable import ProjectWorkspaces

final class SwitcherPanelControllerTests: XCTestCase {
    func testPanelCanJoinAllSpaces() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let catalogService = ProjectCatalogService(
            paths: .defaultPaths(),
            fileSystem: MissingConfigFileSystem()
        )
        let controller = SwitcherPanelController(
            projectCatalogService: catalogService,
            logger: NoopLogger(),
            workspaceManager: TestWorkspaceManager()
        )

        let behavior = controller.panelCollectionBehaviorForTesting()
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertTrue(behavior.contains(.transient))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
    }

    func testShowMakesPanelVisibleWhenConfigIsMissing() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let catalogService = ProjectCatalogService(
            paths: .defaultPaths(),
            fileSystem: MissingConfigFileSystem()
        )
        let controller = SwitcherPanelController(
            projectCatalogService: catalogService,
            logger: NoopLogger(),
            workspaceManager: TestWorkspaceManager()
        )

        let expectation = expectation(description: "Switcher panel becomes visible")

        DispatchQueue.main.async {
            controller.show(origin: .menu)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertTrue(controller.isPanelVisibleForTesting())
            controller.dismiss()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testShowWaitsForFocusSnapshotBeforeShowingPanel() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let catalogService = ProjectCatalogService(
            paths: .defaultPaths(),
            fileSystem: MissingConfigFileSystem()
        )
        let workspaceManager = BlockingWorkspaceManager()
        let controller = SwitcherPanelController(
            projectCatalogService: catalogService,
            logger: NoopLogger(),
            workspaceManager: workspaceManager
        )

        let expectation = expectation(description: "Switcher panel becomes visible after snapshot")

        DispatchQueue.main.async {
            controller.show(origin: .menu)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertFalse(controller.isPanelVisibleForTesting())
            workspaceManager.release()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            XCTAssertTrue(controller.isPanelVisibleForTesting())
            controller.dismiss()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testShouldRestoreFocusOnDismissReasons() {
        let catalogService = ProjectCatalogService(
            paths: .defaultPaths(),
            fileSystem: MissingConfigFileSystem()
        )
        let controller = SwitcherPanelController(
            projectCatalogService: catalogService,
            logger: NoopLogger(),
            workspaceManager: TestWorkspaceManager()
        )

        XCTAssertTrue(controller.shouldRestoreFocus(reason: .toggle))
        XCTAssertTrue(controller.shouldRestoreFocus(reason: .escape))
        XCTAssertTrue(controller.shouldRestoreFocus(reason: .windowClose))
        XCTAssertFalse(controller.shouldRestoreFocus(reason: .activationRequested))
        XCTAssertFalse(controller.shouldRestoreFocus(reason: .activationSucceeded))
        XCTAssertFalse(controller.shouldRestoreFocus(reason: .unknown))
    }
}

private struct MissingConfigFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool {
        false
    }

    func directoryExists(at url: URL) -> Bool {
        false
    }

    func isExecutableFile(at url: URL) -> Bool {
        false
    }

    func readFile(at url: URL) throws -> Data {
        throw missingFileError(url)
    }

    func createDirectory(at url: URL) throws {
        throw missingFileError(url)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        throw missingFileError(url)
    }

    func removeItem(at url: URL) throws {
        throw missingFileError(url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        throw missingFileError(sourceURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        throw missingFileError(url)
    }

    func writeFile(at url: URL, data: Data) throws {
        throw missingFileError(url)
    }

    func syncFile(at url: URL) throws {
        throw missingFileError(url)
    }

    @discardableResult
    func replaceItemAt(_ originalURL: URL, withItemAt newItemURL: URL) throws -> URL? {
        throw missingFileError(originalURL)
    }

    private func missingFileError(_ url: URL) -> NSError {
        NSError(
            domain: "MissingConfigFileSystem",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unexpected file system access: \(url.path)"]
        )
    }
}

private struct NoopLogger: ProjectWorkspacesLogging {
    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError> {
        .success(())
    }
}

private struct TestWorkspaceManager: WorkspaceManaging {
    var snapshotProvider: () -> WorkspaceFocusSnapshot? = { nil }

    func activate(
        projectId _: String,
        focusIdeWindow _: Bool,
        switchWorkspace _: Bool,
        progress _: ((ActivationProgress) -> Void)?,
        cancellationToken _: ActivationCancellationToken?
    ) -> ActivationOutcome {
        .failure(error: .cancelled)
    }

    func focusWorkspaceAndWindow(report _: ActivationReport) -> Result<Void, ActivationError> {
        .success(())
    }

    func captureFocusSnapshot() -> WorkspaceFocusSnapshot? {
        snapshotProvider()
    }

    func restoreFocusSnapshot(_: WorkspaceFocusSnapshot) {}

    func workspaceExists(name _: String) -> Bool {
        false
    }
}

private final class BlockingWorkspaceManager: WorkspaceManaging {
    private let semaphore = DispatchSemaphore(value: 0)

    func activate(
        projectId _: String,
        focusIdeWindow _: Bool,
        switchWorkspace _: Bool,
        progress _: ((ActivationProgress) -> Void)?,
        cancellationToken _: ActivationCancellationToken?
    ) -> ActivationOutcome {
        .failure(error: .cancelled)
    }

    func focusWorkspaceAndWindow(report _: ActivationReport) -> Result<Void, ActivationError> {
        .success(())
    }

    func captureFocusSnapshot() -> WorkspaceFocusSnapshot? {
        _ = semaphore.wait(timeout: .now() + 1.0)
        return nil
    }

    func restoreFocusSnapshot(_: WorkspaceFocusSnapshot) {}

    func workspaceExists(name _: String) -> Bool {
        false
    }

    func release() {
        semaphore.signal()
    }
}
