import Foundation
import Testing

@testable import AgentPanelCore

@Suite("FocusEvent Tests")
struct FocusEventTests {
    // MARK: - FocusEventKind Tests

    @Test("FocusEventKind has expected cases")
    func focusEventKindHasExpectedCases() {
        let allCases = FocusEventKind.allCases
        #expect(allCases.count == 6)
        #expect(allCases.contains(.projectActivated))
        #expect(allCases.contains(.projectDeactivated))
        #expect(allCases.contains(.windowFocused))
        #expect(allCases.contains(.windowDefocused))
        #expect(allCases.contains(.sessionStarted))
        #expect(allCases.contains(.sessionEnded))
    }

    @Test("FocusEventKind encodes to raw string value")
    func focusEventKindEncodesToRawValue() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(FocusEventKind.projectActivated)
        let string = String(data: data, encoding: .utf8)
        #expect(string == "\"projectActivated\"")
    }

    // MARK: - FocusEvent Codable Tests

    @Test("FocusEvent round-trips through JSON encoding")
    func focusEventRoundTrips() throws {
        let timestamp = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let id = UUID()
        let event = FocusEvent(
            id: id,
            kind: .projectActivated,
            timestamp: timestamp,
            projectId: "my-project",
            windowId: 123,
            appBundleId: "com.test.app",
            metadata: ["source": "hotkey"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FocusEvent.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.kind == .projectActivated)
        #expect(decoded.timestamp == timestamp)
        #expect(decoded.projectId == "my-project")
        #expect(decoded.windowId == 123)
        #expect(decoded.appBundleId == "com.test.app")
        #expect(decoded.metadata?["source"] == "hotkey")
    }

    @Test("FocusEvent with nil optional fields round-trips")
    func focusEventWithNilsRoundTrips() throws {
        let event = FocusEvent(
            kind: .sessionStarted,
            timestamp: Date(),
            projectId: nil,
            windowId: nil,
            appBundleId: nil,
            metadata: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FocusEvent.self, from: data)

        #expect(decoded.kind == .sessionStarted)
        #expect(decoded.projectId == nil)
        #expect(decoded.windowId == nil)
        #expect(decoded.appBundleId == nil)
        #expect(decoded.metadata == nil)
    }

    // MARK: - FocusEvent Equatable Tests

    @Test("FocusEvent equality compares all fields")
    func focusEventEquality() {
        let timestamp = Date()
        let id = UUID()
        let event1 = FocusEvent(
            id: id,
            kind: .windowFocused,
            timestamp: timestamp,
            projectId: "proj",
            windowId: 1,
            appBundleId: "com.test",
            metadata: ["key": "value"]
        )
        let event2 = FocusEvent(
            id: id,
            kind: .windowFocused,
            timestamp: timestamp,
            projectId: "proj",
            windowId: 1,
            appBundleId: "com.test",
            metadata: ["key": "value"]
        )
        let event3 = FocusEvent(
            id: UUID(), // Different ID
            kind: .windowFocused,
            timestamp: timestamp,
            projectId: "proj",
            windowId: 1,
            appBundleId: "com.test",
            metadata: ["key": "value"]
        )

        #expect(event1 == event2)
        #expect(event1 != event3)
    }

    // MARK: - FocusEvent Identifiable Tests

    @Test("FocusEvent conforms to Identifiable")
    func focusEventIsIdentifiable() {
        let id = UUID()
        let event = FocusEvent(id: id, kind: .sessionStarted, timestamp: Date())
        #expect(event.id == id)
    }

    // MARK: - Factory Method Tests

    @Test("projectActivated factory creates correct event")
    func projectActivatedFactory() {
        let event = FocusEvent.projectActivated(
            projectId: "my-project",
            metadata: ["source": "menu"]
        )

        #expect(event.kind == .projectActivated)
        #expect(event.projectId == "my-project")
        #expect(event.windowId == nil)
        #expect(event.appBundleId == nil)
        #expect(event.metadata?["source"] == "menu")
    }

    @Test("projectDeactivated factory creates correct event")
    func projectDeactivatedFactory() {
        let event = FocusEvent.projectDeactivated(projectId: "old-project")

        #expect(event.kind == .projectDeactivated)
        #expect(event.projectId == "old-project")
    }

    @Test("windowFocused factory creates correct event")
    func windowFocusedFactory() {
        let event = FocusEvent.windowFocused(
            windowId: 42,
            appBundleId: "com.test.app",
            projectId: "proj"
        )

        #expect(event.kind == .windowFocused)
        #expect(event.windowId == 42)
        #expect(event.appBundleId == "com.test.app")
        #expect(event.projectId == "proj")
    }

    @Test("windowDefocused factory creates correct event")
    func windowDefocusedFactory() {
        let event = FocusEvent.windowDefocused(
            windowId: 42,
            appBundleId: "com.test.app"
        )

        #expect(event.kind == .windowDefocused)
        #expect(event.windowId == 42)
        #expect(event.appBundleId == "com.test.app")
        #expect(event.projectId == nil)
    }

    @Test("sessionStarted factory creates correct event")
    func sessionStartedFactory() {
        let event = FocusEvent.sessionStarted(metadata: ["version": "1.0"])

        #expect(event.kind == .sessionStarted)
        #expect(event.projectId == nil)
        #expect(event.metadata?["version"] == "1.0")
    }

    @Test("sessionEnded factory creates correct event")
    func sessionEndedFactory() {
        let event = FocusEvent.sessionEnded()

        #expect(event.kind == .sessionEnded)
        #expect(event.projectId == nil)
        #expect(event.metadata == nil)
    }
}
