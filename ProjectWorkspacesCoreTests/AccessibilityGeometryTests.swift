import CoreGraphics
import XCTest

@testable import ProjectWorkspacesCore

final class AccessibilityGeometryTests: XCTestCase {
    func testAppKitToAXTopLeftConversion() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 400)
        let mainHeight: CGFloat = 1200

        let position = appKitFrameToAXPositionTopLeft(frame: frame, mainDisplayHeightPoints: mainHeight)

        XCTAssertEqual(position.x, 100, accuracy: 0.001)
        XCTAssertEqual(position.y, 1200 - 200 - 400, accuracy: 0.001)
    }

    func testRoundTripConversionPreservesFrame() {
        let frame = CGRect(x: 50, y: 75, width: 640, height: 480)
        let mainHeight: CGFloat = 1440

        let position = appKitFrameToAXPositionTopLeft(frame: frame, mainDisplayHeightPoints: mainHeight)
        let roundTrip = axPositionTopLeftToAppKitFrame(
            position: position,
            size: frame.size,
            mainDisplayHeightPoints: mainHeight
        )

        XCTAssertEqual(roundTrip.origin.x, frame.origin.x, accuracy: 0.001)
        XCTAssertEqual(roundTrip.origin.y, frame.origin.y, accuracy: 0.001)
        XCTAssertEqual(roundTrip.size.width, frame.size.width, accuracy: 0.001)
        XCTAssertEqual(roundTrip.size.height, frame.size.height, accuracy: 0.001)
    }
}
