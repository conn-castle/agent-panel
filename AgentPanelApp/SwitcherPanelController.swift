import AppKit

import apcore

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
    case windowClose
    case unknown
}

private enum SwitcherTiming {
    static let visibilityCheckDelaySeconds: TimeInterval = 0.15
}

/// Controls the switcher panel lifecycle and keyboard-driven UX.
final class SwitcherPanelController: NSObject {
    private let logger: AgentPanelLogging

    private let panel: SwitcherPanel
    private let searchField: NSSearchField
    private let tableView: NSTableView
    private let statusLabel: NSTextField

    private var allProjects: [ProjectConfig] = []
    private var filteredProjects: [ProjectConfig] = []
    private var configErrorMessage: String?
    private var switcherSessionId: String?
    private var sessionOrigin: SwitcherPresentationSource = .unknown
    private var lastFilterQuery: String = ""
    private var lastStatusMessage: String?
    private var lastStatusLevel: StatusLevel?
    private var expectsVisible: Bool = false
    private var pendingVisibilityCheckToken: UUID?

    /// Creates a switcher panel controller.
    /// - Parameter logger: Logger used for switcher diagnostics.
    init(logger: AgentPanelLogging = AgentPanelLogger()) {
        self.logger = logger

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
        resetState()
        expectsVisible = true
        beginSession(origin: origin)
        logShowRequested(origin: origin)
        showPanel()
        loadProjects()
        applyFilter(query: "")
        scheduleVisibilityCheck(origin: origin)
    }

    /// Dismisses the switcher panel and clears transient state.
    func dismiss(reason: SwitcherDismissReason = .unknown) {
        expectsVisible = false
        endSession(reason: reason)
        panel.orderOut(nil)
        resetState()
    }

    /// Returns the panel visibility for tests.
    func isPanelVisibleForTesting() -> Bool {
        panel.isVisible
    }

    /// Returns the panel collection behavior for tests.
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

    /// Loads projects from config and surfaces warnings or failures.
    private func loadProjects() {
        switch ConfigLoader.loadDefault() {
        case .failure(let error):
            allProjects = []
            filteredProjects = []
            configErrorMessage = error.message
            setStatus(message: "Config error: \(error.message)", level: .error)
            logConfigFailure(error)
        case .success(let result):
            guard let config = result.config else {
                allProjects = []
                filteredProjects = []
                let firstFinding = result.findings.first
                configErrorMessage = firstFinding?.title ?? "Config error"
                setStatus(message: "Config error: \(configErrorMessage ?? "Unknown")", level: .error)
                logConfigFindingsFailure(result.findings)
                return
            }

            allProjects = config.projects
            configErrorMessage = nil

            let warnings = result.findings.filter { $0.severity == .warn }
            if warnings.isEmpty {
                clearStatus()
                logConfigLoaded(projectCount: config.projects.count)
            } else {
                setStatus(message: "Config warnings detected. Run Doctor for details.", level: .warning)
                logConfigWarnings(projectCount: config.projects.count, warningCount: warnings.count)
            }
        }
    }

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

        filteredProjects = filterProjects(allProjects, query: query)
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

    /// Starts a new switcher session for log correlation.
    private func beginSession(origin: SwitcherPresentationSource) {
        switcherSessionId = UUID().uuidString
        sessionOrigin = origin
        logEvent(
            event: "switcher.session.start",
            context: ["source": origin.rawValue]
        )
    }

    /// Ends the current switcher session and records the reason.
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
    private func logShowRequested(origin: SwitcherPresentationSource) {
        logEvent(
            event: "switcher.show.requested",
            context: ["source": origin.rawValue]
        )
    }

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

    /// Logs a config load failure for diagnostics.
    private func logConfigFailure(_ error: ConfigError) {
        let configPath = AgentPanelPaths.defaultPaths().configFile.path
        logEvent(
            event: "switcher.config.failure",
            level: .error,
            message: error.message,
            context: ["config_path": configPath]
        )
    }

    /// Logs config findings failure for diagnostics.
    private func logConfigFindingsFailure(_ findings: [ConfigFinding]) {
        let configPath = AgentPanelPaths.defaultPaths().configFile.path
        let primary = findings.first
        logEvent(
            event: "switcher.config.failure",
            level: .error,
            message: primary?.title,
            context: [
                "finding_count": "\(findings.count)",
                "config_path": configPath
            ]
        )
    }

    /// Logs config warnings for diagnostics.
    private func logConfigWarnings(projectCount: Int, warningCount: Int) {
        let configPath = AgentPanelPaths.defaultPaths().configFile.path
        logEvent(
            event: "switcher.config.warnings",
            level: .warn,
            message: "Config warnings detected.",
            context: [
                "project_count": "\(projectCount)",
                "warning_count": "\(warningCount)",
                "config_path": configPath
            ]
        )
    }

    /// Logs successful config load summaries.
    private func logConfigLoaded(projectCount: Int) {
        let configPath = AgentPanelPaths.defaultPaths().configFile.path
        logEvent(
            event: "switcher.config.loaded",
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

    /// Logs that a project was selected.
    private func handleSelection() {
        guard let project = selectedProject() else {
            logEvent(
                event: "switcher.selection.skipped",
                level: .warn,
                message: "Selection skipped because no project is selected.",
                context: ["reason": "no_selection"]
            )
            return
        }

        logEvent(
            event: "switcher.project.selected",
            context: [
                "project_id": project.id,
                "project_name": project.name
            ]
        )
        // TODO: Wire project activation.
    }

    /// Returns the currently selected project, if any.
    private func selectedProject() -> ProjectConfig? {
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

    private var emptyStateMessage: String? {
        if let configErrorMessage {
            return configErrorMessage
        }
        return filteredProjects.isEmpty ? "No matches" : nil
    }
}

extension SwitcherPanelController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        dismiss(reason: .windowClose)
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
        applyFilter(query: field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            logEvent(event: "switcher.action.enter")
            handleSelection()
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            logEvent(event: "switcher.action.escape")
            dismiss(reason: .escape)
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

private func projectCell(for project: ProjectConfig, tableView: NSTableView) -> NSTableCellView {
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

private func configureProjectCell(_ cell: ProjectRowView, project: ProjectConfig) {
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
