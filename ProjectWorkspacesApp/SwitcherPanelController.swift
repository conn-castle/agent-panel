import AppKit

import ProjectWorkspacesCore

/// Source of a switcher presentation request.
enum SwitcherPresentationSource: String {
    case menu
    case hotkey
    case unknown
}

/// Reason the switcher panel was dismissed.
enum SwitcherDismissReason: String {
    case toggle
    case escape
    case activationRequested
    case activationSucceeded
    case activationWarning
    case windowClose
    case unknown
}

/// Switcher UI states.
private enum SwitcherState: Equatable {
    case browsing
    case loading(projectId: String, step: String)
    case warning(projectId: String, message: String)
    case error(projectId: String, message: String)
}

/// Controls the switcher panel lifecycle and keyboard-driven UX.
final class SwitcherPanelController: NSObject {
    private let projectCatalogService: ProjectCatalogService
    private let projectFilter: ProjectFilter
    private let activationService: ActivationService
    private let logger: ProjectWorkspacesLogging

    private let panel: SwitcherPanel
    private let searchField: NSSearchField
    private let tableView: NSTableView
    private let statusLabel: NSTextField
    private let progressIndicator: NSProgressIndicator
    private let retryButton: NSButton
    private let cancelButton: NSButton

    private var allProjects: [ProjectListItem] = []
    private var filteredProjects: [ProjectListItem] = []
    private var catalogErrorMessage: String?
    private var switcherSessionId: String?
    private var sessionOrigin: SwitcherPresentationSource = .unknown
    private var lastFilterQuery: String = ""
    private var lastStatusMessage: String?
    private var lastStatusLevel: StatusLevel?
    private var expectsVisible: Bool = false
    private var pendingVisibilityCheckToken: UUID?
    private var isActivating: Bool = false
    private var state: SwitcherState = .browsing
    private var activeProject: ProjectListItem?
    private var activationRequestId: UUID?
    private var activationCancellationToken: ActivationCancellationToken?
    private var previousFocusSnapshot: SwitcherFocusSnapshot?
    private let focusProvider: SwitcherAeroSpaceProviding

    /// Creates a switcher panel controller.
    /// - Parameters:
    ///   - projectCatalogService: Service that loads configured projects.
    ///   - projectFilter: Filter for case-insensitive matching.
    ///   - activationService: Activation service used to switch projects.
    init(
        projectCatalogService: ProjectCatalogService = ProjectCatalogService(),
        projectFilter: ProjectFilter = ProjectFilter(),
        activationService: ActivationService = ActivationService(),
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger(),
        focusProvider: SwitcherAeroSpaceProviding? = nil
    ) {
        self.projectCatalogService = projectCatalogService
        self.projectFilter = projectFilter
        self.activationService = activationService
        self.logger = logger
        self.focusProvider = focusProvider ?? AeroSpaceSwitcherService(logger: logger)

        self.panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.searchField = NSSearchField()
        self.tableView = NSTableView()
        self.statusLabel = NSTextField(labelWithString: "")
        self.progressIndicator = NSProgressIndicator()
        self.retryButton = NSButton(title: "Retry", target: nil, action: nil)
        self.cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

        super.init()

        configurePanel()
        configureSearchField()
        configureTableView()
        configureStatusLabel()
        configureProgressIndicator()
        configureActionButtons()
        layoutContent()
    }

    /// Toggles the switcher panel visibility.
    func toggle(origin: SwitcherPresentationSource = .unknown) {
        if panel.isVisible {
            switch state {
            case .loading:
                focusPanelForCancel()
            case .browsing, .error, .warning:
                dismiss(reason: .toggle)
            }
        } else {
            show(origin: origin)
        }
    }

    /// Shows the switcher panel and resets transient state.
    func show(origin: SwitcherPresentationSource = .unknown) {
        resetState()
        expectsVisible = true
        beginSession(origin: origin)
        logShowRequested(origin: origin)
        capturePreviousFocusSnapshot { [weak self] in
            guard let self else { return }
            guard self.expectsVisible else { return }
            self.showPanel()
            self.loadProjects()
            self.applyFilter(query: "")
            self.scheduleVisibilityCheck(origin: origin)
        }
    }

