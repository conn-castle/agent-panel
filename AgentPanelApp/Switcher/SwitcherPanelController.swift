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

// MARK: - Controller

/// Controls the switcher panel lifecycle and keyboard-driven UX.
final class SwitcherPanelController: NSObject {
    private let logger: AgentPanelLogging
    private let session: SwitcherSession
    private let projectManager: ProjectManager

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

    /// The captured focus state before the switcher opened.
    /// Used for restore-on-cancel via ProjectManager.
    private var capturedFocus: CapturedFocus?

    /// Creates a switcher panel controller.
    /// - Parameters:
    ///   - logger: Logger used for switcher diagnostics.
    ///   - projectManager: Project manager for config, sorting, and focus operations.
    init(
        logger: AgentPanelLogging = AgentPanelLogger(),
        projectManager: ProjectManager = ProjectManager()
    ) {
        self.logger = logger
        self.session = SwitcherSession(logger: logger)
        self.projectManager = projectManager

        self.panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.nonactivatingPanel, .titled, .closable],
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
    ///
    /// - Parameters:
    ///   - origin: Source that triggered the toggle.
    ///   - previousApp: The app that was active before AgentPanel was activated.
    ///                  Must be captured BEFORE calling NSApp.activate().
    ///   - capturedFocus: The window focus state captured before activation.
    ///                    Must be captured BEFORE calling NSApp.activate().
    func toggle(origin: SwitcherPresentationSource = .unknown, previousApp: NSRunningApplication? = nil, capturedFocus: CapturedFocus? = nil) {
        if panel.isVisible {
            dismiss(reason: .toggle)
        } else {
            show(origin: origin, previousApp: previousApp, capturedFocus: capturedFocus)
        }
    }

