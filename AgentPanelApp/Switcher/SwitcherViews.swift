//
//  SwitcherViews.swift
//  AgentPanel
//
//  View components for the project switcher panel.
//  Contains the custom panel class, cell views, and factory functions
//  for rendering project rows and empty states.
//

import AppKit

import apcore

/// Custom panel that can control key window behavior.
final class SwitcherPanel: NSPanel {
    var allowsKeyWindow: Bool = true

    override var canBecomeKey: Bool {
        allowsKeyWindow
    }
}

/// Table cell view for displaying a project row with color swatch.
final class ProjectRowView: NSTableCellView {
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

// MARK: - Cell Factory Functions

/// Creates or reuses a project cell for display.
/// - Parameters:
///   - project: Project to display.
///   - tableView: Table view for cell reuse.
/// - Returns: Configured table cell view.
func projectCell(for project: ProjectConfig, tableView: NSTableView) -> NSTableCellView {
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

/// Configures a project cell with project data.
/// - Parameters:
///   - cell: Cell to configure.
///   - project: Project providing display data.
func configureProjectCell(_ cell: ProjectRowView, project: ProjectConfig) {
    cell.nameLabel.stringValue = project.name
    cell.swatchView.layer?.backgroundColor = nsColor(from: project.color).cgColor
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

/// Converts a color string to an NSColor using the project palette.
/// - Parameter colorString: Color name or hex value.
/// - Returns: Resolved NSColor, or accent color as fallback.
func nsColor(from colorString: String) -> NSColor {
    guard let rgb = ProjectColorPalette.resolve(colorString) else {
        return .controlAccentColor
    }
    return NSColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
}
