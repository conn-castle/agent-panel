import XCTest

@testable import ProjectWorkspacesCore

final class ActivationServiceTests: XCTestCase {
    private let aerospacePath = TestConstants.aerospacePath
    private let listWindowsFormat = TestConstants.listWindowsFormat

    // MARK: - Success Path Tests

    func testActivationIsIdempotentWhenWindowsExist() {
        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "30"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.existing(windowId: 30)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report, let warnings):
            XCTAssertEqual(report.ideWindowId, 12)
            XCTAssertEqual(report.chromeWindowId, 30)
            XCTAssertTrue(warnings.isEmpty)
        }

        XCTAssertEqual(ideLauncher.callCount, 0)
        XCTAssertEqual(chromeLauncher.callCount, 1)
        XCTAssertEqual(chromeLauncher.lastWindowToken?.value, "PW:codex")
        XCTAssertEqual(logger.entries.count, 1)
    }

    func testActivationCreatesMissingWindows() {
        let ideWindow = windowPayload(
            id: 42,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "42"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "77"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "42"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.created(windowId: 77)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report, let warnings):
            XCTAssertEqual(report.ideWindowId, 42)
            XCTAssertEqual(report.chromeWindowId, 77)
            XCTAssertTrue(warnings.isEmpty)
        }

        XCTAssertEqual(ideLauncher.callCount, 1)
        XCTAssertEqual(chromeLauncher.callCount, 1)
        XCTAssertEqual(logger.entries.count, 1)
    }

    func testActivationFailsWhenMultipleTokenIdeWindowsAppearAfterLaunch() {
        let ideWindowA = windowPayload(
            id: 10,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - A"
        )
        let ideWindowB = windowPayload(
            id: 44,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - B"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindowA, ideWindowB]), stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.created(windowId: 88)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .success:
            XCTFail("Expected failure when multiple token windows appear.")
        case .failure(let error):
            XCTAssertEqual(error, .ideWindowTokenAmbiguous(token: "PW:codex", windowIds: [10, 44]))
        }
    }

    func testActivationIgnoresUntokenedChromeWindows() {
        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "99"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.created(windowId: 99)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report, _):
            XCTAssertEqual(report.ideWindowId, 12)
            XCTAssertEqual(report.chromeWindowId, 99)
        }

        XCTAssertEqual(ideLauncher.callCount, 0)
        XCTAssertEqual(chromeLauncher.callCount, 1)
    }

    func testActivationFailsWhenMultipleTokenIdeWindowsExist() {
        let ideWindowA = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - A"
        )
        let ideWindowB = windowPayload(
            id: 14,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - B"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindowA, ideWindowB]), stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.created(windowId: 99)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .success:
            XCTFail("Expected failure when multiple token IDE windows exist.")
        case .failure(let error):
            XCTAssertEqual(error, .ideWindowTokenAmbiguous(token: "PW:codex", windowIds: [12, 14]))
        }

        XCTAssertEqual(ideLauncher.callCount, 0)
        XCTAssertEqual(chromeLauncher.callCount, 0)
    }

    func testActivationFailsWhenLogWriteFailsOnSuccess() {
        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "floating", "--window-id", "30"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "12"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.existing(windowId: 30)
        let logger = TestLogger()
        logger.shouldFail = true
        logger.failureError = .writeFailed("log failure")

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .success:
            XCTFail("Expected failure when log write fails")
        case .failure(let error):
            XCTAssertEqual(error, .logWriteFailed(.writeFailed("log failure")))
        }

        XCTAssertEqual(logger.entries.count, 1)
    }

    // MARK: - Error Path Tests

    func testActivationFailsWhenProjectNotFound() {
        let responses: AeroSpaceCommandResponses = [:]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.created(windowId: 99)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "nonexistent")
        switch outcome {
        case .success:
            XCTFail("Expected failure for nonexistent project")
        case .failure(let error):
            if case .projectNotFound(let projectId, let available) = error {
                XCTAssertEqual(projectId, "nonexistent")
                XCTAssertEqual(available, ["codex"])
            } else {
                XCTFail("Expected projectNotFound error, got: \(error)")
            }
        }

        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries[0].level, .error)
    }

    func testActivationFailsWhenWorkspaceSwitchFails() {
        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .failure(.nonZeroExit(
                    command: "aerospace workspace pw-codex",
                    result: CommandResult(exitCode: 1, stdout: "", stderr: "workspace error")
                ))
            ],
            // Readiness probe is called when a command fails with nonZeroExit
            signature(["list-workspaces", "--focused", "--count"]): [
                .success(CommandResult(exitCode: 0, stdout: "1\n", stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.created(windowId: 99)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .success:
            XCTFail("Expected failure when workspace switch fails")
        case .failure(let error):
            if case .aeroSpaceFailed = error {
                // Expected
            } else {
                XCTFail("Expected aeroSpaceFailed error, got: \(error)")
            }
        }

        XCTAssertEqual(ideLauncher.callCount, 0)
        XCTAssertEqual(chromeLauncher.callCount, 0)
    }

    func testActivationFailsWhenIdeTokenWindowNotDetectedAfterTimeout() {
        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.created(windowId: 99)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger,
            pollIntervalMs: 10,
            pollTimeoutMs: 30
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .success:
            XCTFail("Expected failure when IDE window not detected")
        case .failure(let error):
            XCTAssertEqual(error, .ideWindowTokenNotDetected(token: "PW:codex"))
        }

        XCTAssertEqual(ideLauncher.callCount, 1)
        XCTAssertEqual(chromeLauncher.callCount, 0)
    }

    func testActivationFailsWhenChromeLaunchFails() {
        let ideWindow = windowPayload(
            id: 42,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.failure(.chromeNotFound)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .success:
            XCTFail("Expected failure when Chrome launch fails")
        case .failure(let error):
            if case .chromeLaunchFailed(let chromeError) = error {
                XCTAssertEqual(chromeError, .chromeNotFound)
            } else {
                XCTFail("Expected chromeLaunchFailed error, got: \(error)")
            }
        }

        XCTAssertEqual(ideLauncher.callCount, 0)
        XCTAssertEqual(chromeLauncher.callCount, 1)
    }

    func testActivationFailsWhenIdeLaunchFails() {
        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--all", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.failure(.openFailed(
            ProcessCommandError.launchFailed(command: "open", underlyingError: "test error")
        ))
        let chromeLauncher = TestChromeLauncher.created(windowId: 99)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .success:
            XCTFail("Expected failure when IDE launch fails")
        case .failure(let error):
            if case .ideLaunchFailed = error {
                // Expected
            } else {
                XCTFail("Expected ideLaunchFailed error, got: \(error)")
            }
        }

        XCTAssertEqual(ideLauncher.callCount, 1)
        XCTAssertEqual(chromeLauncher.callCount, 0)
    }

    // MARK: - Test Helpers

    private func makeService(
        responses: AeroSpaceCommandResponses,
        ideLauncher: TestIdeLauncher,
        chromeLauncher: TestChromeLauncher,
        logger: TestLogger,
        pollIntervalMs: Int = 10,
        pollTimeoutMs: Int = 50
    ) -> ActivationService {
        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let configURL = paths.configFile
        let fileSystem = TestFileSystem(files: [configURL.path: Data(validConfigTOML().utf8)])

        let configLoader = ConfigLoader(paths: paths, fileSystem: fileSystem)
        let resolver = TestBinaryResolver.success(path: aerospacePath)
        let runner = SequencedAeroSpaceCommandRunner(responses: responses)
        let appDiscovery = TestAppDiscovery(bundleIds: [
            TestConstants.vscodeBundleId: TestConstants.vscodeAppURL
        ])
        let ideResolver = IdeAppResolver(fileSystem: fileSystem, appDiscovery: appDiscovery)

        return ActivationService(
            configLoader: configLoader,
            aeroSpaceBinaryResolver: resolver,
            aeroSpaceCommandRunner: runner,
            aeroSpaceTimeoutSeconds: 1,
            ideLauncher: ideLauncher,
            chromeLauncherFactory: { _ in chromeLauncher },
            ideAppResolver: ideResolver,
            logger: logger,
            sleeper: TestSleeper(),
            pollIntervalMs: pollIntervalMs,
            pollTimeoutMs: pollTimeoutMs
        )
    }

    private func signature(_ arguments: [String]) -> AeroSpaceCommandSignature {
        AeroSpaceCommandSignature(path: aerospacePath, arguments: arguments)
    }
}
