import AppKit
import CoreGraphics
import Foundation

/// Supported display modes for layout decisions.
enum DisplayMode: String, Codable, Equatable {
    case laptop
    case ultrawide
}

/// Display information needed for display mode detection and layout geometry.
struct DisplayInfo: Equatable {
    let displayId: CGDirectDisplayID
    let pixelWidth: Int
    let framePoints: CGRect
    let visibleFramePoints: CGRect
    let screenCount: Int
}

/// Errors thrown when display information cannot be resolved.
enum DisplayInfoError: Error, Equatable {
    case mainDisplayUnavailable
    case missingScreen(displayId: CGDirectDisplayID)
    case invalidPixelWidth(Int)
}

/// Provides display information for layout decisions.
protocol DisplayInfoProviding {
    /// Returns info about the main display.
    /// - Returns: Display info for the current main display.
    /// - Throws: `DisplayInfoError` if the display cannot be resolved.
    func mainDisplayInfo() throws -> DisplayInfo
}

/// Default display info provider using CoreGraphics and AppKit.
struct DefaultDisplayInfoProvider: DisplayInfoProviding {
    /// Creates a default display info provider.
    init() {}

    /// Returns info about the main display using `CGMainDisplayID`.
    /// - Returns: Display info for the current main display.
    /// - Throws: `DisplayInfoError` if the display cannot be resolved.
    func mainDisplayInfo() throws -> DisplayInfo {
        let displayId = CGMainDisplayID()
        guard displayId != 0 else {
            throw DisplayInfoError.mainDisplayUnavailable
        }

        let pixelWidth = Int(CGDisplayPixelsWide(displayId))
        guard pixelWidth > 0 else {
            throw DisplayInfoError.invalidPixelWidth(pixelWidth)
        }

        let screens = NSScreen.screens
        guard let screen = screens.first(where: { screen in
            guard let screenDisplayId = screen.displayId else {
                return false
            }
            return screenDisplayId == displayId
        }) else {
            throw DisplayInfoError.missingScreen(displayId: displayId)
        }

        return DisplayInfo(
            displayId: displayId,
            pixelWidth: pixelWidth,
            framePoints: screen.frame,
            visibleFramePoints: screen.visibleFrame,
            screenCount: screens.count
        )
    }
}

/// Detects the current display mode based on main display width.
struct DisplayModeDetector {
    private let displayInfoProvider: DisplayInfoProviding
    private let ultrawideMinWidthPx: Int

    /// Creates a display mode detector.
    /// - Parameters:
    ///   - displayInfoProvider: Provider used to resolve display info.
    ///   - ultrawideMinWidthPx: Minimum pixel width to treat a display as ultrawide.
    init(
        displayInfoProvider: DisplayInfoProviding = DefaultDisplayInfoProvider(),
        ultrawideMinWidthPx: Int
    ) {
        precondition(ultrawideMinWidthPx > 0, "ultrawideMinWidthPx must be positive")
        self.displayInfoProvider = displayInfoProvider
        self.ultrawideMinWidthPx = ultrawideMinWidthPx
    }

    /// Determines the active display mode.
    /// - Returns: `.ultrawide` when the main display meets or exceeds the threshold; otherwise `.laptop`.
    /// - Throws: `DisplayInfoError` if display info cannot be resolved.
    func detect() throws -> DisplayMode {
        let info = try displayInfoProvider.mainDisplayInfo()
        return info.pixelWidth >= ultrawideMinWidthPx ? .ultrawide : .laptop
    }
}

private extension NSScreen {
    var displayId: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = deviceDescription[key] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
