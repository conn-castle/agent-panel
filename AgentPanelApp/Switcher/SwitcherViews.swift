//
//  SwitcherViews.swift
//  AgentPanel
//
//  View components for the project switcher panel.
//  Contains the custom panel class, cell views, and factory functions
//  for rendering project rows and empty states.
//

import AppKit

import AgentPanelCore

/// Custom panel that can control key window behavior.
final class SwitcherPanel: NSPanel {
    var allowsKeyWindow: Bool = true

    override var canBecomeKey: Bool {
        allowsKeyWindow
    }

    override var canBecomeMain: Bool {
        allowsKeyWindow
    }
}

/// Table cell view for section header rows in the results list.
final class SectionHeaderRowView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

/// Table cell view for an action row such as "Back to Previous Window".
final class ActionRowView: NSTableCellView {
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let shortcutLabel = NSTextField(labelWithString: "")
    private let shortcutContainer = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        iconView.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = "Back to Previous Window"

        shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.stringValue = "\u{21E7}\u{21A9}"
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        shortcutContainer.translatesAutoresizingMaskIntoConstraints = false
        shortcutContainer.wantsLayer = true
        shortcutContainer.layer?.cornerRadius = 6
        shortcutContainer.layer?.masksToBounds = true
        shortcutContainer.layer?.backgroundColor = NSColor.controlColor.cgColor
        shortcutContainer.layer?.borderWidth = 1
        shortcutContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        shortcutContainer.addSubview(shortcutLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, titleLabel, spacer, shortcutContainer])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            shortcutLabel.leadingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor, constant: 8),
            shortcutLabel.trailingAnchor.constraint(equalTo: shortcutContainer.trailingAnchor, constant: -8),
            shortcutLabel.topAnchor.constraint(equalTo: shortcutContainer.topAnchor, constant: 3),
            shortcutLabel.bottomAnchor.constraint(equalTo: shortcutContainer.bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        shortcutContainer.layer?.backgroundColor = NSColor.controlColor.cgColor
        shortcutContainer.layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

/// Table cell view for displaying a project row with color swatch, current badge, and close button.
final class ProjectRowView: NSTableCellView {
    let swatchView = NSView()
    let nameLabel = NSTextField(labelWithString: "")
    let currentPillContainer = NSView()
    let currentPillLabel = NSTextField(labelWithString: "Current")
    let closeButton = NSButton(frame: .zero)
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered: Bool = false {
        didSet {
            updateCloseButtonAppearance()
        }
    }
    private var isRowSelected: Bool = false {
        didSet {
            updateCloseButtonAppearance()
        }
    }
    private var canClose: Bool = false {
        didSet {
            updateCloseButtonAppearance()
        }
    }

    /// Called when the close button is clicked.
    var onClose: (() -> Void)?

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
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.lineBreakMode = .byTruncatingTail

        currentPillContainer.wantsLayer = true
        currentPillContainer.layer?.cornerRadius = 9
        currentPillContainer.layer?.masksToBounds = true
        currentPillContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        currentPillContainer.translatesAutoresizingMaskIntoConstraints = false
        currentPillContainer.isHidden = true

        currentPillLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        currentPillLabel.textColor = .controlAccentColor
        currentPillLabel.translatesAutoresizingMaskIntoConstraints = false
        currentPillContainer.addSubview(currentPillLabel)

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close project")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 8
        closeButton.layer?.masksToBounds = true
        closeButton.setAccessibilityLabel("Close project")
        closeButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [swatchView, nameLabel, spacer, currentPillContainer, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            swatchView.widthAnchor.constraint(equalToConstant: 10),
            swatchView.heightAnchor.constraint(equalToConstant: 10),
            currentPillLabel.leadingAnchor.constraint(equalTo: currentPillContainer.leadingAnchor, constant: 8),
            currentPillLabel.trailingAnchor.constraint(equalTo: currentPillContainer.trailingAnchor, constant: -8),
            currentPillLabel.topAnchor.constraint(equalTo: currentPillContainer.topAnchor, constant: 2),
            currentPillLabel.bottomAnchor.constraint(equalTo: currentPillContainer.bottomAnchor, constant: -2),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])

        updateCloseButtonAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        currentPillContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
    }

    func setRowSelected(_ selected: Bool) {
        isRowSelected = selected
    }

    func setCurrent(_ isCurrent: Bool) {
        currentPillContainer.isHidden = !isCurrent
        setAccessibilityLabel(
            isCurrent
                ? "\(nameLabel.stringValue), Current"
                : nameLabel.stringValue
        )
    }

    func setCloseEnabled(_ enabled: Bool) {
        canClose = enabled
        closeButton.isEnabled = enabled
    }

    private func updateCloseButtonAppearance() {
        let emphasized = isHovered || isRowSelected
        let alpha: CGFloat
        if canClose {
            alpha = emphasized ? 0.72 : 0.5
        } else {
            alpha = 0.0
        }

        closeButton.alphaValue = alpha
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.layer?.backgroundColor = NSColor.clear.cgColor
    }

    @objc private func closeButtonPressed() {
        onClose?()
    }
}

