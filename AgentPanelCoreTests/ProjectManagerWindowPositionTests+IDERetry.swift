import XCTest

@testable import AgentPanelCore

extension ProjectManagerWindowPositionTests {
    // MARK: - IDE Fallback Tests

    func testIDEFallbackUsedAfterTokenRetryExhaustion() async {
        let projectId = "fb-ide-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        let ideKey = "com.microsoft.VSCode|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // All 10 retries fail with transient token-miss
        positioner.getFrameSequences[ideKey] = Array(repeating: .failure(tokenMiss), count: 10)
        // Fallback succeeds
        positioner.getFallbackFrameResults["com.microsoft.VSCode"] = .success(defaultIdeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "FB", path: "/tmp/fb", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNil(success.layoutWarning, "Fallback succeeded — no warning expected")
        }

        // Probe runs on first miss, then fallback runs after retry exhaustion.
        XCTAssertEqual(positioner.getFallbackFrameCalls.count, 2)
        XCTAssertEqual(positioner.getFallbackFrameCalls[0], "com.microsoft.VSCode")
        XCTAssertEqual(positioner.getFallbackFrameCalls[1], "com.microsoft.VSCode")
        // Verify token retries were not short-circuited by the probe.
        let ideGetCalls = positioner.getFrameCalls.filter { $0.bundleId == "com.microsoft.VSCode" }
        XCTAssertEqual(ideGetCalls.count, 10)
        // Verify positioning proceeded (IDE + Chrome setWindowFrames)
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
    }

    func testIDEFallbackFailureReturnsLayoutWarning() async {
        let projectId = "fb-ide-2"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        let ideKey = "com.microsoft.VSCode|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        positioner.getFrameSequences[ideKey] = Array(repeating: .failure(tokenMiss), count: 10)
        // Fallback also fails
        positioner.getFallbackFrameResults["com.microsoft.VSCode"] =
            .failure(ApCoreError(category: .window, message: "Ambiguous: 3 windows"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "FB2", path: "/tmp/fb2", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should have layout warning when fallback fails")
            XCTAssertTrue(success.layoutWarning?.contains("Ambiguous") == true)
        }

        // No setWindowFrames calls since IDE frame was never resolved
        XCTAssertTrue(positioner.setFrameCalls.isEmpty)
    }

    func testIDEPermanentErrorSkipsFallback() async {
        let projectId = "fb-ide-3"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        // Permanent error (not "No window found with token")
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] =
            .failure(ApCoreError(category: .window, message: "AX permission denied"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "FB3", path: "/tmp/fb3", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("AX permission denied") == true)
        }

        // Permanent error: no fallback attempted, no retry
        XCTAssertTrue(positioner.getFallbackFrameCalls.isEmpty)
        XCTAssertEqual(positioner.getFrameCalls.count, 1)
    }

    // MARK: - Zero-Windows Fast-Fail

