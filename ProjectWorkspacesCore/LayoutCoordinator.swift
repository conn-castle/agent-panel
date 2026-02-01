import ApplicationServices
import Foundation

/// Activated window metadata used for layout decisions.
struct ActivatedWindow: Equatable {
    let windowId: Int
    let wasCreated: Bool
}

// MARK: - Window Position Convergence

/// Result of waiting for a window's AX position to converge on-screen.
enum WindowPositionConvergenceResult {
    /// Window position converged to on-screen within timeout.
    case converged(frame: CGRect)
    /// Window position did not converge within timeout; last observed frame provided.
    case timedOut(lastFrame: CGRect)
    /// Failed to read window frame from AX.
    case readFailed(error: AccessibilityWindowError)
}

/// Configuration for window position convergence waiting.
struct WindowPositionConvergenceConfig {
    /// Maximum time to wait for convergence (seconds).
    let timeoutSeconds: TimeInterval
    /// Initial delay between polls (seconds).
    let initialDelaySeconds: TimeInterval
    /// Multiplier for exponential backoff.
    let backoffMultiplier: Double
    /// Maximum delay between polls (seconds).
    let maxDelaySeconds: TimeInterval
    /// Number of consecutive on-screen reads required for stability.
    let consecutiveReadsRequired: Int

    /// Default configuration: 1.5s timeout, 20ms initial delay, 2x backoff, 200ms max delay, 2 consecutive reads.
    static let `default` = WindowPositionConvergenceConfig(
        timeoutSeconds: 1.5,
        initialDelaySeconds: 0.02,
        backoffMultiplier: 2.0,
        maxDelaySeconds: 0.2,
        consecutiveReadsRequired: 2
    )
}

/// Configuration for waiting on the expected workspace to become focused.
struct WorkspaceFocusWaitConfig {
    /// Maximum time to wait for workspace focus (milliseconds).
    let timeoutMs: Int
    /// Poll interval for focused workspace checks (milliseconds).
    let pollIntervalMs: Int

    /// Default configuration: 2000ms timeout with 50ms polling.
    static let `default` = WorkspaceFocusWaitConfig(
        timeoutMs: 2000,
        pollIntervalMs: 50
    )
}

