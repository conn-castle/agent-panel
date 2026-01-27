import AppKit
import Foundation

/// Display metrics used for layout calculation.
public struct DisplayInfo: Equatable, Sendable {
    public let visibleFrame: CGRect
    public let widthPixels: Double

    /// Creates a display info payload.
    /// - Parameters:
    ///   - visibleFrame: Visible frame in points.
    ///   - widthPixels: Visible width in pixels.
    public init(visibleFrame: CGRect, widthPixels: Double) {
        self.visibleFrame = visibleFrame
        self.widthPixels = widthPixels
    }
}

/// Provides display information for layout calculations.
public protocol DisplayInfoProviding {
    /// Returns the current main display info.
    func mainDisplayInfo() -> DisplayInfo?
}

/// Default display info provider backed by NSScreen.
public struct SystemDisplayInfoProvider: DisplayInfoProviding {
    /// Creates a system display provider.
    public init() {}

    /// Returns the visible frame and pixel width for the main screen.
    public func mainDisplayInfo() -> DisplayInfo? {
        guard let screen = NSScreen.main else {
            return nil
        }
        let visibleFrame = screen.visibleFrame
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return nil
        }
        let widthPixels = visibleFrame.width * screen.backingScaleFactor
        return DisplayInfo(visibleFrame: visibleFrame, widthPixels: widthPixels)
    }
}

/// Default layout frames for IDE and Chrome windows.
public struct ProjectLayout: Equatable, Sendable {
    public let ideFrame: CGRect
    public let chromeFrame: CGRect

    /// Creates a layout payload.
    /// - Parameters:
    ///   - ideFrame: Frame for the IDE window.
    ///   - chromeFrame: Frame for the Chrome window.
    public init(ideFrame: CGRect, chromeFrame: CGRect) {
        self.ideFrame = ideFrame
        self.chromeFrame = chromeFrame
    }
}

/// Calculates default layouts for activation.
public struct DefaultLayoutCalculator {
    /// Creates a default layout calculator.
    public init() {}

    /// Builds the default layout for the display.
    /// - Parameters:
    ///   - display: Display info containing visible frame and pixel width.
    ///   - ultrawideMinWidthPx: Minimum pixel width to treat a display as ultrawide.
    /// - Returns: Default IDE/Chrome frames.
    public func layout(for display: DisplayInfo, ultrawideMinWidthPx: Int) -> ProjectLayout {
        if display.widthPixels >= Double(ultrawideMinWidthPx) {
            return ultrawideLayout(for: display.visibleFrame)
        }
        return laptopLayout(for: display.visibleFrame)
    }

    private func laptopLayout(for frame: CGRect) -> ProjectLayout {
        ProjectLayout(ideFrame: frame, chromeFrame: frame)
    }

    private func ultrawideLayout(for frame: CGRect) -> ProjectLayout {
        let segmentWidth = frame.width / 8.0
        let ideFrame = CGRect(
            x: frame.minX + segmentWidth * 2.0,
            y: frame.minY,
            width: segmentWidth * 3.0,
            height: frame.height
        )
        let chromeFrame = CGRect(
            x: frame.minX + segmentWidth * 5.0,
            y: frame.minY,
            width: segmentWidth * 3.0,
            height: frame.height
        )
        return ProjectLayout(ideFrame: ideFrame, chromeFrame: chromeFrame)
    }
}
