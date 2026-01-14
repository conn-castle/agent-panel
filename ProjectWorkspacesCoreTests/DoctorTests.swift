import XCTest

@testable import ProjectWorkspacesCore

final class DoctorTests: XCTestCase {
    func testDoctorFailsWhenAccessibilityMissing() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ], executableFiles: [
            aerospacePath
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: [
                "com.google.Chrome": "/Applications/Google Chrome.app",
                "com.microsoft.VSCode": "/Applications/Visual Studio Code.app"
            ],
            nameMap: [:],
            bundleIdForPath: [
                "/Applications/Google Chrome.app": "com.google.Chrome",
                "/Applications/Visual Studio Code.app": "com.microsoft.VSCode"
            ]
        )

        let commandRunner = makePassingCommandRunner(
            executablePath: aerospacePath,
            previousWorkspace: "pw-codex"
        )

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: false),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Accessibility permission missing" })
    }

    func testDoctorFailsWhenChromeMissing() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ], executableFiles: [
            aerospacePath
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: [
                "com.microsoft.VSCode": "/Applications/Visual Studio Code.app"
            ],
            nameMap: [:],
            bundleIdForPath: [
                "/Applications/Visual Studio Code.app": "com.microsoft.VSCode"
            ]
        )

        let commandRunner = makePassingCommandRunner(
            executablePath: aerospacePath,
            previousWorkspace: "pw-codex"
        )

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Google Chrome not found" })
    }

    func testDoctorFailsWhenHotkeyUnavailable() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ], executableFiles: [
            aerospacePath
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: [
                "com.google.Chrome": "/Applications/Google Chrome.app",
                "com.microsoft.VSCode": "/Applications/Visual Studio Code.app"
            ],
            nameMap: [:],
            bundleIdForPath: [
                "/Applications/Google Chrome.app": "com.google.Chrome",
                "/Applications/Visual Studio Code.app": "com.microsoft.VSCode"
            ]
        )

        let commandRunner = makePassingCommandRunner(
            executablePath: aerospacePath,
            previousWorkspace: "pw-codex"
        )

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: false),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Cmd+Shift+Space hotkey cannot be registered" })
    }

    func testDoctorSkipsHotkeyCheckWhenAgentRunning() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ], executableFiles: [
            aerospacePath
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: [
                "com.google.Chrome": "/Applications/Google Chrome.app",
                "com.microsoft.VSCode": "/Applications/Visual Studio Code.app"
            ],
            nameMap: [:],
            bundleIdForPath: [
                "/Applications/Google Chrome.app": "com.google.Chrome",
                "/Applications/Visual Studio Code.app": "com.microsoft.VSCode"
            ]
        )

        let commandRunner = makePassingCommandRunner(
            executablePath: aerospacePath,
            previousWorkspace: "pw-codex"
        )

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: false),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: true),
            commandRunner: commandRunner
        )

        let report = doctor.run()

        XCTAssertFalse(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Cmd+Shift+Space hotkey check skipped" })
    }

    func testDoctorWarnsOnSwitcherHotkey() {
        let config = makeValidConfig(includeSwitcherHotkey: true)
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ], executableFiles: [
            aerospacePath
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: [
                "com.google.Chrome": "/Applications/Google Chrome.app",
                "com.microsoft.VSCode": "/Applications/Visual Studio Code.app"
            ],
            nameMap: [:],
            bundleIdForPath: [
                "/Applications/Google Chrome.app": "com.google.Chrome",
                "/Applications/Visual Studio Code.app": "com.microsoft.VSCode"
            ]
        )

        let commandRunner = makePassingCommandRunner(
            executablePath: aerospacePath,
            previousWorkspace: "pw-codex"
        )

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains { $0.title == "global.switcherHotkey is ignored" })
    }

    func testDoctorFailsWhenConfigMissing() {
        let aerospacePath = "/opt/homebrew/bin/aerospace"
        let fileSystem = TestFileSystem(files: [:], directories: [], executableFiles: [
            aerospacePath
        ])
        let commandRunner = makePassingCommandRunner(
            executablePath: aerospacePath,
            previousWorkspace: "pw-inbox"
        )
        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: TestAppDiscovery(
                bundleIdMap: ["com.google.Chrome": "/Applications/Google Chrome.app"],
                nameMap: [:],
                bundleIdForPath: ["/Applications/Google Chrome.app": "com.google.Chrome"]
            ),
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Config file missing" })
    }

    func testDoctorFailsWhenAerospaceCliMissing() {
        let config = makeValidConfig()
        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ], executableFiles: [
            "/usr/bin/which"
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: [
                "com.google.Chrome": "/Applications/Google Chrome.app",
                "com.microsoft.VSCode": "/Applications/Visual Studio Code.app"
            ],
            nameMap: [:],
            bundleIdForPath: [
                "/Applications/Google Chrome.app": "com.google.Chrome",
                "/Applications/Visual Studio Code.app": "com.microsoft.VSCode"
            ]
        )

        let commandRunner = TestCommandRunner(results: [
            CommandSignature(path: "/usr/bin/which", arguments: ["aerospace"]): [
                CommandResult(exitCode: 1, stdout: "", stderr: "not found")
            ]
        ])

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "AeroSpace CLI not found" })
    }

    func testDoctorWarnsWhenAerospaceRestoreFails() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"
        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ], executableFiles: [
            aerospacePath
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: [
                "com.google.Chrome": "/Applications/Google Chrome.app",
                "com.microsoft.VSCode": "/Applications/Visual Studio Code.app"
            ],
            nameMap: [:],
            bundleIdForPath: [
                "/Applications/Google Chrome.app": "com.google.Chrome",
                "/Applications/Visual Studio Code.app": "com.microsoft.VSCode"
            ]
        )

        let commandRunner = TestCommandRunner(results: [
            CommandSignature(path: aerospacePath, arguments: ["list-workspaces", "--focused"]): [
                CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""),
                CommandResult(exitCode: 0, stdout: "pw-inbox\n", stderr: "")
            ],
            CommandSignature(path: aerospacePath, arguments: ["workspace", "pw-inbox"]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ],
            CommandSignature(path: aerospacePath, arguments: ["workspace", "pw-codex"]): [
                CommandResult(exitCode: 1, stdout: "", stderr: "restore failed")
            ]
        ])

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner
        )

        let report = doctor.run()

        XCTAssertFalse(report.hasFailures)
        XCTAssertTrue(report.findings.contains {
            $0.title == "Doctor changed your AeroSpace workspace to pw-inbox but could not restore the previous workspace."
        })
    }

    func testDoctorFailsWhenFocusedWorkspaceIsNotInboxAfterSwitch() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"
        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ], executableFiles: [
            aerospacePath
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: [
                "com.google.Chrome": "/Applications/Google Chrome.app",
                "com.microsoft.VSCode": "/Applications/Visual Studio Code.app"
            ],
            nameMap: [:],
            bundleIdForPath: [
                "/Applications/Google Chrome.app": "com.google.Chrome",
                "/Applications/Visual Studio Code.app": "com.microsoft.VSCode"
            ]
        )

        let commandRunner = TestCommandRunner(results: [
            CommandSignature(path: aerospacePath, arguments: ["list-workspaces", "--focused"]): [
                CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""),
                CommandResult(exitCode: 0, stdout: "pw-other\n", stderr: "")
            ],
            CommandSignature(path: aerospacePath, arguments: ["workspace", "pw-inbox"]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ])

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "AeroSpace did not switch to pw-inbox" })
    }
}

