import XCTest

@testable import ProjectWorkspacesCore

final class IdeLauncherTests: XCTestCase {
    func testIdeCommandTakesPriorityForVSCode() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let paths = ProjectWorkspacesPaths(homeDirectory: home)
        let project = makeProject(ide: .vscode, ideCommand: "code .")
        let workspacePath = paths.vscodeWorkspaceFile(projectId: project.id).path

        let vscodeAppURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)
        let cliPath = vscodeAppURL
            .appendingPathComponent("Contents/Resources/app/bin/code", isDirectory: false)
            .path

        let runner = IdeRecordingCommandRunner(results: [
            IdeCommandSignature(path: "/bin/zsh", arguments: ["-lc", "code ."]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ],
            IdeCommandSignature(path: cliPath, arguments: ["-r", workspacePath]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])

        let fileSystem = IdeTestFileSystem(
            executableFiles: [cliPath],
            directories: ["/Users/tester/.local/share/project-workspaces/bin"]
        )
        let appDiscovery = IdeTestAppDiscovery(bundleIds: ["com.microsoft.VSCode": vscodeAppURL])
        let logger = IdeTestLogger()
        let launcher = IdeLauncher(
            paths: paths,
            fileSystem: fileSystem,
            commandRunner: runner,
            environment: IdeTestEnvironment(values: [:]),
            appDiscovery: appDiscovery,
            permissions: IdeTestPermissions(),
            logger: logger
        )

        let result = launcher.launch(project: project, ideConfig: makeIdeConfig(vscodePath: nil, antigravityPath: nil))

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let success):
            XCTAssertTrue(success.warnings.isEmpty)
        }

        XCTAssertEqual(runner.invocations.count, 2)
        XCTAssertEqual(runner.invocations[0].path, "/bin/zsh")
        XCTAssertEqual(runner.invocations[1].path, cliPath)
        XCTAssertTrue(logger.entries.isEmpty)
    }

    func testIdeCommandFailureFallsBackToVSCodeOpen() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let paths = ProjectWorkspacesPaths(homeDirectory: home)
        let project = makeProject(ide: .vscode, ideCommand: "code .")
        let workspacePath = paths.vscodeWorkspaceFile(projectId: project.id).path

        let vscodeAppURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)
        let cliPath = vscodeAppURL
            .appendingPathComponent("Contents/Resources/app/bin/code", isDirectory: false)
            .path

        let runner = IdeRecordingCommandRunner(results: [
            IdeCommandSignature(path: "/bin/zsh", arguments: ["-lc", "code ."]): [
                CommandResult(exitCode: 1, stdout: "", stderr: "boom")
            ],
            IdeCommandSignature(path: "/usr/bin/open", arguments: ["-a", vscodeAppURL.path, workspacePath]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ],
            IdeCommandSignature(path: cliPath, arguments: ["-r", workspacePath]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])

        let fileSystem = IdeTestFileSystem(
            executableFiles: [cliPath],
            directories: ["/Users/tester/.local/share/project-workspaces/bin"]
        )
        let appDiscovery = IdeTestAppDiscovery(bundleIds: ["com.microsoft.VSCode": vscodeAppURL])
        let logger = IdeTestLogger()
        let launcher = IdeLauncher(
            paths: paths,
            fileSystem: fileSystem,
            commandRunner: runner,
            environment: IdeTestEnvironment(values: [:]),
            appDiscovery: appDiscovery,
            permissions: IdeTestPermissions(),
            logger: logger
        )

        let result = launcher.launch(project: project, ideConfig: makeIdeConfig(vscodePath: nil, antigravityPath: nil))

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let success):
            XCTAssertEqual(success.warnings.count, 1)
            if case .ideCommandFailed = success.warnings[0] {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected ideCommandFailed warning")
            }
        }

        XCTAssertEqual(runner.invocations.count, 3)
        XCTAssertEqual(runner.invocations[1].path, "/usr/bin/open")
        XCTAssertEqual(runner.invocations[2].path, cliPath)
        XCTAssertEqual(logger.entries.count, 1)
    }

    func testAntigravityIdeCommandFailureFallsBackToAntigravityOpen() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let paths = ProjectWorkspacesPaths(homeDirectory: home)
        let project = makeProject(ide: .antigravity, ideCommand: "antigravity --open")
        let antigravityAppPath = "/Applications/Antigravity.app"

        let runner = IdeRecordingCommandRunner(results: [
            IdeCommandSignature(path: "/bin/zsh", arguments: ["-lc", "antigravity --open"]): [
                CommandResult(exitCode: 1, stdout: "", stderr: "boom")
            ],
            IdeCommandSignature(path: "/usr/bin/open", arguments: ["-a", antigravityAppPath, project.path]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])

        let fileSystem = IdeTestFileSystem(
            directories: [antigravityAppPath, "/Users/tester/.local/share/project-workspaces/bin"]
        )
        let appDiscovery = IdeTestAppDiscovery()
        let logger = IdeTestLogger()
        let launcher = IdeLauncher(
            paths: paths,
            fileSystem: fileSystem,
            commandRunner: runner,
            environment: IdeTestEnvironment(values: [:]),
            appDiscovery: appDiscovery,
            permissions: IdeTestPermissions(),
            logger: logger
        )

        let ideConfig = makeIdeConfig(vscodePath: nil, antigravityPath: antigravityAppPath)
        let result = launcher.launch(project: project, ideConfig: ideConfig)

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let success):
            XCTAssertEqual(success.warnings.count, 1)
        }

        XCTAssertEqual(runner.invocations.count, 2)
        XCTAssertEqual(runner.invocations[1].arguments, ["-a", antigravityAppPath, project.path])
    }

    func testLauncherFailureFallsBackToOpen() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let paths = ProjectWorkspacesPaths(homeDirectory: home)
        let project = makeProject(ide: .vscode, ideCommand: "")
        let workspacePath = paths.vscodeWorkspaceFile(projectId: project.id).path

        let launcherPath = "/Users/tester/src/codex/.agent-layer/open-vscode.command"
        let vscodeAppURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)
        let cliPath = vscodeAppURL
            .appendingPathComponent("Contents/Resources/app/bin/code", isDirectory: false)
            .path

        let runner = IdeRecordingCommandRunner(results: [
            IdeCommandSignature(path: launcherPath, arguments: []): [
                CommandResult(exitCode: 1, stdout: "", stderr: "boom")
            ],
            IdeCommandSignature(path: "/usr/bin/open", arguments: ["-a", vscodeAppURL.path, workspacePath]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ],
            IdeCommandSignature(path: cliPath, arguments: ["-r", workspacePath]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])

        let fileSystem = IdeTestFileSystem(
            executableFiles: [launcherPath, cliPath],
            files: [launcherPath],
            directories: ["/Users/tester/.local/share/project-workspaces/bin"]
        )
        let appDiscovery = IdeTestAppDiscovery(bundleIds: ["com.microsoft.VSCode": vscodeAppURL])
        let logger = IdeTestLogger()
        let launcher = IdeLauncher(
            paths: paths,
            fileSystem: fileSystem,
            commandRunner: runner,
            environment: IdeTestEnvironment(values: [:]),
            appDiscovery: appDiscovery,
            permissions: IdeTestPermissions(),
            logger: logger
        )

        let result = launcher.launch(project: project, ideConfig: makeIdeConfig(vscodePath: nil, antigravityPath: nil))

        switch result {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let success):
            XCTAssertEqual(success.warnings.count, 1)
            if case .launcherFailed = success.warnings[0] {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected launcherFailed warning")
            }
        }

        XCTAssertEqual(runner.invocations[0].path, launcherPath)
        XCTAssertEqual(runner.invocations[1].path, "/usr/bin/open")
    }

    func testFallbackOpenFailureReturnsError() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let paths = ProjectWorkspacesPaths(homeDirectory: home)
        let project = makeProject(ide: .vscode, ideCommand: "code .")
        let workspacePath = paths.vscodeWorkspaceFile(projectId: project.id).path

        let vscodeAppURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)
        let cliPath = vscodeAppURL
            .appendingPathComponent("Contents/Resources/app/bin/code", isDirectory: false)
            .path

        let runner = IdeRecordingCommandRunner(results: [
            IdeCommandSignature(path: "/bin/zsh", arguments: ["-lc", "code ."]): [
                CommandResult(exitCode: 1, stdout: "", stderr: "boom")
            ],
            IdeCommandSignature(path: "/usr/bin/open", arguments: ["-a", vscodeAppURL.path, workspacePath]): [
                CommandResult(exitCode: 1, stdout: "", stderr: "open failed")
            ]
        ])

        let fileSystem = IdeTestFileSystem(
            executableFiles: [cliPath],
            directories: ["/Users/tester/.local/share/project-workspaces/bin"]
        )
        let appDiscovery = IdeTestAppDiscovery(bundleIds: ["com.microsoft.VSCode": vscodeAppURL])
        let logger = IdeTestLogger()
        let launcher = IdeLauncher(
            paths: paths,
            fileSystem: fileSystem,
            commandRunner: runner,
            environment: IdeTestEnvironment(values: [:]),
            appDiscovery: appDiscovery,
            permissions: IdeTestPermissions(),
            logger: logger
        )

        let result = launcher.launch(project: project, ideConfig: makeIdeConfig(vscodePath: nil, antigravityPath: nil))

        switch result {
        case .failure(let error):
            if case .openFailed = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected openFailed error")
            }
        case .success:
            XCTFail("Expected failure result")
        }
    }

    private func makeProject(ide: IdeKind, ideCommand: String) -> ProjectConfig {
        ProjectConfig(
            id: "codex",
            name: "Codex",
            path: "/Users/tester/src/codex",
            colorHex: "#7C3AED",
            repoUrl: nil,
            ide: ide,
            ideUseAgentLayerLauncher: true,
            ideCommand: ideCommand,
            chromeUrls: []
        )
    }

    private func makeIdeConfig(vscodePath: String?, antigravityPath: String?) -> IdeConfig {
        IdeConfig(
            vscode: IdeAppConfig(appPath: vscodePath, bundleId: nil),
            antigravity: IdeAppConfig(appPath: antigravityPath, bundleId: nil)
        )
    }
}

