import Foundation

extension ProjectManager {
    /// Captures current window positions for a project before closing or exiting.
    ///
    /// Non-fatal: failures are logged but do not block the caller.
    func captureWindowPositions(projectId: String) {
        guard let positioner = windowPositioner,
              let detector = screenModeDetector,
              let store = windowPositionStore,
              let config = withState({ config }) else {
            return
        }

        // Read IDE primary frame
        let ideFrame: CGRect
        switch positioner.getPrimaryWindowFrame(bundleId: ApVSCodeLauncher.bundleId, projectId: projectId) {
        case .success(let frame):
            ideFrame = frame
        case .failure(let error):
            logEvent("capture_position.ide_read_failed", level: .warn, message: error.message)
            return
        }

        // Read Chrome primary frame with bounded retry + fallback.
        // Chrome title is set synchronously via AppleScript but AX visibility can lag.
        let captureRetryInterval = windowPollInterval // ~0.1s default, injectable for tests
        let maxCaptureRetries = 5
        var chromeFrame: CGRect?
        var captureAttempt = 0
        captureLoop: while true {
            captureAttempt += 1
            switch positioner.getPrimaryWindowFrame(bundleId: ApChromeLauncher.bundleId, projectId: projectId) {
            case .success(let frame):
                if captureAttempt > 1 {
                    logEvent("capture_position.chrome_read_retried", context: [
                        "project_id": projectId,
                        "attempts": "\(captureAttempt)"
                    ])
                }
                chromeFrame = frame
                break captureLoop
            case .failure(let error):
                let isTransient = error.message.hasPrefix("No window found with token")
                if isTransient && captureAttempt < maxCaptureRetries {
                    Thread.sleep(forTimeInterval: captureRetryInterval)
                    continue
                }
                // Retry exhausted or permanent error — try fallback
                if isTransient {
                    switch positioner.getFallbackWindowFrame(bundleId: ApChromeLauncher.bundleId) {
                    case .success(let fallbackFrame):
                        logEvent("capture_position.chrome_fallback_used", level: .warn, context: [
                            "project_id": projectId,
                            "attempts": "\(captureAttempt)"
                        ])
                        chromeFrame = fallbackFrame
                        break captureLoop
                    case .failure(let fallbackError):
                        logEvent("capture_position.chrome_read_failed", level: .warn,
                                 message: "Chrome frame unavailable after retries — preserving previous saved layout: \(fallbackError.message)",
                                 context: ["project_id": projectId, "attempts": "\(captureAttempt)"])
                        chromeFrame = nil
                        break captureLoop
                    }
                } else {
                    logEvent("capture_position.chrome_read_failed", level: .warn,
                             message: "Chrome frame read failed (permanent): \(error.message)",
                             context: ["project_id": projectId])
                    chromeFrame = nil
                    break captureLoop
                }
            }
        }

        // Skip save when Chrome frame is unavailable — preserve previous complete capture as canonical
        guard let resolvedChromeFrame = chromeFrame else {
            logEvent("capture_position.skipped_partial", level: .warn,
                     message: "Skipping layout save — Chrome frame unavailable, preserving previous saved layout",
                     context: ["project_id": projectId])
            return
        }

        // Detect screen mode
        let centerPoint = CGPoint(x: ideFrame.midX, y: ideFrame.midY)
        let screenMode: ScreenMode
        switch detector.detectMode(containingPoint: centerPoint, threshold: config.layout.smallScreenThreshold) {
        case .success(let mode):
            screenMode = mode
        case .failure(let error):
            logEvent("capture_position.screen_mode_failed", level: .warn, message: error.message)
            screenMode = .wide
        }

        // Save complete frames (both IDE and Chrome available)
        let frames = SavedWindowFrames(
            ide: SavedFrame(rect: ideFrame),
            chrome: SavedFrame(rect: resolvedChromeFrame)
        )
        switch store.save(projectId: projectId, mode: screenMode, frames: frames) {
        case .success:
            logEvent("capture_position.saved", context: [
                "project_id": projectId, "mode": screenMode.rawValue
            ])
        case .failure(let error):
            logEvent("capture_position.save_failed", level: .warn, message: error.message)
        }
    }

}
