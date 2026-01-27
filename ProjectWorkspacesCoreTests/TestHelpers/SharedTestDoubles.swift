import Foundation
import XCTest

@testable import ProjectWorkspacesCore

// MARK: - Noop Logger (distinct from TestLogger in TestSupport.swift)

struct NoopLogger: ProjectWorkspacesLogging {
    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
        let _ = event
        let _ = level
        let _ = message
        let _ = context
        return .success(())
    }
}

// MARK: - Geometry Applier Test Double

final class TestGeometryApplier: WindowGeometryApplying {
    struct Call: Equatable {
        let windowId: Int
        let frame: CGRect
        let workspaceName: String
    }

    private(set) var calls: [Call] = []
    private(set) var callCount = 0
    private var outcomes: [WindowGeometryOutcome]

    init(outcomes: [WindowGeometryOutcome] = [.applied]) {
        self.outcomes = outcomes
    }

    func apply(frame: CGRect, toWindowId windowId: Int, inWorkspace workspaceName: String) -> WindowGeometryOutcome {
        calls.append(Call(windowId: windowId, frame: frame, workspaceName: workspaceName))
        callCount += 1
        if !outcomes.isEmpty {
            return outcomes.removeFirst()
        }
        return .applied
    }
}

// MARK: - Focus Controller Test Double

final class TestFocusController: WindowFocusing {
    private(set) var calls: [Int] = []
    private let result: Result<CommandResult, AeroSpaceCommandError>

    init(result: Result<CommandResult, AeroSpaceCommandError>) {
        self.result = result
    }

    func focus(windowId: Int) -> Result<CommandResult, AeroSpaceCommandError> {
        calls.append(windowId)
        return result
    }
}

// MARK: - Focus Verifier Test Double

final class TestFocusVerifier: FocusVerifying {
    private(set) var callCount = 0
    private let result: FocusVerificationResult

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

// MARK: - Accessibility Applier Test Double

final class TestAccessibilityApplier: WindowAccessibilityApplying {
    private(set) var callCount = 0
    private let result: Result<Void, WindowGeometryError>

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
    private(set) var callCount = 0
    private var responses: [Result<[AeroSpaceWindow], AeroSpaceCommandError>]

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
