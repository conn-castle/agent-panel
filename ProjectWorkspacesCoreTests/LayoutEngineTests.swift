import CoreGraphics
import XCTest

@testable import ProjectWorkspacesCore

final class LayoutEngineTests: XCTestCase {
    func testNormalizeAndDenormalizeRoundTrip() throws {
        let engine = LayoutEngine()
        let visibleFrame = CGRect(x: 10, y: 20, width: 1000, height: 800)
        let frame = CGRect(x: 260, y: 60, width: 500, height: 400)

        let normalized = try engine.normalize(frame, in: visibleFrame)
        let denormalized = denormalize(normalized, in: visibleFrame)

        XCTAssertEqual(denormalized.origin.x, frame.origin.x, accuracy: 0.001)
        XCTAssertEqual(denormalized.origin.y, frame.origin.y, accuracy: 0.001)
        XCTAssertEqual(denormalized.size.width, frame.size.width, accuracy: 0.001)
        XCTAssertEqual(denormalized.size.height, frame.size.height, accuracy: 0.001)
    }

    func testNormalizeThrowsOnInvalidVisibleFrame() {
        let engine = LayoutEngine()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 0, height: 0)

        XCTAssertThrowsError(try engine.normalize(frame, in: visibleFrame)) { error in
            XCTAssertEqual(error as? LayoutEngineError, .invalidVisibleFrame(visibleFrame))
        }
    }

    func testIsFrameOnMainDisplayUsesMidpoint() {
        let engine = LayoutEngine()
        let mainFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let frameInside = CGRect(x: 50, y: 50, width: 20, height: 20)
        let frameOutside = CGRect(x: 120, y: 120, width: 20, height: 20)

        XCTAssertTrue(engine.isFrameOnMainDisplay(frameInside, mainFramePoints: mainFrame))
        XCTAssertFalse(engine.isFrameOnMainDisplay(frameOutside, mainFramePoints: mainFrame))
    }
}
