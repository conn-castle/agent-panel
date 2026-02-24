import Foundation
import XCTest
@testable import AgentPanelCore

/// Tests for window positioning integration in ProjectManager
/// (selectProject positioning, closeProject capture, exitToNonProjectWindow capture).
final class ProjectManagerWindowPositionTests: XCTestCase {

    // MARK: - Test Doubles

    private struct NoopLogger: AgentPanelLogging {
        func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
            .success(())
        }
    }

    private struct NoopTabCapture: ChromeTabCapturing {
        func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> { .success([]) }
    }

    private struct NoopGitRemoteResolver: GitRemoteResolving {
        func resolve(projectPath: String) -> String? { nil }
    }

    private struct NoopIdeLauncher: IdeLauncherProviding {
        func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> { .success(()) }
    }

    private struct NoopChromeLauncher: ChromeLauncherProviding {
        func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> { .success(()) }
    }

    private final class RecordingWindowPositioner: WindowPositioning {
        var getFrameResults: [String: Result<CGRect, ApCoreError>] = [:]
        var setFrameResults: [String: Result<WindowPositionResult, ApCoreError>] = [:]
        var trusted: Bool = true
        private(set) var setFrameCalls: [(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffset: CGFloat)] = []
        private(set) var getFrameCalls: [(bundleId: String, projectId: String)] = []

        func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, ApCoreError> {
            getFrameCalls.append((bundleId, projectId))
            let key = "\(bundleId)|\(projectId)"
            return getFrameResults[key] ?? .failure(ApCoreError(category: .window, message: "no stub for \(key)"))
        }

        func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, ApCoreError> {
            setFrameCalls.append((bundleId, projectId, primaryFrame, cascadeOffsetPoints))
            let key = "\(bundleId)|\(projectId)"
            return setFrameResults[key] ?? .success(WindowPositionResult(positioned: 1, matched: 1))
        }

        var recoverWindowCalls: [(bundleId: String, windowTitle: String)] = []
        var recoverWindowResult: Result<RecoveryOutcome, ApCoreError> = .success(.unchanged)
        func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, ApCoreError> {
            recoverWindowCalls.append((bundleId: bundleId, windowTitle: windowTitle))
            return recoverWindowResult
        }

        func isAccessibilityTrusted() -> Bool { trusted }

        func promptForAccessibility() -> Bool { trusted }
    }

    private final class RecordingPositionStore: WindowPositionStoring {
        var loadResults: [String: Result<SavedWindowFrames?, ApCoreError>] = [:]
        private(set) var saveCalls: [(projectId: String, mode: ScreenMode, frames: SavedWindowFrames)] = []
        var saveResult: Result<Void, ApCoreError> = .success(())

        func load(projectId: String, mode: ScreenMode) -> Result<SavedWindowFrames?, ApCoreError> {
            let key = "\(projectId)|\(mode.rawValue)"
            return loadResults[key] ?? .success(nil)
        }

        func save(projectId: String, mode: ScreenMode, frames: SavedWindowFrames) -> Result<Void, ApCoreError> {
            saveCalls.append((projectId, mode, frames))
            return saveResult
        }
    }

    private struct StubScreenModeDetector: ScreenModeDetecting {
        var mode: ScreenMode = .wide
        var physicalWidth: Double = 27.0
        var visibleFrame: CGRect = CGRect(x: 0, y: 0, width: 2560, height: 1415)

        func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, ApCoreError> {
            .success(mode)
        }

        func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, ApCoreError> {
            .success(physicalWidth)
        }

        func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
            visibleFrame
        }
    }

    /// AeroSpace stub that makes selectProject succeed with minimal ceremony.
    private final class SimpleAeroSpaceStub: AeroSpaceProviding {
        let projectId: String
        let ideWindowId: Int
        let chromeWindowId: Int
        var allWindows: [ApWindow] = []
        private var focusedWindowResult: Result<ApWindow, ApCoreError>

        init(projectId: String, ideWindowId: Int = 101, chromeWindowId: Int = 100) {
            self.projectId = projectId
            self.ideWindowId = ideWindowId
            self.chromeWindowId = chromeWindowId
            self.focusedWindowResult = .success(ApWindow(
                windowId: ideWindowId,
                appBundleId: "com.microsoft.VSCode",
                workspace: "ap-\(projectId)",
                windowTitle: "AP:\(projectId) - VS Code"
            ))
        }

        private var chromeWindow: ApWindow {
            ApWindow(windowId: chromeWindowId, appBundleId: "com.google.Chrome",
                     workspace: "ap-\(projectId)", windowTitle: "AP:\(projectId) - Chrome")
        }
        private var ideWindow: ApWindow {
            ApWindow(windowId: ideWindowId, appBundleId: "com.microsoft.VSCode",
                     workspace: "ap-\(projectId)", windowTitle: "AP:\(projectId) - VS Code")
        }

        func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
        func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
        func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }

        func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> {
            .success([ApWorkspaceSummary(workspace: "ap-\(projectId)", isFocused: true)])
        }

        func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
        func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }

        func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> {
            if bundleId == "com.google.Chrome" { return .success([chromeWindow]) }
            if bundleId == "com.microsoft.VSCode" { return .success([ideWindow]) }
            return .success([])
        }

        func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
            .success([chromeWindow, ideWindow])
        }
        func listAllWindows() -> Result<[ApWindow], ApCoreError> {
            if !allWindows.isEmpty {
                return .success(allWindows)
            }
            return .success([chromeWindow, ideWindow])
        }

        func focusedWindow() -> Result<ApWindow, ApCoreError> { focusedWindowResult }
        func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
            let candidates = allWindows.isEmpty ? [chromeWindow, ideWindow] : allWindows
            if let window = candidates.first(where: { $0.windowId == windowId }) {
                focusedWindowResult = .success(window)
            }
            return .success(())
        }
        func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> { .success(()) }
        func focusWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
    }

    // MARK: - Helpers

    private func makeManager(
        aerospace: AeroSpaceProviding,
        windowPositioner: WindowPositioning? = nil,
        windowPositionStore: WindowPositionStoring? = nil,
        screenModeDetector: ScreenModeDetecting? = nil
    ) -> ProjectManager {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let chromeTabsDir = tmp.appendingPathComponent("pm-window-tabs-\(UUID().uuidString)", isDirectory: true)
        let recencyPath = tmp.appendingPathComponent("pm-window-recency-\(UUID().uuidString).json")
        let focusHistoryPath = tmp.appendingPathComponent("pm-window-focus-\(UUID().uuidString).json")
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: NoopIdeLauncher(),
            agentLayerIdeLauncher: NoopIdeLauncher(),
            chromeLauncher: NoopChromeLauncher(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: NoopTabCapture(),
            gitRemoteResolver: NoopGitRemoteResolver(),
            logger: NoopLogger(),
            recencyFilePath: recencyPath,
            focusHistoryFilePath: focusHistoryPath,
            windowPositioner: windowPositioner,
            windowPositionStore: windowPositionStore,
            screenModeDetector: screenModeDetector
        )
    }

    private let defaultIdeFrame = CGRect(x: 100, y: 200, width: 1200, height: 800)
    private let defaultChromeFrame = CGRect(x: 1400, y: 200, width: 1100, height: 800)

    // MARK: - selectProject Tests

    func testSelectProjectPositionsWindowsWithComputedLayout() async {
        let projectId = "alpha"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        // Configure positioner: getPrimaryWindowFrame succeeds for IDE (used to determine monitor)
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let success):
            XCTAssertNil(success.layoutWarning, "No layout warning expected for successful positioning")
            XCTAssertEqual(success.ideWindowId, 101)
        }

        // Verify setWindowFrames was called for both IDE and Chrome
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
        XCTAssertEqual(positioner.setFrameCalls[0].bundleId, "com.microsoft.VSCode")
        XCTAssertEqual(positioner.setFrameCalls[1].bundleId, "com.google.Chrome")
    }

    func testSelectProjectUsesSavedFramesWhenAvailable() async {
        let projectId = "beta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let savedFrames = SavedWindowFrames(
            ide: SavedFrame(x: 50, y: 50, width: 1000, height: 700),
            chrome: SavedFrame(x: 1100, y: 50, width: 900, height: 700)
        )
        store.loadResults["\(projectId)|wide"] = .success(savedFrames)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Beta", path: "/tmp/beta", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success, got: \(error)") }

        // Verify the IDE was positioned using saved (clamped) frame, not computed
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
        let ideCall = positioner.setFrameCalls[0]
        XCTAssertEqual(ideCall.primaryFrame.origin.x, 50, accuracy: 1)
    }

    func testSelectProjectReturnsLayoutWarningOnIDEFrameReadFailure() async {
        let projectId = "gamma"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        // IDE frame read fails
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] =
            .failure(ApCoreError(category: .window, message: "AX timeout"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Gamma", path: "/tmp/gamma", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Activation should succeed even when positioning fails: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should have a layout warning")
            XCTAssertTrue(success.layoutWarning?.contains("AX timeout") == true)
        }
    }

    func testSelectProjectSkipsPositioningWhenNoPositioner() async {
        let projectId = "delta"
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        // No positioner/detector/store → positioning disabled
        let manager = makeManager(aerospace: aerospace)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Delta", path: "/tmp/delta", color: "yellow", useAgentLayer: false)],
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
    }

    // MARK: - closeProject Tests

    func testCloseProjectCapturesWindowPositions() {
        let projectId = "epsilon"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(defaultChromeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Epsilon", path: "/tmp/epsilon", color: "purple", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = manager.closeProject(projectId: projectId)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Verify positions were saved
        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertEqual(store.saveCalls[0].projectId, projectId)
        XCTAssertEqual(store.saveCalls[0].mode, .wide)
        XCTAssertEqual(store.saveCalls[0].frames.ide.x, Double(defaultIdeFrame.origin.x), accuracy: 1)
        XCTAssertEqual(store.saveCalls[0].frames.chrome!.x, Double(defaultChromeFrame.origin.x), accuracy: 1)
    }

    func testCloseProjectSkipsSaveWhenIDEFrameReadFails() {
        let projectId = "zeta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        // IDE frame read fails — should not save
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] =
            .failure(ApCoreError(category: .window, message: "gone"))
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(defaultChromeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Zeta", path: "/tmp/zeta", color: "orange", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        XCTAssertTrue(store.saveCalls.isEmpty, "Should not save when IDE frame unreadable")
    }

    func testCloseProjectSavesIDEOnlyWhenChromeFrameReadFails() {
        let projectId = "eta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] =
            .failure(ApCoreError(category: .window, message: "gone"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Eta", path: "/tmp/eta", color: "cyan", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Should save IDE-only (partial save) when Chrome frame unreadable
        XCTAssertEqual(store.saveCalls.count, 1, "Should save IDE-only when Chrome frame fails")
        XCTAssertEqual(store.saveCalls[0].projectId, projectId)
        XCTAssertEqual(store.saveCalls[0].frames.ide.x, Double(defaultIdeFrame.origin.x), accuracy: 1)
        XCTAssertNil(store.saveCalls[0].frames.chrome, "Chrome frame should be nil in partial save")
    }

    // MARK: - exitToNonProjectWindow Tests

    func testExitCapturesWindowPositionsBeforeFocusRestore() {
        let projectId = "theta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(defaultChromeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Theta", path: "/tmp/theta", color: "pink", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Push a non-project focus entry for exit to restore
        manager.pushFocusForTest(CapturedFocus(windowId: 42, appBundleId: "com.other", workspace: "main"))

        let result = manager.exitToNonProjectWindow()

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertEqual(store.saveCalls[0].projectId, projectId)
    }

    func testExitSkipsCaptureWhenNoPositioner() {
        let projectId = "iota"
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        let manager = makeManager(aerospace: aerospace)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Iota", path: "/tmp/iota", color: "white", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Push a non-project focus entry
        manager.pushFocusForTest(CapturedFocus(windowId: 42, appBundleId: "com.other", workspace: "main"))

        let result = manager.exitToNonProjectWindow()
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }
        // No crash = positioning gracefully skipped
    }

    // MARK: - Screen Mode Fallback Tests

    func testPositioningFallsToWideOnScreenModeDetectionFailure() async {
        let projectId = "kappa"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Detector that fails on mode detection
        struct FailingDetector: ScreenModeDetecting {
            func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, ApCoreError> {
                .failure(ApCoreError(category: .system, message: "EDID broken"))
            }
            func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, ApCoreError> {
                .failure(ApCoreError(category: .system, message: "EDID broken"))
            }
            func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
                CGRect(x: 0, y: 0, width: 2560, height: 1415)
            }
        }

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: FailingDetector()
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Kappa", path: "/tmp/kappa", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        // Should succeed (non-fatal) — used .wide fallback
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Verify it still positioned windows (using .wide mode and 32.0 inch fallback)
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
    }

    func testPositioningSkippedWhenScreenNotFound() async {
        let projectId = "lambda"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Detector that returns nil for screen
        struct NoScreenDetector: ScreenModeDetecting {
            func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, ApCoreError> {
                .success(.wide)
            }
            func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, ApCoreError> {
                .success(27.0)
            }
            func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
                nil
            }
        }

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: NoScreenDetector()
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Lambda", path: "/tmp/lambda", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("screen not found") == true)
        }

        // No setWindowFrames calls since positioning was skipped
        XCTAssertTrue(positioner.setFrameCalls.isEmpty)
    }

    // MARK: - Store Load Failure Fallback

    func testPositioningUsesComputedLayoutOnStoreLoadFailure() async {
        let projectId = "mu"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Store load fails
        store.loadResults["\(projectId)|wide"] = .failure(ApCoreError(category: .fileSystem, message: "corrupt"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Mu", path: "/tmp/mu", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Should still have positioned using computed layout
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
    }

    // MARK: - Partial Write Failure Tests

    func testPartialIDEWriteFailureProducesWarning() async {
        let projectId = "nu"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        // IDE: 1 of 3 positioned (partial failure)
        positioner.setFrameResults["com.microsoft.VSCode|\(projectId)"] =
            .success(WindowPositionResult(positioned: 1, matched: 3))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Nu", path: "/tmp/nu", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should have a layout warning for partial failure")
            XCTAssertTrue(success.layoutWarning?.contains("1 of 3") == true,
                          "Warning should mention positioned/matched counts: \(success.layoutWarning ?? "")")
        }
    }

    func testPartialChromeWriteFailureProducesWarning() async {
        let projectId = "xi"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        // Chrome: 2 of 5 positioned (partial failure)
        positioner.setFrameResults["com.google.Chrome|\(projectId)"] =
            .success(WindowPositionResult(positioned: 2, matched: 5))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Xi", path: "/tmp/xi", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should have a layout warning for partial Chrome failure")
            XCTAssertTrue(success.layoutWarning?.contains("2 of 5") == true,
                          "Warning should mention Chrome partial failure: \(success.layoutWarning ?? "")")
        }
    }

    func testZeroPositionedProducesWarning() async {
        let projectId = "omicron"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        // IDE: 0 of 0 (no matching windows found, but set returned success)
        positioner.setFrameResults["com.microsoft.VSCode|\(projectId)"] =
            .success(WindowPositionResult(positioned: 0, matched: 0))
        positioner.setFrameResults["com.google.Chrome|\(projectId)"] =
            .success(WindowPositionResult(positioned: 0, matched: 0))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Omicron", path: "/tmp/omicron", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should warn when zero windows positioned")
            XCTAssertTrue(success.layoutWarning?.contains("no windows") == true,
                          "Warning should mention zero positioned: \(success.layoutWarning ?? "")")
        }
    }

    // MARK: - Partial Dependency Wiring Tests

    func testPartialDependencyWiringProducesWarning() async {
        let projectId = "pi"
        let positioner = RecordingWindowPositioner()
        // Provide positioner + detector but NO store → partial deps
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: nil,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Pi", path: "/tmp/pi", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should warn about partial dependency wiring")
            XCTAssertTrue(success.layoutWarning?.contains("windowPositionStore") == true,
                          "Warning should name the missing dependency: \(success.layoutWarning ?? "")")
        }

        // setWindowFrames should NOT have been called (positioning disabled)
        XCTAssertTrue(positioner.setFrameCalls.isEmpty)
    }

    func testPartialDependencyWiringOnlyStoreProducesWarning() async {
        let projectId = "rho"
        let store = RecordingPositionStore()
        // Only store — no positioner or detector
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: nil,
            windowPositionStore: store,
            screenModeDetector: nil
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Rho", path: "/tmp/rho", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should warn about partial deps")
            XCTAssertTrue(success.layoutWarning?.contains("windowPositioner") == true)
            XCTAssertTrue(success.layoutWarning?.contains("screenModeDetector") == true)
        }
    }

    // MARK: - Physical Width Fallback Tests

    func testPhysicalWidthFallbackProducesWarning() async {
        let projectId = "sigma"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Detector that fails on physicalWidthInches but succeeds on everything else
        struct PhysicalWidthFailingDetector: ScreenModeDetecting {
            func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, ApCoreError> {
                .success(.wide)
            }
            func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, ApCoreError> {
                .failure(ApCoreError(category: .system, message: "EDID not available"))
            }
            func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
                CGRect(x: 0, y: 0, width: 2560, height: 1415)
            }
        }

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: PhysicalWidthFailingDetector()
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Sigma", path: "/tmp/sigma", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should warn about physical width fallback")
            XCTAssertTrue(success.layoutWarning?.contains("32\"") == true,
                          "Warning should mention 32\" fallback: \(success.layoutWarning ?? "")")
        }

        // Should still have positioned windows despite fallback
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
    }

    // MARK: - Capture-on-Switch Tests (project-to-project)

    func testSelectProjectCapturesSourceProjectPositionsOnSwitch() async {
        let sourceId = "alpha"
        let targetId = "beta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()

        // Stub supports target project for activation
        let aerospace = SimpleAeroSpaceStub(projectId: targetId)

        // Configure positioner for source project capture (IDE + Chrome reads)
        positioner.getFrameResults["com.microsoft.VSCode|\(sourceId)"] = .success(defaultIdeFrame)
        positioner.getFrameResults["com.google.Chrome|\(sourceId)"] = .success(defaultChromeFrame)
        // Configure positioner for target project positioning
        positioner.getFrameResults["com.microsoft.VSCode|\(targetId)"] = .success(defaultIdeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [
                ProjectConfig(id: sourceId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false),
                ProjectConfig(id: targetId, name: "Beta", path: "/tmp/beta", color: "red", useAgentLayer: false)
            ],
            chrome: ChromeConfig()
        ))

        // Pre-captured focus is from source project workspace (ap-alpha)
        let preFocus = CapturedFocus(windowId: 50, appBundleId: "com.microsoft.VSCode", workspace: "ap-\(sourceId)")
        let result = await manager.selectProject(projectId: targetId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Verify source project positions were captured before switching
        XCTAssertEqual(store.saveCalls.count, 1, "Should capture source project positions on switch")
        XCTAssertEqual(store.saveCalls[0].projectId, sourceId)
        XCTAssertEqual(store.saveCalls[0].frames.ide.x, Double(defaultIdeFrame.origin.x), accuracy: 1)
        XCTAssertEqual(store.saveCalls[0].frames.chrome!.x, Double(defaultChromeFrame.origin.x), accuracy: 1)
    }

    func testSelectProjectDoesNotCaptureWhenSourceIsNonProjectWorkspace() async {
        let targetId = "gamma"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: targetId)

        positioner.getFrameResults["com.microsoft.VSCode|\(targetId)"] = .success(defaultIdeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: targetId, name: "Gamma", path: "/tmp/gamma", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Pre-captured focus is from a non-project workspace (e.g., "main")
        let preFocus = CapturedFocus(windowId: 1, appBundleId: "com.apple.finder", workspace: "main")
        let result = await manager.selectProject(projectId: targetId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // No capture should have happened — source is not a project workspace
        XCTAssertTrue(store.saveCalls.isEmpty, "Should not capture when source is non-project workspace")
    }

    // MARK: - Partial Restore Tests (saved IDE + computed Chrome)

    func testSelectProjectUsesSavedIDEAndComputedChromeWhenChromeIsNil() async {
        let projectId = "delta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Saved frames with IDE only (Chrome is nil — partial save from earlier)
        let ideOnlyFrames = SavedWindowFrames(
            ide: SavedFrame(x: 50, y: 50, width: 1000, height: 700),
            chrome: nil
        )
        store.loadResults["\(projectId)|wide"] = .success(ideOnlyFrames)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Delta", path: "/tmp/delta", color: "yellow", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Verify both IDE and Chrome were positioned
        XCTAssertEqual(positioner.setFrameCalls.count, 2)

        // IDE should use saved frame (clamped)
        let ideCall = positioner.setFrameCalls[0]
        XCTAssertEqual(ideCall.bundleId, "com.microsoft.VSCode")
        XCTAssertEqual(ideCall.primaryFrame.origin.x, 50, accuracy: 1)

        // Chrome should use computed frame (not saved, since chrome was nil)
        let chromeCall = positioner.setFrameCalls[1]
        XCTAssertEqual(chromeCall.bundleId, "com.google.Chrome")
        // Computed frame should NOT be at x=50 (that was the saved IDE position)
        // It should be from WindowLayoutEngine.computeLayout
        XCTAssertNotEqual(chromeCall.primaryFrame.origin.x, 50, accuracy: 1,
                          "Chrome should use computed layout, not saved IDE position")
    }
}