    /// Dismisses the switcher panel and clears transient state.
    func dismiss(reason: SwitcherDismissReason = .unknown) {
        expectsVisible = false
        endSession(reason: reason)
        panel.orderOut(nil)
        resetState()
        if shouldRestoreFocus(reason: reason) {
            restorePreviousFocusIfNeeded()
        }
    }

    /// Returns the panel visibility for tests.
    /// - Returns: True if the panel is visible.
    func isPanelVisibleForTesting() -> Bool {
        panel.isVisible
    }

    /// Returns the panel collection behavior for tests.
    /// - Returns: Collection behavior flags for the panel.
    func panelCollectionBehaviorForTesting() -> NSWindow.CollectionBehavior {
        panel.collectionBehavior
    }

    /// Configures the switcher panel presentation behavior.
    private func configurePanel() {
        panel.title = "Project Switcher"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
    }

    /// Configures the search field appearance and delegate wiring.
    private func configureSearchField() {
        searchField.placeholderString = "Type to filter projects"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
    }

    /// Configures the table view used for project rows.
    private func configureTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ProjectColumn"))
        column.title = "Project"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Configures the status label used for warnings and errors.
    private func configureStatusLabel() {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Configures the progress indicator shown during loading.
    private func configureProgressIndicator() {
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Configures retry/cancel buttons shown on errors.
    private func configureActionButtons() {
        retryButton.target = self
        retryButton.action = #selector(retryActivation(_:))
        retryButton.bezelStyle = .rounded
        retryButton.isHidden = true
        retryButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.target = self
        cancelButton.action = #selector(cancelActivation(_:))
        cancelButton.bezelStyle = .rounded
        cancelButton.isHidden = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Lays out the panel content using Auto Layout.
    private func layoutContent() {
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let statusStack = NSStackView(views: [progressIndicator, statusLabel])
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 8
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [retryButton, cancelButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let footerStack = NSStackView(views: [statusStack, spacer, buttonStack])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 8
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [searchField, scrollView, footerStack])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = panel.contentView else {
            return
        }

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    /// Loads projects from config and surfaces warnings or failures.
    private func loadProjects() {
        switch projectCatalogService.listProjects() {
        case .failure(let error):
            allProjects = []
            filteredProjects = []
            catalogErrorMessage = error.findings.first?.title ?? "Config error"
            setStatus(message: "Config error: \(catalogErrorMessage ?? "Unknown")", level: .error)
            logCatalogFailure(error)
        case .success(let result):
            allProjects = result.projects
            catalogErrorMessage = nil
            if result.warnings.isEmpty {
                clearStatus()
                logCatalogLoaded(projectCount: result.projects.count)
            } else {
                setStatus(message: "Config warnings detected. Run Doctor for details.", level: .warning)
                logCatalogWarnings(result)
            }
        }
    }

    /// Applies filtering and updates selection.
    /// - Parameter query: Current filter query.
    private func applyFilter(query: String) {
        guard case .browsing = state else {
            return
        }
        let previousQuery = lastFilterQuery
        lastFilterQuery = query
        guard catalogErrorMessage == nil else {
            filteredProjects = []
            tableView.reloadData()
            tableView.deselectAll(nil)
            logEvent(
                event: "switcher.filter.skipped",
                level: .warn,
                message: "Filter skipped due to config error.",
                context: [
                    "query": query,
                    "previous_query": previousQuery,
                    "reason": "config_error"
                ]
            )
            return
        }

        filteredProjects = projectFilter.filter(projects: allProjects, query: query)
        tableView.reloadData()
        updateSelectionAfterFilter()

        logEvent(
            event: "switcher.filter.applied",
            context: [
                "query": query,
                "previous_query": previousQuery,
                "total_count": "\(allProjects.count)",
                "filtered_count": "\(filteredProjects.count)"
            ]
        )

        if filteredProjects.isEmpty {
            logEvent(
                event: "switcher.filter.empty",
                message: "No matches.",
                context: ["query": query]
            )
        }
    }

    /// Resets query, selection, and status labels.
    private func resetState() {
        allProjects = []
        searchField.stringValue = ""
        searchField.isEnabled = true
        searchField.isEditable = true
        catalogErrorMessage = nil
        filteredProjects = []
        tableView.isEnabled = true
        lastFilterQuery = ""
        lastStatusMessage = nil
        lastStatusLevel = nil
        isActivating = false
        activeProject = nil
        activationCancellationToken = nil
        activationRequestId = nil
        panel.allowsKeyWindow = true
        setState(.browsing)
        tableView.reloadData()
        tableView.deselectAll(nil)
    }

    /// Shows the panel and focuses the search field.
    private func showPanel() {
        panel.allowsKeyWindow = true
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    /// Starts a new switcher session for log correlation.
    /// - Parameter origin: Source of the presentation request.
    private func beginSession(origin: SwitcherPresentationSource) {
        switcherSessionId = UUID().uuidString
        sessionOrigin = origin
        logEvent(
            event: "switcher.session.start",
            context: ["source": origin.rawValue]
        )
    }

    /// Ends the current switcher session and records the reason.
    /// - Parameter reason: Dismissal reason.
    private func endSession(reason: SwitcherDismissReason) {
        guard switcherSessionId != nil else {
            return
        }

        logEvent(
            event: "switcher.session.end",
            context: ["reason": reason.rawValue]
        )
        switcherSessionId = nil
        sessionOrigin = .unknown
    }

    /// Writes a structured log entry with switcher session context.
    /// - Parameters:
    ///   - event: Event name.
    ///   - level: Severity level.
    ///   - message: Optional message.
    ///   - context: Optional structured context.
    private func logEvent(
        event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        var mergedContext = context ?? [:]
        if mergedContext["session_id"] == nil, let sessionId = switcherSessionId {
            mergedContext["session_id"] = sessionId
        }
        if mergedContext["source"] == nil, sessionOrigin != .unknown {
            mergedContext["source"] = sessionOrigin.rawValue
        }

        let contextValue = mergedContext.isEmpty ? nil : mergedContext
        _ = logger.log(event: event, level: level, message: message, context: contextValue)
    }

    /// Records a show request for diagnostic tracing.
    /// - Parameter origin: Source of the presentation request.
    private func logShowRequested(origin: SwitcherPresentationSource) {
        logEvent(
            event: "switcher.show.requested",
            context: ["source": origin.rawValue]
        )
    }

    /// Schedules a visibility check to confirm the panel appeared.
    /// - Parameter origin: Source of the presentation request.
    private func scheduleVisibilityCheck(origin: SwitcherPresentationSource) {
        let token = UUID()
        pendingVisibilityCheckToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.verifyPanelVisibility(token: token, origin: origin)
        }
    }

    /// Verifies panel visibility and logs failures.
    /// - Parameters:
    ///   - token: Visibility token for the latest show request.
    ///   - origin: Source of the presentation request.
    private func verifyPanelVisibility(token: UUID, origin: SwitcherPresentationSource) {
        guard pendingVisibilityCheckToken == token, expectsVisible else {
            return
        }

        let context = [
            "source": origin.rawValue,
            "visible": panel.isVisible ? "true" : "false",
            "key": panel.isKeyWindow ? "true" : "false",
            "main": panel.isMainWindow ? "true" : "false"
        ]

        if panel.isVisible {
            logEvent(
                event: "switcher.show.visible",
                context: context
            )
        } else {
            logEvent(
                event: "switcher.show.not_visible",
                level: .error,
                message: "Switcher panel failed to become visible.",
                context: context
            )
        }
    }

    /// Logs a catalog load failure for diagnostics.
    /// - Parameter error: Catalog error containing findings.
    private func logCatalogFailure(_ error: ProjectCatalogError) {
        let primary = error.findings.first
        let detail = primary?.bodyLines.first ?? ""
        let configPath = ProjectWorkspacesPaths.defaultPaths().configFile.path
        logEvent(
            event: "switcher.catalog.failure",
            level: .error,
            message: primary?.title,
            context: [
                "finding_count": "\(error.findings.count)",
                "finding_detail": detail,
                "config_path": configPath
            ]
        )
    }

    /// Logs a catalog warning summary for diagnostics.
    /// - Parameter result: Catalog result with warnings.
    private func logCatalogWarnings(_ result: ProjectCatalogResult) {
        let configPath = ProjectWorkspacesPaths.defaultPaths().configFile.path
        logEvent(
            event: "switcher.catalog.warnings",
            level: .warn,
            message: "Config warnings detected.",
            context: [
                "project_count": "\(result.projects.count)",
                "warning_count": "\(result.warnings.count)",
                "config_path": configPath
            ]
        )
    }

    /// Logs successful catalog load summaries.
    /// - Parameter projectCount: Count of projects loaded.
    private func logCatalogLoaded(projectCount: Int) {
        let configPath = ProjectWorkspacesPaths.defaultPaths().configFile.path
        logEvent(
            event: "switcher.catalog.loaded",
            context: [
                "project_count": "\(projectCount)",
                "config_path": configPath
            ]
        )
    }

    /// Updates selection after filtering.
    private func updateSelectionAfterFilter() {
        guard !filteredProjects.isEmpty else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    /// Activates the selected project if available.
    private func activateSelectedProject() {
        guard !isActivating else {
            return
        }
        guard let project = selectedProject() else {
            logEvent(
                event: "switcher.activate.skipped",
                level: .warn,
                message: "Activation skipped because no project is selected.",
                context: ["reason": "no_selection"]
            )
            return
        }

        logEvent(
            event: "switcher.activate.requested",
            context: [
                "project_id": project.id,
                "project_name": project.name
            ]
        )

        beginActivation(project: project)
    }

    /// Starts activation for the selected project and transitions the UI to loading.
    /// - Parameter project: Project to activate.
    private func beginActivation(project: ProjectListItem) {
        isActivating = true
        activeProject = project

        let requestId = UUID()
        activationRequestId = requestId
        let cancellationToken = ActivationCancellationToken()
        activationCancellationToken = cancellationToken

        // Show loading state immediately before any async work
        enterLoadingState(project: project, step: "Switching workspace…")

        // Log workspace existence check asynchronously (for diagnostics only)
        let workspaceName = "pw-\(project.id)"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let workspaceExists = self.focusProvider.workspaceExists(workspaceName: workspaceName)
            self.logEvent(
                event: "switcher.workspace.checked",
                context: [
                    "project_id": project.id,
                    "workspace": workspaceName,
                    "exists": "\(workspaceExists)"
                ]
            )
        }

        DispatchQueue.main.async {
            self.startActivation(
                project: project,
                requestId: requestId,
                cancellationToken: cancellationToken
            )
        }
    }

    /// Runs activation on a background queue and forwards progress/outcome to the main thread.
    /// - Parameters:
    ///   - project: Project being activated.
    ///   - requestId: Identifier used to ignore stale updates.
    ///   - cancellationToken: Token used to cancel activation.
    private func startActivation(
        project: ProjectListItem,
        requestId: UUID,
        cancellationToken: ActivationCancellationToken
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = self.activationService.activate(
                projectId: project.id,
                focusIdeWindow: true,
                switchWorkspace: true,
                progress: { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.handleActivationProgress(progress, requestId: requestId, project: project)
                    }
                },
                cancellationToken: cancellationToken
            )
            DispatchQueue.main.async {
                self.handleActivationOutcome(outcome, project: project, requestId: requestId)
            }
        }
    }

    /// Updates the loading UI for activation progress events.
    /// - Parameters:
    ///   - progress: Activation progress milestone.
    ///   - requestId: Identifier used to ignore stale updates.
    ///   - project: Project being activated.
    private func handleActivationProgress(
        _ progress: ActivationProgress,
        requestId: UUID,
        project: ProjectListItem
    ) {
        guard requestId == activationRequestId else { return }
        switch progress {
        case .switchingWorkspace(_):
            updateLoadingStep(project: project, step: "Switching workspace…")
        case .switchedWorkspace(_):
            panel.orderFront(nil)
        case .ensuringChrome:
            updateLoadingStep(project: project, step: "Opening Chrome…")
        case .ensuringIde:
            updateLoadingStep(project: project, step: "Opening VS Code…")
        case .applyingLayout:
            updateLoadingStep(project: project, step: "Applying layout…")
        case .finishing:
            updateLoadingStep(project: project, step: "Finishing…")
        }
    }

    /// Handles activation outcomes and updates UI state.
    private func handleActivationOutcome(
        _ outcome: ActivationOutcome,
        project: ProjectListItem,
        requestId: UUID
    ) {
        guard requestId == activationRequestId else { return }
        activationRequestId = nil
        activationCancellationToken = nil
        isActivating = false

        let projectContext = [
            "project_id": project.id,
            "project_name": project.name
        ]

        switch outcome {
        case .success(let report, let warnings):
            if warnings.isEmpty {
                logEvent(
                    event: "switcher.activate.success",
                    level: .info,
                    message: nil,
                    context: projectContext
                )
                dismiss(reason: .activationSucceeded)
                focusWorkspaceAndIdeAfterDismiss(report: report)
            } else {
                let warningDetails = warnings.map { $0.userMessage }.joined(separator: " | ")
                logEvent(
                    event: "switcher.activate.success",
                    level: .warn,
                    message: "Activation completed with warnings.",
                    context: projectContext.merging(
                        [
                            "warning_count": "\(warnings.count)",
                            "warnings": warningDetails
                        ],
                        uniquingKeysWith: { current, _ in current }
                    )
                )
                // Show warning to user without auto-dismiss; focus IDE in background
                enterWarningState(project: project, message: "Activated with warnings. See logs.")
                focusWorkspaceAndIdeInBackground(report: report)
            }
        case .failure(let error):
            if case .cancelled = error {
                return
            }
            let finding = error.asFindings().first
            let message = finding?.title ?? "Activation failed"
            logEvent(
                event: "switcher.activate.failure",
                level: .error,
                message: message,
                context: projectContext
            )
            enterErrorState(project: project, message: message)
        }
    }

    /// Focuses the workspace and IDE window after the switcher is dismissed.
    /// - Parameter report: Activation report containing workspace and window information.
    private func focusWorkspaceAndIdeAfterDismiss(report: ActivationReport) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.logEvent(
                event: "switcher.ide.focus.requested",
                context: [
                    "workspace": report.workspaceName,
                    "window_id": "\(report.ideWindowId)"
                ]
            )
            DispatchQueue.global(qos: .userInitiated).async {
                let focusResult = self.activationService.focusWorkspaceAndWindow(report: report)
                DispatchQueue.main.async {
                    self.handlePostDismissFocusResult(focusResult, report: report)
                }
            }
        }
    }

