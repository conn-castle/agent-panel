import Foundation

/// Severity level for Doctor findings.
public enum DoctorSeverity: String, CaseIterable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"

    /// Sort order for display purposes.
    public var sortOrder: Int {
        switch self {
        case .fail:
            return 0
        case .warn:
            return 1
        case .pass:
            return 2
        }
    }
}

/// A single Doctor finding rendered in the report.
public struct DoctorFinding: Equatable, Sendable {
    public let severity: DoctorSeverity
    public let title: String
    public let detail: String?
    public let fix: String?
    public let snippet: String?

    /// Creates a Doctor finding.
    /// - Parameters:
    ///   - severity: PASS, WARN, or FAIL severity.
    ///   - title: Short summary of the finding.
    ///   - detail: Optional detail text for additional context.
    ///   - fix: Optional "Fix:" guidance for the user.
    ///   - snippet: Optional copy/paste snippet to resolve the finding.
    public init(
        severity: DoctorSeverity,
        title: String,
        detail: String? = nil,
        fix: String? = nil,
        snippet: String? = nil
    ) {
        self.severity = severity
        self.title = title
        self.detail = detail
        self.fix = fix
        self.snippet = snippet
    }
}

/// A structured Doctor report.
public struct DoctorReport: Equatable, Sendable {
    public let findings: [DoctorFinding]

    /// Creates a Doctor report.
    /// - Parameter findings: Findings to include in the report.
    public init(findings: [DoctorFinding]) {
        self.findings = findings
    }

    /// Returns true when the report contains any FAIL findings.
    public var hasFailures: Bool {
        findings.contains { $0.severity == .fail }
    }

    /// Renders the report as a human-readable string.
    /// - Returns: A formatted report suitable for CLI output.
    public func rendered() -> String {
        let indexed = findings.enumerated()
        let sortedFindings = indexed.sorted { lhs, rhs in
            let leftOrder = lhs.element.severity.sortOrder
            let rightOrder = rhs.element.severity.sortOrder
            if leftOrder == rightOrder {
                return lhs.offset < rhs.offset
            }
            return leftOrder < rightOrder
        }.map { $0.element }

        var lines: [String] = []
        lines.append("Doctor report")
        lines.append("")

        if sortedFindings.isEmpty {
            lines.append("PASS: no issues found")
        } else {
            for finding in sortedFindings {
                lines.append("\(finding.severity.rawValue): \(finding.title)")
                if let detail = finding.detail, !detail.isEmpty {
                    lines.append("  Detail: \(detail)")
                }
                if let fix = finding.fix, !fix.isEmpty {
                    lines.append("  Fix: \(fix)")
                }
                if let snippet = finding.snippet, !snippet.isEmpty {
                    lines.append("  Snippet:")
                    lines.append("  ```toml")
                    for line in snippet.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append("  \(line)")
                    }
                    lines.append("  ```")
                }
            }
        }

        let passCount = sortedFindings.filter { $0.severity == .pass }.count
        let warnCount = sortedFindings.filter { $0.severity == .warn }.count
        let failCount = sortedFindings.filter { $0.severity == .fail }.count

        lines.append("")
        lines.append("Summary: \(passCount) PASS, \(warnCount) WARN, \(failCount) FAIL")

        return lines.joined(separator: "\n")
    }
}
