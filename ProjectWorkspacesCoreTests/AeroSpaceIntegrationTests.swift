import XCTest

@testable import ProjectWorkspacesCore

final class AeroSpaceIntegrationTests: XCTestCase {
    func testCanSwitchEnumerateAndFocusWindow() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_AEROSPACE_IT"] != "1",
            "Set RUN_AEROSPACE_IT=1 to run AeroSpace integration tests."
        )

        let resolver = DefaultAeroSpaceBinaryResolver()
        let executableURL: URL
        switch resolver.resolve() {
        case .failure(let error):
            XCTFail("Failed to resolve AeroSpace CLI: \(error)")
            return
        case .success(let url):
            executableURL = url
        }

        let runner = AeroSpaceCommandExecutor.shared
        let previousWorkspace = try focusedWorkspace(executableURL: executableURL, runner: runner)
        defer {
            let restoreOutcome = AeroSpaceClient(
                executableURL: executableURL,
                commandRunner: runner,
                timeoutSeconds: 2
            ).switchWorkspace(previousWorkspace)
            if case .failure(let error) = restoreOutcome {
                let attachment = XCTAttachment(
                    string: "Failed to restore workspace \(previousWorkspace): \(error)"
                )
                XCTContext.runActivity(named: "Workspace restore failed") { activity in
                    activity.add(attachment)
                }
            }
        }

        let client = AeroSpaceClient(
            executableURL: executableURL,
            commandRunner: runner,
            timeoutSeconds: 2
        )

        let switchOutcome = client.switchWorkspace("pw-inbox")
        if case .failure(let error) = switchOutcome {
            XCTFail("Failed to switch workspace: \(error)")
            return
        }

        let windowsOutcome = client.listWindowsAllDecoded()
        let windows: [AeroSpaceWindow]
        switch windowsOutcome {
        case .failure(let error):
            XCTFail("Failed to list windows: \(error)")
            return
        case .success(let decoded):
            windows = decoded
        }

        guard let window = windows.first else {
            XCTFail("No windows available to focus. Open at least one window before running this test.")
            return
        }

        let focusOutcome = client.focusWindow(windowId: window.windowId)
        if case .failure(let error) = focusOutcome {
            XCTFail("Failed to focus window \(window.windowId): \(error)")
            return
        }

    }

    private func focusedWorkspace(
        executableURL: URL,
        runner: AeroSpaceCommandRunning
    ) throws -> String {
        let client = AeroSpaceClient(
            executableURL: executableURL,
            commandRunner: runner,
            timeoutSeconds: 2
        )
        switch client.focusedWorkspace() {
        case .failure(let error):
            throw error
        case .success(let workspace):
            return workspace
        }
    }
}
