import CoreGraphics
import Foundation

/// Converts an AppKit frame (bottom-left origin) into an AX top-left position.
/// - Parameters:
///   - frame: AppKit frame in points.
///   - mainDisplayHeightPoints: Main display height in points.
/// - Returns: AX position using top-left origin.
func appKitFrameToAXPositionTopLeft(
    frame: CGRect,
    mainDisplayHeightPoints: CGFloat
) -> CGPoint {
    let x = frame.origin.x
    let y = mainDisplayHeightPoints - frame.origin.y - frame.height
    return CGPoint(x: x, y: y)
}

/// Converts an AX top-left position + size into an AppKit frame (bottom-left origin).
/// - Parameters:
///   - position: AX position using top-left origin.
///   - size: AX size.
///   - mainDisplayHeightPoints: Main display height in points.
/// - Returns: AppKit frame in points.
func axPositionTopLeftToAppKitFrame(
    position: CGPoint,
    size: CGSize,
    mainDisplayHeightPoints: CGFloat
) -> CGRect {
    let x = position.x
    let y = mainDisplayHeightPoints - position.y - size.height
    return CGRect(x: x, y: y, width: size.width, height: size.height)
}
