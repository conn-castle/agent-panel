//
//  DoctorWindowController.swift
//  AgentPanel
//
//  UI controller for the Doctor diagnostic window.
//  Manages window creation, report display, and button actions
//  for the system health check panel.
//

import AppKit

import AgentPanelCore

/// Controls the Doctor diagnostic window presentation.
///
/// Separates Doctor window UI concerns from the main AppDelegate.
/// Uses callback-based interface for actions to maintain clear separation.
final class DoctorWindowController {
    // MARK: - Action Callbacks

    /// Called when user requests to run Doctor.
    var onRunDoctor: (() -> Void)?
    /// Called when user requests to copy the report.
    var onCopyReport: (() -> Void)?
    /// Called when user requests to install AeroSpace.
    var onInstallAeroSpace: (() -> Void)?
    /// Called when user requests to start AeroSpace.
    var onStartAeroSpace: (() -> Void)?
    /// Called when user requests to reload AeroSpace config.
    var onReloadConfig: (() -> Void)?
    /// Called when user closes the window.
    var onClose: (() -> Void)?

    // MARK: - UI State

    private var window: NSWindow?
    private var textView: NSTextView?
    private var buttons: DoctorButtons?
    private(set) var lastReport: DoctorReport?

    // MARK: - Public Interface

    /// Shows the Doctor report in a panel window.
    /// - Parameter report: Doctor report to display.
    func showReport(_ report: DoctorReport) {
        if window == nil {
            setupWindow()
        }

        updateUI(with: report)

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Updates the UI with a new report.
    /// - Parameter report: Doctor report to display.
    func updateUI(with report: DoctorReport) {
        lastReport = report
        textView?.string = report.rendered()
        textView?.scrollToBeginningOfDocument(nil)

        if let buttons {
            buttons.installAeroSpace.isEnabled = report.actions.canInstallAeroSpace
            buttons.startAeroSpace.isEnabled = report.actions.canStartAeroSpace
            buttons.reloadConfig.isEnabled = report.actions.canReloadAeroSpaceConfig
        }
    }

    /// Closes the Doctor window.
    func close() {
        window?.close()
    }

    // MARK: - Window Setup

    private func setupWindow() {
        let windowInstance = makeWindow()
        let textViewInstance = makeTextView()
        let buttonsInstance = makeButtons()
        let contentView = makeContentView(textView: textViewInstance, buttons: buttonsInstance)
        windowInstance.contentView = contentView
        windowInstance.isReleasedWhenClosed = false

        window = windowInstance
        textView = textViewInstance
        buttons = buttonsInstance
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Doctor"
        window.center()
        return window
    }

    private func makeContentView(textView: NSTextView, buttons: DoctorButtons) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = textView
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)

        let primaryRow = makeButtonRow(buttons: [
            buttons.runDoctor,
            buttons.copyReport,
            buttons.installAeroSpace,
            buttons.startAeroSpace
        ])

        let secondaryRow = makeButtonRow(buttons: [
            buttons.reloadConfig,
            buttons.close
        ])

        container.addArrangedSubview(scrollView)
        container.addArrangedSubview(primaryRow)
        container.addArrangedSubview(secondaryRow)

        let contentView = NSView()
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        return contentView
    }

    private func makeButtonRow(buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.distribution = .fillProportionally
        return row
    }

    private func makeButtons() -> DoctorButtons {
        let runDoctorButton = makeButton(title: "Run Doctor", action: #selector(handleRunDoctor))
        let copyReportButton = makeButton(title: "Copy Report", action: #selector(handleCopyReport))
        let installAeroSpaceButton = makeButton(title: "Install AeroSpace", action: #selector(handleInstallAeroSpace))
        let startAeroSpaceButton = makeButton(title: "Start AeroSpace", action: #selector(handleStartAeroSpace))
        let reloadConfigButton = makeButton(title: "Reload AeroSpace Config", action: #selector(handleReloadConfig))
        let closeButton = makeButton(title: "Close", action: #selector(handleClose))

        return DoctorButtons(
            runDoctor: runDoctorButton,
            copyReport: copyReportButton,
            installAeroSpace: installAeroSpaceButton,
            startAeroSpace: startAeroSpaceButton,
            reloadConfig: reloadConfigButton,
            close: closeButton
        )
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func makeTextView() -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        return textView
    }

    // MARK: - Button Actions

    @objc private func handleRunDoctor() {
        onRunDoctor?()
    }

    @objc private func handleCopyReport() {
        onCopyReport?()
    }

    @objc private func handleInstallAeroSpace() {
        onInstallAeroSpace?()
    }

    @objc private func handleStartAeroSpace() {
        onStartAeroSpace?()
    }

    @objc private func handleReloadConfig() {
        onReloadConfig?()
    }

    @objc private func handleClose() {
        onClose?()
    }
}

// MARK: - Supporting Types

/// Holds references to Doctor window buttons for state management.
struct DoctorButtons {
    let runDoctor: NSButton
    let copyReport: NSButton
    let installAeroSpace: NSButton
    let startAeroSpace: NSButton
    let reloadConfig: NSButton
    let close: NSButton
}