// MARK: - Cell Factory Functions

/// Creates or reuses a project cell for display.
/// - Parameters:
///   - project: Project to display.
///   - isActive: Whether this project is the currently active one.
///   - isOpen: Whether this project has an open workspace.
///   - onClose: Callback when the close button is clicked.
///   - tableView: Table view for cell reuse.
/// - Returns: Configured table cell view.
func projectCell(
    for project: ProjectConfig,
    isActive: Bool,
    isOpen: Bool,
    query: String,
    isSelected: Bool,
    onClose: (() -> Void)?,
    tableView: NSTableView
) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("ProjectRow")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ProjectRowView {
        configureProjectCell(
            cell,
            project: project,
            isActive: isActive,
            isOpen: isOpen,
            query: query,
            isSelected: isSelected,
            onClose: onClose
        )
        return cell
    }

    let cell = ProjectRowView()
    cell.identifier = identifier
    configureProjectCell(
        cell,
        project: project,
        isActive: isActive,
        isOpen: isOpen,
        query: query,
        isSelected: isSelected,
        onClose: onClose
    )
    return cell
}

/// Configures a project cell with project data.
/// - Parameters:
///   - cell: Cell to configure.
///   - project: Project providing display data.
///   - isActive: Whether this project is the currently active one.
///   - isOpen: Whether this project has an open workspace.
///   - onClose: Callback when the close button is clicked.
func configureProjectCell(
    _ cell: ProjectRowView,
    project: ProjectConfig,
    isActive: Bool,
    isOpen: Bool,
    query: String,
    isSelected: Bool,
    onClose: (() -> Void)?
) {
    cell.nameLabel.attributedStringValue = highlightedProjectName(project.name, query: query)
    cell.swatchView.layer?.backgroundColor = nsColor(from: project.color).cgColor
    cell.setCurrent(isActive)
    cell.setCloseEnabled(isOpen)
    cell.setRowSelected(isSelected)
    cell.onClose = onClose
    cell.closeButton.setAccessibilityLabel("Close project \(project.name)")
}

/// Creates or reuses a section header cell.
/// - Parameters:
///   - title: Header text.
///   - tableView: Table view for cell reuse.
/// - Returns: Configured table cell view.
func sectionHeaderCell(title: String, tableView: NSTableView) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("SectionHeaderRow")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SectionHeaderRowView {
        cell.titleLabel.stringValue = title.uppercased()
        return cell
    }

    let cell = SectionHeaderRowView()
    cell.identifier = identifier
    cell.titleLabel.stringValue = title.uppercased()
    return cell
}

/// Creates or reuses the "Back to Previous Window" action row cell.
/// - Parameter tableView: Table view for cell reuse.
/// - Returns: Configured table cell view.
func backActionCell(tableView: NSTableView) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("BackActionRow")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ActionRowView {
        return cell
    }

    let cell = ActionRowView()
    cell.identifier = identifier
    cell.setAccessibilityLabel("Back to Previous Window")
    return cell
}

/// Creates or reuses an empty state cell for display.
/// - Parameters:
///   - message: Message to display.
///   - tableView: Table view for cell reuse.
/// - Returns: Configured table cell view.
func emptyStateCell(message: String, tableView: NSTableView) -> NSTableCellView {
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

/// Highlights query matches in the project name.
/// - Parameters:
///   - name: Project display name.
///   - query: Search query.
/// - Returns: Attributed display name with matched ranges emphasized.
func highlightedProjectName(_ name: String, query: String) -> NSAttributedString {
    let attributed = NSMutableAttributedString(
        string: name,
        attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]
    )

    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
        return attributed
    }

    var searchStart = name.startIndex

    while searchStart < name.endIndex,
          let range = name.range(
              of: trimmedQuery,
              options: [.caseInsensitive, .diacriticInsensitive],
              range: searchStart..<name.endIndex
          ) {
        let nsRange = NSRange(range, in: name)
        attributed.addAttributes(
            [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)],
            range: nsRange
        )
        searchStart = range.upperBound
    }

    return attributed
}

/// Converts a color string to an NSColor using the project palette.
/// - Parameter colorString: Color name or hex value.
/// - Returns: Resolved NSColor, or accent color as fallback.
func nsColor(from colorString: String) -> NSColor {
    guard let rgb = ProjectColorPalette.resolve(colorString) else {
        return .controlAccentColor
    }
    return NSColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
}
