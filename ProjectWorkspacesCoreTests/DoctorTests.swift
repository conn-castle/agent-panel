import XCTest

@testable import ProjectWorkspacesCore

final class DoctorTests: XCTestCase {
    func testDoctorFailsWhenAccessibilityMissing() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
        ], executableFiles: [
            aerospacePath,
            "/opt/homebrew/bin/brew"
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Accessibility permission missing" })
    }

    func testDoctorFailsWhenChromeMissing() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Google Chrome not found" })
    }

    func testDoctorFailsWhenHotkeyUnavailable() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Cmd+Shift+Space hotkey cannot be registered" })
    }

    func testDoctorSkipsHotkeyCheckWhenAgentRunning() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
        ], executableFiles: [
            aerospacePath,
            "/opt/homebrew/bin/brew"
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertFalse(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Cmd+Shift+Space hotkey check skipped" })
    }

    func testDoctorWarnsOnSwitcherHotkey() {
        let config = makeValidConfig(includeSwitcherHotkey: true)
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains { $0.title == "global.switcherHotkey is ignored" })
    }

    func testDoctorFailsWhenAeroSpaceConfigMissing() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.title == "No AeroSpace config found. Starting AeroSpace will load the default tiling config and may resize/tile all windows."
        })
        XCTAssertTrue(report.actions.canInstallSafeAeroSpaceConfig)
        XCTAssertFalse(report.actions.canStartAeroSpace)
        XCTAssertFalse(report.actions.canReloadAeroSpaceConfig)
    }

    func testDoctorFailsWhenAeroSpaceConfigAmbiguous() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData(),
            "/Users/tester/.config/aerospace/aerospace.toml": Data("user-config".utf8)
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.title == "AeroSpace config is ambiguous (found in more than one location)."
        })
        XCTAssertFalse(report.actions.canInstallSafeAeroSpaceConfig)
        XCTAssertFalse(report.actions.canStartAeroSpace)
        XCTAssertFalse(report.actions.canReloadAeroSpaceConfig)
        XCTAssertFalse(report.actions.canUninstallSafeAeroSpaceConfig)
    }

    func testDoctorInstallsSafeAeroSpaceConfig() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.installSafeAeroSpaceConfig()

        XCTAssertTrue(report.findings.contains {
            $0.title == "Installed safe AeroSpace config at: ~/.aerospace.toml"
        })
        XCTAssertNotNil(fileSystem.fileData(atPath: "/Users/tester/.aerospace.toml"))
    }

    func testDoctorUninstallsSafeAeroSpaceConfig() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"
        let fixedDate = Date(timeIntervalSince1970: 0)

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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

        var results: [DoctorCommandSignature: [CommandResult]] = [
            DoctorCommandSignature(path: aerospacePath, arguments: ["reload-config", "--no-gui"]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ],
            DoctorCommandSignature(path: aerospacePath, arguments: ["config", "--config-path"]): [
                CommandResult(exitCode: 0, stdout: "/Users/tester/.aerospace.toml\n", stderr: "")
            ],
            DoctorCommandSignature(path: aerospacePath, arguments: ["list-workspaces", "--focused"]): [
                CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""),
                CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""),
                CommandResult(exitCode: 0, stdout: "pw-inbox\n", stderr: ""),
                CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: "")
            ],
            DoctorCommandSignature(path: aerospacePath, arguments: ["summon-workspace", "pw-inbox"]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ],
            DoctorCommandSignature(path: aerospacePath, arguments: ["summon-workspace", "pw-codex"]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ]
        addCompatibilityStubs(results: &results, executablePath: aerospacePath)
        let commandRunner = TestCommandRunner(results: results)

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:]),
            dateProvider: TestDateProvider(date: fixedDate)
        )

        let report = doctor.uninstallSafeAeroSpaceConfig()
        let backupPath = "/Users/tester/.aerospace.toml.projectworkspaces.bak.19700101-000000"

        XCTAssertTrue(report.findings.contains {
            $0.title == "Backed up ~/.aerospace.toml to: \(backupPath)"
        })
        XCTAssertNil(fileSystem.fileData(atPath: "/Users/tester/.aerospace.toml"))
        XCTAssertNotNil(fileSystem.fileData(atPath: backupPath))
    }

    func testDoctorUninstallSkipsUserManagedConfig() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": Data("user-config".utf8)
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.uninstallSafeAeroSpaceConfig()

        XCTAssertNotNil(fileSystem.fileData(atPath: "/Users/tester/.aerospace.toml"))
        XCTAssertTrue(report.rendered().contains(
            "INFO  AeroSpace config appears user-managed; ProjectWorkspaces will not modify it."
        ))
    }

    func testDoctorFailsWhenConfigMissing() {
        let aerospacePath = "/opt/homebrew/bin/aerospace"
        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Applications/AeroSpace.app"
        ], executableFiles: [
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Config file missing" })
    }

    func testDoctorFailsWhenAerospaceCliMissing() {
        let config = makeValidConfig()
        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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
            DoctorCommandSignature(path: "/usr/bin/which", arguments: ["aerospace"]): [
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
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "aerospace CLI not found" })
    }

    func testDoctorWarnsWhenAerospaceRestoreFails() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"
        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
        ], executableFiles: [
            aerospacePath,
            "/opt/homebrew/bin/brew"
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

        var results: [DoctorCommandSignature: [CommandResult]] = [
            DoctorCommandSignature(path: aerospacePath, arguments: ["config", "--config-path"]): [
                CommandResult(exitCode: 0, stdout: "/Users/tester/.aerospace.toml\n", stderr: "")
            ],
            DoctorCommandSignature(path: aerospacePath, arguments: ["list-workspaces", "--focused"]): [
                CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""),
                CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""),
                CommandResult(exitCode: 0, stdout: "pw-inbox\n", stderr: "")
            ],
            DoctorCommandSignature(path: aerospacePath, arguments: ["summon-workspace", "pw-inbox"]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ],
            DoctorCommandSignature(path: aerospacePath, arguments: ["summon-workspace", "pw-codex"]): [
                CommandResult(exitCode: 1, stdout: "", stderr: "restore failed")
            ]
        ]
        addCompatibilityStubs(results: &results, executablePath: aerospacePath)
        let commandRunner = TestCommandRunner(results: results)

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertFalse(report.hasFailures)
        XCTAssertTrue(report.findings.contains {
            $0.title == "Could not restore previous workspace automatically."
        })
    }

    func testDoctorFailsWhenFocusedWorkspaceIsNotInboxAfterSwitch() {
        let config = makeValidConfig()
        let aerospacePath = "/opt/homebrew/bin/aerospace"
        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8),
            "/Users/tester/.aerospace.toml": makeSafeAeroSpaceConfigData()
        ], directories: [
            "/Users/tester/src/codex",
            "/Applications/AeroSpace.app"
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

        var results: [DoctorCommandSignature: [CommandResult]] = [
            DoctorCommandSignature(path: aerospacePath, arguments: ["config", "--config-path"]): [
                CommandResult(exitCode: 0, stdout: "/Users/tester/.aerospace.toml\n", stderr: "")
            ],
            DoctorCommandSignature(path: aerospacePath, arguments: ["list-workspaces", "--focused"]): [
                CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""),
                CommandResult(exitCode: 0, stdout: "pw-codex\n", stderr: ""),
                CommandResult(exitCode: 0, stdout: "pw-other\n", stderr: "")
            ],
            DoctorCommandSignature(path: aerospacePath, arguments: ["summon-workspace", "pw-inbox"]): [
                CommandResult(exitCode: 0, stdout: "", stderr: "")
            ]
        ]
        addCompatibilityStubs(results: &results, executablePath: aerospacePath)
        let commandRunner = TestCommandRunner(results: results)

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true),
            runningApplicationChecker: TestRunningApplicationChecker(isRunning: false),
            commandRunner: commandRunner,
            aeroSpaceCommandRunner: commandRunner,
            environment: TestEnvironment(values: [:])
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains {
            $0.title == "AeroSpace workspace switching failed. ProjectWorkspaces cannot operate safely."
        })
    }
}

