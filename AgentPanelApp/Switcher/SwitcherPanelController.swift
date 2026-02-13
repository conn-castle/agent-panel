//
//  SwitcherPanelController.swift
//  AgentPanel
//
//  Core controller for the project switcher panel.
//  Manages panel lifecycle, keyboard navigation, grouped project rows,
//  and selection handling.
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

// SwitcherDismissReason is defined in AgentPanelCore/SwitcherDismissPolicy.swift

/// Timing constants for switcher behavior.
private enum SwitcherTiming {
    static let visibilityCheckDelaySeconds: TimeInterval = 0.15
    static let queryReuseWindowSeconds: TimeInterval = 10.0
}

/// Layout constants for the switcher panel.
private enum SwitcherLayout {
    static let panelWidth: CGFloat = 560
    static let initialPanelHeight: CGFloat = 420
    static let minPanelHeight: CGFloat = 280
    static let maxHeightScreenFraction: CGFloat = 0.65
    static let chromeHeightEstimate: CGFloat = 185
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

/// Row model for the grouped switcher results list.
private enum SwitcherListRow {
    case sectionHeader(title: String)
    case backAction
    case project(project: ProjectConfig, isCurrent: Bool, isOpen: Bool)
    case emptyState(message: String)

    var isSelectable: Bool {
        switch self {
        case .backAction, .project:
            return true
        case .sectionHeader, .emptyState:
            return false
        }
    }

    var selectionKey: String? {
        switch self {
        case .backAction:
            return "action:back"
        case .project(let project, _, _):
            return "project:\(project.id)"
        case .sectionHeader, .emptyState:
            return nil
        }
    }
}

/// Builder for grouped switcher rows and selection indices.
private enum SwitcherListModelBuilder {
    /// Builds grouped rows from current filter and workspace state.
    static func buildRows(
        filteredProjects: [ProjectConfig],
        activeProjectId: String?,
        openIds: Set<String>,
        query: String
    ) -> [SwitcherListRow] {
        var rows: [SwitcherListRow] = []

        if activeProjectId != nil {
            rows.append(.sectionHeader(title: "Actions"))
            rows.append(.backAction)
        }

        if let activeProjectId,
           let currentProject = filteredProjects.first(where: { $0.id == activeProjectId }) {
            rows.append(.sectionHeader(title: "Current"))
            rows.append(
                .project(
                    project: currentProject,
                    isCurrent: true,
                    isOpen: openIds.contains(currentProject.id)
                )
            )
        }

        let recentProjects = filteredProjects.filter { $0.id != activeProjectId }
        if !recentProjects.isEmpty {
            rows.append(.sectionHeader(title: "Recent"))
            for project in recentProjects {
                rows.append(
                    .project(
                        project: project,
                        isCurrent: false,
                        isOpen: openIds.contains(project.id)
                    )
                )
            }
        }

        if rows.isEmpty {
            let message = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "No projects available"
                : "No matching projects"
            rows = [.emptyState(message: message)]
        }

        return rows
    }

    /// Returns the row index for a stable selection key.
    static func rowIndex(forSelectionKey selectionKey: String, in rows: [SwitcherListRow]) -> Int? {
        rows.firstIndex(where: { $0.selectionKey == selectionKey && $0.isSelectable })
    }

    /// Returns the default selection index for open/filter states.
    static func defaultSelectionIndex(in rows: [SwitcherListRow], preferCurrentProject: Bool) -> Int? {
        if preferCurrentProject,
           let currentProjectIndex = rows.firstIndex(where: {
               if case .project(_, let isCurrent, _) = $0 {
                   return isCurrent
               }
               return false
           }) {
            return currentProjectIndex
        }

        if let firstProjectIndex = rows.firstIndex(where: {
            if case .project = $0 {
                return true
            }
            return false
        }) {
            return firstProjectIndex
        }

        return rows.firstIndex(where: { $0.isSelectable })
    }
}

// MARK: - Controller

/// Controls the switcher panel lifecycle and keyboard-driven UX.
final class SwitcherPanelController: NSObject {
    private let logger: AgentPanelLogging
    private let session: SwitcherSession
    private let projectManager: ProjectManager

