//
//  SwitcherPanelController.swift
//  AgentPanel
//
//  Core controller for the project switcher panel.
//  Manages panel lifecycle, keyboard navigation, project filtering,
//  and selection handling. Coordinates with SwitcherSession for logging
//  and SwitcherViews for rendering.
//

import AppKit

import AgentPanelCore

// MARK: - Supporting Types

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
    case projectSelected
    case windowClose
    case unknown
}

/// Timing constants for switcher behavior.
private enum SwitcherTiming {
    static let visibilityCheckDelaySeconds: TimeInterval = 0.15
}

/// Visual severity level for status messages.
private enum StatusLevel: Equatable {
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

// MARK: - Focus Operations Protocol

/// Protocol for window focus operations via AeroSpace.
/// Allows dependency injection for testing and graceful degradation.
protocol FocusOperations {
    /// Returns the currently focused window, if available.
    func focusedWindow() -> ApWindow?

    /// Focuses a specific window by ID.
    /// - Parameter windowId: The AeroSpace window ID to focus.
    /// - Returns: True if focus was successful.
    func focusWindow(windowId: Int) -> Bool
}

/// Default implementation using ApCore.
final class ApCoreFocusOperations: FocusOperations {
    private let apCore: ApCore?

    init(config: Config?) {
        if let config {
            self.apCore = ApCore(config: config)
        } else {
            self.apCore = nil
        }
    }

    func focusedWindow() -> ApWindow? {
        guard let apCore else { return nil }
        switch apCore.focusedWindow() {
        case .success(let window):
            return window
        case .failure:
            return nil
        }
    }

