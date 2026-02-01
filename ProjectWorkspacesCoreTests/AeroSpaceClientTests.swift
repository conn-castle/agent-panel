import XCTest

@testable import ProjectWorkspacesCore

final class AeroSpaceClientTests: XCTestCase {
    func testResolverUsesCandidatePathWhenExecutableExists() {
        let fileSystem = ExecutableOnlyFileSystem(executableFiles: ["/opt/homebrew/bin/aerospace"])
        let commandRunner = ClientTestCommandRunner(results: [:])
        let resolver = DefaultAeroSpaceBinaryResolver(fileSystem: fileSystem, commandRunner: commandRunner)

        let result = resolver.resolve()

        switch result {
        case .failure(let error):
            XCTFail("Expected resolver success, got error: \(error)")
        case .success(let url):
            XCTAssertEqual(url.path, "/opt/homebrew/bin/aerospace")
        }
        XCTAssertTrue(commandRunner.invocations.isEmpty)
    }

    func testResolverUsesWhichWhenCandidatesMissing() {
        let resolvedPath = "/custom/bin/aerospace"
        let fileSystem = ExecutableOnlyFileSystem(executableFiles: ["/usr/bin/which", resolvedPath])
        let commandRunner = ClientTestCommandRunner(results: [
            ClientCommandSignature(path: "/usr/bin/which", arguments: ["aerospace"]): [
                CommandResult(exitCode: 0, stdout: "\(resolvedPath)\n", stderr: "")
            ]
        ])
        let resolver = DefaultAeroSpaceBinaryResolver(fileSystem: fileSystem, commandRunner: commandRunner)

        let result = resolver.resolve()

        switch result {
        case .failure(let error):
            XCTFail("Expected resolver success, got error: \(error)")
        case .success(let url):
            XCTAssertEqual(url.path, resolvedPath)
        }
        XCTAssertEqual(commandRunner.invocations.count, 1)
        XCTAssertEqual(commandRunner.invocations.first?.environment?["PATH"], "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
    }

    func testClientBuildsExpectedCommands() {
        let runner = RecordingAeroSpaceCommandRunner(
            result: .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
        )
        let format = "%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title} %{window-layout} %{monitor-appkit-nsscreen-screens-id}"
        let client = AeroSpaceClient(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/aerospace"),
            commandRunner: runner,
            timeoutSeconds: 2
        )

        _ = client.switchWorkspace("pw-codex")
        _ = client.summonWorkspace("pw-codex")
        _ = client.focusedWorkspace()
        _ = client.listWorkspaces()
        _ = client.listWindows(workspace: "pw-codex")
        _ = client.listWindowsAll()
        _ = client.listWindowsOnFocusedMonitor(appBundleId: "com.example.app")
        _ = client.focusWindow(windowId: 42)
        _ = client.moveWindow(windowId: 42, to: "pw-codex")
        _ = client.flattenWorkspaceTree(workspace: "pw-codex")
        _ = client.balanceSizes(workspace: "pw-codex")
        _ = client.setLayout(windowId: 42, layout: .hTiles)
        _ = client.setFloatingLayout(windowId: 42)
        _ = client.resizeWidth(windowId: 42, width: 900)
        _ = client.closeWindow(windowId: 42)

        let expected = [
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["workspace", "pw-codex"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["summon-workspace", "pw-codex"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["list-workspaces", "--focused", "--format", "%{workspace}"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["list-workspaces", "--all"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["list-windows", "--workspace", "pw-codex", "--json", "--format", format],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["list-windows", "--all", "--json", "--format", format],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["list-windows", "--monitor", "focused", "--app-bundle-id", "com.example.app", "--json", "--format", format],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["focus", "--window-id", "42"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["move-node-to-workspace", "--window-id", "42", "pw-codex"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["flatten-workspace-tree", "--workspace", "pw-codex"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["balance-sizes", "--workspace", "pw-codex"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["layout", "--window-id", "42", "h_tiles"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["layout", "--window-id", "42", "floating"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["resize", "--window-id", "42", "width", "900"],
                timeoutSeconds: 2
            ),
            AeroSpaceClientCommandCall(
                path: "/opt/homebrew/bin/aerospace",
                arguments: ["close", "--window-id", "42"],
                timeoutSeconds: 2
            )
        ]

        XCTAssertEqual(runner.calls, expected)
    }

    func testClientPropagatesTimeoutError() {
        let result = CommandResult(exitCode: 15, stdout: "", stderr: "")
        let error = AeroSpaceCommandError.timedOut(
            command: "aerospace workspace pw-codex",
            timeoutSeconds: 1,
            result: result
        )
        let runner = RecordingAeroSpaceCommandRunner(result: .failure(error))
        let client = AeroSpaceClient(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/aerospace"),
            commandRunner: runner,
            timeoutSeconds: 1
        )

        let outcome = client.switchWorkspace("pw-codex")

        switch outcome {
        case .success:
            XCTFail("Expected failure result")
        case .failure(let received):
            XCTAssertEqual(received, error)
        }
    }

    func testClientInitializerResolvesOnce() throws {
        let resolver = RecordingBinaryResolver(
            result: .success(URL(fileURLWithPath: "/opt/homebrew/bin/aerospace"))
        )
        let runner = RecordingAeroSpaceCommandRunner(
            result: .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
        )

        _ = try AeroSpaceClient(resolver: resolver, commandRunner: runner, timeoutSeconds: 2)

        XCTAssertEqual(resolver.callCount, 1)
    }
}

private struct ClientCommandSignature: Hashable {
    let path: String
    let arguments: [String]
}

private struct ClientCommandInvocation: Equatable {
    let path: String
    let arguments: [String]
    let environment: [String: String]?
}

private final class ClientTestCommandRunner: CommandRunning {
    private(set) var invocations: [ClientCommandInvocation] = []
    private var results: [ClientCommandSignature: [CommandResult]]

    init(results: [ClientCommandSignature: [CommandResult]]) {
        self.results = results
    }

    func run(
        command: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> CommandResult {
        invocations.append(
            ClientCommandInvocation(
                path: command.path,
                arguments: arguments,
                environment: environment
            )
        )
        let signature = ClientCommandSignature(path: command.path, arguments: arguments)
        guard var queue = results[signature], !queue.isEmpty else {
            throw NSError(domain: "ClientTestCommandRunner", code: 1)
        }
        let result = queue.removeFirst()
        results[signature] = queue
        return result
    }
}

private final class ExecutableOnlyFileSystem: FileSystem {
    private let executableFiles: Set<String>

    init(executableFiles: Set<String> = []) {
        self.executableFiles = executableFiles
    }

    func fileExists(at url: URL) -> Bool {
        false
    }

    func directoryExists(at url: URL) -> Bool {
        false
    }

    func isExecutableFile(at url: URL) -> Bool {
        executableFiles.contains(url.path)
    }

    func readFile(at url: URL) throws -> Data {
        throw NSError(domain: "ExecutableOnlyFileSystem", code: 1)
    }

    func createDirectory(at url: URL) throws {
        throw NSError(domain: "ExecutableOnlyFileSystem", code: 2)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        throw NSError(domain: "ExecutableOnlyFileSystem", code: 3)
    }

    func removeItem(at url: URL) throws {
        throw NSError(domain: "ExecutableOnlyFileSystem", code: 4)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        throw NSError(domain: "ExecutableOnlyFileSystem", code: 5)
    }

    func appendFile(at url: URL, data: Data) throws {
        throw NSError(domain: "ExecutableOnlyFileSystem", code: 6)
    }

    func writeFile(at url: URL, data: Data) throws {
        throw NSError(domain: "ExecutableOnlyFileSystem", code: 7)
    }

    func syncFile(at url: URL) throws {
        throw NSError(domain: "ExecutableOnlyFileSystem", code: 8)
    }

    @discardableResult
    func replaceItemAt(_ originalURL: URL, withItemAt newItemURL: URL) throws -> URL? {
        throw NSError(domain: "ExecutableOnlyFileSystem", code: 9)
    }
}

private struct AeroSpaceClientCommandCall: Equatable {
    let path: String
    let arguments: [String]
    let timeoutSeconds: TimeInterval
}

private final class RecordingAeroSpaceCommandRunner: AeroSpaceCommandRunning {
    private(set) var calls: [AeroSpaceClientCommandCall] = []
    private let result: Result<CommandResult, AeroSpaceCommandError>

    init(result: Result<CommandResult, AeroSpaceCommandError>) {
        self.result = result
    }

    func run(
        executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        calls.append(
            AeroSpaceClientCommandCall(
                path: executable.path,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds
            )
        )
        return result
    }
}

private final class RecordingBinaryResolver: AeroSpaceBinaryResolving {
    private(set) var callCount: Int = 0
    private let result: Result<URL, AeroSpaceBinaryResolutionError>

    init(result: Result<URL, AeroSpaceBinaryResolutionError>) {
        self.result = result
    }

    func resolve() -> Result<URL, AeroSpaceBinaryResolutionError> {
        callCount += 1
        return result
    }
}