    /// Handles the result of post-dismiss focus attempt.
    private func handlePostDismissFocusResult(
        _ result: Result<Void, ActivationError>,
        report: ActivationReport
    ) {
        switch result {
        case .success:
            logEvent(
                event: "switcher.ide.focus.completed",
                context: [
                    "workspace": report.workspaceName,
                    "window_id": "\(report.ideWindowId)"
                ]
            )
        case .failure(let error):
            let detail = error.asFindings().first?.title ?? "Focus failed"
            logEvent(
                event: "switcher.ide.focus.failed",
                level: .warn,
                message: detail,
                context: [
                    "workspace": report.workspaceName,
                    "window_id": "\(report.ideWindowId)"
                ]
            )
        }
    }

    /// Captures the previously focused AeroSpace window and workspace (best effort).
    /// Captures the previously focused window/workspace before the switcher becomes key.
    /// - Parameter completion: Optional completion called on the main thread.
    private func capturePreviousFocusSnapshot(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = self.focusProvider.captureSnapshot()
            DispatchQueue.main.async {
                self.previousFocusSnapshot = snapshot
                completion?()
            }
        }
    }

    /// Attempts to restore focus to the previously focused AeroSpace window/workspace.
    private func restorePreviousFocusIfNeeded() {
        guard let snapshot = previousFocusSnapshot else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            self.focusProvider.restore(snapshot: snapshot)
        }
        previousFocusSnapshot = nil
    }

    /// Returns the currently selected project, if any.
    private func selectedProject() -> ProjectListItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredProjects.count else {
            return nil
        }
        return filteredProjects[row]
    }

    /// Updates the status label with a message and visual level.
    private func setStatus(message: String, level: StatusLevel) {
        statusLabel.stringValue = message
        statusLabel.textColor = level.textColor
        statusLabel.isHidden = false

        let levelLabel: String
        switch level {
        case .info:
            levelLabel = "info"
        case .warning:
            levelLabel = "warning"
        case .error:
            levelLabel = "error"
        }

        if lastStatusMessage != message || lastStatusLevel != level {
            logEvent(
                event: "switcher.status.updated",
                level: level == .error ? .error : (level == .warning ? .warn : .info),
                message: message,
                context: ["status_level": levelLabel]
            )
            lastStatusMessage = message
            lastStatusLevel = level
        }
    }

    /// Hides the status label.
    private func clearStatus() {
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        statusLabel.textColor = .secondaryLabelColor

        if lastStatusMessage != nil || lastStatusLevel != nil {
            logEvent(event: "switcher.status.cleared")
            lastStatusMessage = nil
            lastStatusLevel = nil
        }
    }

    /// Updates the UI state and applies its visual changes.
    /// - Parameter newState: Desired switcher state.
    private func setState(_ newState: SwitcherState) {
        state = newState
        applyState()
    }

    /// Applies the current state to the UI controls.
    private func applyState() {
        switch state {
        case .browsing:
            progressIndicator.stopAnimation(nil)
            progressIndicator.isHidden = true
            retryButton.isHidden = true
            cancelButton.isHidden = true
            searchField.isEditable = true
            tableView.isEnabled = true
            clearStatus()
        case .loading(_, let step):
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
            retryButton.isHidden = true
            cancelButton.isHidden = true
            searchField.isEditable = false
            tableView.isEnabled = false
            setStatus(message: step, level: .info)
        case .warning(_, let message):
            progressIndicator.stopAnimation(nil)
            progressIndicator.isHidden = true
            retryButton.isHidden = true
            cancelButton.isHidden = false // Show cancel/dismiss button
            searchField.isEditable = false
            tableView.isEnabled = false
            setStatus(message: message, level: .warning)
        case .error(_, let message):
            progressIndicator.stopAnimation(nil)
            progressIndicator.isHidden = true
            retryButton.isHidden = false
            cancelButton.isHidden = false
            searchField.isEditable = false
            tableView.isEnabled = false
            setStatus(message: message, level: .error)
        }
    }

    /// Enters loading state and ensures the panel is visible but non-key.
    /// - Parameters:
    ///   - project: Project being activated.
    ///   - step: Step label to display.
    private func enterLoadingState(project: ProjectListItem, step: String) {
        panel.allowsKeyWindow = false
        let message = "\(project.name) — \(step)"
        setState(.loading(projectId: project.id, step: message))
        panel.orderFront(nil)
        panel.resignKey()
    }

    /// Updates the loading step text for the current project.
    /// - Parameters:
    ///   - project: Project being activated.
    ///   - step: Step label to display.
    private func updateLoadingStep(project: ProjectListItem, step: String) {
        guard case .loading = state else {
            let message = "\(project.name) — \(step)"
            setState(.loading(projectId: project.id, step: message))
            return
        }
        let message = "\(project.name) — \(step)"
        setState(.loading(projectId: project.id, step: message))
    }

    /// Enters error state and makes the panel key to allow retry/cancel input.
    /// - Parameters:
    ///   - project: Project that failed to activate.
    ///   - message: Error message to display.
    private func enterErrorState(project: ProjectListItem, message: String) {
        panel.allowsKeyWindow = true
        let formatted = "\(project.name) — \(message)"
        setState(.error(projectId: project.id, message: formatted))
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    /// Enters warning state and makes the panel key to show the warning.
    /// - Parameters:
    ///   - project: Project that activated with warnings.
    ///   - message: Warning message to display.
    private func enterWarningState(project: ProjectListItem, message: String) {
        panel.allowsKeyWindow = true
        let formatted = "\(project.name) — \(message)"
        setState(.warning(projectId: project.id, message: formatted))
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    /// Focuses the workspace and IDE window in the background without dismissing.
    /// Used when activation succeeds with warnings.
    /// - Parameter report: Activation report containing workspace and window information.
    private func focusWorkspaceAndIdeInBackground(report: ActivationReport) {
        logEvent(
            event: "switcher.ide.focus.requested",
            context: [
                "workspace": report.workspaceName,
                "window_id": "\(report.ideWindowId)",
                "mode": "background"
            ]
        )
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let focusResult = self?.activationService.focusWorkspaceAndWindow(report: report)
            DispatchQueue.main.async {
                guard let self else { return }
                switch focusResult {
                case .success:
                    self.logEvent(
                        event: "switcher.ide.focus.completed",
                        context: [
                            "workspace": report.workspaceName,
                            "window_id": "\(report.ideWindowId)",
                            "mode": "background"
                        ]
                    )
                case .failure(let error):
                    let detail = error.asFindings().first?.title ?? "Focus failed"
                    self.logEvent(
                        event: "switcher.ide.focus.failed",
                        level: .warn,
                        message: detail,
                        context: [
                            "workspace": report.workspaceName,
                            "window_id": "\(report.ideWindowId)",
                            "mode": "background"
                        ]
                    )
                case .none:
                    break
                }
            }
        }
    }

    /// Focuses the panel while loading so the user can cancel with Escape.
    private func focusPanelForCancel() {
        panel.allowsKeyWindow = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(searchField)
    }

    @objc private func retryActivation(_ sender: Any?) {
        guard let project = activeProject else {
            return
        }
        logEvent(
            event: "switcher.activate.retry",
            context: ["project_id": project.id, "project_name": project.name]
        )
        beginActivation(project: project)
    }

    @objc private func cancelActivation(_ sender: Any?) {
        cancelActivation()
    }

    /// Cancels the in-flight activation and dismisses the switcher.
    private func cancelActivation() {
        if case .loading = state {
            activationCancellationToken?.cancel()
            let context = activeProject.map { ["project_id": $0.id, "project_name": $0.name] }
            logEvent(event: "switcher.activate.cancelled", context: context)
        }
        activationCancellationToken = nil
        activationRequestId = nil
        isActivating = false
        dismiss(reason: .escape)
    }

    /// Determines whether to restore the previously focused app after dismissing the switcher.
    /// - Parameter reason: Dismissal reason for the switcher panel.
    /// - Returns: True if focus should be restored to the pre-switcher app.
    func shouldRestoreFocus(reason: SwitcherDismissReason) -> Bool {
        switch reason {
        case .toggle, .escape, .windowClose:
            return true
        case .activationRequested, .activationSucceeded, .activationWarning, .unknown:
            return false
        }
    }

    private var emptyStateMessage: String? {
        if let catalogErrorMessage {
            return catalogErrorMessage
        }
        return filteredProjects.isEmpty ? "No matches" : nil
    }
}