private struct IdeCommandSignature: Hashable {
    let path: String
    let arguments: [String]
}

private struct IdeCommandInvocation: Equatable {
    let path: String
    let arguments: [String]
    let environment: [String: String]?
    let workingDirectory: String?
}

private final class IdeRecordingCommandRunner: CommandRunning {
    private(set) var invocations: [IdeCommandInvocation] = []
    private var results: [IdeCommandSignature: [CommandResult]]

    init(results: [IdeCommandSignature: [CommandResult]]) {
        self.results = results
    }

    func run(
        command: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> CommandResult {
        invocations.append(
            IdeCommandInvocation(
                path: command.path,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory?.path
            )
        )
        let signature = IdeCommandSignature(path: command.path, arguments: arguments)
        guard var queue = results[signature], !queue.isEmpty else {
            throw NSError(domain: "IdeRecordingCommandRunner", code: 1)
        }
        let result = queue.removeFirst()
        results[signature] = queue
        return result
    }
}

private final class IdeTestFileSystem: FileSystem {
    private let executableFiles: Set<String>
    private var files: Set<String>
    private var directories: Set<String>
    private(set) var writtenFiles: [String: Data] = [:]

    init(
        executableFiles: Set<String> = [],
        files: Set<String> = [],
        directories: Set<String> = []
    ) {
        self.executableFiles = executableFiles
        self.files = files
        self.directories = directories
    }