/// Waits for a window's AX-reported position to converge on-screen.
///
/// AeroSpace positions windows off-screen when they're on non-focused workspaces.
/// After a workspace switch, there's a delay before the Accessibility API reports
/// the window's new on-screen position. This function polls with exponential backoff
/// until the position stabilizes on-screen or a timeout is reached.
///
/// - Parameters:
///   - element: AX element for the window.
///   - mainFramePoints: Main display frame in points (used for on-screen check).
///   - mainDisplayHeightPoints: Main display height for coordinate conversion.
///   - windowManager: Accessibility window manager for reading frames.
///   - layoutEngine: Layout engine for on-screen check.
///   - config: Convergence configuration.
/// - Returns: Convergence result indicating success, timeout, or failure.
func waitForWindowPositionConvergence(
    element: AXUIElement,
    mainFramePoints: CGRect,
    mainDisplayHeightPoints: CGFloat,
    windowManager: AccessibilityWindowManaging,
    layoutEngine: LayoutEngine,
    config: WindowPositionConvergenceConfig = .default
) -> WindowPositionConvergenceResult {
    let startTime = CFAbsoluteTimeGetCurrent()
    var currentDelay = config.initialDelaySeconds
    var consecutiveOnScreenCount = 0
    var lastFrame: CGRect = .zero

    while true {
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if elapsed >= config.timeoutSeconds {
            return .timedOut(lastFrame: lastFrame)
        }

        let frameResult = windowManager.frame(of: element, mainDisplayHeightPoints: mainDisplayHeightPoints)
        switch frameResult {
        case .failure(let error):
            return .readFailed(error: error)
        case .success(let frame):
            lastFrame = frame
            let isOnScreen = layoutEngine.isFrameOnMainDisplay(frame, mainFramePoints: mainFramePoints)

            if isOnScreen {
                consecutiveOnScreenCount += 1
                if consecutiveOnScreenCount >= config.consecutiveReadsRequired {
                    return .converged(frame: frame)
                }
            } else {
                consecutiveOnScreenCount = 0
            }
        }

        // Calculate remaining time and sleep with backoff
        let remainingTime = config.timeoutSeconds - (CFAbsoluteTimeGetCurrent() - startTime)
        let sleepTime = min(currentDelay, remainingTime, config.maxDelaySeconds)
        if sleepTime > 0 {
            usleep(UInt32(sleepTime * 1_000_000))
        }
        currentDelay = min(currentDelay * config.backoffMultiplier, config.maxDelaySeconds)
    }
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
    private let focusWaitConfig: WorkspaceFocusWaitConfig
    private let focusWaitSleeper: AeroSpaceSleeping
    private let windowConvergenceConfig: WindowPositionConvergenceConfig

    init(
        stateStore: StateStoring = StateStore(),
        layoutEngine: LayoutEngine = LayoutEngine(),
        windowManager: AccessibilityWindowManaging = AccessibilityWindowManager(),
        layoutObserver: LayoutObserving = LayoutObserver(),
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger(),
        focusWaitConfig: WorkspaceFocusWaitConfig = .default,
        focusWaitSleeper: AeroSpaceSleeping = SystemAeroSpaceSleeper(),
        windowConvergenceConfig: WindowPositionConvergenceConfig = .default
    ) {
        self.stateStore = stateStore
        self.layoutEngine = layoutEngine
        self.windowManager = windowManager
        self.layoutObserver = layoutObserver
        self.logger = logger
        self.focusWaitConfig = focusWaitConfig
        self.focusWaitSleeper = focusWaitSleeper
        self.windowConvergenceConfig = windowConvergenceConfig
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

        let workspaceName = "pw-\(projectId)"
        let focusStatus = waitForFocusedWorkspace(
            workspaceName: workspaceName,
            client: client,
            warnings: &warnings
        )

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
            focusStatus: focusStatus,
            warnings: &warnings
        )
        let chromeContext = resolveWindowContext(
            kind: .chrome,
            windowId: chromeWindow.windowId,
            client: client,
            environment: environment,
            focusStatus: focusStatus,
            warnings: &warnings
        )

        var ideRectToPersist: NormalizedRect?
        var chromeRectToPersist: NormalizedRect?

        // Helper to check if layout should be applied to a window context.
        // Apply if window is on main display OR requires forced repositioning.
        func shouldApplyLayout(_ context: WindowContext?) -> Bool {
            guard let context else { return false }
            return context.isOnMainDisplay || context.requiresRepositioning
        }

        if let persistedLayout {
            ideRectToPersist = persistedLayout.ideRect
            chromeRectToPersist = persistedLayout.chromeRect
            if let ideContext, shouldApplyLayout(ideContext) {
                applyLayoutRect(
                    persistedLayout.ideRect,
                    context: ideContext,
                    environment: environment,
                    warnings: &warnings
                )
            }
            if let chromeContext, shouldApplyLayout(chromeContext) {
                applyLayoutRect(
                    persistedLayout.chromeRect,
                    context: chromeContext,
                    environment: environment,
                    warnings: &warnings
                )
            }
        } else {
            if ideWindow.wasCreated {
                if let ideContext, shouldApplyLayout(ideContext) {
                    applyLayoutRect(
                        defaultLayout.ideRect,
                        context: ideContext,
                        environment: environment,
                        warnings: &warnings
                    )
                    ideRectToPersist = defaultLayout.ideRect
                }
            } else if let ideContext, ideContext.isOnMainDisplay {
                // Only normalize existing frame if window is actually on-screen
                // (don't normalize off-screen coordinates)
                ideRectToPersist = normalizeFrame(
                    ideContext.frame,
                    visibleFrame: environment.visibleFramePoints,
                    windowId: ideContext.windowId,
                    warnings: &warnings
                )
            } else if let ideContext, ideContext.requiresRepositioning {
                // Window needs repositioning - apply default layout and persist that
                applyLayoutRect(
                    defaultLayout.ideRect,
                    context: ideContext,
                    environment: environment,
                    warnings: &warnings
                )
                ideRectToPersist = defaultLayout.ideRect
            }

            if chromeWindow.wasCreated {
                if let chromeContext, shouldApplyLayout(chromeContext) {
                    applyLayoutRect(
                        defaultLayout.chromeRect,
                        context: chromeContext,
                        environment: environment,
                        warnings: &warnings
                    )
                    chromeRectToPersist = defaultLayout.chromeRect
                }
            } else if let chromeContext, chromeContext.isOnMainDisplay {
                // Only normalize existing frame if window is actually on-screen
                chromeRectToPersist = normalizeFrame(
                    chromeContext.frame,
                    visibleFrame: environment.visibleFramePoints,
                    windowId: chromeContext.windowId,
                    warnings: &warnings
                )
            } else if let chromeContext, chromeContext.requiresRepositioning {
                // Window needs repositioning - apply default layout and persist that
                applyLayoutRect(
                    defaultLayout.chromeRect,
                    context: chromeContext,
                    environment: environment,
                    warnings: &warnings
                )
                chromeRectToPersist = defaultLayout.chromeRect
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
        focusStatus: WorkspaceFocusStatus,
        warnings: inout [ActivationWarning]
    ) -> WindowContext? {
        // Step 1: Focus the window via AeroSpace.
        switch client.focusWindow(windowId: windowId) {
        case .failure(let error):
            warnings.append(.layoutApplyFailed(kind: kind, windowId: windowId, detail: "Focus failed: \(error)"))
            return nil
        case .success:
            break
        }

        // Step 2: Get the accessibility element directly by window ID.
        // This avoids the race condition where the system's focused window attribute lags behind AeroSpace focus changes.
        let elementResult = windowManager.element(for: windowId)
        guard case .success(let element) = elementResult else {
            if case .failure(let error) = elementResult {
                warnings.append(.layoutApplyFailed(kind: kind, windowId: windowId, detail: "AX element lookup failed: \(error)"))
            }
            return nil
        }

        let frame: CGRect
        let isOnMainDisplay: Bool
        let requiresRepositioning: Bool

        if focusStatus.isFocused {
            // Step 3: Wait for window position to converge on-screen.
            // AeroSpace positions windows off-screen when they're on non-focused workspaces.
            // After a workspace switch, the AX coordinates may lag behind the actual repositioning.
            // We use timeout-based polling with exponential backoff and require consecutive on-screen
            // reads for stability.
            let convergenceResult = waitForWindowPositionConvergence(
                element: element,
                mainFramePoints: environment.mainFramePoints,
                mainDisplayHeightPoints: environment.mainDisplayHeightPoints,
                windowManager: windowManager,
                layoutEngine: layoutEngine,
                config: windowConvergenceConfig
            )

            switch convergenceResult {
            case .converged(let convergedFrame):
                // Window position converged on-screen within timeout
                frame = convergedFrame
                isOnMainDisplay = true
                requiresRepositioning = false

            case .timedOut(let lastFrame):
                // Window did not converge within timeout - treat as needing forced repositioning.
                // This could be AX lag exceeding our timeout, or a genuinely off-screen window.
                // Either way, we'll force-reposition it to bring it on-screen.
                frame = lastFrame
                isOnMainDisplay = false
                requiresRepositioning = true
                warnings.append(.windowOffMainDisplay(kind: kind, windowId: windowId))

            case .readFailed(let error):
                // Failed to read frame from AX - cannot proceed
                warnings.append(.layoutApplyFailed(kind: kind, windowId: windowId, detail: "Frame read failed: \(error)"))
                return nil
            }
        } else {
            // Workspace is not focused; skip AX frame reads and reposition deterministically.
            frame = .zero
            isOnMainDisplay = false
            requiresRepositioning = true
            _ = logger.log(
                event: "layout.window.hidden",
                level: .info,
                message: "Skipping AX convergence because workspace is not focused.",
                context: [
                    "kind": kind.rawValue,
                    "window_id": "\(windowId)",
                    "workspace_expected": focusStatus.expectedWorkspace,
                    "workspace_last_focused": focusStatus.lastFocusedWorkspace ?? "unknown"
                ]
            )
        }

        return WindowContext(
            kind: kind,
            windowId: windowId,
            element: element,
            frame: frame,
            isOnMainDisplay: isOnMainDisplay,
            requiresRepositioning: requiresRepositioning
        )
    }

    /// Outcome of waiting for the expected workspace to become focused.
    private struct WorkspaceFocusStatus {
        let expectedWorkspace: String
        let lastFocusedWorkspace: String?
        let isFocused: Bool
    }

    /// Waits for the expected workspace to become focused before proceeding with AX checks.
    /// - Parameters:
    ///   - workspaceName: Expected workspace name (e.g., pw-<projectId>).
    ///   - client: AeroSpace client used to query focus.
    ///   - warnings: Accumulates non-fatal activation warnings.
    /// - Returns: Focus status used to gate off-screen warnings.
    private func waitForFocusedWorkspace(
        workspaceName: String,
        client: AeroSpaceClient,
        warnings: inout [ActivationWarning]
    ) -> WorkspaceFocusStatus {
        var lastFocused: String? = nil
        let outcome: PollOutcome<Void, AeroSpaceCommandError> = Poller.poll(
            intervalMs: focusWaitConfig.pollIntervalMs,
            timeoutMs: focusWaitConfig.timeoutMs,
            sleeper: focusWaitSleeper
        ) {
            switch client.focusedWorkspace() {
            case .success(let focused):
                lastFocused = focused
                return focused == workspaceName ? .success(()) : .keepWaiting
            case .failure(let error):
                if WindowDetectionRetryPolicy.shouldRetryPoll(error) {
                    return .keepWaiting
                }
                return .failure(error)
            }
        }

        switch outcome {
        case .success:
            return WorkspaceFocusStatus(
                expectedWorkspace: workspaceName,
                lastFocusedWorkspace: lastFocused ?? workspaceName,
                isFocused: true
            )
        case .timedOut:
            warnings.append(.workspaceNotFocused(expected: workspaceName, lastFocused: lastFocused))
            return WorkspaceFocusStatus(
                expectedWorkspace: workspaceName,
                lastFocusedWorkspace: lastFocused,
                isFocused: false
            )
        case .failure(let error):
            warnings.append(.workspaceFocusFailed(detail: "\(error)"))
            return WorkspaceFocusStatus(
                expectedWorkspace: workspaceName,
                lastFocusedWorkspace: lastFocused,
                isFocused: false
            )
        }
    }

    private func applyLayoutRect(
        _ rect: NormalizedRect,
        context: WindowContext,
        environment: LayoutEnvironment,
        warnings: inout [ActivationWarning]
    ) {
        // Apply layout if:
        // 1. Window is on main display (normal case), OR
        // 2. Window requires repositioning (force-recenter after timeout)
        guard context.isOnMainDisplay || context.requiresRepositioning else { return }

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
    /// True if the window was off-screen after AX convergence timeout and needs forced repositioning.
    let requiresRepositioning: Bool
}