extension SwitcherPanelController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        switch state {
        case .loading:
            cancelActivation()
        case .browsing, .error, .warning:
            dismiss(reason: .windowClose)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if case .loading = state {
            panel.allowsKeyWindow = false
        }
    }
}

extension SwitcherPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if emptyStateMessage != nil {
            return 1
        }
        return filteredProjects.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let emptyStateMessage {
            return emptyStateCell(message: emptyStateMessage, tableView: tableView)
        }

        let project = filteredProjects[row]
        return projectCell(for: project, tableView: tableView)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        emptyStateMessage == nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard emptyStateMessage == nil else {
            return
        }
        guard case .browsing = state else {
            return
        }

        let row = tableView.selectedRow
        guard row >= 0, row < filteredProjects.count else {
            logEvent(event: "switcher.selection.cleared")
            return
        }

        let project = filteredProjects[row]
        logEvent(
            event: "switcher.selection.changed",
            context: [
                "row": "\(row)",
                "project_id": project.id,
                "project_name": project.name
            ]
        )
    }
}

extension SwitcherPanelController: NSSearchFieldDelegate, NSControlTextEditingDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else {
            return
        }
        guard case .browsing = state else {
            field.stringValue = lastFilterQuery
            return
        }
        applyFilter(query: field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            logEvent(event: "switcher.action.enter")
            if case .browsing = state {
                activateSelectedProject()
            }
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            logEvent(event: "switcher.action.escape")
            switch state {
            case .browsing:
                dismiss(reason: .escape)
            case .loading:
                cancelActivation()
            case .error:
                cancelActivation()
            case .warning:
                dismiss(reason: .activationWarning)
            }
            return true
        }

        return false
    }
}

