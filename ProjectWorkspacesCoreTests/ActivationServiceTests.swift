import XCTest

@testable import ProjectWorkspacesCore

final class ActivationServiceTests: XCTestCase {
    private let aerospacePath = TestConstants.aerospacePath
    private let listWindowsFormat = TestConstants.listWindowsFormat

    func testActivationLaunchesMissingWindowsAndAppliesLayout() throws {
        let fileSystem = TestFileSystem()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        fileSystem.addFile(at: paths.configFile.path, content: validConfigTOML())
        let configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
        let stateStore = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        let ideWindow = windowPayload(
            id: 12,
            workspace: "1",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - VS Code"
        )
        let chromeWindow = chromeWindowPayload(
            id: 30,
            workspace: "1",
            windowTitle: "PW:codex - Google Chrome"
        )

        let focusResponses = [
            Result<CommandResult, AeroSpaceCommandError>.success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: "")),
            Result<CommandResult, AeroSpaceCommandError>.success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
        ]

        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json"]): [
                .success(CommandResult(exitCode: 0, stdout: "[]", stderr: ""))
            ],
            signature(["focus", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["move-node-to-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-workspaces", "--focused", "--format", "%{workspace}"]): focusResponses,
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow, chromeWindow]), stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "12", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "30", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["flatten-workspace-tree", "--workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["balance-sizes", "--workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "12", "h_tiles"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["resize", "--window-id", "12", "width", "1200"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]

        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let resolver = FixedBinaryResolver(result: .success(URL(fileURLWithPath: aerospacePath)))
        let appDiscovery = TestAppDiscovery(bundleIds: [
            TestConstants.vscodeBundleId: TestConstants.vscodeAppURL,
            ChromeApp.bundleId: URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)
        ])
        let ideResolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)
        let screenMetrics = TestScreenMetricsProvider(widthsByIndex: [1: 2000])
        let clock = TestClock()
        let sleeper = AdvancingSleeper(clock: clock)
        let logger = TestLogger()

        let openRunner = RecordingCommandRunner()
        let ideOpenArgs = [
            "-n",
            "-a",
            TestConstants.vscodeAppURL.path,
            paths.vscodeWorkspaceFile(projectId: "codex").path
        ]
        openRunner.addResult(
            for: OpenCommandSignature(path: "/usr/bin/open", arguments: ideOpenArgs),
            result: CommandResult(exitCode: 0, stdout: "", stderr: "")
        )
        let chromeOpenArgs = [
            "-n",
            "-a",
            "/Applications/Google Chrome.app",
            "--args",
            "--new-window",
            "--window-name=PW:codex"
        ]
        openRunner.addResult(
            for: OpenCommandSignature(path: "/usr/bin/open", arguments: chromeOpenArgs),
            result: CommandResult(exitCode: 0, stdout: "", stderr: "")
        )

        let service = ActivationService(
            configLoader: configLoader,
            aeroSpaceBinaryResolver: resolver,
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 2,
            commandRunner: openRunner,
            ideAppResolver: ideResolver,
            appDiscovery: appDiscovery,
            workspaceGenerator: VSCodeWorkspaceGenerator(paths: paths, fileSystem: fileSystem),
            stateStore: stateStore,
            screenMetricsProvider: screenMetrics,
            logger: logger,
            sleeper: sleeper,
            clock: clock,
            focusTiming: .fixed,
            windowDetectionTiming: .standard
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report):
            XCTAssertEqual(report.projectId, "codex")
            XCTAssertEqual(report.workspaceName, "pw-codex")
            XCTAssertEqual(report.ideWindowId, 12)
            XCTAssertEqual(report.chromeWindowId, 30)
        }

        XCTAssertEqual(openRunner.invocations.count, 2)

        let data = try XCTUnwrap(fileSystem.fileData(atPath: paths.stateFile.path))
        let decoded = try JSONDecoder().decode(BindingState.self, from: data)
        XCTAssertEqual(decoded.projects["codex"]?.ideBindings.first?.windowId, 12)
        XCTAssertEqual(decoded.projects["codex"]?.chromeBindings.first?.windowId, 30)
    }

    func testActivationSkipsLayoutWhenWorkspaceAlreadyOpen() {
        let fileSystem = TestFileSystem()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        fileSystem.addFile(at: paths.configFile.path, content: validConfigTOML())

        let ideBinding = WindowBinding(windowId: 12, appBundleId: TestConstants.vscodeBundleId, role: .ide, titleAtBindTime: "PW:codex")
        let chromeBinding = WindowBinding(windowId: 30, appBundleId: ChromeApp.bundleId, role: .chrome, titleAtBindTime: "PW:codex")
        let state = BindingState(projects: ["codex": ProjectBindings(ideBindings: [ideBinding], chromeBindings: [chromeBinding])])
        let encoded = try? JSONEncoder().encode(state)
        if let encoded {
            fileSystem.addFile(at: paths.stateFile.path, data: encoded)
        }

        let configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
        let stateStore = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - VS Code"
        )
        let chromeWindow = chromeWindowPayload(
            id: 30,
            workspace: "1",
            windowTitle: "PW:codex - Google Chrome"
        )

        let focusResponses = [
            Result<CommandResult, AeroSpaceCommandError>.success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: "")),
            Result<CommandResult, AeroSpaceCommandError>.success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
        ]

        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json"]): [
                .success(CommandResult(exitCode: 0, stdout: "[]", stderr: ""))
            ],
            signature(["focus", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["move-node-to-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-workspaces", "--focused", "--format", "%{workspace}"]): focusResponses,
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow, chromeWindow]), stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "30", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]

        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let resolver = FixedBinaryResolver(result: .success(URL(fileURLWithPath: aerospacePath)))
        let appDiscovery = TestAppDiscovery(bundleIds: [
            TestConstants.vscodeBundleId: TestConstants.vscodeAppURL,
            ChromeApp.bundleId: URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)
        ])
        let ideResolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)
        let screenMetrics = TestScreenMetricsProvider(widthsByIndex: [1: 2000])
        let clock = TestClock()
        let sleeper = AdvancingSleeper(clock: clock)
        let logger = TestLogger()
        let openRunner = RecordingCommandRunner()

        let service = ActivationService(
            configLoader: configLoader,
            aeroSpaceBinaryResolver: resolver,
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 2,
            commandRunner: openRunner,
            ideAppResolver: ideResolver,
            appDiscovery: appDiscovery,
            workspaceGenerator: VSCodeWorkspaceGenerator(paths: paths, fileSystem: fileSystem),
            stateStore: stateStore,
            screenMetricsProvider: screenMetrics,
            logger: logger,
            sleeper: sleeper,
            clock: clock,
            focusTiming: .fixed,
            windowDetectionTiming: .standard
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report):
            XCTAssertEqual(report.ideWindowId, 12)
            XCTAssertEqual(report.chromeWindowId, 30)
        }

        XCTAssertTrue(openRunner.invocations.isEmpty)
    }

    func testActivationPrunesStaleBindings() throws {
        let fileSystem = TestFileSystem()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        fileSystem.addFile(at: paths.configFile.path, content: validConfigTOML())

        let staleBinding = WindowBinding(windowId: 99, appBundleId: TestConstants.vscodeBundleId, role: .ide, titleAtBindTime: "PW:codex")
        let state = BindingState(projects: ["codex": ProjectBindings(ideBindings: [staleBinding], chromeBindings: [])])
        let encoded = try JSONEncoder().encode(state)
        fileSystem.addFile(at: paths.stateFile.path, data: encoded)

        let configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
        let stateStore = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        let mismatchedWindow = windowPayload(
            id: 99,
            workspace: "1",
            bundleId: "com.other.app",
            appName: "Other",
            windowTitle: "Other"
        )
        let newIdeWindow = windowPayload(
            id: 12,
            workspace: "1",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - VS Code"
        )
        let chromeWindow = chromeWindowPayload(
            id: 30,
            workspace: "1",
            windowTitle: "PW:codex - Google Chrome"
        )

        let focusResponses = [
            Result<CommandResult, AeroSpaceCommandError>.success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: "")),
            Result<CommandResult, AeroSpaceCommandError>.success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
        ]

        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json"]): [
                .success(CommandResult(exitCode: 0, stdout: "[]", stderr: ""))
            ],
            signature(["focus", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["move-node-to-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-workspaces", "--focused", "--format", "%{workspace}"]): focusResponses,
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([mismatchedWindow]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([newIdeWindow]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([newIdeWindow, chromeWindow]), stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "12", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "30", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["flatten-workspace-tree", "--workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["balance-sizes", "--workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "12", "h_tiles"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["resize", "--window-id", "12", "width", "1200"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]

        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let resolver = FixedBinaryResolver(result: .success(URL(fileURLWithPath: aerospacePath)))
        let appDiscovery = TestAppDiscovery(bundleIds: [
            TestConstants.vscodeBundleId: TestConstants.vscodeAppURL,
            ChromeApp.bundleId: URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)
        ])
        let ideResolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)
        let screenMetrics = TestScreenMetricsProvider(widthsByIndex: [1: 2000])
        let clock = TestClock()
        let sleeper = AdvancingSleeper(clock: clock)
        let logger = TestLogger()

        let openRunner = RecordingCommandRunner()
        let ideOpenArgs = [
            "-n",
            "-a",
            TestConstants.vscodeAppURL.path,
            paths.vscodeWorkspaceFile(projectId: "codex").path
        ]
        openRunner.addResult(
            for: OpenCommandSignature(path: "/usr/bin/open", arguments: ideOpenArgs),
            result: CommandResult(exitCode: 0, stdout: "", stderr: "")
        )
        let chromeOpenArgs = [
            "-n",
            "-a",
            "/Applications/Google Chrome.app",
            "--args",
            "--new-window",
            "--window-name=PW:codex"
        ]
        openRunner.addResult(
            for: OpenCommandSignature(path: "/usr/bin/open", arguments: chromeOpenArgs),
            result: CommandResult(exitCode: 0, stdout: "", stderr: "")
        )

        let service = ActivationService(
            configLoader: configLoader,
            aeroSpaceBinaryResolver: resolver,
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 2,
            commandRunner: openRunner,
            ideAppResolver: ideResolver,
            appDiscovery: appDiscovery,
            workspaceGenerator: VSCodeWorkspaceGenerator(paths: paths, fileSystem: fileSystem),
            stateStore: stateStore,
            screenMetricsProvider: screenMetrics,
            logger: logger,
            sleeper: sleeper,
            clock: clock,
            focusTiming: .fixed,
            windowDetectionTiming: .standard
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success:
            break
        }

        let data = try XCTUnwrap(fileSystem.fileData(atPath: paths.stateFile.path))
        let decoded = try JSONDecoder().decode(BindingState.self, from: data)
        XCTAssertEqual(decoded.projects["codex"]?.ideBindings.first?.windowId, 12)
        XCTAssertNotEqual(decoded.projects["codex"]?.ideBindings.first?.windowId, 99)
    }

    func testActivationKeepsFirstValidBindingAfterPrune() throws {
        let fileSystem = TestFileSystem()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        fileSystem.addFile(at: paths.configFile.path, content: validConfigTOML())

        let staleBinding = WindowBinding(windowId: 99, appBundleId: TestConstants.vscodeBundleId, role: .ide, titleAtBindTime: "PW:codex")
        let validBinding = WindowBinding(windowId: 12, appBundleId: TestConstants.vscodeBundleId, role: .ide, titleAtBindTime: "PW:codex")
        let chromeBinding = WindowBinding(windowId: 30, appBundleId: ChromeApp.bundleId, role: .chrome, titleAtBindTime: "PW:codex")
        let state = BindingState(projects: [
            "codex": ProjectBindings(ideBindings: [staleBinding, validBinding], chromeBindings: [chromeBinding])
        ])
        let encoded = try JSONEncoder().encode(state)
        fileSystem.addFile(at: paths.stateFile.path, data: encoded)

        let configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
        let stateStore = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - VS Code"
        )
        let chromeWindow = chromeWindowPayload(
            id: 30,
            workspace: "1",
            windowTitle: "PW:codex - Google Chrome"
        )

        let focusResponses = [
            Result<CommandResult, AeroSpaceCommandError>.success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: "")),
            Result<CommandResult, AeroSpaceCommandError>.success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
        ]

        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json"]): [
                .success(CommandResult(exitCode: 0, stdout: "[]", stderr: ""))
            ],
            signature(["focus", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["move-node-to-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-workspaces", "--focused", "--format", "%{workspace}"]): focusResponses,
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow, chromeWindow]), stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "30", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]

        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let resolver = FixedBinaryResolver(result: .success(URL(fileURLWithPath: aerospacePath)))
        let appDiscovery = TestAppDiscovery(bundleIds: [
            TestConstants.vscodeBundleId: TestConstants.vscodeAppURL,
            ChromeApp.bundleId: URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)
        ])
        let ideResolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)
        let screenMetrics = TestScreenMetricsProvider(widthsByIndex: [1: 2000])
        let clock = TestClock()
        let sleeper = AdvancingSleeper(clock: clock)
        let logger = TestLogger()
        let openRunner = RecordingCommandRunner()

        let service = ActivationService(
            configLoader: configLoader,
            aeroSpaceBinaryResolver: resolver,
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 2,
            commandRunner: openRunner,
            ideAppResolver: ideResolver,
            appDiscovery: appDiscovery,
            workspaceGenerator: VSCodeWorkspaceGenerator(paths: paths, fileSystem: fileSystem),
            stateStore: stateStore,
            screenMetricsProvider: screenMetrics,
            logger: logger,
            sleeper: sleeper,
            clock: clock,
            focusTiming: .fixed,
            windowDetectionTiming: .standard
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report):
            XCTAssertEqual(report.ideWindowId, 12)
            XCTAssertEqual(report.chromeWindowId, 30)
        }

        XCTAssertTrue(openRunner.invocations.isEmpty)

        let data = try XCTUnwrap(fileSystem.fileData(atPath: paths.stateFile.path))
        let decoded = try JSONDecoder().decode(BindingState.self, from: data)
        XCTAssertEqual(decoded.projects["codex"]?.ideBindings.count, 1)
        XCTAssertEqual(decoded.projects["codex"]?.ideBindings.first?.windowId, 12)
    }

    func testActivationReissuesWorkspaceSwitchAndFailsAfterDeadline() {
        let fileSystem = TestFileSystem()
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        fileSystem.addFile(at: paths.configFile.path, content: validConfigTOML())
        let configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
        let stateStore = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        let focusResponses = Array(repeating: Result<CommandResult, AeroSpaceCommandError>.success(
            CommandResult(exitCode: 0, stdout: "pw-other\n", stderr: "")
        ), count: 120)

        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-other\n", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json"]): [
                .success(CommandResult(exitCode: 0, stdout: "[]", stderr: ""))
            ],
            signature(["focus", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["move-node-to-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "--help"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["summon-workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-workspaces", "--focused", "--format", "%{workspace}"]): focusResponses
        ]

        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let resolver = FixedBinaryResolver(result: .success(URL(fileURLWithPath: aerospacePath)))
        let appDiscovery = TestAppDiscovery(bundleIds: [TestConstants.vscodeBundleId: TestConstants.vscodeAppURL])
        let ideResolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)
        let screenMetrics = TestScreenMetricsProvider(widthsByIndex: [1: 2000])
        let clock = TestClock()
        let sleeper = AdvancingSleeper(clock: clock)
        let logger = TestLogger()
        let openRunner = RecordingCommandRunner()

        let service = ActivationService(
            configLoader: configLoader,
            aeroSpaceBinaryResolver: resolver,
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 2,
            commandRunner: openRunner,
            ideAppResolver: ideResolver,
            appDiscovery: appDiscovery,
            workspaceGenerator: VSCodeWorkspaceGenerator(paths: paths, fileSystem: fileSystem),
            stateStore: stateStore,
            screenMetricsProvider: screenMetrics,
            logger: logger,
            sleeper: sleeper,
            clock: clock,
            focusTiming: .fixed,
            windowDetectionTiming: .standard
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .success:
            XCTFail("Expected focus failure")
        case .failure(let error):
            switch error {
            case .workspaceNotFocused(let expected, let observed, let elapsedMs):
                XCTAssertEqual(expected, "pw-codex")
                XCTAssertEqual(observed, "pw-other")
                XCTAssertGreaterThanOrEqual(elapsedMs, 5000)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }

        let workspaceCalls = runner.invocations.filter { $0.arguments == ["summon-workspace", "pw-codex"] }
        XCTAssertEqual(workspaceCalls.count, 2)
    }

    private func signature(_ arguments: [String]) -> AeroSpaceCommandSignature {
        AeroSpaceCommandSignature(path: aerospacePath, arguments: arguments)
    }
}

private struct FixedBinaryResolver: AeroSpaceBinaryResolving {
    let result: Result<URL, AeroSpaceBinaryResolutionError>

    func resolve() -> Result<URL, AeroSpaceBinaryResolutionError> {
        result
    }
}
