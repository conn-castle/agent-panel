import AppKit

import ProjectWorkspacesCore

/// Source of a switcher presentation request.
enum SwitcherPresentationSource: String {
    case menu
    case hotkey
    case unknown
}

/// Controls the switcher panel lifecycle and keyboard-driven UX.
final class SwitcherPanelController: NSObject {
    private let projectCatalogService: ProjectCatalogService
    private let projectFilter: ProjectFilter
    private let activationService: ActivationService
    private let logger: ProjectWorkspacesLogging

    private let panel: NSPanel
    private let searchField: NSSearchField
    private let tableView: NSTableView
    private let statusLabel: NSTextField

    private var allProjects: [ProjectListItem] = []
    private var filteredProjects: [ProjectListItem] = []
    private var catalogErrorMessage: String?
    private var isBusy: Bool = false
    private var expectsVisible: Bool = false
    private var pendingVisibilityCheckToken: UUID?

    /// Creates a switcher panel controller.
    /// - Parameters:
    ///   - projectCatalogService: Service that loads configured projects.
    ///   - projectFilter: Filter for case-insensitive matching.
    ///   - activationService: Activation service used to switch projects.
    init(
        projectCatalogService: ProjectCatalogService = ProjectCatalogService(),
        projectFilter: ProjectFilter = ProjectFilter(),
        activationService: ActivationService = ActivationService(),
        logger: ProjectWorkspacesLogging = ProjectWorkspacesLogger()
    ) {
        self.projectCatalogService = projectCatalogService
        self.projectFilter = projectFilter
        self.activationService = activationService
        self.logger = logger

        self.panel = NSPanel(
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
            dismiss()
        } else {
            show(origin: origin)
        }
    }

    /// Shows the switcher panel and resets transient state.
    func show(origin: SwitcherPresentationSource = .unknown) {
        resetState()
        expectsVisible = true
        logShowRequested(origin: origin)
        showPanel()
        loadProjects()
        applyFilter(query: "")
        scheduleVisibilityCheck(origin: origin)
    }

    /// Dismisses the switcher panel and clears transient state.
    func dismiss() {
        expectsVisible = false
        panel.orderOut(nil)
        resetState()
    }

    /// Returns the panel visibility for tests.
    /// - Returns: True if the panel is visible.
    func isPanelVisibleForTesting() -> Bool {
        panel.isVisible
    }

    /// Configures the switcher panel presentation behavior.
    private func configurePanel() {
        panel.title = "Project Switcher"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient]
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
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Lays out the panel content using Auto Layout.
    private func layoutContent() {
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [searchField, scrollView, statusLabel])
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
        guard catalogErrorMessage == nil else {
            filteredProjects = []
            tableView.reloadData()
            tableView.deselectAll(nil)
            return
        }

        filteredProjects = projectFilter.filter(projects: allProjects, query: query)
        tableView.reloadData()
        updateSelectionAfterFilter()
    }

    /// Resets query, selection, and status labels.
    private func resetState() {
        isBusy = false
        allProjects = []
        searchField.stringValue = ""
        searchField.isEnabled = true
        catalogErrorMessage = nil
        filteredProjects = []
        tableView.isEnabled = true
        clearStatus()
        tableView.reloadData()
        tableView.deselectAll(nil)
    }

    /// Shows the panel and focuses the search field.
    private func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    /// Records a show request for diagnostic tracing.
    /// - Parameter origin: Source of the presentation request.
    private func logShowRequested(origin: SwitcherPresentationSource) {
        _ = logger.log(
            event: "switcher.show.requested",
            level: .info,
            message: nil,
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
            _ = logger.log(
                event: "switcher.show.visible",
                level: .info,
                message: nil,
                context: context
            )
        } else {
            _ = logger.log(
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
        _ = logger.log(
            event: "switcher.catalog.failure",
            level: .error,
            message: primary?.title,
            context: [
                "finding_count": "\(error.findings.count)",
                "finding_detail": detail
            ]
        )
    }

    /// Logs a catalog warning summary for diagnostics.
    /// - Parameter result: Catalog result with warnings.
    private func logCatalogWarnings(_ result: ProjectCatalogResult) {
        _ = logger.log(
            event: "switcher.catalog.warnings",
            level: .warn,
            message: "Config warnings detected.",
            context: [
                "project_count": "\(result.projects.count)",
                "warning_count": "\(result.warnings.count)"
            ]
        )
    }

    /// Logs successful catalog load summaries.
    /// - Parameter projectCount: Count of projects loaded.
    private func logCatalogLoaded(projectCount: Int) {
        _ = logger.log(
            event: "switcher.catalog.loaded",
            level: .info,
            message: nil,
            context: ["project_count": "\(projectCount)"]
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
        guard !isBusy, let project = selectedProject() else {
            return
        }

        setBusy(true, message: "Activating...")

        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = self.activationService.activate(projectId: project.id)
            DispatchQueue.main.async {
                self.handleActivationOutcome(outcome)
            }
        }
    }

    /// Handles activation outcomes and updates UI state.
    /// - Parameter outcome: Activation result.
    private func handleActivationOutcome(_ outcome: ActivationOutcome) {
        switch outcome {
        case .success(_, let warnings):
            if warnings.isEmpty {
                dismiss()
            } else {
                setStatus(message: "Activated with warnings. See logs.", level: .warning)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.dismiss()
                }
            }
        case .failure(let error):
            setBusy(false, message: nil)
            let finding = error.asFindings().first
            let message = finding?.title ?? "Activation failed"
            setStatus(message: message, level: .error)
        }
    }

    /// Returns the currently selected project, if any.
    private func selectedProject() -> ProjectListItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredProjects.count else {
            return nil
        }
        return filteredProjects[row]
    }

    /// Sets busy state and updates UI controls.
    /// - Parameters:
    ///   - busy: True when activation is in progress.
    ///   - message: Optional status message.
    private func setBusy(_ busy: Bool, message: String?) {
        isBusy = busy
        searchField.isEnabled = !busy
        tableView.isEnabled = !busy
        if let message {
            setStatus(message: message, level: .info)
        } else {
            clearStatus()
        }
    }

    /// Updates the status label with a message and visual level.
    private func setStatus(message: String, level: StatusLevel) {
        statusLabel.stringValue = message
        statusLabel.textColor = level.textColor
        statusLabel.isHidden = false
    }

    /// Hides the status label.
    private func clearStatus() {
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        statusLabel.textColor = .secondaryLabelColor
    }

    private var emptyStateMessage: String? {
        if let catalogErrorMessage {
            return catalogErrorMessage
        }
        return filteredProjects.isEmpty ? "No matches" : nil
    }
}

extension SwitcherPanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        resetState()
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
            activateSelectedProject()
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
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