private enum StatusLevel {
    case info
    case warning
    case error

    var textColor: NSColor {
        switch self {
        case .info:
            return .secondaryLabelColor
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }
}

final class SwitcherPanel: NSPanel {
    var allowsKeyWindow: Bool = true

    override var canBecomeKey: Bool {
        allowsKeyWindow
    }
}

struct SwitcherFocusSnapshot: Equatable {
    let windowId: Int?
    let workspaceName: String?
}

protocol SwitcherAeroSpaceProviding {
    func captureSnapshot() -> SwitcherFocusSnapshot?
    func restore(snapshot: SwitcherFocusSnapshot)
    func workspaceExists(workspaceName: String) -> Bool
}

struct AeroSpaceSwitcherService: SwitcherAeroSpaceProviding {
    private let logger: ProjectWorkspacesLogging
    private let timeoutSeconds: TimeInterval

    init(logger: ProjectWorkspacesLogging, timeoutSeconds: TimeInterval = 2) {
        self.logger = logger
        self.timeoutSeconds = timeoutSeconds
    }

    func captureSnapshot() -> SwitcherFocusSnapshot? {
        guard let client = makeClient() else { return nil }

        if case .success(let windows) = client.listWindowsFocusedDecoded(),
           let focused = windows.first {
            return SwitcherFocusSnapshot(windowId: focused.windowId, workspaceName: focused.workspace)
        }

        if case .success(let workspace) = client.focusedWorkspace() {
            return SwitcherFocusSnapshot(windowId: nil, workspaceName: workspace)
        }

        return nil
    }

