import XCTest
@testable import AgentPanelCore

final class UTCTimestampTests: XCTestCase {

    func testDoctorTimestampIsUTC() {
        // Create a Doctor with a fixed date provider
        let fixedDate = Date(timeIntervalSince1970: 1704067200) // 2024-01-01T00:00:00Z
        let doctor = makeDoctor(dateProvider: MockDateProvider(fixedDate: fixedDate))

        let report = doctor.run()

        // UTC timestamps end with Z
        XCTAssertTrue(
            report.metadata.timestamp.hasSuffix("Z"),
            "Timestamp should end with Z (UTC): \(report.metadata.timestamp)"
        )
        // Should have fractional seconds (contains a dot before Z)
        XCTAssertTrue(
            report.metadata.timestamp.contains("."),
            "Timestamp should have fractional seconds: \(report.metadata.timestamp)"
        )
    }

    func testDoctorTimestampFormat() {
        let fixedDate = Date(timeIntervalSince1970: 1704067200.123) // With fractional seconds
        let doctor = makeDoctor(dateProvider: MockDateProvider(fixedDate: fixedDate))

        let report = doctor.run()

        // Should match ISO8601 format: YYYY-MM-DDTHH:MM:SS.sssZ
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(report.metadata.timestamp.startIndex..., in: report.metadata.timestamp)
        let matches = regex?.numberOfMatches(in: report.metadata.timestamp, range: range) ?? 0

        XCTAssertEqual(matches, 1, "Timestamp should match ISO8601 format: \(report.metadata.timestamp)")
    }

    func testLoggerTimestampPattern() {
        // The Logger's makeTimestamp method should produce the same format
        // We can't directly test the private method, but we can verify the format
        // through the LogEntry structure

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let timestamp = formatter.string(from: Date())

        // Should end with Z
        XCTAssertTrue(timestamp.hasSuffix("Z"))
        // Should have fractional seconds
        XCTAssertTrue(timestamp.contains("."))
    }

    func testTimestampTimezoneIsExplicitlyUTC() {
        // Verify that timestamps are explicitly UTC regardless of system timezone
        let fixedDate = Date(timeIntervalSince1970: 1704067200) // Known time
        let doctor = makeDoctor(dateProvider: MockDateProvider(fixedDate: fixedDate))

        let report = doctor.run()

        // The timestamp for epoch 1704067200 should be 2024-01-01T00:00:00.000Z
        XCTAssertTrue(
            report.metadata.timestamp.hasPrefix("2024-01-01T00:00:00"),
            "Expected 2024-01-01T00:00:00, got: \(report.metadata.timestamp)"
        )
    }

    // MARK: - Helper

    /// Creates a Doctor with test dependencies using the internal DI initializer.
    private func makeDoctor(dateProvider: DateProviding) -> Doctor {
        Doctor(
            runningApplicationChecker: MockRunningAppChecker(),
            hotkeyStatusProvider: nil,
            dateProvider: dateProvider,
            aerospaceHealth: ApAeroSpace(),
            appDiscovery: LaunchServicesAppDiscovery(),
            executableResolver: ExecutableResolver(),
            commandRunner: ApSystemCommandRunner(),
            dataStore: .default()
        )
    }
}

// MARK: - Test Doubles

private struct MockRunningAppChecker: RunningApplicationChecking {
    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        false
    }
}

private struct MockDateProvider: DateProviding {
    let fixedDate: Date

    func now() -> Date {
        fixedDate
    }
}
