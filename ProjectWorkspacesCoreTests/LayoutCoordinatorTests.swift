import ApplicationServices
import CoreGraphics
import Foundation
import XCTest

@testable import ProjectWorkspacesCore

final class LayoutCoordinatorTests: XCTestCase {
    func testApplyLayoutPersistsWhenPersistedLayoutExistsAndWindowOffMain() throws {
        let mainFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let displayInfo = DisplayInfo(
            displayId: 1,
            pixelWidth: 1920,
            framePoints: mainFrame,
            visibleFramePoints: visibleFrame,
            screenCount: 1
        )
        let layoutEngine = LayoutEngine(displayInfoProvider: TestDisplayInfoProvider(info: displayInfo))

        let ideRect = try NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let chromeRect = try NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let persistedLayout = ProjectLayout(ideRect: ideRect, chromeRect: chromeRect)

        let projectState = ProjectState(
            managed: ManagedWindowState(ideWindowId: 101, chromeWindowId: 202),
            layouts: LayoutsByDisplayMode(laptop: persistedLayout, ultrawide: nil)
        )
        let state = LayoutState(projects: ["hydroponics": projectState])

        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = TestFileSystem()
        let encoded = try JSONEncoder().encode(state)
        fileSystem.addFile(at: paths.stateFile.path, data: encoded)
        let stateStore = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        let ideElement = AXUIElementCreateSystemWide()
        let chromeElement = AXUIElementCreateApplication(getpid())
        let windowManager = TestWindowManager(
            focusedElements: [ideElement, chromeElement],
            frames: [
                ObjectIdentifier(ideElement): CGRect(x: 0, y: 0, width: 50, height: 100),
                ObjectIdentifier(chromeElement): CGRect(x: 200, y: 0, width: 50, height: 100)
            ]
        )

        let observer = TestLayoutObserver()
        let logger = TestLogger()
        let coordinator = LayoutCoordinator(
            stateStore: stateStore,
            layoutEngine: layoutEngine,
            windowManager: windowManager,
            layoutObserver: observer,
            logger: logger
        )

        let focusResult: Result<CommandResult, AeroSpaceCommandError> = .success(CommandResult(exitCode: 0, stdout: "", stderr: ""))
        let runner = SequencedAeroSpaceCommandRunner(responses: [
            AeroSpaceCommandSignature(path: TestConstants.aerospacePath, arguments: ["focus", "--window-id", "101"]): [focusResult],
            AeroSpaceCommandSignature(path: TestConstants.aerospacePath, arguments: ["focus", "--window-id", "202"]): [focusResult]
        ])
        let client = AeroSpaceClient(
            executableURL: URL(fileURLWithPath: TestConstants.aerospacePath),
            commandRunner: runner,
            timeoutSeconds: 1,
            clock: SystemDateProvider(),
            sleeper: TestSleeper(),
            jitterProvider: SystemAeroSpaceJitterProvider(),
            retryPolicy: .standard,
            windowDecoder: AeroSpaceWindowDecoder()
        )

        let config = Config(
            global: GlobalConfig(defaultIde: .vscode, globalChromeUrls: []),
            display: DisplayConfig(ultrawideMinWidthPx: 5000),
            ide: IdeConfig(vscode: IdeAppConfig(appPath: nil, bundleId: nil), antigravity: nil),
            projects: []
        )

        _ = coordinator.applyLayout(
            projectId: "hydroponics",
            config: config,
            ideWindow: ActivatedWindow(windowId: 101, wasCreated: false),
            chromeWindow: ActivatedWindow(windowId: 202, wasCreated: false),
            client: client
        )

        let storedData = try XCTUnwrap(fileSystem.fileData(atPath: paths.stateFile.path))
        let decoded = try JSONDecoder().decode(LayoutState.self, from: storedData)
        let savedLayout = decoded.projects["hydroponics"]?.layouts.layout(for: .laptop)

        XCTAssertEqual(savedLayout, persistedLayout)
        XCTAssertNotNil(observer.lastContext)
        XCTAssertNotNil(windowManager.setFrames[ObjectIdentifier(ideElement)])
        XCTAssertNil(windowManager.setFrames[ObjectIdentifier(chromeElement)])
    }
}

private struct TestDisplayInfoProvider: DisplayInfoProviding {
    let info: DisplayInfo

    func mainDisplayInfo() throws -> DisplayInfo {
        info
    }
}

private final class TestLayoutObserver: LayoutObserving {
    private(set) var lastContext: LayoutObservationContext?
    private(set) var stopCount: Int = 0

    func startObserving(
        context: LayoutObservationContext,
        warningSink _: @escaping (ActivationWarning) -> Void
    ) -> [ActivationWarning] {
        lastContext = context
        return []
    }

    func stopObserving() {
        stopCount += 1
    }
}

private final class TestWindowManager: AccessibilityWindowManaging {
    private var focusedElements: [AXUIElement]
    private var focusedIndex: Int = 0
    private var frames: [ObjectIdentifier: CGRect]
    private(set) var setFrames: [ObjectIdentifier: CGRect] = [:]

    init(focusedElements: [AXUIElement], frames: [ObjectIdentifier: CGRect]) {
        self.focusedElements = focusedElements
        self.frames = frames
    }

    func focusedWindowElement() -> Result<AXUIElement, AccessibilityWindowError> {
        guard focusedIndex < focusedElements.count else {
            return .failure(.focusedWindowUnavailable("No focused element"))
        }
        let element = focusedElements[focusedIndex]
        focusedIndex += 1
        return .success(element)
    }

    func element(for windowId: Int) -> Result<AXUIElement, AccessibilityWindowError> {
        guard focusedIndex < focusedElements.count else {
            return .failure(.windowNotFound(windowId))
        }
        let element = focusedElements[focusedIndex]
        focusedIndex += 1
        return .success(element)
    }

    func frame(of element: AXUIElement, mainDisplayHeightPoints _: CGFloat) -> Result<CGRect, AccessibilityWindowError> {
        guard let frame = frames[ObjectIdentifier(element)] else {
            return .failure(.attributeReadFailed("Missing frame"))
        }
        return .success(frame)
    }

    func setFrame(
        _ frame: CGRect,
        for element: AXUIElement,
        mainDisplayHeightPoints _: CGFloat
    ) -> Result<Void, AccessibilityWindowError> {
        setFrames[ObjectIdentifier(element)] = frame
        return .success(())
    }

    func addObserver(
        for _: AXUIElement,
        notifications _: [CFString],
        handler _: @escaping () -> Void
    ) -> Result<AccessibilityObservationToken, AccessibilityWindowError> {
        .success(TestObserverToken())
    }

    func removeObserver(_ token: AccessibilityObservationToken) {
        token.invalidate()
    }
}

private final class TestObserverToken: AccessibilityObservationToken {
    func invalidate() {}
}

private struct FixedDateProvider: DateProviding {
    let date: Date

    init(date: Date = Date(timeIntervalSince1970: 0)) {
        self.date = date
    }

    func now() -> Date {
        date
    }
}
