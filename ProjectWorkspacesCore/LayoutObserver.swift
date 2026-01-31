import ApplicationServices
import Foundation

/// Context required to observe layout changes for a project.
struct LayoutObservationContext {
    let projectId: String
    let displayMode: DisplayMode
    let environment: LayoutEnvironment
    let ideWindowId: Int
    let chromeWindowId: Int
    let ideElement: AXUIElement
    let chromeElement: AXUIElement
    let initialLayout: ProjectLayout
}

/// Provides layout observation lifecycle control.
protocol LayoutObserving {
    /// Starts observing layout changes for the current activation.
    /// - Parameters:
    ///   - context: Observation context for the activated project.
    ///   - warningSink: Receives non-fatal warnings emitted by observation.
    /// - Returns: Immediate warnings produced while registering observers.
    func startObserving(
        context: LayoutObservationContext,
        warningSink: @escaping (ActivationWarning) -> Void
    ) -> [ActivationWarning]
    /// Stops observing layout changes and releases any observer tokens.
    func stopObserving()
}

/// Debounce scheduler abstraction for testing.
protocol DebounceScheduling {
    /// Schedules an action after the delay, returning a cancelable token.
    /// - Parameters:
    ///   - delaySeconds: Delay in seconds before the action runs.
    ///   - action: Action to run after the delay.
    /// - Returns: Token that can cancel the scheduled work.
    func schedule(after delaySeconds: TimeInterval, action: @escaping () -> Void) -> DebounceToken
    /// Cancels a previously scheduled action.
    /// - Parameter token: Token returned by `schedule`.
    func cancel(_ token: DebounceToken)
}

/// Opaque debounce token.
final class DebounceToken {
    fileprivate let workItem: DispatchWorkItem?
    fileprivate let id: UUID = UUID()

    init(workItem: DispatchWorkItem?) {
        self.workItem = workItem
    }
}

/// Default debounce scheduler backed by DispatchQueue.
struct DispatchDebounceScheduler: DebounceScheduling {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    func schedule(after delaySeconds: TimeInterval, action: @escaping () -> Void) -> DebounceToken {
        let workItem = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + delaySeconds, execute: workItem)
        return DebounceToken(workItem: workItem)
    }

    func cancel(_ token: DebounceToken) {
        token.workItem?.cancel()
    }
}

/// Observes window move/resize and persists layout changes.
final class LayoutObserver: LayoutObserving {
    private let windowManager: AccessibilityWindowManaging
    private let stateStore: StateStoring
    private let layoutEngine: LayoutEngine
    private let scheduler: DebounceScheduling
    private let debounceDelaySeconds: TimeInterval
    private let epsilon: Double

    private var session: ObservationSession?

    init(
        windowManager: AccessibilityWindowManaging = AccessibilityWindowManager(),
        stateStore: StateStoring = StateStore(),
        layoutEngine: LayoutEngine = LayoutEngine(),
        scheduler: DebounceScheduling = DispatchDebounceScheduler(),
        debounceDelaySeconds: TimeInterval = 0.5,
        epsilon: Double = 0.001
    ) {
        self.windowManager = windowManager
        self.stateStore = stateStore
        self.layoutEngine = layoutEngine
        self.scheduler = scheduler
        self.debounceDelaySeconds = debounceDelaySeconds
        self.epsilon = epsilon
    }

    /// Starts observing move/resize events for the current layout context.
    /// - Parameters:
    ///   - context: Observation context for the activated project.
    ///   - warningSink: Receives non-fatal warnings emitted by observation.
    /// - Returns: Immediate warnings produced while registering observers.
    func startObserving(
        context: LayoutObservationContext,
        warningSink: @escaping (ActivationWarning) -> Void
    ) -> [ActivationWarning] {
        var immediateWarnings: [ActivationWarning] = []
        stopObserving()
        let session = ObservationSession(
            context: context,
            warningSink: warningSink,
            epsilon: epsilon
        )
        self.session = session

        let notifications: [CFString] = [kAXMovedNotification as CFString, kAXResizedNotification as CFString]

        let ideObserver = windowManager.addObserver(
            for: context.ideElement,
            notifications: notifications
        ) { [weak self] in
            self?.handleWindowEvent(kind: .ide)
        }

        if case .success(let token) = ideObserver {
            session.ideObserverToken = token
        } else if case .failure(let error) = ideObserver {
            immediateWarnings.append(
                .layoutObserverFailed(kind: .ide, windowId: context.ideWindowId, detail: "\(error)")
            )
        }

        let chromeObserver = windowManager.addObserver(
            for: context.chromeElement,
            notifications: notifications
        ) { [weak self] in
            self?.handleWindowEvent(kind: .chrome)
        }

        if case .success(let token) = chromeObserver {
            session.chromeObserverToken = token
        } else if case .failure(let error) = chromeObserver {
            immediateWarnings.append(
                .layoutObserverFailed(kind: .chrome, windowId: context.chromeWindowId, detail: "\(error)")
            )
        }
        return immediateWarnings
    }