    func focusWindow(windowId: Int) -> Bool {
        guard let apCore else { return false }
        switch apCore.focusWindow(windowId: windowId) {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

// MARK: - Controller

/// Controls the switcher panel lifecycle and keyboard-driven UX.
final class SwitcherPanelController: NSObject {
    private let logger: AgentPanelLogging
    private let session: SwitcherSession
    private let stateStore: StateStore
    private let focusHistoryStore: FocusHistoryStore
    private var focusOperations: FocusOperations?

    private let panel: SwitcherPanel
    private let searchField: NSSearchField
    private let tableView: NSTableView
    private let statusLabel: NSTextField

    private var allProjects: [ProjectConfig] = []
    private var filteredProjects: [ProjectConfig] = []
    private var configErrorMessage: String?
    private var lastFilterQuery: String = ""
    private var lastStatusMessage: String?
    private var lastStatusLevel: StatusLevel?
    private var expectsVisible: Bool = false
    private var pendingVisibilityCheckToken: UUID?
    private var previouslyActiveApp: NSRunningApplication?

    /// The window that was focused before the switcher opened.
    /// Used for restore-on-cancel via AeroSpace.
    private var defocusedWindow: ApWindow?

    /// Current app state (loaded on init, updated on focus events).
    private var appState: AppState

    /// Creates a switcher panel controller.
    /// - Parameters:
    ///   - logger: Logger used for switcher diagnostics.
    ///   - stateStore: Store for persisting app state.
    ///   - focusHistoryStore: Store for focus history operations.
    init(
        logger: AgentPanelLogging = AgentPanelLogger(),
        stateStore: StateStore = StateStore(),
        focusHistoryStore: FocusHistoryStore = FocusHistoryStore()
    ) {
        self.logger = logger
        self.session = SwitcherSession(logger: logger)
        self.stateStore = stateStore
        self.focusHistoryStore = focusHistoryStore

        // Load initial state
        switch stateStore.load() {
        case .success(let state):
            self.appState = state
        case .failure(let error):
            _ = logger.log(
                event: "switcher.state.load.failed",
                level: .error,
                message: "Failed to load state: \(error)",
                context: nil
            )
            self.appState = AppState()
        }

        self.panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.searchField = NSSearchField()
        self.tableView = NSTableView()
        self.statusLabel = NSTextField(labelWithString: "")

        super.init()

        configurePanel()
        configureSearchField()
        configureTableView()
        configureStatusLabel()
        layoutContent()
    }

    // MARK: - Public Interface

    /// Toggles the switcher panel visibility.
    func toggle(origin: SwitcherPresentationSource = .unknown) {
        if panel.isVisible {
            dismiss(reason: .toggle)
        } else {
            show(origin: origin)
        }
    }

    /// Shows the switcher panel and resets transient state.
    func show(origin: SwitcherPresentationSource = .unknown) {
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        resetState()
        expectsVisible = true
        session.begin(origin: origin)
        session.logShowRequested(origin: origin)

        // Load config and set up focus operations
        loadProjects()

        // Capture the currently focused window before showing switcher
        captureDefocusedWindow()

        showPanel()
        applyFilter(query: "")
        scheduleVisibilityCheck(origin: origin)
    }

    /// Dismisses the switcher panel and clears transient state.
    func dismiss(reason: SwitcherDismissReason = .unknown) {
        expectsVisible = false
        session.end(reason: reason)
        panel.orderOut(nil)

        // Restore focus unless a project was selected (switching context)
        if reason != .projectSelected {
            restorePreviousFocus()
        }

        resetState()
    }

    // MARK: - Focus Capture and Restore

    /// Captures the currently focused window via AeroSpace.
    private func captureDefocusedWindow() {
        guard let focusOps = focusOperations else {
            defocusedWindow = nil
            return
        }

        if let window = focusOps.focusedWindow() {
            defocusedWindow = window

            // Record windowDefocused event
            let event = FocusEvent.windowDefocused(
                windowId: window.windowId,
                appBundleId: window.appBundleId,
                metadata: ["source": "switcher_opened"]
            )
            appState = focusHistoryStore.record(event: event, state: appState)
            saveState()

            session.logEvent(
                event: "switcher.focus.captured",
                context: [
                    "window_id": "\(window.windowId)",
                    "app_bundle_id": window.appBundleId
                ]
            )
        } else {
            defocusedWindow = nil
            session.logEvent(
                event: "switcher.focus.capture_failed",
                level: .warn,
                message: "Could not capture focused window from AeroSpace."
            )
        }
    }

    /// Restores focus to the previously focused window or app.
    private func restorePreviousFocus() {
        // Try AeroSpace restore first
        if let window = defocusedWindow, let focusOps = focusOperations {
            if focusOps.focusWindow(windowId: window.windowId) {
                // Record windowFocused event for restore
                let event = FocusEvent.windowFocused(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    metadata: ["source": "switcher_restore"]
                )
                appState = focusHistoryStore.record(event: event, state: appState)
                saveState()

                session.logEvent(
                    event: "switcher.focus.restored",
                    context: [
                        "window_id": "\(window.windowId)",
                        "method": "aerospace"
                    ]
                )
                defocusedWindow = nil
                previouslyActiveApp = nil
                return
            } else {
                session.logEvent(
                    event: "switcher.focus.restore_failed",
                    level: .warn,
                    message: "AeroSpace focus restore failed, falling back to app activation.",
                    context: ["window_id": "\(window.windowId)"]
                )
            }
        }

        // Fallback: activate the previously active app
        if let previousApp = previouslyActiveApp {
            previousApp.activate()
            session.logEvent(
                event: "switcher.focus.restored",
                context: [
                    "app_bundle_id": previousApp.bundleIdentifier ?? "unknown",
                    "method": "app_activation"
                ]
            )
        }

        defocusedWindow = nil
        previouslyActiveApp = nil
    }

    /// Saves the current app state to disk.
    private func saveState() {
        let result = stateStore.save(appState, prunedWith: focusHistoryStore)
        if case .failure(let error) = result {
            _ = logger.log(
                event: "switcher.state.save.failed",
                level: .error,
                message: "Failed to save state: \(error)",
                context: nil
            )
        }
    }

    // MARK: - Private Configuration

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

    /// Lays out the panel content using Auto Layout.
    private func layoutContent() {
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let statusStack = NSStackView(views: [statusLabel])
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 8
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [searchField, scrollView, statusStack])
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

    // MARK: - State Management

    /// Resets query, selection, and status labels.
    private func resetState() {
        allProjects = []
        searchField.stringValue = ""
        searchField.isEnabled = true
        searchField.isEditable = true
        configErrorMessage = nil
        filteredProjects = []
        tableView.isEnabled = true
        lastFilterQuery = ""
        lastStatusMessage = nil
        lastStatusLevel = nil
        tableView.reloadData()
        tableView.deselectAll(nil)
        clearStatus()
    }

    /// Shows the panel and focuses the search field.
    private func showPanel() {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    // MARK: - Project Loading

    /// Loads projects from config and surfaces warnings or failures.
    private func loadProjects() {
        switch ConfigLoader.loadDefault() {
        case .failure(let error):
            allProjects = []
            filteredProjects = []
            configErrorMessage = error.message
            focusOperations = nil
            setStatus(message: "Config error: \(error.message)", level: .error)
            session.logConfigFailure(error)
        case .success(let result):
            guard let config = result.config else {
                allProjects = []
                filteredProjects = []
                let firstFinding = result.findings.first
                configErrorMessage = firstFinding?.title ?? "Config error"
                focusOperations = nil
                setStatus(message: "Config error: \(configErrorMessage ?? "Unknown")", level: .error)
                session.logConfigFindingsFailure(result.findings)
                return
            }

            allProjects = config.projects
            configErrorMessage = nil
            focusOperations = ApCoreFocusOperations(config: config)

            let warnings = result.findings.filter { $0.severity == .warn }
            if warnings.isEmpty {
                clearStatus()
                session.logConfigLoaded(projectCount: config.projects.count)
            } else {
                setStatus(message: "Config warnings detected. Run Doctor for details.", level: .warning)
                session.logConfigWarnings(projectCount: config.projects.count, warningCount: warnings.count)
            }
        }
    }

    // MARK: - Filtering

    /// Filters projects by case-insensitive substring match on id or name.
    private func filterProjects(_ projects: [ProjectConfig], query: String) -> [ProjectConfig] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return projects
        }

        let needle = trimmed.lowercased()
        return projects.filter { project in
            project.id.lowercased().contains(needle)
                || project.name.lowercased().contains(needle)
        }
    }

    /// Applies filtering and updates selection.
    private func applyFilter(query: String) {
        let previousQuery = lastFilterQuery
        lastFilterQuery = query
        guard configErrorMessage == nil else {
            filteredProjects = []
            tableView.reloadData()
            tableView.deselectAll(nil)
            session.logEvent(
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

        filteredProjects = filterProjects(allProjects, query: query)
        tableView.reloadData()
        updateSelectionAfterFilter()

        session.logEvent(
            event: "switcher.filter.applied",
            context: [
                "query": query,
                "previous_query": previousQuery,
                "total_count": "\(allProjects.count)",
                "filtered_count": "\(filteredProjects.count)"
            ]
        )

        if filteredProjects.isEmpty {
            session.logEvent(
                event: "switcher.filter.empty",
                message: "No matches.",
                context: ["query": query]
            )
        }
    }

    /// Updates selection after filtering.
    private func updateSelectionAfterFilter() {
        guard !filteredProjects.isEmpty else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    // MARK: - Selection

    /// Handles project selection (Enter key).
    private func handleSelection() {
        guard let project = selectedProject() else {
            session.logEvent(
                event: "switcher.selection.skipped",
                level: .warn,
                message: "Selection skipped because no project is selected.",
                context: ["reason": "no_selection"]
            )
            return
        }

        // Record projectActivated event
        let event = FocusEvent.projectActivated(
            projectId: project.id,
            metadata: ["project_name": project.name]
        )
        appState = focusHistoryStore.record(event: event, state: appState)
        saveState()

        session.logEvent(
            event: "switcher.project.selected",
            context: [
                "project_id": project.id,
                "project_name": project.name
            ]
        )

        // Dismiss without restoring previous focus (we're switching to this project)
        dismiss(reason: .projectSelected)

        // TODO: Wire project activation (Phase 3).
    }

    /// Returns the currently selected project, if any.
    private func selectedProject() -> ProjectConfig? {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredProjects.count else {
            return nil
        }
        return filteredProjects[row]
    }

    // MARK: - Status Display

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
            session.logEvent(
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
            session.logEvent(event: "switcher.status.cleared")
            lastStatusMessage = nil
            lastStatusLevel = nil
        }
    }

    private var emptyStateMessage: String? {
        if let configErrorMessage {
            return configErrorMessage
        }
        return filteredProjects.isEmpty ? "No matches" : nil
    }

    // MARK: - Visibility Verification

    /// Schedules a visibility check to confirm the panel appeared.
    private func scheduleVisibilityCheck(origin: SwitcherPresentationSource) {
        let token = UUID()
        pendingVisibilityCheckToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + SwitcherTiming.visibilityCheckDelaySeconds) { [weak self] in
            self?.verifyPanelVisibility(token: token, origin: origin)
        }
    }

    /// Verifies panel visibility and logs failures.
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
            session.logEvent(
                event: "switcher.show.visible",
                context: context
            )
        } else {
            session.logEvent(
                event: "switcher.show.not_visible",
                level: .error,
                message: "Switcher panel failed to become visible.",
                context: context
            )
        }
    }
}

// MARK: - NSWindowDelegate

extension SwitcherPanelController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        dismiss(reason: .windowClose)
    }
}

// MARK: - NSTableViewDataSource, NSTableViewDelegate

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

        let row = tableView.selectedRow
        guard row >= 0, row < filteredProjects.count else {
            session.logEvent(event: "switcher.selection.cleared")
            return
        }

        let project = filteredProjects[row]
        session.logEvent(
            event: "switcher.selection.changed",
            context: [
                "row": "\(row)",
                "project_id": project.id,
                "project_name": project.name
            ]
        )
    }
}

// MARK: - NSSearchFieldDelegate, NSControlTextEditingDelegate

extension SwitcherPanelController: NSSearchFieldDelegate, NSControlTextEditingDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else {
            return
        }
        applyFilter(query: field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            session.logEvent(event: "switcher.action.enter")
            handleSelection()
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            session.logEvent(event: "switcher.action.escape")
            dismiss(reason: .escape)
            return true
        }

        return false
    }
}