    private let panel: SwitcherPanel
    private let titleLabel: NSTextField
    private let searchField: NSSearchField
    private let tableView: NSTableView
    private let scrollView: NSScrollView
    private let statusLabel: NSTextField
    private let keybindHintLabel: NSTextField

    private var allProjects: [ProjectConfig] = []
    private var filteredProjects: [ProjectConfig] = []
    private var rows: [SwitcherListRow] = []
    private var activeProjectId: String?
    private var openIds: Set<String> = []
    private var keyEventMonitor: Any?
    private var configErrorMessage: String?
    private var lastFilterQuery: String = ""
    private var lastStatusMessage: String?
    private var lastStatusLevel: StatusLevel?
    private var expectsVisible: Bool = false
    private var pendingVisibilityCheckToken: UUID?
    private var previouslyActiveApp: NSRunningApplication?
    private var suppressedActionEventTimestamp: TimeInterval?
    private var isDismissing: Bool = false
    private var isActivating: Bool = false
    private var lastDismissedAt: Date?
    private var lastDismissedQuery: String = ""
    private var restoreFocusTask: Task<Void, Never>?

    /// The captured focus state before the switcher opened.
    /// Used for restore-on-cancel via ProjectManager.
    private var capturedFocus: CapturedFocus?

    /// Called when a project operation fails (select, close, exit, workspace query, config load).
    /// Used by AppDelegate to trigger a background health indicator refresh.
    var onProjectOperationFailed: (() -> Void)?

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
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SwitcherLayout.panelWidth,
                height: SwitcherLayout.initialPanelHeight
            ),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        self.titleLabel = NSTextField(labelWithString: "Agent Panel Switcher")
        self.searchField = NSSearchField()
        self.tableView = NSTableView()
        self.scrollView = NSScrollView()
        self.statusLabel = NSTextField(labelWithString: "")
        self.keybindHintLabel = NSTextField(labelWithString: "")

        super.init()

