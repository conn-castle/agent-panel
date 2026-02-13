import AppKit
import AgentPanelCore
import os

/// AX API-based window positioning implementation.
///
/// Resolves windows by bundle ID + title token (`AP:<projectId>`), reads/writes
/// window frames via Accessibility APIs, and handles NSScreen-to-AX coordinate conversion.
///
/// All public API frames use NSScreen coordinate space (origin bottom-left, Y up).
/// AX coordinate conversion is handled internally.
public struct AXWindowPositioner: WindowPositioning {
    private static let logger = Logger(subsystem: "com.agentpanel", category: "AXWindowPositioner")

    /// Safety ceiling per AX element. Normal calls complete in 1–5ms.
    private static let axTimeoutSeconds: Float = 0.5

    public init() {}

    // MARK: - WindowPositioning Protocol

    public func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, ApCoreError> {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.get_frame_total bundleId=\(bundleId) projectId=\(projectId) elapsed=\(String(format: "%.1f", ms))ms")
            if ms > 100 { Self.logger.warning("ax.get_frame_total SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }
        }

        let token = "AP:\(projectId)"

        let matches: [AXUIElement]
        switch findMatchingWindows(bundleId: bundleId, token: token) {
        case .success(let windows):
            matches = windows
        case .failure(let error):
            return .failure(error)
        }

        guard let primary = matches.first else {
            return .failure(ApCoreError(
                category: .window,
                message: "No window found with token '\(token)' for \(bundleId)"
            ))
        }

        return readFrameNSScreen(element: primary, bundleId: bundleId)
    }

    public func setWindowFrames(
        bundleId: String,
        projectId: String,
        primaryFrame: CGRect,
        cascadeOffsetPoints: CGFloat
    ) -> Result<WindowPositionResult, ApCoreError> {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.set_frames_total bundleId=\(bundleId) projectId=\(projectId) elapsed=\(String(format: "%.1f", ms))ms")
            if ms > 100 { Self.logger.warning("ax.set_frames_total SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }
        }

        let token = "AP:\(projectId)"

        let matches: [AXUIElement]
        switch findMatchingWindows(bundleId: bundleId, token: token) {
        case .success(let windows):
            matches = windows
        case .failure(let error):
            return .failure(error)
        }

        guard !matches.isEmpty else {
            return .failure(ApCoreError(
                category: .window,
                message: "No window found with token '\(token)' for \(bundleId)"
            ))
        }

        // Determine the screen containing the primary frame for cascade clamping
        let screenFrame = NSScreen.screens.first {
            $0.visibleFrame.contains(CGPoint(x: primaryFrame.midX, y: primaryFrame.midY))
        }?.visibleFrame

        var positioned = 0
        var lastError: ApCoreError?
        for (index, element) in matches.enumerated() {
            let offset = CGFloat(index) * cascadeOffsetPoints
            var frame = CGRect(
                x: primaryFrame.origin.x + offset,
                y: primaryFrame.origin.y - offset, // Down in NSScreen = lower Y
                width: primaryFrame.width,
                height: primaryFrame.height
            )

            // Clamp cascade frames to screen bounds to prevent off-screen windows
            if let screenFrame {
                frame = clampFrameToScreen(frame: frame, screenVisibleFrame: screenFrame)
            }

            switch writeFrameNSScreen(element: element, frame: frame, bundleId: bundleId) {
            case .success:
                positioned += 1
            case .failure(let error):
                lastError = error
                Self.logger.warning("Failed to set frame for match \(index) of \(bundleId): \(error.message)")
            }
        }

        if positioned == 0, let error = lastError {
            return .failure(error)
        }

        return .success(WindowPositionResult(positioned: positioned, matched: matches.count))
    }

    public func isAccessibilityTrusted() -> Bool {
        let t0 = CFAbsoluteTimeGetCurrent()
        let trusted = AXIsProcessTrusted()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        Self.logger.debug("ax.is_trusted elapsed=\(String(format: "%.1f", ms))ms result=\(trusted)")
        return trusted
    }

    public func promptForAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Self.logger.debug("ax.prompt_accessibility result=\(trusted)")
        return trusted
    }

    // MARK: - AX Window Resolution

    /// Finds all AX windows matching the title token, sorted by title for stable ordering.
    ///
    /// If window enumeration fails for all PIDs (e.g., AX permission denied), returns `.failure`
    /// with the last AX error instead of an empty success.
    private func findMatchingWindows(bundleId: String, token: String) -> Result<[AXUIElement], ApCoreError> {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard !apps.isEmpty else {
            return .failure(ApCoreError(
                category: .window,
                message: "No running application with bundle ID '\(bundleId)'"
            ))
        }

        // Sort PIDs ascending for deterministic order
        let sortedPids = apps.map { $0.processIdentifier }.sorted()

        var allMatches: [(title: String, element: AXUIElement)] = []
        var lastEnumerationError: AXError?
        var anyEnumerationSucceeded = false

        for pid in sortedPids {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, Self.axTimeoutSeconds)

            var windowsValue: AnyObject?
            let t0 = CFAbsoluteTimeGetCurrent()
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.enumerate_windows bundleId=\(bundleId) pid=\(pid) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
            if ms > 100 { Self.logger.warning("ax.enumerate_windows SLOW bundleId=\(bundleId) pid=\(pid) elapsed=\(String(format: "%.1f", ms))ms") }

            guard result == .success, let windows = windowsValue as? [AXUIElement] else {
                lastEnumerationError = result
                continue
            }

            anyEnumerationSucceeded = true
            for window in windows {
                AXUIElementSetMessagingTimeout(window, Self.axTimeoutSeconds)
                if let title = readTitle(element: window, bundleId: bundleId), title.contains(token) {
                    allMatches.append((title: title, element: window))
                }
            }
        }

        // If no PID succeeded enumeration, surface the AX error rather than returning empty success
        if !anyEnumerationSucceeded, let axError = lastEnumerationError {
            return .failure(ApCoreError(
                category: .window,
                message: "Failed to enumerate windows for \(bundleId)",
                detail: "AX error: \(axError.rawValue) (may indicate missing Accessibility permission)"
            ))
        }

        // Sort by title for stable ordering; secondary sort by hash for deterministic tie-break
        allMatches.sort {
            if $0.title != $1.title { return $0.title < $1.title }
            // Stable tie-break: use AXUIElement hash
            return CFHash($0.element) < CFHash($1.element)
        }

        return .success(allMatches.map { $0.element })
    }

    // MARK: - AX Attribute Read/Write

    private func readTitle(element: AXUIElement, bundleId: String) -> String? {
        var titleValue: AnyObject?
        let t0 = CFAbsoluteTimeGetCurrent()
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        Self.logger.debug("ax.read_title bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.read_title SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else { return nil }
        return titleValue as? String
    }

    private func readFrameNSScreen(element: AXUIElement, bundleId: String) -> Result<CGRect, ApCoreError> {
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

    private func writeFrameNSScreen(element: AXUIElement, frame: CGRect, bundleId: String) -> Result<Void, ApCoreError> {
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
    private func clampFrameToScreen(frame: CGRect, screenVisibleFrame: CGRect) -> CGRect {
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
