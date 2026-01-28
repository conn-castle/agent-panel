import XCTest

@testable import ProjectWorkspacesCore

final class ChromeLauncherTests: XCTestCase {
    private let aeroSpacePath = TestConstants.aerospacePath
    private let chromeAppURL = TestConstants.chromeAppURL
    private let listWindowsFormat = TestConstants.listWindowsFormat

    func testExistingChromeReturnsExistingOutcome() {
        let token = ProjectWindowToken(projectId: "codex")
        let chromeWindow = chromeWindowPayload(id: 10, workspace: "pw-other", windowTitle: "PW:codex - Chrome")
        let responses: AeroSpaceCommandResponses = [
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "10", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let commandRunner = RecordingCommandRunner()
        let sleeper = TestSleeper()
        let launcher = makeLauncher(
            runner: runner,
            commandRunner: commandRunner,
            sleeper: sleeper
        )

        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            windowToken: token,
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome, .existing(windowId: 10))
        }

        XCTAssertTrue(commandRunner.invocations.isEmpty)
    }

    func testExistingMultipleChromeReturnsAmbiguous() {
        let token = ProjectWindowToken(projectId: "codex")
        let chromeWindowOne = chromeWindowPayload(id: 42, workspace: "pw-codex", windowTitle: "PW:codex - A")
        let chromeWindowTwo = chromeWindowPayload(id: 7, workspace: "pw-other", windowTitle: "PW:codex - B")
        let responses: AeroSpaceCommandResponses = [
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindowOne, chromeWindowTwo]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let commandRunner = RecordingCommandRunner()
        let sleeper = TestSleeper()
        let launcher = makeLauncher(
            runner: runner,
            commandRunner: commandRunner,
            sleeper: sleeper
        )

        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            windowToken: token,
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .success:
            XCTFail("Expected ambiguous failure.")
        case .failure(let error):
            XCTAssertEqual(error, .chromeWindowAmbiguous(token: "PW:codex", windowIds: [7, 42]))
        }
    }

    func testLaunchArgumentsOrderedAndDeduped() {
        let token = ProjectWindowToken(projectId: "codex")
        let responses: AeroSpaceCommandResponses = [
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    chromeWindowPayload(id: 55, workspace: "pw-codex", windowTitle: "PW:codex - Chrome")
                ]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-n",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
            "--window-name=PW:codex",
            "https://one.example",
            "https://two.example",
            "https://three.example"
        ]
        let commandRunner = RecordingCommandRunner(results: [
            OpenCommandSignature(path: "/usr/bin/open", arguments: openArgs): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])
        let sleeper = TestSleeper()
        let launcher = makeLauncher(
            runner: runner,
            commandRunner: commandRunner,
            sleeper: sleeper
        )

        let project = makeProject(
            repoUrl: "https://two.example",
            chromeUrls: ["https://three.example", "https://one.example"]
        )

        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            windowToken: token,
            globalChromeUrls: ["https://one.example", "https://two.example"],
            project: project,
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome, .created(windowId: 55))
        }

        XCTAssertEqual(commandRunner.invocations.count, 1)
        XCTAssertEqual(commandRunner.invocations[0].arguments, openArgs)
    }

    func testLaunchUsesAboutBlankWhenUrlsEmpty() {
        let token = ProjectWindowToken(projectId: "codex")
        let responses: AeroSpaceCommandResponses = [
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    chromeWindowPayload(id: 88, workspace: "pw-codex", windowTitle: "PW:codex - Chrome")
                ]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-n",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
            "--window-name=PW:codex",
            "about:blank"
        ]
        let commandRunner = RecordingCommandRunner(results: [
            OpenCommandSignature(path: "/usr/bin/open", arguments: openArgs): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])
        let sleeper = TestSleeper()
        let launcher = makeLauncher(
            runner: runner,
            commandRunner: commandRunner,
            sleeper: sleeper
        )

        let project = makeProject(repoUrl: nil, chromeUrls: [])
        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            windowToken: token,
            globalChromeUrls: [],
            project: project,
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome, .created(windowId: 88))
        }

        XCTAssertEqual(commandRunner.invocations.count, 1)
        XCTAssertEqual(commandRunner.invocations[0].arguments, openArgs)
    }

    func testLaunchIncludesProfileDirectoryWhenConfigured() {
        let token = ProjectWindowToken(projectId: "codex")
        let responses: AeroSpaceCommandResponses = [
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    chromeWindowPayload(id: 66, workspace: "pw-codex", windowTitle: "PW:codex - Chrome")
                ]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-n",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
            "--window-name=PW:codex",
            "--profile-directory=Profile 2",
            "about:blank"
        ]
        let commandRunner = RecordingCommandRunner(results: [
            OpenCommandSignature(path: "/usr/bin/open", arguments: openArgs): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])
        let sleeper = TestSleeper()
        let launcher = makeLauncher(
            runner: runner,
            commandRunner: commandRunner,
            sleeper: sleeper
        )

        let project = makeProject(chromeProfileDirectory: "Profile 2")
        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            windowToken: token,
            globalChromeUrls: [],
            project: project,
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome, .created(windowId: 66))
        }

        XCTAssertEqual(commandRunner.invocations.count, 1)
        XCTAssertEqual(commandRunner.invocations[0].arguments, openArgs)
    }

    func testPollingMultipleNewWindowsReturnsAmbiguousSorted() {
        let token = ProjectWindowToken(projectId: "codex")
        let newWindows = [
            chromeWindowPayload(id: 12, workspace: "pw-codex", windowTitle: "PW:codex - A"),
            chromeWindowPayload(id: 3, workspace: "pw-codex", windowTitle: "PW:codex - B")
        ]
        let responses: AeroSpaceCommandResponses = [
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON(newWindows), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-n",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
            "--window-name=PW:codex",
            "about:blank"
        ]
        let commandRunner = RecordingCommandRunner(results: [
            OpenCommandSignature(path: "/usr/bin/open", arguments: openArgs): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])
        let sleeper = TestSleeper()
        // Shorten polling to keep the test fast.
        let launcher = makeLauncher(
            runner: runner,
            commandRunner: commandRunner,
            sleeper: sleeper,
            pollTimeoutMs: 200
        )

        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            windowToken: token,
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .success:
            XCTFail("Expected ambiguous failure.")
        case .failure(let error):
            XCTAssertEqual(error, .chromeWindowAmbiguous(token: "PW:codex", windowIds: [3, 12]))
        }
    }

    func testPollingTimeoutReturnsNotDetected() {
        let token = ProjectWindowToken(projectId: "codex")
        let responses: AeroSpaceCommandResponses = [
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-n",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
            "--window-name=PW:codex",
            "about:blank"
        ]
        let commandRunner = RecordingCommandRunner(results: [
            OpenCommandSignature(path: "/usr/bin/open", arguments: openArgs): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])
        let sleeper = TestSleeper()
        let launcher = makeLauncher(
            runner: runner,
            commandRunner: commandRunner,
            sleeper: sleeper,
            pollIntervalMs: 10,
            pollTimeoutMs: 10
        )

        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            windowToken: token,
            globalChromeUrls: [],
            project: makeProject(repoUrl: nil, chromeUrls: []),
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .success:
            XCTFail("Expected failure when no Chrome window is detected.")
        case .failure(let error):
            XCTAssertEqual(error, .chromeWindowNotDetected(token: "PW:codex"))
        }

        XCTAssertEqual(commandRunner.invocations.count, 1)
    }

    func testRefocusAfterCreationWhenProvided() {
        let token = ProjectWindowToken(projectId: "codex")
        let responses: AeroSpaceCommandResponses = [
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([
                    chromeWindowPayload(id: 99, workspace: "pw-codex", windowTitle: "PW:codex - Chrome")
                ]), stderr: ""))
            ],
            signature(["focus", "--window-id", "321"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-n",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
            "--window-name=PW:codex",
            "about:blank"
        ]
        let commandRunner = RecordingCommandRunner(results: [
            OpenCommandSignature(path: "/usr/bin/open", arguments: openArgs): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])
        let sleeper = TestSleeper()
        let launcher = makeLauncher(
            runner: runner,
            commandRunner: commandRunner,
            sleeper: sleeper,
            refocusDelayMs: 100
        )

        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            windowToken: token,
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: 321
        )

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome, .created(windowId: 99))
        }

        XCTAssertEqual(sleeper.sleepCalls, [0.1])
        XCTAssertEqual(runner.calls.last?.arguments, ["focus", "--window-id", "321"])
    }

    private func makeLauncher(
        runner: SequencedAeroSpaceCommandRunner,
        commandRunner: RecordingCommandRunner,
        sleeper: TestSleeper,
        pollIntervalMs: Int = ChromeLauncher.defaultPollIntervalMs,
        pollTimeoutMs: Int = ChromeLauncher.defaultPollTimeoutMs,
        refocusDelayMs: Int = ChromeLauncher.defaultRefocusDelayMs
    ) -> ChromeLauncher {
        let client = AeroSpaceClient(
            executableURL: URL(fileURLWithPath: aeroSpacePath),
            commandRunner: runner,
            timeoutSeconds: 1
        )
        return ChromeLauncher(
            aeroSpaceClient: client,
            commandRunner: commandRunner,
            appDiscovery: TestAppDiscovery(bundleIds: [ChromeLauncher.chromeBundleId: chromeAppURL]),
            sleeper: sleeper,
            pollIntervalMs: pollIntervalMs,
            pollTimeoutMs: pollTimeoutMs,
            refocusDelayMs: refocusDelayMs
        )
    }

    private func makeProject(
        repoUrl: String? = nil,
        chromeUrls: [String] = [],
        chromeProfileDirectory: String? = nil
    ) -> ProjectConfig {
        ProjectConfig(
            id: "codex",
            name: "Codex",
            path: "/Users/tester/src/codex",
            colorHex: "#7C3AED",
            repoUrl: repoUrl,
            ide: .vscode,
            ideUseAgentLayerLauncher: true,
            ideCommand: "",
            chromeUrls: chromeUrls,
            chromeProfileDirectory: chromeProfileDirectory
        )
    }

    private func signature(_ arguments: [String]) -> AeroSpaceCommandSignature {
        AeroSpaceCommandSignature(path: aeroSpacePath, arguments: arguments)
    }
}

final class ProjectWindowTokenTests: XCTestCase {
    func testMatchesAcceptsTrailingDelimiterOrEnd() {
        let token = ProjectWindowToken(projectId: "code")

        XCTAssertTrue(token.matches(windowTitle: "PW:code - Chrome"))
        XCTAssertTrue(token.matches(windowTitle: "Chrome PW:code"))
    }

    func testMatchesRejectsPrefixOfLongerProjectId() {
        let token = ProjectWindowToken(projectId: "code")

        XCTAssertFalse(token.matches(windowTitle: "PW:codex - Chrome"))
    }
}
