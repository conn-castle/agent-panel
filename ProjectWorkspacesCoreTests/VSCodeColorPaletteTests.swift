import XCTest

@testable import ProjectWorkspacesCore

final class VSCodeColorPaletteTests: XCTestCase {
    func testPaletteBuildsExpectedDerivedColors() {
        let palette = VSCodeColorPalette()
        let result = palette.customizations(for: "#7C3AED")

        let customizations: VSCodeColorCustomizations
        switch result {
        case .failure(let error):
            XCTFail("Unexpected palette error: \(error)")
            return
        case .success(let values):
            customizations = values
        }

        XCTAssertEqual(customizations["titleBar.activeBackground"], "#7C3AED")
        XCTAssertEqual(customizations["titleBar.inactiveBackground"], "#51269A")
        XCTAssertEqual(customizations["activityBar.background"], "#6931C9")
        XCTAssertEqual(customizations["statusBar.background"], "#632EBE")
        XCTAssertEqual(customizations["statusBarItem.hoverBackground"], "#703FC3")
        XCTAssertEqual(customizations["activityBarBadge.background"], "#9D6BF2")
        XCTAssertEqual(customizations["titleBar.activeForeground"], "#FFFFFF")
        XCTAssertEqual(customizations["titleBar.inactiveForeground"], "#CCCCCC")
    }

    func testPaletteUsesBlackForegroundForLightBackgrounds() {
        let palette = VSCodeColorPalette()
        let result = palette.customizations(for: "#FFFFFF")

        let customizations: VSCodeColorCustomizations
        switch result {
        case .failure(let error):
            XCTFail("Unexpected palette error: \(error)")
            return
        case .success(let values):
            customizations = values
        }

        XCTAssertEqual(customizations["titleBar.activeForeground"], "#000000")
        XCTAssertEqual(customizations["titleBar.inactiveForeground"], "#333333")
    }
}
