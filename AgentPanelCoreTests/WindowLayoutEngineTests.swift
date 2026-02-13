import XCTest
@testable import AgentPanelCore

final class WindowLayoutEngineTests: XCTestCase {

    // Standard test screen: 2560x1440 visible frame at (0, 25) for dock/menu
    private let wideScreen = CGRect(x: 0, y: 25, width: 2560, height: 1415)
    private let wideScreenInches: Double = 27.0

    // Small laptop: 1440x900 visible frame at (0, 25)
    private let smallScreen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let smallScreenInches: Double = 13.3

    private let defaultConfig = LayoutConfig()

    // MARK: - Small Screen Mode

    func testSmallModeMaximizesBothWindows() {
        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: smallScreen,
            screenPhysicalWidthInches: smallScreenInches,
            screenMode: .small,
            config: defaultConfig
        )

        XCTAssertEqual(layout.ideFrame, smallScreen)
        XCTAssertEqual(layout.chromeFrame, smallScreen)
    }

    func testSmallModeIgnoresLayoutConfig() {
        let customConfig = LayoutConfig(
            windowHeight: 50,
            maxWindowWidth: 10,
            idePosition: .right,
            justification: .left,
            maxGap: 20
        )

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: smallScreen,
            screenPhysicalWidthInches: smallScreenInches,
            screenMode: .small,
            config: customConfig
        )

        // Still maximized regardless of config
        XCTAssertEqual(layout.ideFrame, smallScreen)
        XCTAssertEqual(layout.chromeFrame, smallScreen)
    }

    // MARK: - Wide Screen Mode: Default Config (IDE left, justify right)

    func testWideDefaultLayout() {
        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: defaultConfig
        )

        // Window height = 90% of 1415 = 1273.5
        let expectedHeight: CGFloat = 1415 * 0.9
        XCTAssertEqual(layout.ideFrame.height, expectedHeight, accuracy: 0.1)
        XCTAssertEqual(layout.chromeFrame.height, expectedHeight, accuracy: 0.1)

        // Top-aligned
        let expectedY = wideScreen.maxY - expectedHeight
        XCTAssertEqual(layout.ideFrame.origin.y, expectedY, accuracy: 0.1)
        XCTAssertEqual(layout.chromeFrame.origin.y, expectedY, accuracy: 0.1)

        // Chrome on right, justified right: chromeX = maxX - windowWidth
        XCTAssertEqual(layout.chromeFrame.maxX, wideScreen.maxX, accuracy: 0.1)

        // IDE on left of Chrome with gap
        XCTAssertTrue(layout.ideFrame.maxX <= layout.chromeFrame.minX)

        // Both windows same width
        XCTAssertEqual(layout.ideFrame.width, layout.chromeFrame.width, accuracy: 0.1)
    }

    // MARK: - IDE Position Variants

    func testIdeRightChromLeft() {
        let config = LayoutConfig(idePosition: .right)

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: config
        )

        // IDE is on the right, Chrome on the left (justified right)
        XCTAssertGreaterThan(layout.ideFrame.origin.x, layout.chromeFrame.origin.x)
        XCTAssertEqual(layout.ideFrame.maxX, wideScreen.maxX, accuracy: 0.1)
    }

    // MARK: - Justification Variants

    func testLeftJustification() {
        let config = LayoutConfig(justification: .left)

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: config
        )

        // IDE on left, anchored to left edge
        XCTAssertEqual(layout.ideFrame.origin.x, wideScreen.minX, accuracy: 0.1)
        // Chrome to the right of IDE
        XCTAssertGreaterThan(layout.chromeFrame.origin.x, layout.ideFrame.maxX - 1)
    }

    func testLeftJustificationIdeRight() {
        let config = LayoutConfig(idePosition: .right, justification: .left)

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: config
        )

        // Chrome on left (anchored to left edge), IDE on right
        XCTAssertEqual(layout.chromeFrame.origin.x, wideScreen.minX, accuracy: 0.1)
        XCTAssertGreaterThan(layout.ideFrame.origin.x, layout.chromeFrame.maxX - 1)
    }

    // MARK: - Window Height

    func testCustomWindowHeight() {
        let config = LayoutConfig(windowHeight: 50)

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: config
        )

        let expectedHeight = wideScreen.height * 0.5
        XCTAssertEqual(layout.ideFrame.height, expectedHeight, accuracy: 0.1)
        XCTAssertEqual(layout.chromeFrame.height, expectedHeight, accuracy: 0.1)

        // Top-aligned
        let expectedY = wideScreen.maxY - expectedHeight
        XCTAssertEqual(layout.ideFrame.origin.y, expectedY, accuracy: 0.1)
    }

    func testWindowHeight100FillsScreen() {
        let config = LayoutConfig(windowHeight: 100)

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: config
        )

        XCTAssertEqual(layout.ideFrame.height, wideScreen.height, accuracy: 0.1)
        XCTAssertEqual(layout.ideFrame.origin.y, wideScreen.origin.y, accuracy: 0.1)
    }

    // MARK: - Max Window Width Cap

    func testMaxWindowWidthCaps() {
        // On a 27" screen, 2560 pts / 27" ≈ 94.8 pts/inch
        // maxWindowWidth 18" → 18 * 94.8 ≈ 1706 pts
        // Half screen = 1280 pts, which is less than 1706, so half screen wins
        let config = LayoutConfig(maxWindowWidth: 18)

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: config
        )

        // Window width should be capped at half screen (1280) since that's smaller than 18" in points
        XCTAssertEqual(layout.ideFrame.width, wideScreen.width * 0.5, accuracy: 0.1)
    }

    func testSmallMaxWindowWidthApplied() {
        // maxWindowWidth 8" → 8 * 94.8 ≈ 758 pts (less than half screen 1280)
        let config = LayoutConfig(maxWindowWidth: 8)

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: config
        )

        let ppi = wideScreen.width / CGFloat(wideScreenInches)
        let expectedWidth = 8.0 * ppi
        XCTAssertEqual(layout.ideFrame.width, expectedWidth, accuracy: 0.1)
        XCTAssertEqual(layout.chromeFrame.width, expectedWidth, accuracy: 0.1)
    }

    // MARK: - Gap Calculation

    func testZeroGap() {
        let config = LayoutConfig(maxGap: 0)

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: config
        )

        // Windows should be adjacent (right-justified)
        XCTAssertEqual(layout.chromeFrame.minX, layout.ideFrame.maxX, accuracy: 0.1)
    }

    func testGapExceedsRemainingSpace() {
        // maxGap 50% on a screen where windows take most of the width
        let config = LayoutConfig(maxWindowWidth: 12, maxGap: 50)

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: wideScreen,
            screenPhysicalWidthInches: wideScreenInches,
            screenMode: .wide,
            config: config
        )

        // Gap should be clamped to remaining space
        let actualGap = layout.chromeFrame.minX - layout.ideFrame.maxX
        let totalOccupied = layout.ideFrame.width + layout.chromeFrame.width + actualGap
        XCTAssertLessThanOrEqual(totalOccupied, wideScreen.width + 0.1)
    }

    // MARK: - Non-Primary Monitor (offset origin)

    func testNonPrimaryMonitorOffset() {
        // Second monitor at x=2560
        let secondScreen = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        let secondScreenInches = 24.0

        let layout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: secondScreen,
            screenPhysicalWidthInches: secondScreenInches,
            screenMode: .wide,
            config: defaultConfig
        )

        // Windows should be within the second monitor's bounds
        XCTAssertGreaterThanOrEqual(layout.ideFrame.origin.x, secondScreen.minX)
        XCTAssertLessThanOrEqual(layout.ideFrame.maxX, secondScreen.maxX + 0.1)
        XCTAssertGreaterThanOrEqual(layout.chromeFrame.origin.x, secondScreen.minX)
        XCTAssertLessThanOrEqual(layout.chromeFrame.maxX, secondScreen.maxX + 0.1)
    }

    // MARK: - All 4 Justification x IdePosition Combos

    func testAllFourCombinations() {
        let combos: [(LayoutConfig.IdePosition, LayoutConfig.Justification)] = [
            (.left, .left), (.left, .right), (.right, .left), (.right, .right)
        ]

        for (idePos, justification) in combos {
            let config = LayoutConfig(idePosition: idePos, justification: justification)
            let layout = WindowLayoutEngine.computeLayout(
                screenVisibleFrame: wideScreen,
                screenPhysicalWidthInches: wideScreenInches,
                screenMode: .wide,
                config: config
            )

            // Both windows within screen bounds
            XCTAssertGreaterThanOrEqual(
                layout.ideFrame.origin.x, wideScreen.minX - 0.1,
                "IDE x for ide=\(idePos) just=\(justification)"
            )
            XCTAssertLessThanOrEqual(
                layout.ideFrame.maxX, wideScreen.maxX + 0.1,
                "IDE maxX for ide=\(idePos) just=\(justification)"
            )
            XCTAssertGreaterThanOrEqual(
                layout.chromeFrame.origin.x, wideScreen.minX - 0.1,
                "Chrome x for ide=\(idePos) just=\(justification)"
            )
            XCTAssertLessThanOrEqual(
                layout.chromeFrame.maxX, wideScreen.maxX + 0.1,
                "Chrome maxX for ide=\(idePos) just=\(justification)"
            )

            // IDE position relative to Chrome
            if idePos == .left {
                XCTAssertLessThan(
                    layout.ideFrame.origin.x, layout.chromeFrame.origin.x,
                    "IDE should be left of Chrome for ide=\(idePos)"
                )
            } else {
                XCTAssertGreaterThan(
                    layout.ideFrame.origin.x, layout.chromeFrame.origin.x,
                    "IDE should be right of Chrome for ide=\(idePos)"
                )
            }
        }
    }

    // MARK: - Clamp/Fit Logic

    func testClampOversizedWidth() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 0, y: 0, width: 2000, height: 800)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.width, 1440)
        XCTAssertEqual(clamped.height, 800)
        // Centered horizontally
        XCTAssertEqual(clamped.midX, screen.midX, accuracy: 0.1)
    }

    func testClampOversizedHeight() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 100, y: 100, width: 1000, height: 1200)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.width, 1000)
        XCTAssertEqual(clamped.height, 900)
        // Centered because height was resized
        XCTAssertEqual(clamped.midY, screen.midY, accuracy: 0.1)
    }

    func testClampOversizedBothDimensions() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 0, y: 0, width: 2000, height: 1200)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.width, 1440)
        XCTAssertEqual(clamped.height, 900)
        XCTAssertEqual(clamped.midX, screen.midX, accuracy: 0.1)
        XCTAssertEqual(clamped.midY, screen.midY, accuracy: 0.1)
    }

    func testClampOffScreenRight() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1200, y: 100, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.width, 800)
        XCTAssertEqual(clamped.height, 600)
        XCTAssertLessThanOrEqual(clamped.maxX, screen.maxX + 0.1)
        XCTAssertGreaterThanOrEqual(clamped.origin.x, screen.minX)
    }

    func testClampOffScreenLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -200, y: 100, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.origin.x, 0)
        XCTAssertEqual(clamped.width, 800)
    }

    func testClampOffScreenBottom() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = CGRect(x: 100, y: -100, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertGreaterThanOrEqual(clamped.origin.y, screen.minY)
    }

    func testClampOffScreenTop() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = CGRect(x: 100, y: 500, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertLessThanOrEqual(clamped.maxY, screen.maxY + 0.1)
    }

    func testClampFitsNoChange() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped, frame)
    }

    func testClampOnSecondMonitor() {
        let screen = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 2500, y: -50, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertGreaterThanOrEqual(clamped.origin.x, screen.minX)
        XCTAssertGreaterThanOrEqual(clamped.origin.y, screen.minY)
        XCTAssertLessThanOrEqual(clamped.maxX, screen.maxX + 0.1)
        XCTAssertLessThanOrEqual(clamped.maxY, screen.maxY + 0.1)
    }
}