    /// Shows the switcher panel and resets transient state.
    ///
    /// - Parameters:
    ///   - origin: Source that triggered the show.
    ///   - previousApp: The app that was active before AgentPanel was activated.
    ///                  Must be captured BEFORE calling NSApp.activate().
    ///   - capturedFocus: The window focus state captured before activation.
    ///                    Must be captured BEFORE calling NSApp.activate().
    func show(origin: SwitcherPresentationSource = .unknown, previousApp: NSRunningApplication? = nil, capturedFocus: CapturedFocus? = nil) {
        let showStart = CFAbsoluteTimeGetCurrent()

        // Use provided previousApp, or fall back to current frontmost (less reliable)
        previouslyActiveApp = previousApp ?? NSWorkspace.shared.frontmostApplication
        resetState()
        expectsVisible = true
        session.begin(origin: origin)
        session.logShowRequested(origin: origin)

        // Use pre-captured focus (captured before NSApp.activate() in caller)
        self.capturedFocus = capturedFocus

        if let focus = capturedFocus {
            session.logEvent(
                event: "switcher.focus.received",
                context: [
                    "window_id": "\(focus.windowId)",
                    "app_bundle_id": focus.appBundleId
                ]
            )
        } else {
            session.logEvent(
                event: "switcher.focus.not_provided",
                level: .warn,
                message: "No focus state provided; restore-on-cancel may not work."
            )
        }

        // Show panel
        showPanel()

        // Load config and apply filter (should be fast - file read + in-memory sort)
        loadProjects()
        applyFilter(query: "")

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - showStart) * 1000)

        scheduleVisibilityCheck(origin: origin)

        session.logEvent(
            event: "switcher.show.timing",
            context: [
                "total_ms": "\(totalMs)"
            ]
        )
    }

    /// Dismisses the switcher panel and clears transient state.
    func dismiss(reason: SwitcherDismissReason = .unknown) {
        expectsVisible = false
        session.end(reason: reason)

        // Restore focus unless a project was selected (switching context)
        // IMPORTANT: Activate the previous app BEFORE closing the panel to prevent
        // macOS from picking a random window when the panel disappears.
        if reason != .projectSelected {
            // Synchronously activate the previous app first (fast operation)
            if let previousApp = previouslyActiveApp {
                previousApp.activate()
            }
        }

        panel.orderOut(nil)

        // Now do the precise AeroSpace window focus async (can be slow)
        if reason != .projectSelected {
            restorePreviousFocus()
        }

        capturedFocus = nil
        resetState()
    }

    // MARK: - Focus Capture and Restore

    /// Restores focus to the previously focused window or app.
    /// Runs asynchronously to avoid blocking the main thread if AeroSpace commands are slow.
    private func restorePreviousFocus() {
        let focus = capturedFocus
        let previousApp = previouslyActiveApp

        // Clear references immediately so they're not reused
        previouslyActiveApp = nil

        // Run focus restore on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let restoreStart = CFAbsoluteTimeGetCurrent()

            // Try AeroSpace restore first via ProjectManager
            if let focus {
                if self?.projectManager.restoreFocus(focus) == true {
                    let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                    DispatchQueue.main.async {
                        self?.session.logEvent(
                            event: "switcher.focus.restored",
                            context: [
                                "window_id": "\(focus.windowId)",
                                "method": "aerospace",
                                "restore_ms": "\(restoreMs)"
                            ]
                        )
                    }
                    return
                } else {
                    let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                    DispatchQueue.main.async {
                        self?.session.logEvent(
                            event: "switcher.focus.restore_failed",
                            level: .warn,
                            message: "AeroSpace focus restore failed, falling back to app activation.",
                            context: [
                                "window_id": "\(focus.windowId)",
                                "restore_ms": "\(restoreMs)"
                            ]
                        )
                    }
                }
            }

            // Fallback: activate the previously active app (must be on main thread)
            DispatchQueue.main.async {
                if let previousApp {
                    previousApp.activate()
                    let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                    self?.session.logEvent(
                        event: "switcher.focus.restored",
                        context: [
                            "app_bundle_id": previousApp.bundleIdentifier ?? "unknown",
                            "method": "app_activation",
                            "restore_ms": "\(restoreMs)"
                        ]
                    )
                }
            }
        }
    }

    /// Focuses the IDE window after panel dismissal.
    /// Called after project selection to focus the IDE once the panel is closed.
    private func focusIdeWindow(windowId: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if self?.projectManager.focusWindow(windowId: windowId) == true {
                DispatchQueue.main.async {
                    self?.session.logEvent(
                        event: "switcher.ide.focused",
                        context: ["window_id": "\(windowId)"]
                    )
                }
            }
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
    ///
    /// The panel uses `.nonactivatingPanel` style mask which allows it to receive keyboard
    /// input without activating the owning app. This prevents workspace switching when the
    /// switcher is invoked from a different workspace. The system handles keyboard focus
    /// via "key focus theft" - the panel becomes key while the previous app remains active.
    private func showPanel() {
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    // MARK: - Project Loading

    /// Loads projects from config and surfaces warnings or failures.
    private func loadProjects() {
        switch projectManager.loadConfig() {
        case .failure(let error):
            allProjects = []
            filteredProjects = []
            configErrorMessage = configLoadErrorMessage(error)
            setStatus(message: "Config error: \(configErrorMessage ?? "Unknown")", level: .error)
            session.logEvent(
                event: "switcher.config.failed",
                level: .error,
                message: configErrorMessage
            )

        case .success(let config):
            allProjects = config.projects
            configErrorMessage = nil
            clearStatus()
            session.logConfigLoaded(projectCount: config.projects.count)
        }
    }

    /// Converts ConfigLoadError to a user-friendly message.
    private func configLoadErrorMessage(_ error: ConfigLoadError) -> String {
        switch error {
        case .fileNotFound(let path):
            return "Config file not found at \(path)"
        case .readFailed(let path, let detail):
            return "Could not read config at \(path): \(detail)"
        case .parseFailed(let detail):
            return "Config parse error: \(detail)"
        case .validationFailed(let findings):
            let firstFail = findings.first { $0.severity == .fail }
            return firstFail?.title ?? "Config validation failed"
        }
    }

    // MARK: - Filtering

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

        // Sort and filter projects (ProjectManager handles recency internally)
        filteredProjects = projectManager.sortedProjects(query: query)
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

        session.logEvent(
            event: "switcher.project.selected",
            context: [
                "project_id": project.id,
                "project_name": project.name
            ]
        )

        // Show progress and disable interaction during activation
        setStatus(message: "Activating \(project.name)...", level: .info)
        searchField.isEnabled = false
        tableView.isEnabled = false

        // Run activation asynchronously (Chrome and IDE setup run in parallel)
        // Pass the pre-captured focus to avoid redundant AeroSpace calls while panel is visible
        guard let focusForExit = capturedFocus else {
            setStatus(message: "Could not capture focus", level: .error)
            searchField.isEnabled = true
            tableView.isEnabled = true
            return
        }
        let projectId = project.id
        Task { [weak self] in
            guard let self else { return }

            let result = await self.projectManager.selectProject(projectId: projectId, preCapturedFocus: focusForExit)

            await MainActor.run {
                self.searchField.isEnabled = true
                self.tableView.isEnabled = true

                switch result {
                case .success(let ideWindowId):
                    // Dismiss first, then focus the IDE (avoids panel close stealing focus)
                    self.dismiss(reason: .projectSelected)
                    self.focusIdeWindow(windowId: ideWindowId)
                case .failure(let error):
                    self.setStatus(message: self.projectErrorMessage(error), level: .error)
                    self.session.logEvent(
                        event: "switcher.project.activation_failed",
                        level: .error,
                        message: "\(error)",
                        context: ["project_id": projectId]
                    )
                }
            }
        }
    }

    /// Converts ProjectError to a user-friendly message.
    private func projectErrorMessage(_ error: ProjectError) -> String {
        switch error {
        case .projectNotFound(let id):
            return "Project not found: \(id)"
        case .configNotLoaded:
            return "Config not loaded"
        case .aeroSpaceError(let detail):
            return "AeroSpace error: \(detail)"
        case .ideLaunchFailed(let detail):
            return "IDE launch failed: \(detail)"
        case .chromeLaunchFailed(let detail):
            return "Chrome launch failed: \(detail)"
        case .noActiveProject:
            return "No active project"
        case .noPreviousWindow:
            return "No previous window"
        case .windowNotFound(let detail):
            return "Window not found: \(detail)"
        case .focusUnstable(let detail):
            return "Focus unstable: \(detail)"
        }
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

        // Forward arrow keys to table view for navigation
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            let currentRow = tableView.selectedRow
            if currentRow > 0 {
                tableView.selectRowIndexes(IndexSet(integer: currentRow - 1), byExtendingSelection: false)
                tableView.scrollRowToVisible(currentRow - 1)
            }
            return true
        }

        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            let currentRow = tableView.selectedRow
            let maxRow = tableView.numberOfRows - 1
            if currentRow < maxRow {
                tableView.selectRowIndexes(IndexSet(integer: currentRow + 1), byExtendingSelection: false)
                tableView.scrollRowToVisible(currentRow + 1)
            }
            return true
        }

        return false
    }
}
