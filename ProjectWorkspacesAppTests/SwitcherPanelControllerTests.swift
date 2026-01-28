import AppKit
import XCTest

import ProjectWorkspacesCore
@testable import ProjectWorkspaces

final class SwitcherPanelControllerTests: XCTestCase {
    func testShowMakesPanelVisibleWhenConfigIsMissing() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let catalogService = ProjectCatalogService(
            paths: .defaultPaths(),
            fileSystem: MissingConfigFileSystem()
        )
        let controller = SwitcherPanelController(
            projectCatalogService: catalogService,
            logger: NoopLogger()
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
