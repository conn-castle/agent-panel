import ApplicationServices
import Foundation

/// Activated window metadata used for layout decisions.
struct ActivatedWindow: Equatable {
    let windowId: Int
    let wasCreated: Bool
}

/// Coordinates layout application and observation during activation.
protocol LayoutCoordinating {
    /// Stops any active layout observers.
    func stopObserving()
    /// Applies layout and starts observation for the activated project.
    /// - Parameters:
    ///   - projectId: Identifier for the activated project.
    ///   - config: Loaded configuration for display thresholds.
    ///   - ideWindow: Activated IDE window metadata.
    ///   - chromeWindow: Activated Chrome window metadata.
    ///   - client: AeroSpace client used to focus windows.
    /// - Returns: Non-fatal activation warnings.
    func applyLayout(
        projectId: String,
        config: Config,
        ideWindow: ActivatedWindow,
        chromeWindow: ActivatedWindow,
        client: AeroSpaceClient
    ) -> [ActivationWarning]
}

/// Default layout coordinator implementation.
final class LayoutCoordinator: LayoutCoordinating {
    private let stateStore: StateStoring
    private let layoutEngine: LayoutEngine
    private let windowManager: AccessibilityWindowManaging
    private let layoutObserver: LayoutObserving
    private let logger: ProjectWorkspacesLogging

    init(
        stateStore: StateStoring = StateStore(),
        layoutEngine: LayoutEngine = LayoutEngine(),
        windowManager: AccessibilityWindowManaging = AccessibilityWindowManager(),
        layoutObserver: LayoutObserving = LayoutObserver(),
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger()
    ) {
        self.stateStore = stateStore
        self.layoutEngine = layoutEngine
        self.windowManager = windowManager
        self.layoutObserver = layoutObserver
        self.logger = logger
    }

    func stopObserving() {
        layoutObserver.stopObserving()
    }

    /// Applies layout defaults or persisted geometry, then starts observation.
    /// - Parameters:
    ///   - projectId: Identifier for the activated project.
    ///   - config: Loaded configuration for display thresholds.
    ///   - ideWindow: Activated IDE window metadata.
    ///   - chromeWindow: Activated Chrome window metadata.
    ///   - client: AeroSpace client used to focus windows.
    /// - Returns: Non-fatal activation warnings.
    func applyLayout(
        projectId: String,
        config: Config,
        ideWindow: ActivatedWindow,
        chromeWindow: ActivatedWindow,
        client: AeroSpaceClient
    ) -> [ActivationWarning] {
        var warnings: [ActivationWarning] = []

        let environment: LayoutEnvironment
        do {
            environment = try layoutEngine.resolveEnvironment(ultrawideMinWidthPx: config.display.ultrawideMinWidthPx)
        } catch {
            warnings.append(.layoutSkipped(reason: "Display info unavailable: \(error)"))
            layoutObserver.stopObserving()
            return warnings
        }

        if environment.screenCount > 1 {
            warnings.append(.multipleDisplaysDetected(count: environment.screenCount))
        }

        let loadResult = stateStore.load()
        var state: LayoutState
        var canPersistState = true
        switch loadResult {
        case .success(let outcome):
            switch outcome {
            case .missing:
                state = .empty()
            case .loaded(let loaded):
                state = loaded
            case .recovered(let recovered, let backupPath):
                state = recovered
                warnings.append(.stateRecovered(backupPath: backupPath))
            }
        case .failure(let error):
            state = .empty()
            warnings.append(.stateLoadFailed(detail: "State load failed: \(error)"))
            canPersistState = false
        }

        var projectState = state.projects[projectId] ?? ProjectState()
        projectState.managed = ManagedWindowState(
            ideWindowId: ideWindow.windowId,
            chromeWindowId: chromeWindow.windowId
        )

        let displayMode = environment.displayMode
        let persistedLayout = projectState.layouts.layout(for: displayMode)
        let defaultLayout = layoutEngine.defaultLayout(for: displayMode)

        let ideContext = resolveWindowContext(
            kind: .ide,
            windowId: ideWindow.windowId,
            client: client,
            environment: environment,
            warnings: &warnings
        )
        let chromeContext = resolveWindowContext(
            kind: .chrome,
            windowId: chromeWindow.windowId,
            client: client,
            environment: environment,
            warnings: &warnings
        )

        var ideRectToPersist: NormalizedRect?
        var chromeRectToPersist: NormalizedRect?

        if let persistedLayout {
            ideRectToPersist = persistedLayout.ideRect
            chromeRectToPersist = persistedLayout.chromeRect
            if let ideContext, ideContext.isOnMainDisplay {
                applyLayoutRect(
                    persistedLayout.ideRect,
                    context: ideContext,
                    environment: environment,
                    warnings: &warnings
                )
            }
            if let chromeContext, chromeContext.isOnMainDisplay {
                applyLayoutRect(
                    persistedLayout.chromeRect,
                    context: chromeContext,
                    environment: environment,
                    warnings: &warnings
                )
            }
        } else {
            if ideWindow.wasCreated {
                if let ideContext, ideContext.isOnMainDisplay {
                    applyLayoutRect(
                        defaultLayout.ideRect,
                        context: ideContext,
                        environment: environment,
                        warnings: &warnings
                    )
                    ideRectToPersist = defaultLayout.ideRect
                }
            } else if let ideContext, ideContext.isOnMainDisplay {
                ideRectToPersist = normalizeFrame(
                    ideContext.frame,
                    visibleFrame: environment.visibleFramePoints,
                    windowId: ideContext.windowId,
                    warnings: &warnings
                )
            }

            if chromeWindow.wasCreated {
                if let chromeContext, chromeContext.isOnMainDisplay {
                    applyLayoutRect(
                        defaultLayout.chromeRect,
                        context: chromeContext,
                        environment: environment,
                        warnings: &warnings
                    )
                    chromeRectToPersist = defaultLayout.chromeRect
                }
            } else if let chromeContext, chromeContext.isOnMainDisplay {
                chromeRectToPersist = normalizeFrame(
                    chromeContext.frame,
                    visibleFrame: environment.visibleFramePoints,
                    windowId: chromeContext.windowId,
                    warnings: &warnings
                )
            }
        }

        if canPersistState, let ideRectToPersist, let chromeRectToPersist {
            let layout = ProjectLayout(ideRect: ideRectToPersist, chromeRect: chromeRectToPersist)
            projectState.layouts.setLayout(layout, for: displayMode)
            if let ideElement = ideContext?.element, let chromeElement = chromeContext?.element {
                let contextWithElements = LayoutObservationContext(
                    projectId: projectId,
                    displayMode: displayMode,
                    environment: environment,
                    ideWindowId: ideWindow.windowId,
                    chromeWindowId: chromeWindow.windowId,
                    ideElement: ideElement,
                    chromeElement: chromeElement,
                    initialLayout: layout
                )
                let observerWarnings = layoutObserver.startObserving(context: contextWithElements, warningSink: { [logger] warning in
                    _ = logger.log(
                        event: "layout.observer.warning",
                        level: .warn,
                        message: warning.logSummary(),
                        context: nil
                    )
                })
                warnings.append(contentsOf: observerWarnings)
            } else {
                layoutObserver.stopObserving()
            }
        } else {
            layoutObserver.stopObserving()
        }

        state.projects[projectId] = projectState
        if canPersistState {
            if case .failure(let error) = stateStore.save(state) {
                warnings.append(.layoutPersistFailed(detail: "State save failed: \(error)"))
            }
        }

        return warnings
    }

