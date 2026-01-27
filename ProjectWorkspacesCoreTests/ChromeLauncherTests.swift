import XCTest

@testable import ProjectWorkspacesCore

final class ChromeLauncherTests: XCTestCase {
    private let aeroSpacePath = TestConstants.aerospacePath
    private let chromeAppURL = TestConstants.chromeAppURL
    private let listWindowsFormat = TestConstants.listWindowsFormat

    func testWorkspaceNotFocusedReturnsError() {
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-other\n", stderr: ""))
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
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .success:
            XCTFail("Expected failure when workspace is not focused.")
        case .failure(let error):
            XCTAssertEqual(
                error,
                .workspaceNotFocused(expected: "pw-codex", actual: "pw-other")
            )
        }

        XCTAssertTrue(commandRunner.invocations.isEmpty)
    }

    func testExistingChromeReturnsExistingOutcome() {
        let chromeWindow = chromeWindowPayload(id: 10, workspace: "pw-codex")
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
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

    func testExistingMultipleChromeReturnsSortedOutcome() {
        let chromeWindowOne = chromeWindowPayload(id: 42, workspace: "pw-codex")
        let chromeWindowTwo = chromeWindowPayload(id: 7, workspace: "pw-codex")
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
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
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome, .existingMultiple(windowIds: [7, 42]))
        }
    }

    func testLaunchArgumentsOrderedAndDeduped() {
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindowPayload(id: 55, workspace: "pw-codex")]), stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-g",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
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
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindowPayload(id: 88, workspace: "pw-codex")]), stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-g",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
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

    func testPollingMultipleNewWindowsReturnsAmbiguousSorted() {
        let newWindows = [
            chromeWindowPayload(id: 12, workspace: "pw-codex"),
            chromeWindowPayload(id: 3, workspace: "pw-codex")
        ]
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON(newWindows), stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-g",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
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
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .success:
            XCTFail("Expected ambiguous failure.")
        case .failure(let error):
            XCTAssertEqual(error, .chromeWindowAmbiguous(newWindowIds: [3, 12]))
        }
    }

    func testNoFallbackDetectionSkipsListWindowsAll() {
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-g",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
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
            globalChromeUrls: [],
            project: makeProject(repoUrl: nil, chromeUrls: []),
            ideWindowIdToRefocus: nil,
            allowFallbackDetection: false
        )

        switch result {
        case .success:
            XCTFail("Expected failure when no Chrome window is detected.")
        case .failure(let error):
            XCTAssertEqual(error, .chromeWindowNotDetected(expectedWorkspace: "pw-codex"))
        }

        XCTAssertEqual(commandRunner.invocations.count, 1)
    }

    func testTimeoutFallbackFindsElsewhere() {
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindowPayload(id: 77, workspace: "pw-other")]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-g",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
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
            pollIntervalMs: 200,
            pollTimeoutMs: 200
        )

        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .success:
            XCTFail("Expected failure when Chrome launches elsewhere.")
        case .failure(let error):
            XCTAssertEqual(
                error,
                .chromeLaunchedElsewhere(
                    expectedWorkspace: "pw-codex",
                    actualWorkspace: "pw-other",
                    newWindowId: 77
                )
            )
        }
    }

    func testTimeoutFallbackNotDetected() {
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-g",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
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
            pollIntervalMs: 200,
            pollTimeoutMs: 200
        )

        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: nil
        )

        switch result {
        case .success:
            XCTFail("Expected failure when Chrome is not detected.")
        case .failure(let error):
            XCTAssertEqual(error, .chromeWindowNotDetected(expectedWorkspace: "pw-codex"))
        }
    }

    func testTimeoutFallbackDetectsCreatedInExpectedWorkspaceAndRefocuses() {
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindowPayload(id: 5, workspace: "pw-codex")]), stderr: ""))
            ],
            signature(["focus", "--window-id", "222"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-g",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
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
            pollIntervalMs: 200,
            pollTimeoutMs: 200,
            refocusDelayMs: 100
        )

        let result = launcher.ensureWindow(
            expectedWorkspaceName: "pw-codex",
            globalChromeUrls: [],
            project: makeProject(),
            ideWindowIdToRefocus: 222
        )

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let outcome):
            XCTAssertEqual(outcome, .created(windowId: 5))
        }

        XCTAssertEqual(sleeper.sleepCalls, [0.2, 0.1])
        XCTAssertEqual(runner.calls.last?.arguments, ["focus", "--window-id", "222"])
    }

    func testRefocusAfterCreationWhenProvided() {
        let responses: AeroSpaceCommandResponses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindowPayload(id: 99, workspace: "pw-codex")]), stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ],
            signature(["focus", "--window-id", "321"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let openArgs = [
            "-g",
            "-a",
            chromeAppURL.path,
            "--args",
            "--new-window",
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

    private func makeProject(repoUrl: String? = nil, chromeUrls: [String] = []) -> ProjectConfig {
        ProjectConfig(
            id: "codex",
            name: "Codex",
            path: "/Users/tester/src/codex",
            colorHex: "#7C3AED",
            repoUrl: repoUrl,
            ide: .vscode,
            ideUseAgentLayerLauncher: true,
            ideCommand: "",
            chromeUrls: chromeUrls
        )
    }

    private func signature(_ arguments: [String]) -> AeroSpaceCommandSignature {
        AeroSpaceCommandSignature(path: aeroSpacePath, arguments: arguments)
    }
}
