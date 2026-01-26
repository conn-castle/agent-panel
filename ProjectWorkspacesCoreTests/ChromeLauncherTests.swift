import XCTest

@testable import ProjectWorkspacesCore

final class ChromeLauncherTests: XCTestCase {
    private let aeroSpacePath = "/opt/homebrew/bin/aerospace"
    private let chromeAppURL = URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)
    private let listWindowsFormat =
        "%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title}"

    func testWorkspaceNotFocusedReturnsError() {
        let responses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-other\n", stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let commandRunner = RecordingCommandRunner(results: [:])
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
        let chromeWindow = windowPayload(id: 10, workspace: "pw-codex")
        let responses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let commandRunner = RecordingCommandRunner(results: [:])
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
        let chromeWindowOne = windowPayload(id: 42, workspace: "pw-codex")
        let chromeWindowTwo = windowPayload(id: 7, workspace: "pw-codex")
        let responses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindowOne, chromeWindowTwo]), stderr: ""))
            ]
        ]
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let commandRunner = RecordingCommandRunner(results: [:])
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
        let responses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([windowPayload(id: 55, workspace: "pw-codex")]), stderr: ""))
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
        let responses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([windowPayload(id: 88, workspace: "pw-codex")]), stderr: ""))
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
            windowPayload(id: 12, workspace: "pw-codex"),
            windowPayload(id: 3, workspace: "pw-codex")
        ]
        let responses = [
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

    func testTimeoutFallbackFindsElsewhere() {
        let responses = [
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
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([windowPayload(id: 77, workspace: "pw-other")]), stderr: ""))
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
        let responses = [
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
        let responses = [
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
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([windowPayload(id: 5, workspace: "pw-codex")]), stderr: ""))
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
        let responses = [
            signature(["list-workspaces", "--focused"]): [
                .success(CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([windowPayload(id: 99, workspace: "pw-codex")]), stderr: ""))
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

private func windowPayload(id: Int, workspace: String) -> WindowPayload {
    WindowPayload(
        windowId: id,
        workspace: workspace,
        appBundleId: ChromeLauncher.chromeBundleId,
        appName: "Google Chrome",
        windowTitle: "Chrome"
    )
}

private func windowsJSON(_ windows: [WindowPayload]) -> String {
    guard let data = try? JSONEncoder().encode(windows),
          let json = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return json
}

private struct OpenCommandSignature: Hashable {
    let path: String
    let arguments: [String]
}

private struct CommandInvocation: Equatable {
    let path: String
    let arguments: [String]
}

private final class RecordingCommandRunner: CommandRunning {
    private(set) var invocations: [CommandInvocation] = []
    private var results: [OpenCommandSignature: [CommandResult]]

    init(results: [OpenCommandSignature: [CommandResult]]) {
        self.results = results
    }

    func run(
        command: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> CommandResult {
        let _ = environment
        let _ = workingDirectory
        invocations.append(CommandInvocation(path: command.path, arguments: arguments))
        let signature = OpenCommandSignature(path: command.path, arguments: arguments)
        guard var queue = results[signature], !queue.isEmpty else {
            throw NSError(domain: "RecordingCommandRunner", code: 1)
        }
        let result = queue.removeFirst()
        results[signature] = queue
        return result
    }
}

private struct TestAppDiscovery: AppDiscovering {
    let bundleIds: [String: URL]

    init(bundleIds: [String: URL] = [:]) {
        self.bundleIds = bundleIds
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        bundleIds[bundleIdentifier]
    }

    func applicationURL(named appName: String) -> URL? {
        let _ = appName
        return nil
    }

    func bundleIdentifier(forApplicationAt url: URL) -> String? {
        for (bundleId, bundleURL) in bundleIds where bundleURL == url {
            return bundleId
        }
        return nil
    }
}

private final class TestSleeper: AeroSpaceSleeping {
    private(set) var sleepCalls: [TimeInterval] = []

    func sleep(seconds: TimeInterval) {
        sleepCalls.append(seconds)
    }
}
