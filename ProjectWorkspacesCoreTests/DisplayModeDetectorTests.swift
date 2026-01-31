import CoreGraphics
import XCTest

@testable import ProjectWorkspacesCore

final class DisplayModeDetectorTests: XCTestCase {
    func testDetectsUltrawideAtThreshold() throws {
        let info = DisplayInfo(
            displayId: 1,
            pixelWidth: 5000,
            framePoints: .zero,
            visibleFramePoints: .zero,
            screenCount: 1
        )
        let detector = DisplayModeDetector(
            displayInfoProvider: StubDisplayInfoProvider(info: info),
            ultrawideMinWidthPx: 5000
        )

        let mode = try detector.detect()

        XCTAssertEqual(mode, .ultrawide)
    }

    func testDetectsLaptopBelowThreshold() throws {
        let info = DisplayInfo(
            displayId: 1,
            pixelWidth: 4999,
            framePoints: .zero,
            visibleFramePoints: .zero,
            screenCount: 1
        )
        let detector = DisplayModeDetector(
            displayInfoProvider: StubDisplayInfoProvider(info: info),
            ultrawideMinWidthPx: 5000
        )

        let mode = try detector.detect()

        XCTAssertEqual(mode, .laptop)
    }

    func testDetectThrowsWhenDisplayInfoUnavailable() {
        let detector = DisplayModeDetector(
            displayInfoProvider: StubDisplayInfoProvider(error: .mainDisplayUnavailable),
            ultrawideMinWidthPx: 5000
        )

        XCTAssertThrowsError(try detector.detect()) { error in
            XCTAssertEqual(error as? DisplayInfoError, .mainDisplayUnavailable)
        }
    }
}

private struct StubDisplayInfoProvider: DisplayInfoProviding {
    let info: DisplayInfo?
    let error: DisplayInfoError?

    init(info: DisplayInfo) {
        self.info = info
        self.error = nil
    }

    init(error: DisplayInfoError) {
        self.info = nil
        self.error = error
    }

    func mainDisplayInfo() throws -> DisplayInfo {
        if let error {
            throw error
        }
        guard let info else {
            throw DisplayInfoError.mainDisplayUnavailable
        }
        return info
    }
}
