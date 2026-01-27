import Foundation
import XCTest

@testable import ProjectWorkspacesCore

final class ProjectActivationEngineTests: XCTestCase {
    private let aerospacePath = "/opt/homebrew/bin/aerospace"
    private let listWindowsFormat = "%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title}"

    func testActivationIsIdempotentWhenWindowsExist() {
        let config = baseConfig()
        let fileSystem = InMemoryFileSystem(files: [config.path: Data(config.contents.utf8)], directories: ["/Applications/Visual Studio Code.app"])
        let runner = SequencedAeroSpaceCommandRunner(responses: [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 10, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
                    windowPayload(id: 20, workspace: "pw-codex", bundleId: ChromeLauncher.chromeBundleId, appName: "Google Chrome")
                ]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 10, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
                    windowPayload(id: 20, workspace: "pw-codex", bundleId: ChromeLauncher.chromeBundleId, appName: "Google Chrome")
                ]), stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "10"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "20"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "10"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ])
        let ideLauncher = TestIdeLauncher(result: .success(IdeLaunchSuccess(warnings: [])))
        let chromeLauncher = TestChromeLauncher(results: [])
        let geometryApplier = TestGeometryApplier(outcome: .applied)
        let displayProvider = TestDisplayInfoProvider(displayInfo: DisplayInfo(visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600), widthPixels: 800))
        let logger = TestLogger()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let stateStore = ProjectWorkspacesStateStore(paths: paths, fileSystem: fileSystem, logger: logger, dateProvider: FixedDateProvider())

        let engine = ProjectActivationEngine(
            paths: paths,
            fileSystem: fileSystem,
            configParser: ConfigParser(),
            aeroSpaceResolver: TestAeroSpaceResolver(executableURL: URL(fileURLWithPath: aerospacePath)),
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 1,
            commandRunner: TestCommandRunner(),
            appDiscovery: TestAppDiscovery(bundleIds: ["com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)]),
            ideLauncher: ideLauncher,
            chromeLauncherFactory: { _, _, _ in chromeLauncher },
            stateStore: stateStore,
            displayInfoProvider: displayProvider,
            layoutCalculator: DefaultLayoutCalculator(),
            logger: logger,
            dateProvider: FixedDateProvider(),
            sleeper: TestSleeper(),
            logAeroSpaceCommands: false,
            geometryApplierFactory: { _, _ in geometryApplier }
        )

        let result = engine.activate(projectId: "codex")
        switch result {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome.ideWindowId, 10)
            XCTAssertEqual(outcome.chromeWindowId, 20)
            XCTAssertTrue(outcome.warnings.isEmpty)
        }

        XCTAssertEqual(ideLauncher.callCount, 0)
        XCTAssertEqual(chromeLauncher.callCount, 0)
        XCTAssertTrue(geometryApplier.applyCalls.isEmpty)
    }

    func testFloatingFailureIsWarningAndDoesNotFailActivation() {
        let config = baseConfig()
        let fileSystem = InMemoryFileSystem(files: [config.path: Data(config.contents.utf8)], directories: ["/Applications/Visual Studio Code.app"])
        let layoutError = AeroSpaceCommandError.nonZeroExit(
            command: "\(aerospacePath) layout floating --window-id 10",
            result: CommandResult(exitCode: 1, stdout: "", stderr: "")
        )
        let runner = SequencedAeroSpaceCommandRunner(responses: [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 10, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
                    windowPayload(id: 20, workspace: "pw-codex", bundleId: ChromeLauncher.chromeBundleId, appName: "Google Chrome")
                ]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 10, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
                    windowPayload(id: 20, workspace: "pw-codex", bundleId: ChromeLauncher.chromeBundleId, appName: "Google Chrome")
                ]), stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "10"]): [
                .failure(layoutError)
            ],
            signature(["list-workspaces", "--focused", "--count"]): [
                .success(CommandResult(exitCode: 0, stdout: "1\n", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "20"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "10"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ])
        let ideLauncher = TestIdeLauncher(result: .success(IdeLaunchSuccess(warnings: [])))
        let chromeLauncher = TestChromeLauncher(results: [])
        let geometryApplier = TestGeometryApplier(outcome: .applied)
        let displayProvider = TestDisplayInfoProvider(displayInfo: DisplayInfo(visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600), widthPixels: 800))
        let logger = TestLogger()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let stateStore = ProjectWorkspacesStateStore(paths: paths, fileSystem: fileSystem, logger: logger, dateProvider: FixedDateProvider())

        let engine = ProjectActivationEngine(
            paths: paths,
            fileSystem: fileSystem,
            configParser: ConfigParser(),
            aeroSpaceResolver: TestAeroSpaceResolver(executableURL: URL(fileURLWithPath: aerospacePath)),
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 1,
            commandRunner: TestCommandRunner(),
            appDiscovery: TestAppDiscovery(bundleIds: ["com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)]),
            ideLauncher: ideLauncher,
            chromeLauncherFactory: { _, _, _ in chromeLauncher },
            stateStore: stateStore,
            displayInfoProvider: displayProvider,
            layoutCalculator: DefaultLayoutCalculator(),
            logger: logger,
            dateProvider: FixedDateProvider(),
            sleeper: TestSleeper(),
            logAeroSpaceCommands: false,
            geometryApplierFactory: { _, _ in geometryApplier }
        )

        let result = engine.activate(projectId: "codex")
        switch result {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome.ideWindowId, 10)
            XCTAssertEqual(outcome.chromeWindowId, 20)
            XCTAssertEqual(outcome.warnings, [
                .floatingFailed(kind: .ide, windowId: 10, error: layoutError)
            ])
        }
    }

    func testManagedIdeMoveTriggersLayoutApply() {
        let config = baseConfig()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let managedState = ProjectWorkspacesState(
            projects: [
                "codex": ManagedWindowState(ideWindowId: 42, chromeWindowId: 20)
            ]
        )
        let stateData = try? JSONEncoder().encode(managedState)

        let fileSystem = InMemoryFileSystem(
            files: [
                config.path: Data(config.contents.utf8),
                paths.stateFile.path: stateData ?? Data()
            ],
            directories: ["/Applications/Visual Studio Code.app"]
        )

        let runner = SequencedAeroSpaceCommandRunner(responses: [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 20, workspace: "pw-codex", bundleId: ChromeLauncher.chromeBundleId, appName: "Google Chrome")
                ]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 20, workspace: "pw-codex", bundleId: ChromeLauncher.chromeBundleId, appName: "Google Chrome")
                ]), stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 42, workspace: "pw-other", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
                    windowPayload(id: 20, workspace: "pw-codex", bundleId: ChromeLauncher.chromeBundleId, appName: "Google Chrome")
                ]), stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "42", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "42"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "20"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "42"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ])

        let ideLauncher = TestIdeLauncher(result: .success(IdeLaunchSuccess(warnings: [])))
        let chromeLauncher = TestChromeLauncher(results: [])
        let geometryApplier = TestGeometryApplier(outcome: .applied)
        let displayProvider = TestDisplayInfoProvider(displayInfo: DisplayInfo(visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600), widthPixels: 800))
        let logger = TestLogger()
        let stateStore = ProjectWorkspacesStateStore(paths: paths, fileSystem: fileSystem, logger: logger, dateProvider: FixedDateProvider())

        let engine = ProjectActivationEngine(
            paths: paths,
            fileSystem: fileSystem,
            configParser: ConfigParser(),
            aeroSpaceResolver: TestAeroSpaceResolver(executableURL: URL(fileURLWithPath: aerospacePath)),
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 1,
            commandRunner: TestCommandRunner(),
            appDiscovery: TestAppDiscovery(bundleIds: ["com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)]),
            ideLauncher: ideLauncher,
            chromeLauncherFactory: { _, _, _ in chromeLauncher },
            stateStore: stateStore,
            displayInfoProvider: displayProvider,
            layoutCalculator: DefaultLayoutCalculator(),
            logger: logger,
            dateProvider: FixedDateProvider(),
            sleeper: TestSleeper(),
            logAeroSpaceCommands: false,
            geometryApplierFactory: { _, _ in geometryApplier }
        )

        let result = engine.activate(projectId: "codex")
        switch result {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome.ideWindowId, 42)
            XCTAssertEqual(outcome.chromeWindowId, 20)
        }

        XCTAssertEqual(geometryApplier.applyCalls.count, 2)
    }

    func testMultipleIdeWindowsWarnsAndSelectsLowest() {
        let config = baseConfig()
        let fileSystem = InMemoryFileSystem(files: [config.path: Data(config.contents.utf8)], directories: ["/Applications/Visual Studio Code.app"])
        let runner = SequencedAeroSpaceCommandRunner(responses: [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 9, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
                    windowPayload(id: 5, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
                    windowPayload(id: 20, workspace: "pw-codex", bundleId: ChromeLauncher.chromeBundleId, appName: "Google Chrome")
                ]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 9, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
                    windowPayload(id: 5, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
                    windowPayload(id: 20, workspace: "pw-codex", bundleId: ChromeLauncher.chromeBundleId, appName: "Google Chrome")
                ]), stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "5"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "20"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "5"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ])
        let ideLauncher = TestIdeLauncher(result: .success(IdeLaunchSuccess(warnings: [])))
        let chromeLauncher = TestChromeLauncher(results: [])
        let geometryApplier = TestGeometryApplier(outcome: .applied)
        let displayProvider = TestDisplayInfoProvider(displayInfo: DisplayInfo(visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600), widthPixels: 800))
        let logger = TestLogger()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let stateStore = ProjectWorkspacesStateStore(paths: paths, fileSystem: fileSystem, logger: logger, dateProvider: FixedDateProvider())

        let engine = ProjectActivationEngine(
            paths: paths,
            fileSystem: fileSystem,
            configParser: ConfigParser(),
            aeroSpaceResolver: TestAeroSpaceResolver(executableURL: URL(fileURLWithPath: aerospacePath)),
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 1,
            commandRunner: TestCommandRunner(),
            appDiscovery: TestAppDiscovery(bundleIds: ["com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)]),
            ideLauncher: ideLauncher,
            chromeLauncherFactory: { _, _, _ in chromeLauncher },
            stateStore: stateStore,
            displayInfoProvider: displayProvider,
            layoutCalculator: DefaultLayoutCalculator(),
            logger: logger,
            dateProvider: FixedDateProvider(),
            sleeper: TestSleeper(),
            logAeroSpaceCommands: false,
            geometryApplierFactory: { _, _ in geometryApplier }
        )

        let result = engine.activate(projectId: "codex")
        switch result {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome.ideWindowId, 5)
            XCTAssertEqual(outcome.chromeWindowId, 20)
            XCTAssertEqual(outcome.warnings, [
                .multipleWindows(kind: .ide, workspace: "pw-codex", chosenId: 5, extraIds: [9])
            ])
        }
    }

    func testChromeCreatedElsewhereMovesIntoWorkspace() {
        let config = baseConfig()
        let fileSystem = InMemoryFileSystem(files: [config.path: Data(config.contents.utf8)], directories: ["/Applications/Visual Studio Code.app"])
        let runner = SequencedAeroSpaceCommandRunner(responses: [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 10, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code")
                ]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 10, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code")
                ]), stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "77", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "10"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "77"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "10"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ])

        let ideLauncher = TestIdeLauncher(result: .success(IdeLaunchSuccess(warnings: [])))
        let chromeLauncher = TestChromeLauncher(results: [
            .failure(.chromeLaunchedElsewhere(expectedWorkspace: "pw-codex", actualWorkspace: "pw-other", newWindowId: 77))
        ])
        let geometryApplier = TestGeometryApplier(outcome: .applied)
        let displayProvider = TestDisplayInfoProvider(displayInfo: DisplayInfo(visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600), widthPixels: 800))
        let logger = TestLogger()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let stateStore = ProjectWorkspacesStateStore(paths: paths, fileSystem: fileSystem, logger: logger, dateProvider: FixedDateProvider())

        let engine = ProjectActivationEngine(
            paths: paths,
            fileSystem: fileSystem,
            configParser: ConfigParser(),
            aeroSpaceResolver: TestAeroSpaceResolver(executableURL: URL(fileURLWithPath: aerospacePath)),
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 1,
            commandRunner: TestCommandRunner(),
            appDiscovery: TestAppDiscovery(bundleIds: ["com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)]),
            ideLauncher: ideLauncher,
            chromeLauncherFactory: { _, _, _ in chromeLauncher },
            stateStore: stateStore,
            displayInfoProvider: displayProvider,
            layoutCalculator: DefaultLayoutCalculator(),
            logger: logger,
            dateProvider: FixedDateProvider(),
            sleeper: TestSleeper(),
            logAeroSpaceCommands: false,
            geometryApplierFactory: { _, _ in geometryApplier }
        )

        let result = engine.activate(projectId: "codex")
        switch result {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome.ideWindowId, 10)
            XCTAssertEqual(outcome.chromeWindowId, 77)
            XCTAssertTrue(outcome.warnings.isEmpty)
        }

        XCTAssertEqual(geometryApplier.applyCalls.count, 2)
        XCTAssertEqual(chromeLauncher.callCount, 1)
    }

    func testMissingWindowsLaunchesIdeAndChrome() {
        let config = baseConfig()
        let fileSystem = InMemoryFileSystem(files: [config.path: Data(config.contents.utf8)], directories: ["/Applications/Visual Studio Code.app"])
        let runner = SequencedAeroSpaceCommandRunner(responses: [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 11, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code")
                ]), stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    windowPayload(id: 11, workspace: "pw-codex", bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code")
                ]), stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "11"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "55"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "11"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ])

        let ideLauncher = TestIdeLauncher(result: .success(IdeLaunchSuccess(warnings: [])))
        let chromeLauncher = TestChromeLauncher(results: [.success(.created(windowId: 55))])
        let geometryApplier = TestGeometryApplier(outcome: .applied)
        let displayProvider = TestDisplayInfoProvider(displayInfo: DisplayInfo(visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600), widthPixels: 800))
        let logger = TestLogger()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let stateStore = ProjectWorkspacesStateStore(paths: paths, fileSystem: fileSystem, logger: logger, dateProvider: FixedDateProvider())

        let engine = ProjectActivationEngine(
            paths: paths,
            fileSystem: fileSystem,
            configParser: ConfigParser(),
            aeroSpaceResolver: TestAeroSpaceResolver(executableURL: URL(fileURLWithPath: aerospacePath)),
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 1,
            commandRunner: TestCommandRunner(),
            appDiscovery: TestAppDiscovery(bundleIds: ["com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)]),
            ideLauncher: ideLauncher,
            chromeLauncherFactory: { _, _, _ in chromeLauncher },
            stateStore: stateStore,
            displayInfoProvider: displayProvider,
            layoutCalculator: DefaultLayoutCalculator(),
            logger: logger,
            dateProvider: FixedDateProvider(),
            sleeper: TestSleeper(),
            logAeroSpaceCommands: false,
            geometryApplierFactory: { _, _ in geometryApplier }
        )

        let result = engine.activate(projectId: "codex")
        switch result {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome.ideWindowId, 11)
            XCTAssertEqual(outcome.chromeWindowId, 55)
            XCTAssertTrue(outcome.warnings.isEmpty)
        }

        XCTAssertEqual(ideLauncher.callCount, 1)
        XCTAssertEqual(chromeLauncher.callCount, 1)
        XCTAssertEqual(geometryApplier.applyCalls.count, 2)
    }

    private func baseConfig() -> (path: String, contents: String) {
        let contents = """
        [global]
        defaultIde = "vscode"
        globalChromeUrls = ["https://example.com"]

        [display]
        ultrawideMinWidthPx = 5000

        [ide.vscode]
        appPath = "/Applications/Visual Studio Code.app"
        bundleId = "com.microsoft.VSCode"

        [[project]]
        id = "codex"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#7C3AED"
        repoUrl = "https://example.com/repo"
        ide = "vscode"
        ideUseAgentLayerLauncher = true
        ideCommand = ""
        chromeUrls = ["https://example.com/one"]
        """

        let path = "/Users/tester/.config/project-workspaces/config.toml"
        return (path, contents)
    }

    private func signature(_ arguments: [String]) -> AeroSpaceCommandSignature {
        AeroSpaceCommandSignature(path: aerospacePath, arguments: arguments)
    }
}

private struct WindowPayload: Encodable {
    let windowId: Int
    let workspace: String
    let appBundleId: String
    let appName: String
    let windowTitle: String

    enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case workspace
        case appBundleId = "app-bundle-id"
        case appName = "app-name"
        case windowTitle = "window-title"
    }
}

private func windowPayload(id: Int, workspace: String, bundleId: String, appName: String) -> WindowPayload {
    WindowPayload(
        windowId: id,
        workspace: workspace,
        appBundleId: bundleId,
        appName: appName,
        windowTitle: "Window"
    )
}

private func windowsJSON(_ windows: [WindowPayload]) -> String {
    guard let data = try? JSONEncoder().encode(windows),
          let json = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return json
}