// Uses TestFileSystem and TestAppDiscovery from TestSupport.swift

private struct DoctorCommandSignature: Hashable {
    let path: String
    let arguments: [String]
}

private final class TestCommandRunner: CommandRunning, AeroSpaceCommandRunning {
    private var results: [DoctorCommandSignature: [CommandResult]]

    init(results: [DoctorCommandSignature: [CommandResult]]) {
        self.results = results
    }

    /// Runs a stubbed command and returns the next queued result.
    /// - Parameters:
    ///   - command: Executable URL to run.
    ///   - arguments: Arguments passed to the command.
    ///   - environment: Environment variables (unused in this stub).
    ///   - workingDirectory: Working directory (unused in this stub).
    /// - Returns: The queued command result.
    /// - Throws: Error when no stubbed result exists for the command.
    func run(
        command: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> CommandResult {
        let _ = environment
        let _ = workingDirectory
        let signature = DoctorCommandSignature(path: command.path, arguments: arguments)
        guard var queue = results[signature], !queue.isEmpty else {
            throw NSError(domain: "TestCommandRunner", code: 1)
        }
        let result = queue.removeFirst()
        results[signature] = queue
        return result
    }

    func run(
        executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        let _ = timeoutSeconds
        let signature = DoctorCommandSignature(path: executable.path, arguments: arguments)
        guard var queue = results[signature], !queue.isEmpty else {
            preconditionFailure("Missing stubbed response for \(signature.path) \(signature.arguments).")
        }
        let result = queue.removeFirst()
        results[signature] = queue
        if result.exitCode != 0 {
            let commandLabel = ([executable.path] + arguments).joined(separator: " ")
            return .failure(.executionFailed(.nonZeroExit(command: commandLabel, result: result)))
        }
        return .success(result)
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
    \(switcherLine)

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
    var results: [DoctorCommandSignature: [CommandResult]] = [:]
    let configKey = DoctorCommandSignature(path: executablePath, arguments: ["config", "--config-path"])
    results[configKey] = [
        CommandResult(exitCode: 0, stdout: "/Users/tester/.aerospace.toml\n", stderr: "")
    ]
    let focusedKey = DoctorCommandSignature(path: executablePath, arguments: ["list-workspaces", "--focused"])
    results[focusedKey] = [
        CommandResult(exitCode: 0, stdout: "\(previousWorkspace)\n", stderr: ""),
        CommandResult(exitCode: 0, stdout: "\(previousWorkspace)\n", stderr: ""),
        CommandResult(exitCode: 0, stdout: "pw-inbox\n", stderr: ""),
        CommandResult(exitCode: 0, stdout: "\(previousWorkspace)\n", stderr: "")
    ]

    let switchInboxKey = DoctorCommandSignature(path: executablePath, arguments: ["summon-workspace", "pw-inbox"])
    results[switchInboxKey] = [CommandResult(exitCode: 0, stdout: "", stderr: "")]

    if previousWorkspace != "pw-inbox" {
        let restoreKey = DoctorCommandSignature(path: executablePath, arguments: ["summon-workspace", previousWorkspace])
        results[restoreKey] = [CommandResult(exitCode: 0, stdout: "", stderr: "")]
    }

    addCompatibilityStubs(results: &results, executablePath: executablePath)
    return TestCommandRunner(results: results)
}

private func addCompatibilityStubs(
    results: inout [DoctorCommandSignature: [CommandResult]],
    executablePath: String
) {
    let listWindowsKey = DoctorCommandSignature(
        path: executablePath,
        arguments: ["list-windows", "--all", "--json"]
    )
    results[listWindowsKey] = [CommandResult(exitCode: 0, stdout: "[]", stderr: "")]

    let focusHelpKey = DoctorCommandSignature(path: executablePath, arguments: ["focus", "--help"])
    results[focusHelpKey] = [CommandResult(exitCode: 0, stdout: "help", stderr: "")]

    let moveHelpKey = DoctorCommandSignature(
        path: executablePath,
        arguments: ["move-node-to-workspace", "--help"]
    )
    results[moveHelpKey] = [CommandResult(exitCode: 0, stdout: "help", stderr: "")]

    let summonHelpKey = DoctorCommandSignature(
        path: executablePath,
        arguments: ["summon-workspace", "--help"]
    )
    results[summonHelpKey] = [CommandResult(exitCode: 0, stdout: "help", stderr: "")]
}

private func makeSafeAeroSpaceConfigData() -> Data {
    Data("# Managed by ProjectWorkspaces.\n".utf8)
}

// TestAppDiscovery is provided by TestSupport.swift

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

private struct TestEnvironment: EnvironmentProviding {
    let values: [String: String]

    func value(forKey key: String) -> String? {
        values[key]
    }

    func allValues() -> [String: String] {
        values
    }
}

private struct TestDateProvider: DateProviding {
    let date: Date

    func now() -> Date {
        date
    }
}
