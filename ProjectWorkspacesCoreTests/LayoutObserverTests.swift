import ApplicationServices
import CoreGraphics
import Foundation
import XCTest

@testable import ProjectWorkspacesCore

final class LayoutObserverTests: XCTestCase {
    func testObserverPersistsLayoutOnDebouncedChange() throws {
        let environment = LayoutEnvironment(
            displayMode: .laptop,
            visibleFramePoints: CGRect(x: 0, y: 0, width: 100, height: 100),
            mainFramePoints: CGRect(x: 0, y: 0, width: 100, height: 100),
            mainDisplayHeightPoints: 100,
            screenCount: 1
        )

        let ideRect = try NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let chromeRect = try NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let initialLayout = ProjectLayout(ideRect: ideRect, chromeRect: chromeRect)

        let ideElement = AXUIElementCreateSystemWide()
        let chromeElement = AXUIElementCreateApplication(getpid())

        let context = LayoutObservationContext(
            projectId: "hydroponics",
            displayMode: .laptop,
            environment: environment,
            ideWindowId: 101,
            chromeWindowId: 202,
            ideElement: ideElement,
            chromeElement: chromeElement,
            initialLayout: initialLayout
        )

        let paths = ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        let fileSystem = TestFileSystem()
        let stateStore = StateStore(paths: paths, fileSystem: fileSystem, dateProvider: FixedDateProvider())

        let windowManager = TestWindowManager(ideElement: ideElement, chromeElement: chromeElement)
        windowManager.ideFrame = CGRect(x: 0, y: 0, width: 50, height: 100)
        windowManager.chromeFrame = CGRect(x: 50, y: 0, width: 50, height: 100)

        let scheduler = TestDebounceScheduler()
        let observer = LayoutObserver(
            windowManager: windowManager,
            stateStore: stateStore,
            layoutEngine: LayoutEngine(),
            scheduler: scheduler,
            debounceDelaySeconds: 0.5,
            epsilon: 0.001
        )

        _ = observer.startObserving(context: context, warningSink: { _ in })

        windowManager.ideFrame = CGRect(x: 10, y: 0, width: 40, height: 100)
        windowManager.trigger(kind: .ide)

        XCTAssertNotNil(scheduler.lastScheduled)

        scheduler.fire()

        let data = try XCTUnwrap(fileSystem.fileData(atPath: paths.stateFile.path))
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        let projectState = decoded.projects["hydroponics"]
        let savedLayout = projectState?.layouts.layout(for: .laptop)
        let expectedIde = try NormalizedRect(x: 0.1, y: 0, width: 0.4, height: 1)
        let expectedLayout = ProjectLayout(ideRect: expectedIde, chromeRect: chromeRect)

        XCTAssertEqual(savedLayout, expectedLayout)
        XCTAssertEqual(projectState?.managed, ManagedWindowState(ideWindowId: 101, chromeWindowId: 202))
    }

    func testObserverIgnoresChangesWithinEpsilon() throws {
        let environment = LayoutEnvironment(
            displayMode: .laptop,
            visibleFramePoints: CGRect(x: 0, y: 0, width: 100, height: 100),
            mainFramePoints: CGRect(x: 0, y: 0, width: 100, height: 100),
            mainDisplayHeightPoints: 100,
            screenCount: 1
        )

        let ideRect = try NormalizedRect(x: 0.1, y: 0, width: 0.4, height: 1)
        let chromeRect = try NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let initialLayout = ProjectLayout(ideRect: ideRect, chromeRect: chromeRect)

        let ideElement = AXUIElementCreateSystemWide()
        let chromeElement = AXUIElementCreateApplication(getpid())

        let context = LayoutObservationContext(
            projectId: "hydroponics",
            displayMode: .laptop,
            environment: environment,
            ideWindowId: 101,
            chromeWindowId: 202,
            ideElement: ideElement,
            chromeElement: chromeElement,
            initialLayout: initialLayout
        )

        let windowManager = TestWindowManager(ideElement: ideElement, chromeElement: chromeElement)
        windowManager.ideFrame = CGRect(x: 10, y: 0, width: 40, height: 100)
        windowManager.chromeFrame = CGRect(x: 50, y: 0, width: 50, height: 100)

        let scheduler = TestDebounceScheduler()
        let observer = LayoutObserver(
            windowManager: windowManager,
            stateStore: InMemoryStateStore(),
            layoutEngine: LayoutEngine(),
            scheduler: scheduler,
            debounceDelaySeconds: 0.5,
            epsilon: 0.001
        )

        _ = observer.startObserving(context: context, warningSink: { _ in })

        windowManager.ideFrame = CGRect(x: 10.04, y: 0, width: 40, height: 100)
        windowManager.trigger(kind: .ide)

        XCTAssertNil(scheduler.lastScheduled)
    }
}

