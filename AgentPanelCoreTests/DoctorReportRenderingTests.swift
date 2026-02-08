import XCTest
@testable import AgentPanelCore

final class DoctorReportRenderingTests: XCTestCase {

    func testOverallSeverityReturnsFailWhenAnyFindingFails() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [
                DoctorFinding(severity: .pass, title: "Pass"),
                DoctorFinding(severity: .warn, title: "Warn"),
                DoctorFinding(severity: .fail, title: "Fail")
            ]
        )

        XCTAssertEqual(report.overallSeverity, .fail)
        XCTAssertTrue(report.hasFailures)
    }

    func testOverallSeverityReturnsWarnWhenNoFailuresExist() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [
                DoctorFinding(severity: .pass, title: "Pass"),
                DoctorFinding(severity: .warn, title: "Warn")
            ]
        )

        XCTAssertEqual(report.overallSeverity, .warn)
        XCTAssertFalse(report.hasFailures)
    }

    func testOverallSeverityReturnsPassWhenFindingsAreEmpty() {
        let report = DoctorReport(metadata: makeMetadata(), findings: [])

        XCTAssertEqual(report.overallSeverity, .pass)
        XCTAssertFalse(report.hasFailures)
    }

    func testRenderedSortsFindingsBySeverityWithStableOrder() {
        let metadata = makeMetadata(aerospaceApp: "NOT FOUND", aerospaceCli: "NOT FOUND")

        let findings: [DoctorFinding] = [
            DoctorFinding(severity: .pass, title: "Pass A"),
            DoctorFinding(severity: .fail, title: "Fail A"),
            DoctorFinding(severity: .warn, title: "Warn A"),
            DoctorFinding(severity: .fail, title: "Fail B"),
            DoctorFinding(severity: .pass, title: "Pass B")
        ]

        let report = DoctorReport(metadata: metadata, findings: findings)
        let rendered = report.rendered()

        let lines = rendered.split(separator: "\n").map(String.init)
        let findingLines = lines.filter { $0.hasPrefix("FAIL  ") || $0.hasPrefix("WARN  ") || $0.hasPrefix("PASS  ") }

        XCTAssertEqual(findingLines, [
            "FAIL  Fail A",
            "FAIL  Fail B",
            "WARN  Warn A",
            "PASS  Pass A",
            "PASS  Pass B"
        ])
    }

    func testRenderedIncludesSummaryCounts() {
        let metadata = makeMetadata()

        let findings: [DoctorFinding] = [
            DoctorFinding(severity: .pass, title: "Pass A"),
            DoctorFinding(severity: .warn, title: "Warn A"),
            DoctorFinding(severity: .fail, title: "Fail A")
        ]

        let report = DoctorReport(metadata: metadata, findings: findings)
        let rendered = report.rendered()

        XCTAssertTrue(rendered.contains("Summary: 1 PASS, 1 WARN, 1 FAIL"))
    }

    func testRenderedIncludesSnippetAsTomlBlock() {
        let metadata = makeMetadata()

        let finding = DoctorFinding(
            severity: .fail,
            title: "Config invalid",
            detail: "Bad value",
            fix: "Fix the config",
            snippet: "value = \"ok\""
        )

        let report = DoctorReport(metadata: metadata, findings: [finding])
        let rendered = report.rendered()

        XCTAssertTrue(rendered.contains("Snippet:"))
        XCTAssertTrue(rendered.contains("```toml"))
        XCTAssertTrue(rendered.contains("value = \"ok\""))
        XCTAssertTrue(rendered.contains("```"))
    }

    func testRenderedIncludesBodyLinesWhenTitleEmpty() {
        let metadata = makeMetadata()

        let finding = DoctorFinding(
            severity: .pass,
            title: "",
            bodyLines: ["Raw line 1", "Raw line 2"]
        )

        let report = DoctorReport(metadata: metadata, findings: [finding])
        let rendered = report.rendered()

        XCTAssertTrue(rendered.contains("Raw line 1"))
        XCTAssertTrue(rendered.contains("Raw line 2"))
    }

    private func makeMetadata(
        aerospaceApp: String = "AVAILABLE",
        aerospaceCli: String = "AVAILABLE"
    ) -> DoctorMetadata {
        DoctorMetadata(
            timestamp: "2024-01-01T00:00:00.000Z",
            agentPanelVersion: "dev",
            macOSVersion: "macOS 15.7 (Test)",
            aerospaceApp: aerospaceApp,
            aerospaceCli: aerospaceCli
        )
    }
}
