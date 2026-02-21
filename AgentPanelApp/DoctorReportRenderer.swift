//
//  DoctorReportRenderer.swift
//  AgentPanel
//
//  Builds an NSAttributedString from a DoctorReport with colored severity
//  labels, matching the Switcher's design language.
//

import AppKit

import AgentPanelCore

/// Produces rich-text (NSAttributedString) renderings of Doctor reports.
///
/// Mirrors the structure of `DoctorReport.rendered()` but uses colored
/// severity labels and typographic hierarchy instead of plain text.
enum DoctorReportRenderer {

    // MARK: - Design Tokens

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let metadataFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let severityFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private static let findingTitleFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private static let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let snippetFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let summaryFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    private static let timingFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    private static func severityColor(_ severity: DoctorSeverity) -> NSColor {
        switch severity {
        case .fail: return .systemRed
        case .warn: return .systemOrange
        case .pass: return .systemGreen
        }
    }

    // MARK: - Public API

    /// Renders a Doctor report as an attributed string with colored severity labels.
    ///
    /// Same sort order and structure as `DoctorReport.rendered()`:
    /// title, metadata, findings sorted by severity (FAIL > WARN > PASS, stable),
    /// and a summary line with colored counts.
    ///
    /// - Parameter report: The Doctor report to render.
    /// - Returns: A styled attributed string suitable for display in an NSTextView.
    static func render(_ report: DoctorReport) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Title
        appendLine(to: result, "AgentPanel Doctor Report",
                   font: titleFont, color: .labelColor)

        // Metadata
        let metadataLines = buildMetadataLines(report.metadata)
        for line in metadataLines {
            appendLine(to: result, line, font: metadataFont, color: .secondaryLabelColor)
        }

        // Blank line before findings
        appendLine(to: result, "")

        // Sort findings by severity (FAIL > WARN > PASS), stable by original index
        let sortedFindings = report.findings.enumerated().sorted { lhs, rhs in
            let leftOrder = lhs.element.severity.sortOrder
            let rightOrder = rhs.element.severity.sortOrder
            if leftOrder == rightOrder {
                return lhs.offset < rhs.offset
            }
            return leftOrder < rightOrder
        }.map { $0.element }

        // Findings
        if sortedFindings.isEmpty {
            appendSeverityLine(to: result, severity: .pass, text: "  no issues found")
        } else {
            for finding in sortedFindings {
                appendFinding(to: result, finding)
            }
        }

        // Summary
        let countedFindings = sortedFindings.filter { !$0.title.isEmpty }
        let passCount = countedFindings.filter { $0.severity == DoctorSeverity.pass }.count
        let warnCount = countedFindings.filter { $0.severity == DoctorSeverity.warn }.count
        let failCount = countedFindings.filter { $0.severity == DoctorSeverity.fail }.count

        appendLine(to: result, "")
        appendSummaryLine(to: result, passCount: passCount, warnCount: warnCount, failCount: failCount)

        return result
    }

    // MARK: - Metadata

    private static func buildMetadataLines(_ metadata: DoctorMetadata) -> [String] {
        var lines: [String] = []
        lines.append("Timestamp: \(metadata.timestamp)")
        lines.append("AgentPanel version: \(metadata.agentPanelVersion)")
        lines.append("macOS version: \(metadata.macOSVersion)")
        lines.append("AeroSpace app: \(metadata.aerospaceApp)")
        lines.append("aerospace CLI: \(metadata.aerospaceCli)")
        if let ctx = metadata.errorContext {
            lines.append("Triggered by: \(ctx.trigger) (\(ctx.category.rawValue)): \(ctx.message)")
        }
        lines.append("Duration: \(metadata.durationMs)ms")
        if !metadata.sectionTimings.isEmpty {
            let sortedSections = metadata.sectionTimings.sorted { $0.key < $1.key }
            let timingParts = sortedSections.map { "\($0.key)=\($0.value)ms" }
            lines.append("Sections: \(timingParts.joined(separator: ", "))")
        }
        return lines
    }

    // MARK: - Findings

    private static func appendFinding(to result: NSMutableAttributedString, _ finding: DoctorFinding) {
        if finding.title.isEmpty {
            // Findings with empty title: body lines only, no severity prefix
            for line in finding.bodyLines {
                appendLine(to: result, line, font: bodyFont, color: .secondaryLabelColor)
            }
            return
        }

        // Severity label + title on same line
        appendSeverityLine(to: result, severity: finding.severity, text: "  \(finding.title)")

        // Body lines (indented detail/fix)
        for line in finding.bodyLines {
            appendLine(to: result, line, font: bodyFont, color: .secondaryLabelColor)
        }

        // Code snippet with background tint (omit ``` fences)
        if let snippet = finding.snippet, !snippet.isEmpty {
            appendLine(to: result, "  Snippet:", font: bodyFont, color: .secondaryLabelColor)
            for line in snippet.split(separator: "\n", omittingEmptySubsequences: false) {
                appendSnippetLine(to: result, "  \(line)")
            }
        }
    }

    // MARK: - Summary

    private static func appendSummaryLine(
        to result: NSMutableAttributedString,
        passCount: Int,
        warnCount: Int,
        failCount: Int
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: summaryFont,
            .foregroundColor: NSColor.labelColor
        ]
        result.append(NSAttributedString(string: "Summary: ", attributes: attrs))

        let passAttrs: [NSAttributedString.Key: Any] = [
            .font: summaryFont,
            .foregroundColor: severityColor(.pass)
        ]
        result.append(NSAttributedString(string: "\(passCount) PASS", attributes: passAttrs))

        result.append(NSAttributedString(string: ", ", attributes: attrs))

        let warnAttrs: [NSAttributedString.Key: Any] = [
            .font: summaryFont,
            .foregroundColor: severityColor(.warn)
        ]
        result.append(NSAttributedString(string: "\(warnCount) WARN", attributes: warnAttrs))

        result.append(NSAttributedString(string: ", ", attributes: attrs))

        let failAttrs: [NSAttributedString.Key: Any] = [
            .font: summaryFont,
            .foregroundColor: severityColor(.fail)
        ]
        result.append(NSAttributedString(string: "\(failCount) FAIL", attributes: failAttrs))

        result.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    // MARK: - Line Helpers

    private static func appendLine(
        to result: NSMutableAttributedString,
        _ text: String,
        font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        color: NSColor = .labelColor
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        result.append(NSAttributedString(string: text + "\n", attributes: attrs))
    }

    private static func appendSeverityLine(
        to result: NSMutableAttributedString,
        severity: DoctorSeverity,
        text: String
    ) {
        // Colored severity label
        let severityAttrs: [NSAttributedString.Key: Any] = [
            .font: severityFont,
            .foregroundColor: severityColor(severity)
        ]
        result.append(NSAttributedString(string: severity.rawValue, attributes: severityAttrs))

        // Title text after the label
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: findingTitleFont,
            .foregroundColor: NSColor.labelColor
        ]
        result.append(NSAttributedString(string: text + "\n", attributes: titleAttrs))
    }

    private static func appendSnippetLine(to result: NSMutableAttributedString, _ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: snippetFont,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.controlBackgroundColor
        ]
        result.append(NSAttributedString(string: text + "\n", attributes: attrs))
    }
}