private final class TestWindowManager: AccessibilityWindowManaging {
    let ideElement: AXUIElement
    let chromeElement: AXUIElement
    var ideFrame: CGRect = .zero
    var chromeFrame: CGRect = .zero

    private var ideHandler: (() -> Void)?
    private var chromeHandler: (() -> Void)?

    init(ideElement: AXUIElement, chromeElement: AXUIElement) {
        self.ideElement = ideElement
        self.chromeElement = chromeElement
    }

    func focusedWindowElement() -> Result<AXUIElement, AccessibilityWindowError> {
        .failure(.focusedWindowUnavailable("Not used in tests"))
    }

    func element(for windowId: Int) -> Result<AXUIElement, AccessibilityWindowError> {
        .failure(.windowNotFound(windowId))
    }

    func frame(of element: AXUIElement, mainDisplayHeightPoints _: CGFloat) -> Result<CGRect, AccessibilityWindowError> {
        if CFEqual(element, ideElement) {
            return .success(ideFrame)
        }
        if CFEqual(element, chromeElement) {
            return .success(chromeFrame)
        }
        return .failure(.attributeReadFailed("Unknown element"))
    }

    func setFrame(
        _ frame: CGRect,
        for element: AXUIElement,
        mainDisplayHeightPoints _: CGFloat
    ) -> Result<Void, AccessibilityWindowError> {
        if CFEqual(element, ideElement) {
            ideFrame = frame
            return .success(())
        }
        if CFEqual(element, chromeElement) {
            chromeFrame = frame
            return .success(())
        }
        return .failure(.attributeWriteFailed("Unknown element"))
    }

    func addObserver(
        for element: AXUIElement,
        notifications _: [CFString],
        handler: @escaping () -> Void
    ) -> Result<AccessibilityObservationToken, AccessibilityWindowError> {
        if CFEqual(element, ideElement) {
            ideHandler = handler
        } else if CFEqual(element, chromeElement) {
            chromeHandler = handler
        }
        return .success(TestObserverToken())
    }

    func removeObserver(_ token: AccessibilityObservationToken) {
        token.invalidate()
    }

    func trigger(kind: ActivationWindowKind) {
        switch kind {
        case .ide:
            ideHandler?()
        case .chrome:
            chromeHandler?()
        }
    }
}

private final class TestObserverToken: AccessibilityObservationToken {
    private(set) var invalidated = false

    func invalidate() {
        invalidated = true
    }
}

private final class TestDebounceScheduler: DebounceScheduling {
    private(set) var lastScheduled: Scheduled?

    struct Scheduled {
        let delay: TimeInterval
        let action: () -> Void
        let token: DebounceToken
    }

    func schedule(after delaySeconds: TimeInterval, action: @escaping () -> Void) -> DebounceToken {
        let token = DebounceToken(workItem: nil)
        lastScheduled = Scheduled(delay: delaySeconds, action: action, token: token)
        return token
    }

    func cancel(_ token: DebounceToken) {
        if let scheduled = lastScheduled, scheduled.token === token {
            lastScheduled = nil
        }
    }

    func fire() {
        lastScheduled?.action()
        lastScheduled = nil
    }
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
