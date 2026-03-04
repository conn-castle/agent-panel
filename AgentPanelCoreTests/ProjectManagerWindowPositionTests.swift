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
        /// Sequential results: each call shifts the first element. When empty, falls back to getFrameResults.
        var getFrameSequences: [String: [Result<CGRect, ApCoreError>]] = [:]
        var setFrameResults: [String: Result<WindowPositionResult, ApCoreError>] = [:]
        /// Sequential results for setWindowFrames.
        var setFrameSequences: [String: [Result<WindowPositionResult, ApCoreError>]] = [:]
        var trusted: Bool = true
        private(set) var setFrameCalls: [(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffset: CGFloat)] = []
        private(set) var getFrameCalls: [(bundleId: String, projectId: String)] = []

        // Fallback method support
        var getFallbackFrameResults: [String: Result<CGRect, ApCoreError>] = [:]
        var setFallbackFrameResults: [String: Result<WindowPositionResult, ApCoreError>] = [:]
        private(set) var getFallbackFrameCalls: [String] = []
        private(set) var setFallbackFrameCalls: [(bundleId: String, primaryFrame: CGRect)] = []

        func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, ApCoreError> {
            getFrameCalls.append((bundleId, projectId))
            let key = "\(bundleId)|\(projectId)"
            if var seq = getFrameSequences[key], !seq.isEmpty {
                let result = seq.removeFirst()
                getFrameSequences[key] = seq
                return result
            }
            return getFrameResults[key] ?? .failure(ApCoreError(category: .window, message: "no stub for \(key)"))
        }

        func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, ApCoreError> {
            setFrameCalls.append((bundleId, projectId, primaryFrame, cascadeOffsetPoints))
            let key = "\(bundleId)|\(projectId)"
            if var seq = setFrameSequences[key], !seq.isEmpty {
                let result = seq.removeFirst()
                setFrameSequences[key] = seq
                return result
            }
            return setFrameResults[key] ?? .success(WindowPositionResult(positioned: 1, matched: 1))
        }

        func getFallbackWindowFrame(bundleId: String) -> Result<CGRect, ApCoreError> {
            getFallbackFrameCalls.append(bundleId)
            return getFallbackFrameResults[bundleId] ?? .failure(ApCoreError(category: .window, message: "Fallback not available"))
        }

        func setFallbackWindowFrames(bundleId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, ApCoreError> {
            setFallbackFrameCalls.append((bundleId, primaryFrame))
            return setFallbackFrameResults[bundleId] ?? .failure(ApCoreError(category: .window, message: "Fallback not available"))
        }

        var recoverWindowCalls: [(bundleId: String, windowTitle: String)] = []
        var recoverWindowResult: Result<RecoveryOutcome, ApCoreError> = .success(.unchanged)
        func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, ApCoreError> {
            recoverWindowCalls.append((bundleId: bundleId, windowTitle: windowTitle))
            return recoverWindowResult
        }

        var recoverFocusedCalls: [(bundleId: String, screenFrame: CGRect)] = []
        var recoverFocusedResult: Result<RecoveryOutcome, ApCoreError> = .success(.unchanged)
        func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, ApCoreError> {
            recoverFocusedCalls.append((bundleId, screenVisibleFrame))
            return recoverFocusedResult
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
        screenModeDetector: ScreenModeDetecting? = nil,
        windowPollInterval: TimeInterval = 0.1
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
            screenModeDetector: screenModeDetector,
            windowPollInterval: windowPollInterval
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

    func testCloseProjectSkipsSaveWhenChromeFramePermanentlyFails() {
        let projectId = "eta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        // Permanent error (not "No window found with token") — skips save to preserve prior layout
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

        // Skip save entirely when Chrome frame unavailable — preserves previous complete layout
        XCTAssertTrue(store.saveCalls.isEmpty, "Should skip save when Chrome frame permanently unavailable")
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

        // Verify fallback was called
        XCTAssertEqual(positioner.getFallbackFrameCalls.count, 1)
        XCTAssertEqual(positioner.getFallbackFrameCalls[0], "com.microsoft.VSCode")
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

    // MARK: - Chrome Set Retry + Fallback Tests

    func testChromeSetRetriesAndSucceeds() async {
        let projectId = "cs-retry-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // Fail twice, then succeed
        positioner.setFrameSequences[chromeKey] = [
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
            projects: [ProjectConfig(id: projectId, name: "CSR", path: "/tmp/csr", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNil(success.layoutWarning, "Retry succeeded — no warning")
        }

        // IDE set + 3 Chrome set attempts
        let chromeCalls = positioner.setFrameCalls.filter { $0.bundleId == "com.google.Chrome" }
        XCTAssertEqual(chromeCalls.count, 3)
        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty, "Fallback not needed")
    }

    func testChromeSetFallbackUsedAfterRetryExhaustion() async {
        let projectId = "cs-fb-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // All 5 retries fail
        positioner.setFrameSequences[chromeKey] = Array(repeating: .failure(tokenMiss), count: 5)
        // Fallback succeeds
        positioner.setFallbackFrameResults["com.google.Chrome"] =
            .success(WindowPositionResult(positioned: 1, matched: 1))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CSFB", path: "/tmp/csfb", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            // Fallback succeeded — no warning about Chrome failure
            XCTAssertNil(success.layoutWarning)
        }

        XCTAssertEqual(positioner.setFallbackFrameCalls.count, 1)
        XCTAssertEqual(positioner.setFallbackFrameCalls[0].bundleId, "com.google.Chrome")
    }

    func testChromeSetFallbackFailureAddsWarning() async {
        let projectId = "cs-fb-2"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        positioner.setFrameSequences[chromeKey] = Array(repeating: .failure(tokenMiss), count: 5)
        // Fallback also fails
        positioner.setFallbackFrameResults["com.google.Chrome"] =
            .failure(ApCoreError(category: .window, message: "Ambiguous: 2 windows"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CSFB2", path: "/tmp/csfb2", color: "green", useAgentLayer: false)],
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

    func testChromeSetPermanentErrorSkipsFallback() async {
        let projectId = "cs-perm-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            ApWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Permanent error (not "No window found with token")
        let chromeKey = "com.google.Chrome|\(projectId)"
        positioner.setFrameResults[chromeKey] =
            .failure(ApCoreError(category: .window, message: "AX permission denied"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CSPerm", path: "/tmp/csperm", color: "blue", useAgentLayer: false)],
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

        // Permanent error: no fallback attempted, only one Chrome set call
        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty, "Permanent error should not trigger fallback")
        let chromeCalls = positioner.setFrameCalls.filter { $0.bundleId == "com.google.Chrome" }
        XCTAssertEqual(chromeCalls.count, 1, "Should only try once for permanent error")
    }

    // MARK: - Capture Retry + Fallback + Skip-Save Tests

    func testCaptureRetriesChromeReadAndSaves() {
        let projectId = "cap-retry-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // Fail twice, succeed on third
        positioner.getFrameSequences[chromeKey] = [
            .failure(tokenMiss),
            .failure(tokenMiss),
            .success(defaultChromeFrame)
        ]

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CapR", path: "/tmp/capr", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Save should have happened with both IDE and Chrome frames
        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertNotNil(store.saveCalls[0].frames.chrome)
        // Chrome read was called 3 times (2 failures + 1 success)
        let chromeGetCalls = positioner.getFrameCalls.filter { $0.bundleId == "com.google.Chrome" }
        XCTAssertEqual(chromeGetCalls.count, 3)
    }

    func testCaptureUsesChromeReadFallbackAndSaves() {
        let projectId = "cap-fb-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // All 5 retries fail
        positioner.getFrameSequences[chromeKey] = Array(repeating: .failure(tokenMiss), count: 5)
        // Fallback succeeds
        positioner.getFallbackFrameResults["com.google.Chrome"] = .success(defaultChromeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CapFB", path: "/tmp/capfb", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Save should have happened with fallback Chrome frame
        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertNotNil(store.saveCalls[0].frames.chrome)
        XCTAssertEqual(positioner.getFallbackFrameCalls.count, 1)
        XCTAssertEqual(positioner.getFallbackFrameCalls[0], "com.google.Chrome")
    }

    func testCaptureSkipsSaveWhenChromeRetryAndFallbackFail() {
        let projectId = "cap-skip-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = ApCoreError(category: .window, message: "No window found with token 'AP:\(projectId)'")
        // All 5 retries fail
        positioner.getFrameSequences[chromeKey] = Array(repeating: .failure(tokenMiss), count: 5)
        // Fallback also fails
        positioner.getFallbackFrameResults["com.google.Chrome"] =
            .failure(ApCoreError(category: .window, message: "Ambiguous: 2 windows"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CapSkip", path: "/tmp/capskip", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Skip save entirely — preserves previous complete layout
        XCTAssertTrue(store.saveCalls.isEmpty, "Should skip save when Chrome unavailable after retry+fallback")
    }
}