    func testConfirmedZeroWindowsFastFailRequiresRetryConfidence() async {
        let projectId = "zw-ff-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        let ideKey = "com.microsoft.VSCode|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // Persistent transient token misses with repeated zero-window probes.
        // Fast-fail should require additional confidence before short-circuiting.
        positioner.getFrameSequences[ideKey] = [
            .failure(tokenMiss),
            .failure(tokenMiss),
            .failure(tokenMiss),
            .failure(tokenMiss),
            .failure(tokenMiss),
            .failure(tokenMiss),
            .failure(tokenMiss),
            .failure(tokenMiss),
            .failure(tokenMiss),
            .failure(tokenMiss)
        ]
        // Probe reports zero windows.
        positioner.getFallbackFrameResults["com.microsoft.VSCode"] =
            .failure(ApCoreError(category: .window, message: "No windows found for com.microsoft.VSCode (count=0)"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "ZW", path: "/tmp/zw", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should have layout warning for zero windows")
            XCTAssertTrue(success.layoutWarning?.contains("No windows found") == true)
        }

        // Fast-fail should trigger only after retry confidence is met.
        let ideGetCalls = positioner.getFrameCalls.filter { $0.bundleId == "com.microsoft.VSCode" }
        XCTAssertEqual(
            ideGetCalls.count,
            10,
            "Should preserve the full token retry budget before confirming permanent zero-window fast-fail"
        )

        // Probe was called on each retry before the final exhausted attempt.
        // The exhausted attempt should use zero-window fast-fail (not fallback frame resolution).
        XCTAssertEqual(positioner.getFallbackFrameCalls.count, ideGetCalls.count - 1)
        XCTAssertTrue(positioner.getFallbackFrameCalls.allSatisfy { $0 == "com.microsoft.VSCode" })

        // No setWindowFrames since IDE frame was never resolved
        XCTAssertTrue(positioner.setFrameCalls.isEmpty)
    }

    func testTransientEarlyZeroWindowProbesDoNotFastFailWhenTokenRetryRecovers() async {
        let projectId = "zw-probe-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        let ideKey = "com.microsoft.VSCode|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // Two early token misses occur before the title token settles, then recovery succeeds.
        positioner.getFrameSequences[ideKey] = [
            .failure(tokenMiss),
            .failure(tokenMiss),
            .success(defaultIdeFrame)
        ]
        // Early zero-window probe failures are transient/noisy and should not short-circuit retries.
        positioner.getFallbackFrameResults["com.microsoft.VSCode"] =
            .failure(ApCoreError(category: .window, message: "No windows found for com.microsoft.VSCode (count=0)"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Probe", path: "/tmp/probe", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNil(success.layoutWarning, "Token retry succeeded — no layout warning expected")
        }

        // Early zero-window probes must not short-circuit; token retry should recover.
        let ideGetCalls = positioner.getFrameCalls.filter { $0.bundleId == "com.microsoft.VSCode" }
        XCTAssertEqual(ideGetCalls.count, 3, "Expected token retries to continue after early zero-window probes")

        // Probes occur for the early misses only; no third probe after token recovery.
        XCTAssertEqual(positioner.getFallbackFrameCalls.count, 2)

        // Positioning should have proceeded (IDE + Chrome setWindowFrames)
        XCTAssertEqual(positioner.setFrameCalls.count, 2, "Should have set frames for IDE and Chrome")
    }

    // MARK: - IDE Set Retry + Fallback Tests

    func testIDESetRetriesAndSucceeds() async {
        let projectId = "is-retry-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let ideKey = "com.microsoft.VSCode|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // Fail twice, then succeed.
        positioner.setFrameSequences[ideKey] = [
            .failure(tokenMiss),
            .failure(tokenMiss),
            .success(WindowPositionResult(positioned: 1, matched: 1))
        ]

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "ISR", path: "/tmp/isr", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNil(success.layoutWarning, "Retry succeeded — no warning expected")
        }

        let ideSetCalls = positioner.setFrameCalls.filter { $0.bundleId == "com.microsoft.VSCode" }
        XCTAssertEqual(ideSetCalls.count, 3)
        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty, "Fallback not needed")
    }

    func testIDESetFallbackUsedAfterRetryExhaustion() async {
        let projectId = "is-fb-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let ideKey = "com.microsoft.VSCode|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // All retries fail.
        positioner.setFrameSequences[ideKey] = Array(repeating: .failure(tokenMiss), count: 5)
        positioner.setFallbackFrameResults["com.microsoft.VSCode"] =
            .success(WindowPositionResult(positioned: 1, matched: 1))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "ISFB", path: "/tmp/isfb", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNil(success.layoutWarning)
        }

        let ideSetCalls = positioner.setFrameCalls.filter { $0.bundleId == "com.microsoft.VSCode" }
        XCTAssertEqual(ideSetCalls.count, 5)
        XCTAssertEqual(positioner.setFallbackFrameCalls.count, 1)
        XCTAssertEqual(positioner.setFallbackFrameCalls[0].bundleId, "com.microsoft.VSCode")
    }

    func testIDESetFallbackFailureAddsWarning() async {
        let projectId = "is-fb-2"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let ideKey = "com.microsoft.VSCode|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        positioner.setFrameSequences[ideKey] = Array(repeating: .failure(tokenMiss), count: 5)
        positioner.setFallbackFrameResults["com.microsoft.VSCode"] =
            .failure(ApCoreError(category: .window, message: "Ambiguous: 2 windows"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "ISFB2", path: "/tmp/isfb2", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("Ambiguous") == true)
        }
    }

    func testIDESetPermanentErrorSkipsFallback() async {
        let projectId = "is-perm-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Permanent error (not "No window found with token")
        let ideKey = "com.microsoft.VSCode|\(projectId)"
        positioner.setFrameResults[ideKey] =
            .failure(ApCoreError(category: .window, message: "AX permission denied"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "ISPerm", path: "/tmp/isperm", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("AX permission denied") == true)
        }

        // Permanent error: no fallback attempted, only one IDE set call
        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty, "Permanent error should not trigger fallback")
        let ideCalls = positioner.setFrameCalls.filter { $0.bundleId == "com.microsoft.VSCode" }
        XCTAssertEqual(ideCalls.count, 1, "Should only try once for permanent error")
    }

}
