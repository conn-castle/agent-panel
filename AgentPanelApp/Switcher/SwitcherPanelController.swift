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
    ///
    /// - Parameters:
    ///   - origin: Source that triggered the toggle.
    ///   - previousApp: The app that was active before AgentPanel was activated.
    ///                  Must be captured BEFORE calling NSApp.activate().
    func toggle(origin: SwitcherPresentationSource = .unknown, previousApp: NSRunningApplication? = nil) {
        if panel.isVisible {
            dismiss(reason: .toggle)
        } else {
            show(origin: origin, previousApp: previousApp)
        }
    }

    /// Shows the switcher panel and resets transient state.
    ///
    /// - Parameters:
    ///   - origin: Source that triggered the show.
    ///   - previousApp: The app that was active before AgentPanel was activated.
    ///                  Must be captured BEFORE calling NSApp.activate().
    func show(origin: SwitcherPresentationSource = .unknown, previousApp: NSRunningApplication? = nil) {
        // Use provided previousApp, or fall back to current frontmost (less reliable)
        previouslyActiveApp = previousApp ?? NSWorkspace.shared.frontmostApplication
        resetState()
        expectsVisible = true
        session.begin(origin: origin)
        session.logShowRequested(origin: origin)

        // Load config and set up focus operations
        loadProjects()

        // Capture the currently focused window before showing switcher
        capturedFocus = projectManager.captureCurrentFocus()
        if let focus = capturedFocus {
            session.logEvent(
                event: "switcher.focus.captured",
                context: [
                    "window_id": "\(focus.windowId)",
                    "app_bundle_id": focus.appBundleId
                ]
            )
        } else {
            session.logEvent(
                event: "switcher.focus.capture_failed",
                level: .warn,
                message: "Could not capture focused window."
            )
        }

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

        capturedFocus = nil
        resetState()
    }

    // MARK: - Focus Capture and Restore

    /// Restores focus to the previously focused window or app.
    private func restorePreviousFocus() {
        // Try AeroSpace restore first via ProjectManager
        if let focus = capturedFocus {
            if projectManager.restoreFocus(focus) {
                session.logEvent(
                    event: "switcher.focus.restored",
                    context: [
                        "window_id": "\(focus.windowId)",
                        "method": "aerospace"
                    ]
                )
                previouslyActiveApp = nil
                return
            } else {
                session.logEvent(
                    event: "switcher.focus.restore_failed",
                    level: .warn,
                    message: "AeroSpace focus restore failed, falling back to app activation.",
                    context: ["window_id": "\(focus.windowId)"]
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

        previouslyActiveApp = nil
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

        // Dismiss without restoring previous focus (we're switching to this project)
        dismiss(reason: .projectSelected)

        // Activate the project (opens IDE/Chrome, moves to workspace, focuses IDE)
        let result = projectManager.selectProject(projectId: project.id)
        if case .failure(let error) = result {
            session.logEvent(
                event: "switcher.project.activation_failed",
                level: .error,
                message: "\(error)",
                context: ["project_id": project.id]
            )
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

        return false
    }
}
