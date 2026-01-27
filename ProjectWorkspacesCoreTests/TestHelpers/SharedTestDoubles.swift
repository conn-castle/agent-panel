import Foundation
import XCTest

@testable import ProjectWorkspacesCore

// MARK: - Logger Test Doubles

final class TestLogger: ProjectWorkspacesLogging {
    struct Entry: Equatable {
        let event: String
        let level: LogLevel
        let message: String?
        let context: [String: String]?
    }

    private(set) var entries: [Entry] = []

    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
        entries.append(Entry(event: event, level: level, message: message, context: context))
        return .success(())
    }
}

struct NoopLogger: ProjectWorkspacesLogging {
    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
        let _ = event
        let _ = level
        let _ = message
        let _ = context
        return .success(())
    }
}

// MARK: - Sleeper Test Double

final class TestSleeper: AeroSpaceSleeping {
    private(set) var calls: [TimeInterval] = []

    func sleep(seconds: TimeInterval) {
        calls.append(seconds)
    }
}

// MARK: - App Discovery Test Double

struct TestAppDiscovery: AppDiscovering {
    let bundleIds: [String: URL]

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

// MARK: - Command Runner Test Double

final class TestCommandRunner: CommandRunning {
    func run(
        command: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> CommandResult {
        let _ = command
        let _ = arguments
        let _ = environment
        let _ = workingDirectory
        return CommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}

// MARK: - AeroSpace Resolver Test Double

struct TestAeroSpaceResolver: AeroSpaceBinaryResolving {
    let executableURL: URL

    func resolve() -> Result<URL, AeroSpaceBinaryResolutionError> {
        .success(executableURL)
    }
}

// MARK: - IDE Launcher Test Double

final class TestIdeLauncher: IdeLaunching {
    private(set) var callCount = 0
    private let result: Result<IdeLaunchSuccess, IdeLaunchError>

    init(result: Result<IdeLaunchSuccess, IdeLaunchError>) {
        self.result = result
    }

    func launch(project: ProjectConfig, ideConfig: IdeConfig) -> Result<IdeLaunchSuccess, IdeLaunchError> {
        let _ = project
        let _ = ideConfig
        callCount += 1
        return result
    }
}

// MARK: - Chrome Launcher Test Double

final class TestChromeLauncher: ChromeLaunching {
    private(set) var callCount = 0
    private var results: [Result<ChromeLaunchOutcome, ChromeLaunchError>]

    init(results: [Result<ChromeLaunchOutcome, ChromeLaunchError>]) {
        self.results = results
    }

    func ensureWindow(
        expectedWorkspaceName: String,
        globalChromeUrls: [String],
        project: ProjectConfig,
        ideWindowIdToRefocus: Int?
    ) -> Result<ChromeLaunchOutcome, ChromeLaunchError> {
        let _ = expectedWorkspaceName
        let _ = globalChromeUrls
        let _ = project
        let _ = ideWindowIdToRefocus
        callCount += 1
        guard !results.isEmpty else {
            XCTFail("Missing Chrome launcher result stub.")
            return .failure(.chromeWindowNotDetected(expectedWorkspace: expectedWorkspaceName))
        }
        return results.removeFirst()
    }
}

// MARK: - Geometry Applier Test Double

final class TestGeometryApplier: WindowGeometryApplying {
    struct Call: Equatable {
        let windowId: Int
        let frame: CGRect
        let workspaceName: String
    }

    private(set) var applyCalls: [Call] = []
    private let outcome: WindowGeometryOutcome

    init(outcome: WindowGeometryOutcome) {
        self.outcome = outcome
    }

    func apply(frame: CGRect, toWindowId windowId: Int, inWorkspace workspaceName: String) -> WindowGeometryOutcome {
        applyCalls.append(Call(windowId: windowId, frame: frame, workspaceName: workspaceName))
        return outcome
    }
}

// MARK: - Display Info Provider Test Double

struct TestDisplayInfoProvider: DisplayInfoProviding {
    let displayInfo: DisplayInfo?

    func mainDisplayInfo() -> DisplayInfo? {
        displayInfo
    }
}

// MARK: - Focus Verifying Test Double

final class TestFocusVerifier: FocusVerifying {
    let result: FocusVerificationResult
    private(set) var callCount = 0

    init(result: FocusVerificationResult) {
        self.result = result
    }

    func verify(windowId: Int, workspaceName: String) -> FocusVerificationResult {
        let _ = windowId
        let _ = workspaceName
        callCount += 1
        return result
    }
}

// MARK: - Window Focusing Test Double

final class TestFocusController: WindowFocusing {
    private let result: Result<CommandResult, AeroSpaceCommandError>
    private(set) var calls: [Int] = []

    init(result: Result<CommandResult, AeroSpaceCommandError>) {
        self.result = result
    }

    func focus(windowId: Int) -> Result<CommandResult, AeroSpaceCommandError> {
        calls.append(windowId)
        return result
    }
}

// MARK: - Window Accessibility Applying Test Double

final class TestAccessibilityApplier: WindowAccessibilityApplying {
    private let result: Result<Void, WindowGeometryError>
    private(set) var callCount = 0

    init(result: Result<Void, WindowGeometryError>) {
        self.result = result
    }

    func apply(frame: CGRect) -> Result<Void, WindowGeometryError> {
        let _ = frame
        callCount += 1
        return result
    }
}

// MARK: - Focused Window Query Test Double

final class TestFocusedWindowQuery: FocusedWindowQuerying {
    private var responses: [Result<[AeroSpaceWindow], AeroSpaceCommandError>]
    private(set) var callCount = 0

    init(responses: [Result<[AeroSpaceWindow], AeroSpaceCommandError>]) {
        self.responses = responses
    }

    func listWindowsFocusedDecoded() -> Result<[AeroSpaceWindow], AeroSpaceCommandError> {
        callCount += 1
        guard !responses.isEmpty else {
            return .success([])
        }
        return responses.removeFirst()
    }
}