private final class TestFileSystem: FileSystem {
    private var files: [String: Data]
    private var directories: Set<String>
    private var executableFiles: Set<String>

    init(files: [String: Data], directories: Set<String>, executableFiles: Set<String> = []) {
        self.files = files
        self.directories = directories
        self.executableFiles = executableFiles
    }

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        executableFiles.contains(url.path)
    }

    func readFile(at url: URL) throws -> Data {
        if let data = files[url.path] {
            return data
        }
        throw NSError(domain: "TestFileSystem", code: 1)
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = files[url.path] else {
            throw NSError(domain: "TestFileSystem", code: 2)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        if files.removeValue(forKey: url.path) != nil {
            return
        }
        if directories.remove(url.path) != nil {
            return
        }
        throw NSError(domain: "TestFileSystem", code: 3)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        guard let data = files.removeValue(forKey: sourceURL.path) else {
            throw NSError(domain: "TestFileSystem", code: 4)
        }
        if files[destinationURL.path] != nil {
            throw NSError(domain: "TestFileSystem", code: 5)
        }
        files[destinationURL.path] = data
    }

    func appendFile(at url: URL, data: Data) throws {
        if var existing = files[url.path] {
            existing.append(data)
            files[url.path] = existing
        } else {
            files[url.path] = data
        }
    }
}

