import CoreGraphics
import XCTest

@testable import ProjectWorkspacesCore

final class LayoutDefaultsTests: XCTestCase {
    func testLaptopDefaultsUseFullFrame() throws {
        let provider = DefaultLayoutProvider()
        let layout = provider.layout(for: .laptop)
        let fullFrame = try NormalizedRect(x: 0, y: 0, width: 1, height: 1)

        XCTAssertEqual(layout.ideRect, fullFrame)
        XCTAssertEqual(layout.chromeRect, fullFrame)
    }

    func testUltrawideDefaultsUseEightSegments() throws {
        let provider = DefaultLayoutProvider()
        let layout = provider.layout(for: .ultrawide)
        let segment = 1.0 / 8.0

        let expectedIde = try NormalizedRect(x: segment * 2, y: 0, width: segment * 3, height: 1)
        let expectedChrome = try NormalizedRect(x: segment * 5, y: 0, width: segment * 3, height: 1)

        XCTAssertEqual(layout.ideRect, expectedIde)
        XCTAssertEqual(layout.chromeRect, expectedChrome)
    }

    func testNormalizedRectRejectsOutOfBoundsValues() {
        XCTAssertThrowsError(try NormalizedRect(x: -0.1, y: 0, width: 1, height: 1))
        XCTAssertThrowsError(try NormalizedRect(x: 0, y: 0, width: 1.1, height: 1))
        XCTAssertThrowsError(try NormalizedRect(x: 0.9, y: 0, width: 0.2, height: 1))
        XCTAssertThrowsError(try NormalizedRect(x: 0, y: 0.9, width: 1, height: 0.2))
    }

    func testDenormalizeConvertsToPoints() throws {
        let visibleFrame = CGRect(x: 10, y: 20, width: 1000, height: 800)
        let rect = try NormalizedRect(x: 0.25, y: 0.1, width: 0.5, height: 0.5)

        let absolute = denormalize(rect, in: visibleFrame)

        XCTAssertEqual(absolute.origin.x, 10 + 250, accuracy: 0.001)
        XCTAssertEqual(absolute.origin.y, 20 + 80, accuracy: 0.001)
        XCTAssertEqual(absolute.size.width, 500, accuracy: 0.001)
        XCTAssertEqual(absolute.size.height, 400, accuracy: 0.001)
    }
}