    private func resolveWindowContext(
        kind: ActivationWindowKind,
        windowId: Int,
        client: AeroSpaceClient,
        environment: LayoutEnvironment,
        warnings: inout [ActivationWarning]
    ) -> WindowContext? {
        switch client.focusWindow(windowId: windowId) {
        case .failure(let error):
            warnings.append(.layoutApplyFailed(kind: kind, windowId: windowId, detail: "Focus failed: \(error)"))
            return nil
        case .success:
            break
        }

        // Get the accessibility element directly by window ID instead of waiting for the focus attribute to update.
        // This avoids the race condition where the system's focused window attribute lags behind AeroSpace focus changes.
        let elementResult = windowManager.element(for: windowId)
        guard case .success(let element) = elementResult else {
            if case .failure(let error) = elementResult {
                warnings.append(.layoutApplyFailed(kind: kind, windowId: windowId, detail: "AX element lookup failed: \(error)"))
            }
            return nil
        }

        let frameResult = windowManager.frame(of: element, mainDisplayHeightPoints: environment.mainDisplayHeightPoints)
        guard case .success(let frame) = frameResult else {
            if case .failure(let error) = frameResult {
                warnings.append(.layoutApplyFailed(kind: kind, windowId: windowId, detail: "Frame read failed: \(error)"))
            }
            return nil
        }

        let isOnMain = layoutEngine.isFrameOnMainDisplay(frame, mainFramePoints: environment.mainFramePoints)
        if !isOnMain {
            warnings.append(.windowOffMainDisplay(kind: kind, windowId: windowId))
        }

        return WindowContext(
            kind: kind,
            windowId: windowId,
            element: element,
            frame: frame,
            isOnMainDisplay: isOnMain
        )
    }

    private func applyLayoutRect(
        _ rect: NormalizedRect,
        context: WindowContext,
        environment: LayoutEnvironment,
        warnings: inout [ActivationWarning]
    ) {
        guard context.isOnMainDisplay else { return }
        let frame = denormalize(rect, in: environment.visibleFramePoints)
        let result = windowManager.setFrame(
            frame,
            for: context.element,
            mainDisplayHeightPoints: environment.mainDisplayHeightPoints
        )
        if case .failure(let error) = result {
            warnings.append(.layoutApplyFailed(kind: context.kind, windowId: context.windowId, detail: "\(error)"))
        }
    }

    private func normalizeFrame(
        _ frame: CGRect,
        visibleFrame: CGRect,
        windowId: Int,
        warnings: inout [ActivationWarning]
    ) -> NormalizedRect? {
        let normalizedResult = Result { try layoutEngine.normalize(frame, in: visibleFrame) }
        switch normalizedResult {
        case .success(let rect):
            return rect
        case .failure(let error):
            warnings.append(.layoutPersistFailed(detail: "Failed to normalize window \(windowId): \(error)"))
            return nil
        }
    }
}

private struct WindowContext {
    let kind: ActivationWindowKind
    let windowId: Int
    let element: AXUIElement
    let frame: CGRect
    let isOnMainDisplay: Bool
}