    func fileExists(at url: URL) -> Bool {
        files.contains(url.path)
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        executableFiles.contains(url.path)
    }

    func readFile(at url: URL) throws -> Data {
        guard let data = writtenFiles[url.path] else {
            throw NSError(domain: "IdeTestFileSystem", code: 1)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        throw NSError(domain: "IdeTestFileSystem", code: 2)
    }

    func removeItem(at url: URL) throws {
        files.remove(url.path)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        throw NSError(domain: "IdeTestFileSystem", code: 3)
    }

    func appendFile(at url: URL, data: Data) throws {
        throw NSError(domain: "IdeTestFileSystem", code: 4)
    }

    func writeFile(at url: URL, data: Data) throws {
        writtenFiles[url.path] = data
        files.insert(url.path)
    }

    func syncFile(at url: URL) throws {
        throw NSError(domain: "IdeTestFileSystem", code: 5)
    }
}

private struct IdeTestAppDiscovery: AppDiscovering {
    let bundleIds: [String: URL]
    let names: [String: URL]
    let bundleByURL: [URL: String]

    init(bundleIds: [String: URL] = [:], names: [String: URL] = [:]) {
        self.bundleIds = bundleIds
        self.names = names
        var reverse: [URL: String] = [:]
        for (bundleId, url) in bundleIds {
            reverse[url] = bundleId
        }
        self.bundleByURL = reverse
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        bundleIds[bundleIdentifier]
    }

    func applicationURL(named appName: String) -> URL? {
        names[appName]
    }

    func bundleIdentifier(forApplicationAt url: URL) -> String? {
        bundleByURL[url]
    }
}

private struct IdeTestEnvironment: EnvironmentProviding {
    let values: [String: String]

    func value(forKey key: String) -> String? {
        values[key]
    }

    func allValues() -> [String: String] {
        values
    }
}

private struct IdeTestPermissions: FilePermissionsSetting {
    func setExecutable(at url: URL) throws {
        let _ = url
    }
}

private final class IdeTestLogger: ProjectWorkspacesLogging {
    private(set) var entries: [(event: String, level: LogLevel, message: String?, context: [String: String]?)] = []

    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
        entries.append((event: event, level: level, message: message, context: context))
        return .success(())
    }
}