private struct CommandSignature: Hashable {
    let path: String
    let arguments: [String]
}

private final class TestCommandRunner: CommandRunning {
    private var results: [CommandSignature: [CommandResult]]

    init(results: [CommandSignature: [CommandResult]]) {
        self.results = results
    }

    /// Runs a stubbed command and returns the next queued result.
    /// - Parameters:
    ///   - command: Executable URL to run.
    ///   - arguments: Arguments passed to the command.
    ///   - environment: Environment variables (unused in this stub).
    /// - Returns: The queued command result.
    /// - Throws: Error when no stubbed result exists for the command.
    func run(command: URL, arguments: [String], environment: [String: String]?) throws -> CommandResult {
        let _ = environment
        let signature = CommandSignature(path: command.path, arguments: arguments)
        guard var queue = results[signature], !queue.isEmpty else {
            throw NSError(domain: "TestCommandRunner", code: 1)
        }
        let result = queue.removeFirst()
        results[signature] = queue
        return result
    }
}

/// Builds a valid TOML config fixture.
/// - Parameter includeSwitcherHotkey: Whether to include the ignored switcherHotkey field.
/// - Returns: TOML config string.
private func makeValidConfig(includeSwitcherHotkey: Bool = false) -> String {
    let switcherLine = includeSwitcherHotkey ? "switcherHotkey = \"Ctrl+Space\"" : ""
    return """
    [global]
    defaultIde = "vscode"
    globalChromeUrls = []
    \(switcherLine)
    [display]
    ultrawideMinWidthPx = 5000

    [[project]]
    id = "codex"
    name = "Codex"
    path = "/Users/tester/src/codex"
    colorHex = "#7C3AED"
    """
}

/// Builds a passing command runner fixture for AeroSpace connectivity checks.
/// - Parameters:
///   - executablePath: Resolved AeroSpace CLI path.
///   - previousWorkspace: Workspace name to restore after the check.
/// - Returns: A command runner stub with success results.
private func makePassingCommandRunner(executablePath: String, previousWorkspace: String) -> TestCommandRunner {
    var results: [CommandSignature: [CommandResult]] = [:]
    let focusedKey = CommandSignature(path: executablePath, arguments: ["list-workspaces", "--focused"])
    results[focusedKey] = [
        CommandResult(exitCode: 0, stdout: "\(previousWorkspace)\n", stderr: ""),
        CommandResult(exitCode: 0, stdout: "pw-inbox\n", stderr: ""),
        CommandResult(exitCode: 0, stdout: "\(previousWorkspace)\n", stderr: "")
    ]

    let switchInboxKey = CommandSignature(path: executablePath, arguments: ["workspace", "pw-inbox"])
    results[switchInboxKey] = [CommandResult(exitCode: 0, stdout: "", stderr: "")]

    if previousWorkspace != "pw-inbox" {
        let restoreKey = CommandSignature(path: executablePath, arguments: ["workspace", previousWorkspace])
        results[restoreKey] = [CommandResult(exitCode: 0, stdout: "", stderr: "")]
    }

    return TestCommandRunner(results: results)
}

private struct TestAppDiscovery: AppDiscovering {
    let bundleIdMap: [String: String]
    let nameMap: [String: String]
    let bundleIdForPath: [String: String]

    func applicationURL(bundleIdentifier: String) -> URL? {
        guard let path = bundleIdMap[bundleIdentifier] else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func applicationURL(named appName: String) -> URL? {
        guard let path = nameMap[appName] else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func bundleIdentifier(forApplicationAt url: URL) -> String? {
        bundleIdForPath[url.path]
    }
}

private struct TestHotkeyChecker: HotkeyChecking {
    let isAvailable: Bool

    func checkCommandShiftSpace() -> HotkeyCheckResult {
        HotkeyCheckResult(isAvailable: isAvailable, errorCode: isAvailable ? nil : -9876)
    }
}

private struct TestAccessibilityChecker: AccessibilityChecking {
    let isTrusted: Bool

    func isProcessTrusted() -> Bool {
        isTrusted
    }
}

private struct TestRunningApplicationChecker: RunningApplicationChecking {
    let isRunning: Bool

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        let _ = bundleIdentifier
        return isRunning
    }
}
