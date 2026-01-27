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
    public let bodyLines: [String]
    public let snippet: String?

    /// Creates a Doctor finding.
    /// - Parameters:
    ///   - severity: PASS, WARN, or FAIL severity.
    ///   - title: Short summary of the finding.
    ///   - detail: Optional detail text for additional context.
    ///   - fix: Optional "Fix:" guidance for the user.
    ///   - bodyLines: Additional lines to render verbatim after the title.
    ///   - snippet: Optional copy/paste snippet to resolve the finding.
    public init(
        severity: DoctorSeverity,
        title: String,
        detail: String? = nil,
        fix: String? = nil,
        bodyLines: [String] = [],
        snippet: String? = nil
    ) {
        self.severity = severity
        self.title = title
        var lines = bodyLines
        if let detail, !detail.isEmpty {
            lines.append("Detail: \(detail)")
        }
        if let fix, !fix.isEmpty {
            lines.append("Fix: \(fix)")
        }
        self.bodyLines = lines
        self.snippet = snippet
    }
}

/// Report metadata rendered in the Doctor header.
public struct DoctorMetadata: Equatable, Sendable {
    public let timestamp: String
    public let projectWorkspacesVersion: String
    public let macOSVersion: String
    public let aerospaceApp: String
    public let aerospaceCli: String

    /// Creates a report metadata payload.
    /// - Parameters:
    ///   - timestamp: ISO-8601 timestamp string.
    ///   - projectWorkspacesVersion: ProjectWorkspaces version identifier.
    ///   - macOSVersion: macOS version string.
    ///   - aerospaceApp: AeroSpace app path or NOT FOUND.
    ///   - aerospaceCli: AeroSpace CLI path or NOT FOUND.
    public init(
        timestamp: String,
        projectWorkspacesVersion: String,
        macOSVersion: String,
        aerospaceApp: String,
        aerospaceCli: String
    ) {
        self.timestamp = timestamp
        self.projectWorkspacesVersion = projectWorkspacesVersion
        self.macOSVersion = macOSVersion
        self.aerospaceApp = aerospaceApp
        self.aerospaceCli = aerospaceCli
    }
}

/// Action availability for Doctor UI buttons.
public struct DoctorActionAvailability: Equatable, Sendable {
    public let canInstallAeroSpace: Bool
    public let canInstallSafeAeroSpaceConfig: Bool
    public let canStartAeroSpace: Bool
    public let canReloadAeroSpaceConfig: Bool
    public let canDisableAeroSpace: Bool
    public let canUninstallSafeAeroSpaceConfig: Bool

    /// Creates an action availability payload.
    /// - Parameters:
    ///   - canInstallAeroSpace: True when installing AeroSpace via Homebrew is allowed.
    ///   - canInstallSafeAeroSpaceConfig: True when the safe config installer should be enabled.
    ///   - canStartAeroSpace: True when starting AeroSpace is allowed.
    ///   - canReloadAeroSpaceConfig: True when reload should be enabled.
    ///   - canDisableAeroSpace: True when the panic button should be enabled.
    ///   - canUninstallSafeAeroSpaceConfig: True when uninstall should be enabled.
    public init(
        canInstallAeroSpace: Bool,
        canInstallSafeAeroSpaceConfig: Bool,
        canStartAeroSpace: Bool,
        canReloadAeroSpaceConfig: Bool,
        canDisableAeroSpace: Bool,
        canUninstallSafeAeroSpaceConfig: Bool
    ) {
        self.canInstallAeroSpace = canInstallAeroSpace
        self.canInstallSafeAeroSpaceConfig = canInstallSafeAeroSpaceConfig
        self.canStartAeroSpace = canStartAeroSpace
        self.canReloadAeroSpaceConfig = canReloadAeroSpaceConfig
        self.canDisableAeroSpace = canDisableAeroSpace
        self.canUninstallSafeAeroSpaceConfig = canUninstallSafeAeroSpaceConfig
    }

    /// Returns a disabled action set.
    public static let none = DoctorActionAvailability(
        canInstallAeroSpace: false,
        canInstallSafeAeroSpaceConfig: false,
        canStartAeroSpace: false,
        canReloadAeroSpaceConfig: false,
        canDisableAeroSpace: false,
        canUninstallSafeAeroSpaceConfig: false
    )
}

/// A structured Doctor report.
public struct DoctorReport: Equatable, Sendable {
    public let metadata: DoctorMetadata
    public let findings: [DoctorFinding]
    public let actions: DoctorActionAvailability

    /// Creates a Doctor report.
    /// - Parameters:
    ///   - metadata: Header metadata for the report.
    ///   - findings: Findings to include in the report.
    ///   - actions: Action availability for UI controls.
    public init(
        metadata: DoctorMetadata,
        findings: [DoctorFinding],
        actions: DoctorActionAvailability = .none
    ) {
        self.metadata = metadata
        self.findings = findings
        self.actions = actions
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
        lines.append("ProjectWorkspaces Doctor Report")
        lines.append("Timestamp: \(metadata.timestamp)")
        lines.append("ProjectWorkspaces version: \(metadata.projectWorkspacesVersion)")
        lines.append("macOS version: \(metadata.macOSVersion)")
        lines.append("AeroSpace app: \(metadata.aerospaceApp)")
        lines.append("aerospace CLI: \(metadata.aerospaceCli)")
        lines.append("")

        if sortedFindings.isEmpty {
            lines.append("PASS  no issues found")
        } else {
            for finding in sortedFindings {
                if finding.title.isEmpty {
                    for line in finding.bodyLines {
                        lines.append(line)
                    }
                    continue
                }

                lines.append("\(finding.severity.rawValue)  \(finding.title)")
                for line in finding.bodyLines {
                    lines.append(line)
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

        let countedFindings = sortedFindings.filter { !$0.title.isEmpty }
        let passCount = countedFindings.filter { $0.severity == .pass }.count
        let warnCount = countedFindings.filter { $0.severity == .warn }.count
        let failCount = countedFindings.filter { $0.severity == .fail }.count

        lines.append("")
        lines.append("Summary: \(passCount) PASS, \(warnCount) WARN, \(failCount) FAIL")

        return lines.joined(separator: "\n")
    }
}
