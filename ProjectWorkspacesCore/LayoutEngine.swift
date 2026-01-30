import Foundation
import CoreGraphics

/// Output describing the current main display environment.
struct LayoutEnvironment: Equatable {
    let displayMode: DisplayMode
    let visibleFramePoints: CGRect
    let mainFramePoints: CGRect
    let mainDisplayHeightPoints: CGFloat
    let screenCount: Int
}

/// Errors thrown by layout calculations.
enum LayoutEngineError: Error, Equatable {
    case invalidVisibleFrame(CGRect)
}

/// Resolves layout inputs and converts between normalized and screen coordinates.
struct LayoutEngine {
    private let displayInfoProvider: DisplayInfoProviding
    private let defaultLayoutProvider: DefaultLayoutProvider

    init(
        displayInfoProvider: DisplayInfoProviding = DefaultDisplayInfoProvider(),
        defaultLayoutProvider: DefaultLayoutProvider = DefaultLayoutProvider()
    ) {
        self.displayInfoProvider = displayInfoProvider
        self.defaultLayoutProvider = defaultLayoutProvider
    }

    /// Resolves the current display environment.
    /// - Parameter ultrawideMinWidthPx: Minimum pixel width treated as ultrawide.
    /// - Returns: Display environment information.
    /// - Throws: `DisplayInfoError` if display info is unavailable.
    func resolveEnvironment(ultrawideMinWidthPx: Int) throws -> LayoutEnvironment {
        let info = try displayInfoProvider.mainDisplayInfo()
        let displayMode: DisplayMode = info.pixelWidth >= ultrawideMinWidthPx ? .ultrawide : .laptop
        return LayoutEnvironment(
            displayMode: displayMode,
            visibleFramePoints: info.visibleFramePoints,
            mainFramePoints: info.framePoints,
            mainDisplayHeightPoints: info.framePoints.height,
            screenCount: info.screenCount
        )
    }

    /// Returns the default layout for a display mode.
    /// - Parameter displayMode: Current display mode.
    /// - Returns: Default layout for the display mode.
    func defaultLayout(for displayMode: DisplayMode) -> ProjectLayout {
        defaultLayoutProvider.layout(for: displayMode)
    }

    /// Normalizes a frame relative to the visible frame.
    /// - Parameters:
    ///   - frame: AppKit frame in points.
    ///   - visibleFramePoints: Visible frame in points.
    /// - Returns: Normalized rect.
    /// - Throws: `LayoutEngineError` or `NormalizedRectError` when invalid.
    func normalize(_ frame: CGRect, in visibleFramePoints: CGRect) throws -> NormalizedRect {
        guard visibleFramePoints.width > 0, visibleFramePoints.height > 0 else {
            throw LayoutEngineError.invalidVisibleFrame(visibleFramePoints)
        }
        let x = Double((frame.origin.x - visibleFramePoints.origin.x) / visibleFramePoints.width)
        let y = Double((frame.origin.y - visibleFramePoints.origin.y) / visibleFramePoints.height)
        let width = Double(frame.width / visibleFramePoints.width)
        let height = Double(frame.height / visibleFramePoints.height)
        return try NormalizedRect(x: x, y: y, width: width, height: height)
    }

    /// Checks whether a frame belongs to the main display.
    /// - Parameters:
    ///   - frame: AppKit frame in points.
    ///   - mainFramePoints: Main display frame in points.
    /// - Returns: True when the frame midpoint lies within the main display frame.
    func isFrameOnMainDisplay(_ frame: CGRect, mainFramePoints: CGRect) -> Bool {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        return mainFramePoints.contains(midpoint)
    }
}