    /// Stops active observation and clears any debounced saves.
    func stopObserving() {
        guard let session else { return }
        if let ideToken = session.ideObserverToken {
            windowManager.removeObserver(ideToken)
        }
        if let chromeToken = session.chromeObserverToken {
            windowManager.removeObserver(chromeToken)
        }
        if let debounceToken = session.debounceToken {
            scheduler.cancel(debounceToken)
        }
        self.session = nil
    }

    private func handleWindowEvent(kind: ActivationWindowKind) {
        guard let session else { return }
        let context = session.context

        let element: AXUIElement
        let windowId: Int
        switch kind {
        case .ide:
            element = context.ideElement
            windowId = context.ideWindowId
        case .chrome:
            element = context.chromeElement
            windowId = context.chromeWindowId
        }

        let frameResult = windowManager.frame(
            of: element,
            mainDisplayHeightPoints: context.environment.mainDisplayHeightPoints
        )
        guard case .success(let frame) = frameResult else {
            if case .failure(let error) = frameResult {
                session.warningSink(.layoutPersistFailed(detail: "Failed to read frame for window \(windowId): \(error)"))
            }
            return
        }

        if !layoutEngine.isFrameOnMainDisplay(frame, mainFramePoints: context.environment.mainFramePoints) {
            if !session.warnedOffMain.contains(kind) {
                session.warnedOffMain.insert(kind)
                session.warningSink(.windowOffMainDisplay(kind: kind, windowId: windowId))
            }
            return
        }

        let normalizedResult = Result { try layoutEngine.normalize(frame, in: context.environment.visibleFramePoints) }
        guard case .success(let normalized) = normalizedResult else {
            if case .failure(let error) = normalizedResult {
                session.warningSink(.layoutPersistFailed(detail: "Failed to normalize frame for window \(windowId): \(error)"))
            }
            return
        }

        let didChange: Bool
        switch kind {
        case .ide:
            didChange = session.updateIdeRectIfNeeded(normalized)
        case .chrome:
            didChange = session.updateChromeRectIfNeeded(normalized)
        }

        guard didChange else { return }

        if let debounceToken = session.debounceToken {
            scheduler.cancel(debounceToken)
        }

        session.debounceToken = scheduler.schedule(after: debounceDelaySeconds) { [weak self] in
            self?.persistLayoutIfNeeded()
        }
    }

    private func persistLayoutIfNeeded() {
        guard let session else { return }
        guard let layout = session.latestLayout else { return }

        let loadResult = stateStore.load()
        var state: LayoutState

        switch loadResult {
        case .success(let outcome):
            switch outcome {
            case .loaded(let loaded):
                state = loaded
            case .missing:
                state = .empty()
            case .recovered(let recovered, let backupPath):
                state = recovered
                session.warningSink(.stateRecovered(backupPath: backupPath))
            }
        case .failure(let error):
            session.warningSink(.layoutPersistFailed(detail: "State load failed during persistence: \(error)"))
            return
        }

        var projectState = state.projects[session.context.projectId] ?? ProjectState()
        projectState.managed = ManagedWindowState(
            ideWindowId: session.context.ideWindowId,
            chromeWindowId: session.context.chromeWindowId
        )
        projectState.layouts.setLayout(layout, for: session.context.displayMode)
        state.projects[session.context.projectId] = projectState

        if case .failure(let error) = stateStore.save(state) {
            session.warningSink(.layoutPersistFailed(detail: "State save failed: \(error)"))
        }
    }

    private final class ObservationSession {
        let context: LayoutObservationContext
        let warningSink: (ActivationWarning) -> Void
        let epsilon: Double
        var ideObserverToken: AccessibilityObservationToken?
        var chromeObserverToken: AccessibilityObservationToken?
        var debounceToken: DebounceToken?
        var warnedOffMain: Set<ActivationWindowKind> = []

        private(set) var latestLayout: ProjectLayout?

        init(context: LayoutObservationContext, warningSink: @escaping (ActivationWarning) -> Void, epsilon: Double) {
            self.context = context
            self.warningSink = warningSink
            self.epsilon = epsilon
            self.latestLayout = context.initialLayout
        }

        func updateIdeRectIfNeeded(_ rect: NormalizedRect) -> Bool {
            guard var current = latestLayout else { return false }
            if approximatelyEqual(current.ideRect, rect) {
                return false
            }
            current = ProjectLayout(ideRect: rect, chromeRect: current.chromeRect)
            latestLayout = current
            return true
        }

        func updateChromeRectIfNeeded(_ rect: NormalizedRect) -> Bool {
            guard var current = latestLayout else { return false }
            if approximatelyEqual(current.chromeRect, rect) {
                return false
            }
            current = ProjectLayout(ideRect: current.ideRect, chromeRect: rect)
            latestLayout = current
            return true
        }

        private func approximatelyEqual(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Bool {
            abs(lhs.x - rhs.x) < epsilon &&
                abs(lhs.y - rhs.y) < epsilon &&
                abs(lhs.width - rhs.width) < epsilon &&
                abs(lhs.height - rhs.height) < epsilon
        }
    }
}