    func restore(snapshot: SwitcherFocusSnapshot) {
        guard let client = makeClient() else { return }
        if let windowId = snapshot.windowId {
            if case .success = client.focusWindow(windowId: windowId) {
                return
            }
        }
        if let workspaceName = snapshot.workspaceName {
            _ = client.switchWorkspace(workspaceName)
        }
    }

    func workspaceExists(workspaceName: String) -> Bool {
        guard let client = makeClient() else { return false }
        switch client.workspaceExists(workspaceName) {
        case .success(let exists):
            return exists
        case .failure(let error):
            _ = logger.log(
                event: "switcher.workspace.exists.failed",
                level: .warn,
                message: "\(error)",
                context: ["workspace": workspaceName]
            )
            return false
        }
    }

    private func makeClient() -> AeroSpaceClient? {
        do {
            return try AeroSpaceClient(
                resolver: DefaultAeroSpaceBinaryResolver(),
                commandRunner: DefaultAeroSpaceCommandRunner(),
                timeoutSeconds: timeoutSeconds
            )
        } catch {
            _ = logger.log(
                event: "switcher.aerospace.client.failed",
                level: .warn,
                message: "\(error)",
                context: nil
            )
            return nil
        }
    }
}

private final class ProjectRowView: NSTableCellView {
    let swatchView = NSView()
    let nameLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 4
        swatchView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [swatchView, nameLabel])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            swatchView.widthAnchor.constraint(equalToConstant: 12),
            swatchView.heightAnchor.constraint(equalToConstant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
}

private func projectCell(for project: ProjectListItem, tableView: NSTableView) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("ProjectRow")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ProjectRowView {
        configureProjectCell(cell, project: project)
        return cell
    }

    let cell = ProjectRowView()
    cell.identifier = identifier
    configureProjectCell(cell, project: project)
    return cell
}

private func configureProjectCell(_ cell: ProjectRowView, project: ProjectListItem) {
    cell.nameLabel.stringValue = project.name
    cell.swatchView.layer?.backgroundColor = colorFromHex(project.colorHex).cgColor
}

private func emptyStateCell(message: String, tableView: NSTableView) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("EmptyStateRow")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
        cell.textField?.stringValue = message
        return cell
    }

    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: message)
    label.textColor = .secondaryLabelColor
    label.font = NSFont.systemFont(ofSize: 12)
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    cell.addSubview(label)

    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
    ])

    cell.textField = label
    return cell
}

private func colorFromHex(_ hex: String) -> NSColor {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == 7, trimmed.hasPrefix("#") else {
        return .controlAccentColor
    }

    let hexDigits = String(trimmed.dropFirst())
    guard let value = Int(hexDigits, radix: 16) else {
        return .controlAccentColor
    }

    let red = CGFloat((value >> 16) & 0xFF) / 255.0
    let green = CGFloat((value >> 8) & 0xFF) / 255.0
    let blue = CGFloat(value & 0xFF) / 255.0
    return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
}
