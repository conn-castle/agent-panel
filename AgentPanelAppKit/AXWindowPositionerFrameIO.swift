import AppKit
import AgentPanelCore
import os

extension AXWindowPositioner {
    func readFrameNSScreen(element: AXUIElement, bundleId: String) -> Result<CGRect, ApCoreError> {
        guard let primaryHeight = primaryScreenHeight() else {
            return .failure(ApCoreError(
                category: .system,
                message: "Cannot determine primary display",
                detail: "No NSScreen with origin (0,0) found"
            ))
        }

        // Read AX position
        var posValue: AnyObject?
        let t0 = CFAbsoluteTimeGetCurrent()
        var result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        var ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        Self.logger.debug("ax.read_position bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.read_position SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else {
            return .failure(ApCoreError(
                category: .window,
                message: "Failed to read window position for \(bundleId)",
                detail: "AX error: \(result.rawValue)"
            ))
        }

        var axPosition = CGPoint.zero
        // posValue is AnyObject; verify it's an AXValue via CoreFoundation type ID
        guard let posObj = posValue, CFGetTypeID(posObj) == AXValueGetTypeID() else {
            return .failure(ApCoreError(
                category: .window,
                message: "Failed to read window position for \(bundleId)",
                detail: "AX returned unexpected type for position attribute"
            ))
        }
        let posAXValue = posObj as! AXValue
        if !AXValueGetValue(posAXValue, .cgPoint, &axPosition) {
            return .failure(ApCoreError(
                category: .window,
                message: "Failed to unpack window position for \(bundleId)"
            ))
        }

        // Read AX size
        var sizeValue: AnyObject?
        let t1 = CFAbsoluteTimeGetCurrent()
        result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        ms = (CFAbsoluteTimeGetCurrent() - t1) * 1000
        Self.logger.debug("ax.read_size bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.read_size SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else {
            return .failure(ApCoreError(
                category: .window,
                message: "Failed to read window size for \(bundleId)",
                detail: "AX error: \(result.rawValue)"
            ))
        }

        var axSize = CGSize.zero
        guard let sizeObj = sizeValue, CFGetTypeID(sizeObj) == AXValueGetTypeID() else {
            return .failure(ApCoreError(
                category: .window,
                message: "Failed to read window size for \(bundleId)",
                detail: "AX returned unexpected type for size attribute"
            ))
        }
        let sizeAXValue = sizeObj as! AXValue
        if !AXValueGetValue(sizeAXValue, .cgSize, &axSize) {
            return .failure(ApCoreError(
                category: .window,
                message: "Failed to unpack window size for \(bundleId)"
            ))
        }

        // Convert AX → NSScreen
        let nsX = axPosition.x
        let nsY = primaryHeight - axPosition.y - axSize.height

        return .success(CGRect(x: nsX, y: nsY, width: axSize.width, height: axSize.height))
    }

    func writeFrameNSScreen(element: AXUIElement, frame: CGRect, bundleId: String) -> Result<Void, ApCoreError> {
        guard let primaryHeight = primaryScreenHeight() else {
            return .failure(ApCoreError(
                category: .system,
                message: "Cannot determine primary display",
                detail: "No NSScreen with origin (0,0) found"
            ))
        }

        // Convert NSScreen → AX
        let axX = frame.origin.x
        let axY = primaryHeight - frame.origin.y - frame.height

        // Set AX position
        var axPosition = CGPoint(x: axX, y: axY)
        guard let positionValue = AXValueCreate(.cgPoint, &axPosition) else {
            return .failure(ApCoreError(category: .window, message: "Failed to create AX position value"))
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        var result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        var ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        Self.logger.debug("ax.set_position bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.set_position SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else {
            return .failure(ApCoreError(
                category: .window,
                message: "Failed to set window position for \(bundleId)",
                detail: "AX error: \(result.rawValue)"
            ))
        }

        // Set AX size
        var axSize = CGSize(width: frame.width, height: frame.height)
        guard let sizeValue = AXValueCreate(.cgSize, &axSize) else {
            return .failure(ApCoreError(category: .window, message: "Failed to create AX size value"))
        }

        let t1 = CFAbsoluteTimeGetCurrent()
        result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        ms = (CFAbsoluteTimeGetCurrent() - t1) * 1000
        Self.logger.debug("ax.set_size bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.set_size SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else {
            return .failure(ApCoreError(
                category: .window,
                message: "Failed to set window size for \(bundleId)",
                detail: "AX error: \(result.rawValue)"
            ))
        }

        return .success(())
    }

    // MARK: - Primary Screen

    /// Finds the primary screen height by looking for NSScreen with origin at (0, 0).
    /// This is more robust than using `NSScreen.screens[0]`.
    private func primaryScreenHeight() -> CGFloat? {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
    }

    // MARK: - Frame Clamping

    /// Clamps a frame to fit within the screen visible area.
    /// Shrinks if oversized, then shifts to ensure the frame stays on screen.
    func clampFrameToScreen(frame: CGRect, screenVisibleFrame: CGRect) -> CGRect {
        var width = min(frame.width, screenVisibleFrame.width)
        var height = min(frame.height, screenVisibleFrame.height)
        // Don't grow
        width = min(width, frame.width)
        height = min(height, frame.height)

        var x = frame.origin.x
        var y = frame.origin.y

        // Shift into bounds
        if x < screenVisibleFrame.minX { x = screenVisibleFrame.minX }
        if y < screenVisibleFrame.minY { y = screenVisibleFrame.minY }
        if x + width > screenVisibleFrame.maxX { x = screenVisibleFrame.maxX - width }
        if y + height > screenVisibleFrame.maxY { y = screenVisibleFrame.maxY - height }

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
