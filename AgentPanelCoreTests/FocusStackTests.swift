import XCTest
@testable import AgentPanelCore

final class FocusStackTests: XCTestCase {

    // MARK: - Helpers

    private func focus(windowId: Int, workspace: String = "main") -> CapturedFocus {
        CapturedFocus(windowId: windowId, appBundleId: "com.test.app", workspace: workspace)
    }

    // MARK: - Push and Pop

    func testPushAndPopReturnsLastEntry() {
        var stack = FocusStack()
        stack.push(focus(windowId: 1))
        stack.push(focus(windowId: 2))

        let result = stack.popFirstValid { _ in true }
        XCTAssertEqual(result?.windowId, 2)
        // Verify windowId 1 remains by popping it
        let remaining = stack.popFirstValid { _ in true }
        XCTAssertEqual(remaining?.windowId, 1)
        XCTAssertTrue(stack.isEmpty)
    }

    func testPopSkipsStaleThenReturnsValid() {
        var stack = FocusStack()
        stack.push(focus(windowId: 1))  // valid
        stack.push(focus(windowId: 2))  // valid
        stack.push(focus(windowId: 3))  // stale

        // windowId 3 is stale, 2 is valid
        let result = stack.popFirstValid { entry in entry.windowId != 3 }
        XCTAssertEqual(result?.windowId, 2)
        // Verify windowId 1 remains by popping it
        let remaining = stack.popFirstValid { _ in true }
        XCTAssertEqual(remaining?.windowId, 1)
        XCTAssertTrue(stack.isEmpty)
    }

    func testPopReturnsNilWhenEmpty() {
        var stack = FocusStack()
        let result = stack.popFirstValid { _ in true }
        XCTAssertNil(result)
    }

    func testPopReturnsNilWhenAllStale() {
        var stack = FocusStack()
        stack.push(focus(windowId: 1))
        stack.push(focus(windowId: 2))
        stack.push(focus(windowId: 3))

        let result = stack.popFirstValid { _ in false }
        XCTAssertNil(result)
        XCTAssertTrue(stack.isEmpty)
    }

    // MARK: - Deduplication

    func testPushDeduplicatesConsecutive() {
        var stack = FocusStack()
        stack.push(focus(windowId: 1))
        stack.push(focus(windowId: 1))

        XCTAssertEqual(stack.count, 1)
    }

    func testPushAllowsNonConsecutiveDuplicates() {
        var stack = FocusStack()
        stack.push(focus(windowId: 1))
        stack.push(focus(windowId: 2))
        stack.push(focus(windowId: 1))

        XCTAssertEqual(stack.count, 3)
    }

    // MARK: - Max Size

    func testMaxSizeEnforced() {
        var stack = FocusStack(maxSize: 5)
        for i in 1...10 {
            stack.push(focus(windowId: i))
        }

        XCTAssertEqual(stack.count, 5)
        // Pop all and verify oldest entries (1-5) were dropped, 6-10 remain (LIFO order)
        var popped: [Int] = []
        while let entry = stack.popFirstValid(isValid: { _ in true }) {
            popped.append(entry.windowId)
        }
        XCTAssertEqual(popped, [10, 9, 8, 7, 6])
    }

    // MARK: - Workspace preservation

    func testCapturedFocusIncludesWorkspace() {
        var stack = FocusStack()
        let entry = CapturedFocus(windowId: 42, appBundleId: "com.apple.Safari", workspace: "personal")
        stack.push(entry)

        let popped = stack.popFirstValid { _ in true }
        XCTAssertEqual(popped?.windowId, 42)
        XCTAssertEqual(popped?.appBundleId, "com.apple.Safari")
        XCTAssertEqual(popped?.workspace, "personal")
    }

    // MARK: - isEmpty and count

    func testIsEmptyOnFreshStack() {
        let stack = FocusStack()
        XCTAssertTrue(stack.isEmpty)
        XCTAssertEqual(stack.count, 0)
    }

    func testIsEmptyAfterPush() {
        var stack = FocusStack()
        stack.push(focus(windowId: 1))
        XCTAssertFalse(stack.isEmpty)
        XCTAssertEqual(stack.count, 1)
    }
}