        configurePanel()
        configureTitleLabel()
        configureSearchField()
        configureTableView()
        configureStatusLabel()
        configureKeybindHints()
        layoutContent()
    }

    deinit {
        removeKeyEventMonitor()
        restoreFocusTask?.cancel()
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
    func toggle(
        origin: SwitcherPresentationSource = .unknown,
        previousApp: NSRunningApplication? = nil,
        capturedFocus: CapturedFocus? = nil
    ) {
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
    func show(
        origin: SwitcherPresentationSource = .unknown,
        previousApp: NSRunningApplication? = nil,
        capturedFocus: CapturedFocus? = nil
    ) {
        let showStart = CFAbsoluteTimeGetCurrent()
        let shouldReuseQuery = shouldReuseLastQuery()
        let initialQuery = shouldReuseQuery ? lastDismissedQuery : ""

        // Use provided previousApp, or fall back to current frontmost (less reliable)
        restoreFocusTask?.cancel()
        previouslyActiveApp = previousApp ?? NSWorkspace.shared.frontmostApplication
        resetState(initialQuery: initialQuery)
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

        // Show panel first, then load results.
        showPanel(selectAllQuery: shouldReuseQuery && !initialQuery.isEmpty)
        installKeyEventMonitor()

        loadProjects()
        if configErrorMessage == nil {
            refreshWorkspaceState()
        }

        applyFilter(query: initialQuery, preferredSelectionKey: nil, useDefaultSelection: true)

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
        guard !isDismissing else {
            session.logEvent(
                event: "switcher.dismiss.reentrant_blocked",
                level: .warn,
                context: ["reason": reason.rawValue]
            )
            return
        }
        isDismissing = true
        defer { isDismissing = false }

        removeKeyEventMonitor()
        expectsVisible = false
        isActivating = false
        pendingVisibilityCheckToken = nil
        restoreFocusTask?.cancel()
        session.end(reason: reason)

        // Save query for short-term reopen convenience.
        lastDismissedQuery = searchField.stringValue
        lastDismissedAt = Date()

        let shouldRestore = SwitcherDismissPolicy.shouldRestoreFocus(reason: reason)

        // Restore focus unless the action handles it.
        // IMPORTANT: Activate the previous app BEFORE closing the panel to prevent
        // macOS from picking a random window when the panel disappears.
        if shouldRestore {
            if let previousApp = previouslyActiveApp {
                previousApp.activate()
            }
        }

        panel.orderOut(nil)

        // Do precise AeroSpace window focus async (can be slow).
        if shouldRestore {
            restorePreviousFocus()
        } else {
            previouslyActiveApp = nil
        }

        capturedFocus = nil
        resetState(initialQuery: "")
    }

    // MARK: - Focus Capture and Restore

    /// Restores focus to the previously focused window or app.
    /// Runs asynchronously to avoid blocking the main thread if AeroSpace commands are slow.
    private func restorePreviousFocus() {
        let focus = capturedFocus
        let previousApp = previouslyActiveApp
        let projectManager = self.projectManager
        let session = self.session

        // Clear references immediately so they're not reused
        previouslyActiveApp = nil

        restoreFocusTask?.cancel()
        restoreFocusTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            let restoreStart = CFAbsoluteTimeGetCurrent()

            // Try AeroSpace restore first via ProjectManager
            if let focus {
                if projectManager.restoreFocus(focus) {
                    let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                    await MainActor.run {
                        session.logEvent(
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
                    // Window gone — try focusing the workspace the user was on
                    if projectManager.focusWorkspace(name: focus.workspace) {
                        let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                        await MainActor.run {
                            session.logEvent(
                                event: "switcher.focus.restored",
                                context: [
                                    "workspace": focus.workspace,
                                    "method": "workspace_fallback",
                                    "restore_ms": "\(restoreMs)"
                                ]
                            )
                        }
                        return
                    }

                    let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                    await MainActor.run {
                        session.logEvent(
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
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let previousApp {
                    previousApp.activate()
                    let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                    session.logEvent(
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
        panel.title = "Agent Panel Switcher"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
    }

    /// Configures the optional title label shown above the search field.
    private func configureTitleLabel() {
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Configures the search field appearance and delegate wiring.
    private func configureSearchField() {
        searchField.placeholderString = "Search projects…"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
    }

    /// Configures the table view used for grouped rows.
    private func configureTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ProjectColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(handleTableViewAction(_:))
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

    /// Configures the keybind hints footer label.
    private func configureKeybindHints() {
        keybindHintLabel.textColor = .tertiaryLabelColor
        keybindHintLabel.font = NSFont.systemFont(ofSize: 11)
        keybindHintLabel.alignment = .left
        keybindHintLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Lays out the panel content using Auto Layout.
    private func layoutContent() {
        guard let contentView = panel.contentView else {
            return
        }

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 20
        contentView.layer?.masksToBounds = true
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97).cgColor

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let statusStack = NSStackView(views: [statusLabel])
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 8
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, searchField, scrollView, statusStack, keybindHintLabel])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - State Management

    /// Returns true when the previous query should be reused on reopen.
    private func shouldReuseLastQuery() -> Bool {
        guard let lastDismissedAt else {
            return false
        }
        return Date().timeIntervalSince(lastDismissedAt) <= SwitcherTiming.queryReuseWindowSeconds
    }

    /// Resets query, rows, and status labels.
    private func resetState(initialQuery: String) {
        allProjects = []
        searchField.stringValue = initialQuery
        searchField.isEnabled = true
        searchField.isEditable = true
        configErrorMessage = nil
        filteredProjects = []
        rows = []
        activeProjectId = nil
        openIds = []
        tableView.isEnabled = true
        lastFilterQuery = initialQuery
        lastStatusMessage = nil
        lastStatusLevel = nil
        tableView.reloadData()
        tableView.deselectAll(nil)
        clearStatus()
        updateFooterHints()
    }

    /// Shows the panel and focuses the search field.
    ///
    /// The panel uses `.nonactivatingPanel` style mask which allows it to receive keyboard
    /// input without activating the owning app. This prevents workspace switching when the
    /// switcher is invoked from a different workspace. The system handles keyboard focus
    /// via "key focus theft" - the panel becomes key while the previous app remains active.
    private func showPanel(selectAllQuery: Bool) {
        updatePanelSizeForCurrentRows()
        centerPanelOnActiveDisplay()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)

        if selectAllQuery {
            DispatchQueue.main.async { [weak self] in
                self?.searchField.selectText(nil)
            }
        }
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
            onProjectOperationFailed?()

        case .success(let success):
            allProjects = success.config.projects
            configErrorMessage = nil
            if let firstWarning = success.warnings.first {
                setStatus(message: "Config warning: \(firstWarning.title)", level: .warning)
            } else {
                clearStatus()
            }
            session.logConfigLoaded(projectCount: success.config.projects.count)
        }
    }

    /// Refreshes focused/open project workspace state for row grouping and close affordances.
    private func refreshWorkspaceState() {
        switch projectManager.workspaceState() {
        case .success(let state):
            activeProjectId = state.activeProjectId
            openIds = state.openProjectIds
        case .failure(let error):
            activeProjectId = nil
            openIds = []
            setStatus(
                message: "Workspace state unavailable: \(projectErrorMessage(error))",
                level: .warning
            )
            session.logEvent(
                event: "switcher.workspace_state.failed",
                level: .warn,
                message: "\(error)"
            )
            onProjectOperationFailed?()
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

    // MARK: - Filtering and Rows

    /// Applies filtering and updates grouped rows and selection.
    private func applyFilter(
        query: String,
        preferredSelectionKey: String?,
        useDefaultSelection: Bool
    ) {
        let previousQuery = lastFilterQuery
        lastFilterQuery = query
        let fallbackSelectionKey = preferredSelectionKey ?? selectedRowKey()

        guard configErrorMessage == nil else {
            rows = [.emptyState(message: configErrorMessage ?? "Config error")]
            filteredProjects = []
            tableView.reloadData()
            tableView.deselectAll(nil)
            updatePanelSizeForCurrentRows()
            updateFooterHints()
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

        filteredProjects = projectManager.sortedProjects(query: query)
        rows = SwitcherListModelBuilder.buildRows(
            filteredProjects: filteredProjects,
            activeProjectId: activeProjectId,
            openIds: openIds,
            query: query
        )
        tableView.reloadData()
        restoreSelection(
            preferredSelectionKey: fallbackSelectionKey,
            useDefaultSelection: useDefaultSelection
        )
        refreshVisibleProjectRowSelection()
        updatePanelSizeForCurrentRows()
        updateFooterHints()

        session.logEvent(
            event: "switcher.filter.applied",
            context: [
                "query": query,
                "previous_query": previousQuery,
                "total_count": "\(allProjects.count)",
                "filtered_count": "\(filteredProjects.count)"
            ]
        )

        if !rows.contains(where: { if case .project = $0 { return true } else { return false } }) {
            session.logEvent(
                event: "switcher.filter.empty",
                message: "No matches.",
                context: ["query": query]
            )
        }
    }

    /// Restores selection by key, with a fallback default selection policy.
    private func restoreSelection(preferredSelectionKey: String?, useDefaultSelection: Bool) {
        if let preferredSelectionKey,
           let preferredRow = SwitcherListModelBuilder.rowIndex(forSelectionKey: preferredSelectionKey, in: rows) {
            tableView.selectRowIndexes(IndexSet(integer: preferredRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(preferredRow)
            return
        }

        if let fallbackRow = SwitcherListModelBuilder.defaultSelectionIndex(
            in: rows,
            preferCurrentProject: useDefaultSelection
        ) {
            tableView.selectRowIndexes(IndexSet(integer: fallbackRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(fallbackRow)
        } else {
            tableView.deselectAll(nil)
        }
    }

    /// Returns the currently selected row model.
    private func selectedRowModel() -> SwitcherListRow? {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count else {
            return nil
        }
        return rows[row]
    }

    /// Returns the stable key for the selected row, when available.
    private func selectedRowKey() -> String? {
        selectedRowModel()?.selectionKey
    }

    /// Returns the currently selected project row values.
    private func selectedProjectRow() -> (project: ProjectConfig, isCurrent: Bool, isOpen: Bool)? {
        guard let selectedModel = selectedRowModel() else {
            return nil
        }
        if case .project(let project, let isCurrent, let isOpen) = selectedModel {
            return (project, isCurrent, isOpen)
        }
        return nil
    }

    // MARK: - Selection and Actions

    /// Handles the primary action for the selected row.
    private func handlePrimaryAction() {
        guard let selectedModel = selectedRowModel() else {
            session.logEvent(
                event: "switcher.selection.skipped",
                level: .warn,
                message: "Selection skipped because no row is selected.",
                context: ["reason": "no_selection"]
            )
            return
        }

        switch selectedModel {
        case .project(let project, _, _):
            handleProjectSelection(project)
        case .backAction:
            handleExitToNonProject(fromShortcut: false)
        case .sectionHeader, .emptyState:
            break
        }
    }

    /// Handles project switching for a selected project row.
    private func handleProjectSelection(_ project: ProjectConfig) {
        session.logEvent(
            event: "switcher.project.selected",
            context: [
                "project_id": project.id,
                "project_name": project.name
            ]
        )

        // Show progress and disable interaction during activation
        setStatus(message: "Switching to \(project.name)...", level: .info)
        searchField.isEnabled = false
        tableView.isEnabled = false
        isActivating = true

        guard let focusForExit = capturedFocus else {
            setStatus(message: "Could not capture focus", level: .error)
            searchField.isEnabled = true
            tableView.isEnabled = true
            isActivating = false
            return
        }

        let projectId = project.id
        Task { [weak self] in
            guard let self else { return }

            let result = await self.projectManager.selectProject(
                projectId: projectId,
                preCapturedFocus: focusForExit
            )

            await MainActor.run {
                self.isActivating = false
                self.searchField.isEnabled = true
                self.tableView.isEnabled = true

                switch result {
                case .success(let activation):
                    if let warning = activation.tabRestoreWarning {
                        self.session.logEvent(
                            event: "switcher.project.tab_restore_warning",
                            level: .warn,
                            message: warning,
                            context: ["project_id": projectId]
                        )
                    }
                    if let warning = activation.layoutWarning {
                        self.session.logEvent(
                            event: "switcher.project.layout_warning",
                            level: .warn,
                            message: warning,
                            context: ["project_id": projectId]
                        )
                    }
                    // Dismiss first, then focus the IDE (avoids panel close stealing focus)
                    self.dismiss(reason: .projectSelected)
                    self.focusIdeWindow(windowId: activation.ideWindowId)
                case .failure(let error):
                    self.setStatus(message: self.projectErrorMessage(error), level: .error)
                    self.session.logEvent(
                        event: "switcher.project.activation_failed",
                        level: .error,
                        message: "\(error)",
                        context: ["project_id": projectId]
                    )
                    self.onProjectOperationFailed?()
                }
            }
        }
    }

    /// Handles "close selected project" keyboard action.
    private func handleCloseSelectedProject() {
        guard let selectedProject = selectedProjectRow() else {
            session.logEvent(
                event: "switcher.close_project.skipped",
                level: .warn,
                message: "No project selected."
            )
            NSSound.beep()
            return
        }

        guard selectedProject.isOpen else {
            session.logEvent(
                event: "switcher.close_project.skipped",
                level: .warn,
                message: "Selected project is not open.",
                context: ["project_id": selectedProject.project.id]
            )
            setStatus(message: "Project is not currently open.", level: .warning)
            NSSound.beep()
            return
        }

        performCloseProject(
            projectId: selectedProject.project.id,
            projectName: selectedProject.project.name,
            source: "keybind",
            selectedRowAtRequestTime: tableView.selectedRow
        )
    }

    /// Handles close button clicks from a project row.
    private func handleCloseProjectButtonClick(projectId: String, rowIndex: Int) {
        suppressedActionEventTimestamp = NSApp.currentEvent?.timestamp

        let projectName = allProjects.first(where: { $0.id == projectId })?.name ?? projectId
        performCloseProject(
            projectId: projectId,
            projectName: projectName,
            source: "button",
            selectedRowAtRequestTime: rowIndex
        )
    }

    /// Closes a project and keeps the palette open for additional actions.
    private func performCloseProject(
        projectId: String,
        projectName: String,
        source: String,
        selectedRowAtRequestTime: Int
    ) {
        session.logEvent(
            event: "switcher.close_project.requested",
            context: [
                "project_id": projectId,
                "source": source
            ]
        )

        let fallbackSelectionKey = selectionKeyAfterClosingRow(
            closedProjectId: projectId,
            closedRowIndex: selectedRowAtRequestTime
        )

        switch projectManager.closeProject(projectId: projectId) {
        case .success(let closeResult):
            if let warning = closeResult.tabCaptureWarning {
                session.logEvent(
                    event: "switcher.close_project.tab_capture_warning",
                    level: .warn,
                    message: warning,
                    context: ["project_id": projectId]
                )
            }
            session.logEvent(
                event: "switcher.close_project.succeeded",
                context: ["project_id": projectId]
            )

            // closeProject already restored focus (via focus stack or workspace fallback).
            // Refresh captured focus so:
            // - dismiss doesn't restore stale pre-switcher focus (which may have been destroyed)
            // - a subsequent project selection pushes the correct non-project focus entry
            let refreshedFocus = projectManager.captureCurrentFocus()
            if let refreshedFocus,
               let selfBundleId = Bundle.main.bundleIdentifier,
               refreshedFocus.appBundleId != selfBundleId {
                capturedFocus = refreshedFocus
                previouslyActiveApp = NSWorkspace.shared.frontmostApplication
            } else {
                capturedFocus = nil
                previouslyActiveApp = nil
            }

            refreshWorkspaceState()
            applyFilter(
                query: searchField.stringValue,
                preferredSelectionKey: fallbackSelectionKey,
                useDefaultSelection: false
            )
            if closeResult.tabCaptureWarning != nil {
                setStatus(message: "Closed '\(projectName)' (tab capture failed)", level: .warning)
            } else {
                setStatus(message: "Closed '\(projectName)'", level: .info)
            }
        case .failure(let error):
            setStatus(message: projectErrorMessage(error), level: .error)
            session.logEvent(
                event: "switcher.close_project.failed",
                level: .error,
                message: "\(error)",
                context: ["project_id": projectId]
            )
            onProjectOperationFailed?()
        }
    }

    /// Computes the next selection key after closing a row.
    private func selectionKeyAfterClosingRow(
        closedProjectId: String,
        closedRowIndex: Int
    ) -> String? {
        guard !rows.isEmpty else {
            return nil
        }

        for index in (closedRowIndex + 1)..<rows.count {
            guard let key = rows[index].selectionKey else { continue }
            if key != "project:\(closedProjectId)" {
                return key
            }
        }

        if closedRowIndex > 0 {
            for index in stride(from: closedRowIndex - 1, through: 0, by: -1) {
                guard let key = rows[index].selectionKey else { continue }
                if key != "project:\(closedProjectId)" {
                    return key
                }
            }
        }

        return nil
    }

    /// Exits to the last non-project window and dismisses the panel on success.
    private func handleExitToNonProject(fromShortcut: Bool) {
        guard rows.contains(where: {
            if case .backAction = $0 {
                return true
            }
            return false
        }) else {
            if fromShortcut {
                NSSound.beep()
            }
            return
        }

        session.logEvent(event: "switcher.exit_to_previous.requested")

        switch projectManager.exitToNonProjectWindow() {
        case .success:
            session.logEvent(event: "switcher.exit_to_previous.succeeded")
            dismiss(reason: .exitedToNonProject)
        case .failure(let error):
            setStatus(message: projectErrorMessage(error), level: .error)
            session.logEvent(
                event: "switcher.exit_to_previous.failed",
                level: .error,
                message: "\(error)"
            )
            onProjectOperationFailed?()
            NSSound.beep()

            // Refresh row validity in case active-project state changed.
            refreshWorkspaceState()
            applyFilter(
                query: searchField.stringValue,
                preferredSelectionKey: selectedRowKey(),
                useDefaultSelection: false
            )
        }
    }

    /// Moves selection up/down while skipping non-selectable rows.
    private func moveSelection(delta: Int) {
        guard !rows.isEmpty else { return }

        var currentIndex = tableView.selectedRow
        if currentIndex < 0 {
            currentIndex = delta > 0 ? -1 : rows.count
        }

        var candidate = currentIndex + delta
        while candidate >= 0 && candidate < rows.count {
            if rows[candidate].isSelectable {
                tableView.selectRowIndexes(IndexSet(integer: candidate), byExtendingSelection: false)
                tableView.scrollRowToVisible(candidate)
                return
            }
            candidate += delta
        }
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

    /// Updates footer hints based on row selection and available actions.
    private func updateFooterHints() {
        var parts: [String] = ["esc Dismiss"]

        if let selectedProject = selectedProjectRow(), selectedProject.isOpen {
            parts.append("\u{2318}\u{232B} Close Project")
        }

        if rows.contains(where: {
            if case .backAction = $0 {
                return true
            }
            return false
        }) {
            parts.append("\u{21E7}\u{21A9} Back to Previous Window")
        }

        parts.append("\u{21A9} Switch")

        keybindHintLabel.stringValue = parts.joined(separator: "      ")
    }

    // MARK: - Key Event Monitor

    /// Installs a local event monitor for palette-specific shortcuts.
    /// Used instead of performKeyEquivalent because non-activating panels
    /// do not reliably route key equivalents through the standard responder chain.
    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Shift+Return => Back to previous window.
            if (event.keyCode == 36 || event.keyCode == 76), modifiers == [.shift] {
                self.session.logEvent(event: "switcher.action.exit_to_previous_keybind")
                self.handleExitToNonProject(fromShortcut: true)
                return nil
            }

            // Cmd+Delete / Cmd+ForwardDelete => close selected project.
            if (event.keyCode == 51 || event.keyCode == 117), modifiers == [.command] {
                self.session.logEvent(event: "switcher.action.close_project_keybind")
                self.handleCloseSelectedProject()
                return nil
            }

            return event
        }
    }

    /// Removes the local event monitor.
    private func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    // MARK: - Table Row Appearance

    /// Refreshes project row selected-state visuals.
    private func refreshVisibleProjectRowSelection() {
        for (index, rowModel) in rows.enumerated() {
            guard case .project = rowModel else { continue }
            guard let rowView = tableView.view(
                atColumn: 0,
                row: index,
                makeIfNecessary: false
            ) as? ProjectRowView else { continue }
            rowView.setRowSelected(index == tableView.selectedRow)
        }
    }

    // MARK: - Sizing and Positioning

    /// Returns the display frame currently under the mouse pointer.
    private func activeDisplayFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Centers the panel on the active display.
    private func centerPanelOnActiveDisplay() {
        let displayFrame = activeDisplayFrame()
        let x = displayFrame.midX - (panel.frame.width / 2)
        let y = displayFrame.midY - (panel.frame.height / 2)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Updates panel height based on row count and available display height.
    private func updatePanelSizeForCurrentRows() {
        let displayFrame = activeDisplayFrame()
        let maxHeight = floor(displayFrame.height * SwitcherLayout.maxHeightScreenFraction)
        let rowHeights = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + heightForRow(row)
        }
        let targetHeight = max(
            SwitcherLayout.minPanelHeight,
            min(maxHeight, SwitcherLayout.chromeHeightEstimate + rowHeights)
        )

        var frame = panel.frame
        frame.size = NSSize(width: SwitcherLayout.panelWidth, height: targetHeight)
        panel.setFrame(frame, display: true)
        centerPanelOnActiveDisplay()
    }

    /// Returns row height for a given row type.
    private func heightForRow(_ row: SwitcherListRow) -> CGFloat {
        switch row {
        case .sectionHeader:
            return 22
        case .backAction:
            return 36
        case .project:
            return 44
        case .emptyState:
            return 36
        }
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

    // MARK: - Error Display Helpers

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

    // MARK: - Table Click Action

    /// Handles single-click actions on selectable rows.
    @objc private func handleTableViewAction(_ sender: Any?) {
        guard panel.isVisible else { return }

        if let suppressedTimestamp = suppressedActionEventTimestamp,
           let currentTimestamp = NSApp.currentEvent?.timestamp,
           abs(currentTimestamp - suppressedTimestamp) < 0.0001 {
            suppressedActionEventTimestamp = nil
            return
        }
        suppressedActionEventTimestamp = nil
        handlePrimaryAction()
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

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible else { return }
        let decision = SwitcherDismissPolicy.shouldDismissOnResignKey(
            isActivating: isActivating,
            isVisible: true
        )
        switch decision {
        case .dismiss:
            dismiss(reason: .windowClose)
        case .suppress(let reason):
            session.logEvent(
                event: "switcher.resign_key.suppressed",
                level: .info,
                context: ["reason": reason]
            )
        }
    }
}

// MARK: - NSTableViewDataSource, NSTableViewDelegate

extension SwitcherPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < rows.count else {
            return 32
        }
        return heightForRow(rows[row])
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < rows.count else {
            return nil
        }

        switch rows[row] {
        case .sectionHeader(let title):
            return sectionHeaderCell(title: title, tableView: tableView)
        case .backAction:
            return backActionCell(tableView: tableView)
        case .project(let project, let isCurrent, let isOpen):
            return projectCell(
                for: project,
                isActive: isCurrent,
                isOpen: isOpen,
                query: lastFilterQuery,
                isSelected: row == tableView.selectedRow,
                onClose: isOpen ? { [weak self] in
                    self?.handleCloseProjectButtonClick(projectId: project.id, rowIndex: row)
                } : nil,
                tableView: tableView
            )
        case .emptyState(let message):
            return emptyStateCell(message: message, tableView: tableView)
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < rows.count else {
            return false
        }
        return rows[row].isSelectable
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let rowIndex = tableView.selectedRow
        guard rowIndex >= 0, rowIndex < rows.count else {
            session.logEvent(event: "switcher.selection.cleared")
            updateFooterHints()
            refreshVisibleProjectRowSelection()
            return
        }

        switch rows[rowIndex] {
        case .project(let project, _, _):
            session.logEvent(
                event: "switcher.selection.changed",
                context: [
                    "row": "\(rowIndex)",
                    "project_id": project.id,
                    "project_name": project.name
                ]
            )
        case .backAction:
            session.logEvent(
                event: "switcher.selection.changed",
                context: [
                    "row": "\(rowIndex)",
                    "action": "back_to_previous_window"
                ]
            )
        case .sectionHeader, .emptyState:
            break
        }

        updateFooterHints()
        refreshVisibleProjectRowSelection()
    }
}

// MARK: - NSSearchFieldDelegate, NSControlTextEditingDelegate

extension SwitcherPanelController: NSSearchFieldDelegate, NSControlTextEditingDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else {
            return
        }
        applyFilter(
            query: field.stringValue,
            preferredSelectionKey: selectedRowKey(),
            useDefaultSelection: false
        )
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            session.logEvent(event: "switcher.action.enter")
            handlePrimaryAction()
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            session.logEvent(event: "switcher.action.escape")
            dismiss(reason: .escape)
            return true
        }

        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelection(delta: -1)
            return true
        }

        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelection(delta: 1)
            return true
        }

        return false
    }
}
