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
        let chromeWindow = chromeWindowPayload(id: 30, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "12", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "30", "floating"]): [
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
        let chromeWindow = chromeWindowPayload(id: 77, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "42", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "77", "floating"]): [
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
        let chromeWindow = chromeWindowPayload(id: 88, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindowA, ideWindowB]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "10", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "88", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "10"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
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
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report, let warnings):
            XCTAssertEqual(report.ideWindowId, 10)
            XCTAssertEqual(report.chromeWindowId, 88)
            XCTAssertEqual(
                warnings,
                [.multipleWindows(kind: .ide, workspace: "pw-codex", chosenId: 10, extraIds: [44])]
            )
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
        let chromeWindow = chromeWindowPayload(id: 99, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "12", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "99", "floating"]): [
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

    func testActivationChoosesLowestWhenMultipleTokenIdeWindowsExist() {
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
        let chromeWindow = chromeWindowPayload(id: 99, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindowA, ideWindowB]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "12", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "99", "floating"]): [
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
        case .success(let report, let warnings):
            XCTAssertEqual(report.ideWindowId, 12)
            XCTAssertEqual(report.chromeWindowId, 99)
            XCTAssertEqual(
                warnings,
                [.multipleWindows(kind: .ide, workspace: "pw-codex", chosenId: 12, extraIds: [14])]
            )
        }

        XCTAssertEqual(ideLauncher.callCount, 0)
        XCTAssertEqual(chromeLauncher.callCount, 1)
    }

    func testActivationFailsWhenLogWriteFailsOnSuccess() {
        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code"
        )
        let chromeWindow = chromeWindowPayload(id: 30, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "12", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "30", "floating"]): [
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
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ],
            signature(["list-windows", "--focused", "--json", "--format", listWindowsFormat]): [
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

    func testActivationRecoversIdeWindowFromFocusedAfterWorkspaceTimeout() {
        let focusedIdeWindow = windowPayload(
            id: 55,
            workspace: "pw-other",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code"
        )
        let chromeWindow = chromeWindowPayload(id: 99, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: ""))
            ],
            signature(["list-windows", "--focused", "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([focusedIdeWindow]), stderr: ""))
            ],
            signature(["move-node-to-workspace", "--window-id", "55", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "55", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "99", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "55"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
        ]

        let ideLauncher = TestIdeLauncher.success()
        let chromeLauncher = TestChromeLauncher.existing(windowId: 99)
        let logger = TestLogger()

        let service = makeService(
            responses: responses,
            ideLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            logger: logger,
            pollIntervalMs: 10,
            pollTimeoutMs: 20
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report, let warnings):
            XCTAssertEqual(report.ideWindowId, 55)
            XCTAssertEqual(report.chromeWindowId, 99)
            XCTAssertTrue(warnings.isEmpty)
        }

        XCTAssertEqual(ideLauncher.callCount, 1)
        XCTAssertEqual(chromeLauncher.callCount, 1)
    }

    func testActivationKeepsWaitingAfterListWindowsTimeout() {
        let ideWindow = windowPayload(
            id: 71,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code"
        )
        let chromeWindow = chromeWindowPayload(id: 99, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([]), stderr: "")),
                .failure(.timedOut(
                    command: "aerospace list-windows --workspace pw-codex",
                    timeoutSeconds: 2,
                    result: CommandResult(exitCode: 15, stdout: "", stderr: "")
                )),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "71", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["layout", "--window-id", "99", "floating"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["focus", "--window-id", "71"]): [
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
            logger: logger,
            pollIntervalMs: 10,
            pollTimeoutMs: 30
        )

        let outcome = service.activate(projectId: "codex")
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report, let warnings):
            XCTAssertEqual(report.ideWindowId, 71)
            XCTAssertEqual(report.chromeWindowId, 99)
            XCTAssertTrue(warnings.isEmpty)
        }
    }

    func testActivationSkipsFocusWhenDisabled() {
        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code",
            windowLayout: "floating"
        )
        let chromeWindow = chromeWindowPayload(
            id: 30,
            workspace: "pw-codex",
            windowLayout: "floating"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
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

        let outcome = service.activate(projectId: "codex", focusIdeWindow: false)
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report, let warnings):
            XCTAssertEqual(report.ideWindowId, 12)
            XCTAssertEqual(report.chromeWindowId, 30)
            XCTAssertTrue(warnings.isEmpty)
        }
    }

    func testActivationSkipsWorkspaceWhenDisabled() {
        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code",
            windowLayout: "floating"
        )
        let chromeWindow = chromeWindowPayload(
            id: 30,
            workspace: "pw-codex",
            windowLayout: "floating"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
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

        let outcome = service.activate(projectId: "codex", focusIdeWindow: false, switchWorkspace: false)
        switch outcome {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success(let report, let warnings):
            XCTAssertEqual(report.ideWindowId, 12)
            XCTAssertEqual(report.chromeWindowId, 30)
            XCTAssertTrue(warnings.isEmpty)
        }
    }

    func testActivationSkipsLayoutWhenAlreadyFloating() {
        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code",
            windowLayout: "floating"
        )
        let chromeWindow = chromeWindowPayload(
            id: 30,
            workspace: "pw-codex",
            windowLayout: "floating"
        )

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
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
    }

    func testActivationDoesNotWarnWhenLayoutFailureResultsInFloating() {
        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code",
            windowLayout: "tiling"
        )
        let ideWindowAfterLayout = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code",
            windowLayout: "floating"
        )
        let chromeWindow = chromeWindowPayload(id: 30, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindowAfterLayout]), stderr: ""))
            ],
            signature(["layout", "--window-id", "12", "floating"]): [
                .failure(.nonZeroExit(
                    command: "aerospace layout --window-id 12 floating",
                    result: CommandResult(exitCode: 1, stdout: "", stderr: "layout failed")
                ))
            ],
            signature(["list-workspaces", "--focused", "--count"]): [
                .success(CommandResult(exitCode: 0, stdout: "1\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "30", "floating"]): [
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
    }

    func testActivationWarnsWhenFloatingLayoutFails() {
        let ideWindow = windowPayload(
            id: 12,
            workspace: "pw-codex",
            bundleId: TestConstants.vscodeBundleId,
            appName: "Visual Studio Code",
            windowTitle: "PW:codex - Visual Studio Code"
        )
        let chromeWindow = chromeWindowPayload(id: 30, workspace: "pw-codex")

        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
                .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: "")),
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([ideWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "12", "floating"]): [
                .failure(.nonZeroExit(
                    command: "aerospace layout --window-id 12 floating",
                    result: CommandResult(exitCode: 1, stdout: "", stderr: "layout failed")
                ))
            ],
            signature(["list-workspaces", "--focused", "--count"]): [
                .success(CommandResult(exitCode: 0, stdout: "1\n", stderr: ""))
            ],
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", ChromeLauncher.chromeBundleId, "--json", "--format", listWindowsFormat]): [
                .success(CommandResult(exitCode: 0, stdout: windowsJSON([chromeWindow]), stderr: ""))
            ],
            signature(["layout", "--window-id", "30", "floating"]): [
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
            XCTAssertEqual(
                warnings,
                [.layoutFailed(kind: .ide, windowId: 12, error: .nonZeroExit(
                    command: "aerospace layout --window-id 12 floating",
                    result: CommandResult(exitCode: 1, stdout: "", stderr: "layout failed")
                ))]
            )
        }
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
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
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
            signature(["list-windows", "--workspace", "pw-codex", "--app-bundle-id", TestConstants.vscodeBundleId, "--json", "--format", listWindowsFormat]): [
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

    func testFocusWorkspaceAndWindowLogsCommands() {
        let responses: AeroSpaceCommandResponses = [
            signature(["workspace", "pw-codex"]): [
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

        let report = ActivationReport(
            projectId: "codex",
            workspaceName: "pw-codex",
            ideWindowId: 12,
            chromeWindowId: 30
        )

        let result = service.focusWorkspaceAndWindow(report: report)
        switch result {
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        case .success:
            break
        }

        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries.first?.event, "activation.focus")
    }

    // MARK: - Test Helpers

    private func makeService(
        responses: AeroSpaceCommandResponses,
        ideLauncher: TestIdeLauncher,
        chromeLauncher: TestChromeLauncher,
        logger: TestLogger,
        pollIntervalMs: Int = 10,
        pollTimeoutMs: Int = 50,
        workspaceProbeTimeoutMs: Int = 800,
        focusedProbeTimeoutMs: Int = 1000
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
            pollTimeoutMs: pollTimeoutMs,
            workspaceProbeTimeoutMs: workspaceProbeTimeoutMs,
            focusedProbeTimeoutMs: focusedProbeTimeoutMs
        )
    }

    private func signature(_ arguments: [String]) -> AeroSpaceCommandSignature {
        AeroSpaceCommandSignature(path: aerospacePath, arguments: arguments)
    }
}
