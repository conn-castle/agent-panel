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
    static let logger = Logger(subsystem: "com.agentpanel", category: "AXWindowPositioner")

    /// Safety ceiling per AX element. Normal calls complete in 1–5ms.
    static let axTimeoutSeconds: Float = 0.5

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

    public func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, ApCoreError> {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.recover_window bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms")
        }

        // Prefer the app's focused window (set by AeroSpace focus before this call),
        // falling back to title enumeration if the focused window title doesn't match.
        let element: AXUIElement
        switch findFocusedOrTitledWindow(bundleId: bundleId, title: windowTitle) {
        case .success(let match):
            guard let match else {
                return .success(.notFound)
            }
            element = match
        case .failure(let error):
            return .failure(error)
        }

        // Read current frame
        let currentFrame: CGRect
        switch readFrameNSScreen(element: element, bundleId: bundleId) {
        case .success(let frame):
            currentFrame = frame
        case .failure(let error):
            return .failure(error)
        }

        // Compute recovered frame: shrink if oversized, then center on screen
        let needsShrinkWidth = currentFrame.width > screenVisibleFrame.width
        let needsShrinkHeight = currentFrame.height > screenVisibleFrame.height
        let isOffScreen = !screenVisibleFrame.contains(CGPoint(x: currentFrame.midX, y: currentFrame.midY))

        guard needsShrinkWidth || needsShrinkHeight || isOffScreen else {
            return .success(.unchanged)
        }

        let width = needsShrinkWidth ? screenVisibleFrame.width : currentFrame.width
        let height = needsShrinkHeight ? screenVisibleFrame.height : currentFrame.height

        let centeredFrame = CGRect(
            x: screenVisibleFrame.minX + (screenVisibleFrame.width - width) / 2,
            y: screenVisibleFrame.minY + (screenVisibleFrame.height - height) / 2,
            width: width,
            height: height
        )

        switch writeFrameNSScreen(element: element, frame: centeredFrame, bundleId: bundleId) {
        case .success:
            return .success(.recovered)
        case .failure(let error):
            return .failure(error)
        }
    }

}
