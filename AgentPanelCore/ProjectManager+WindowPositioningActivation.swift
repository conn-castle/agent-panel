import Foundation

extension ProjectManager {
    // MARK: - Window Positioning

    /// Positions IDE and Chrome windows after activation.
    ///
    /// Non-fatal: returns a warning string on failure, nil on success.
    /// Requires windowPositioner, screenModeDetector, and windowPositionStore to all be set.
    /// If only some positioning dependencies are wired, returns a diagnostic warning.
    func positionWindows(projectId: String) -> String? {
        // All three positioning deps must be present. If only some are wired, surface a warning.
        let hasPositioner = windowPositioner != nil
        let hasDetector = screenModeDetector != nil
        let hasStore = windowPositionStore != nil
        let hasAny = hasPositioner || hasDetector || hasStore
        let hasAll = hasPositioner && hasDetector && hasStore

        if hasAny && !hasAll {
            let missing = [
                hasPositioner ? nil : "windowPositioner",
                hasDetector ? nil : "screenModeDetector",
                hasStore ? nil : "windowPositionStore"
            ].compactMap { $0 }
            logEvent("position.partial_deps", level: .warn, message: "Missing: \(missing.joined(separator: ", "))")
            return "Window positioning disabled: missing \(missing.joined(separator: ", "))"
        }

        guard let positioner = windowPositioner,
              let detector = screenModeDetector,
              let store = windowPositionStore,
              let config = withState({ config }) else {
            return nil
        }

        var warnings: [String] = []

        // Read IDE frame to determine which monitor the windows are on.
        // VS Code updates its window title asynchronously after launch, so the AX title
        // token may not be ready on the first attempt. Retry briefly to reduce failures.
        let ideFrame: CGRect
        let maxFrameRetries = 10
        let frameRetryInterval = windowPollInterval // ~0.1s default, injectable for tests
        let minimumZeroWindowProbeFailuresForFastFail = 2
        // Require multiple consecutive zero-window confirmations plus roughly half
        // the token retry budget so slower VS Code startups can still recover.
        let minimumZeroWindowRetryAttemptsForFastFail = 6
        var frameAttempt = 0
        var consecutiveZeroWindowProbeFailures = 0

        ideFrameLoop: while true {
            frameAttempt += 1
            switch positioner.getPrimaryWindowFrame(bundleId: ApVSCodeLauncher.bundleId, projectId: projectId) {
            case .success(let frame):
                if frameAttempt > 1 {
                    logEvent("position.ide_frame_read_retried", context: [
                        "project_id": projectId,
                        "attempts": "\(frameAttempt)"
                    ])
                }
                ideFrame = frame
            case .failure(let error):
                // Only retry transient "window not found" errors (title not yet updated).
                // Permanent errors (AX permission denied, app not running, etc.) fail immediately.
                let isTransient = error.isWindowTokenNotFound
                if isTransient && frameAttempt < maxFrameRetries {
                    // Probe for a permanent zero-window condition, but require multiple
                    // confirmations plus minimum retry confidence before fast-failing.
                    let shouldProbeForZeroWindows = frameAttempt == 1 || consecutiveZeroWindowProbeFailures > 0
                    if shouldProbeForZeroWindows {
                        switch positioner.getFallbackWindowFrame(bundleId: ApVSCodeLauncher.bundleId) {
                        case .success:
                            consecutiveZeroWindowProbeFailures = 0
                            // Probe success confirms windows exist. Continue token retries.
                            // Do not use the probe frame here: this path is only for fast-failing
                            // the permanent zero-window condition.
                            break
                        case .failure(let probeError):
                            if probeError.isWindowInventoryEmpty {
                                consecutiveZeroWindowProbeFailures += 1
                                if consecutiveZeroWindowProbeFailures >= minimumZeroWindowProbeFailuresForFastFail,
                                   frameAttempt >= minimumZeroWindowRetryAttemptsForFastFail {
                                    logEvent("position.ide_no_windows", level: .warn,
                                             message: probeError.message,
                                             context: [
                                                "project_id": projectId,
                                                "attempts": "\(frameAttempt)",
                                                "probe_failures": "\(consecutiveZeroWindowProbeFailures)"
                                             ])
                                    return "Window positioning skipped: \(probeError.message)"
                                }
                            } else {
                                consecutiveZeroWindowProbeFailures = 0
                            }
                            // Ambiguous or other error — continue retry loop (token may resolve)
                        }
                    }
                    Thread.sleep(forTimeInterval: frameRetryInterval)
                    continue
                }
                // Retry exhausted or permanent error — try fallback to focused/only window
                if isTransient {
                    switch positioner.getFallbackWindowFrame(bundleId: ApVSCodeLauncher.bundleId) {
                    case .success(let fallbackFrame):
                        logEvent("position.ide_fallback_used", level: .warn, context: [
                            "project_id": projectId,
                            "attempts": "\(frameAttempt)"
                        ])
                        ideFrame = fallbackFrame
                        break ideFrameLoop
                    case .failure(let fallbackError):
                        logEvent("position.ide_frame_read_failed", level: .warn,
                                 message: "Token retry exhausted and fallback failed: \(fallbackError.message)",
                                 context: ["project_id": projectId, "attempts": "\(frameAttempt)"])
                        return "Window positioning skipped: \(fallbackError.message)"
                    }
                } else {
                    logEvent("position.ide_frame_read_failed", level: .warn, message: error.message, context: [
                        "project_id": projectId,
                        "attempts": "\(frameAttempt)"
                    ])
                    return "Window positioning skipped: \(error.message)"
                }
            }
            break ideFrameLoop
        }

        // Detect screen mode (use center of IDE frame as reference point)
        let centerPoint = CGPoint(x: ideFrame.midX, y: ideFrame.midY)
        let screenMode: ScreenMode
        let physicalWidth: Double
        switch detector.detectMode(containingPoint: centerPoint, threshold: config.layout.smallScreenThreshold) {
        case .success(let mode):
            screenMode = mode
        case .failure(let error):
            // EDID failure: log WARN, use .wide as explicit fallback
            logEvent("position.screen_mode_detection_failed", level: .warn, message: error.message)
            screenMode = .wide
        }

        switch detector.physicalWidthInches(containingPoint: centerPoint) {
        case .success(let width):
            physicalWidth = width
        case .failure(let error):
            logEvent("position.physical_width_detection_failed", level: .warn, message: error.message)
            physicalWidth = 32.0
            warnings.append("Display physical width unknown (using 32\" fallback); layout may be imprecise")
        }

        guard let screenVisibleFrame = detector.screenVisibleFrame(containingPoint: centerPoint) else {
            logEvent("position.screen_frame_not_found", level: .warn)
            return "Window positioning skipped: screen not found"
        }

        // Determine target frames (saved or computed)
        let targetLayout: WindowLayout
        switch store.load(projectId: projectId, mode: screenMode) {
        case .success(let savedFrames):
            if let frames = savedFrames {
                // Validate and clamp saved IDE frame to current screen
                let ideTarget = WindowLayoutEngine.clampToScreen(frame: frames.ide.cgRect, screenVisibleFrame: screenVisibleFrame)

                // Chrome: use saved frame if available, otherwise fall back to computed
                let chromeTarget: CGRect
                if let savedChrome = frames.chrome {
                    chromeTarget = WindowLayoutEngine.clampToScreen(frame: savedChrome.cgRect, screenVisibleFrame: screenVisibleFrame)
                    logEvent("position.using_saved_frames", context: ["project_id": projectId, "mode": screenMode.rawValue])
                } else {
                    let computed = WindowLayoutEngine.computeLayout(
                        screenVisibleFrame: screenVisibleFrame,
                        screenPhysicalWidthInches: physicalWidth,
                        screenMode: screenMode,
                        config: config.layout
                    )
                    chromeTarget = computed.chromeFrame
                    logEvent("position.using_saved_ide_computed_chrome", level: .warn,
                             message: "Saved layout has no Chrome frame — using computed Chrome (investigate if recurring)",
                             context: ["project_id": projectId, "mode": screenMode.rawValue])
                }

                targetLayout = WindowLayout(ideFrame: ideTarget, chromeFrame: chromeTarget)
            } else {
                targetLayout = WindowLayoutEngine.computeLayout(
                    screenVisibleFrame: screenVisibleFrame,
                    screenPhysicalWidthInches: physicalWidth,
                    screenMode: screenMode,
                    config: config.layout
                )
                logEvent("position.using_computed_frames", context: ["project_id": projectId, "mode": screenMode.rawValue])
            }
        case .failure(let error):
            logEvent("position.store_load_failed", level: .warn, message: error.message)
            targetLayout = WindowLayoutEngine.computeLayout(
                screenVisibleFrame: screenVisibleFrame,
                screenPhysicalWidthInches: physicalWidth,
                screenMode: screenMode,
                config: config.layout
            )
        }

        // Compute cascade offset in points: 0.5 inches * (screen points / screen inches)
        let cascadeOffsetPoints = CGFloat(0.5 * (Double(screenVisibleFrame.width) / physicalWidth))

        // Position IDE windows (retry briefly — IDE title may not be visible to AX immediately)
        let maxIDESetRetries = 5
        var ideSetAttempt = 0
        ideSetLoop: while true {
            ideSetAttempt += 1
            switch positioner.setWindowFrames(
                bundleId: ApVSCodeLauncher.bundleId,
                projectId: projectId,
                primaryFrame: targetLayout.ideFrame,
                cascadeOffsetPoints: cascadeOffsetPoints
            ) {
            case .success(let result):
                if ideSetAttempt > 1 {
                    logEvent("position.ide_set_retried", context: [
                        "project_id": projectId,
                        "attempts": "\(ideSetAttempt)"
                    ])
                }
                if result.positioned < 1 {
                    logEvent("position.ide_set_none", level: .warn)
                    warnings.append("IDE: no windows were positioned")
                } else if result.hasPartialFailure {
                    logEvent("position.ide_partial", level: .warn, context: ["positioned": "\(result.positioned)", "matched": "\(result.matched)"])
                    warnings.append("IDE: positioned \(result.positioned) of \(result.matched) windows")
                } else {
                    logEvent("position.ide_positioned", context: ["count": "\(result.positioned)"])
                }
                break ideSetLoop
            case .failure(let error):
                let isTransient = error.isWindowTokenNotFound
                if isTransient && ideSetAttempt < maxIDESetRetries {
                    Thread.sleep(forTimeInterval: frameRetryInterval)
                    continue
                }
                // Retry exhausted or permanent error — try fallback
                if isTransient {
                    switch positioner.setFallbackWindowFrames(
                        bundleId: ApVSCodeLauncher.bundleId,
                        primaryFrame: targetLayout.ideFrame,
                        cascadeOffsetPoints: cascadeOffsetPoints
                    ) {
                    case .success(let result):
                        logEvent("position.ide_set_fallback_used", level: .warn, context: [
                            "project_id": projectId,
                            "attempts": "\(ideSetAttempt)",
                            "positioned": "\(result.positioned)"
                        ])
                        if result.positioned < 1 {
                            warnings.append("IDE: no windows were positioned")
                        }
                        break ideSetLoop
                    case .failure(let fallbackError):
                        logEvent("position.ide_set_failed", level: .warn,
                                 message: "Token retry exhausted and fallback failed: \(fallbackError.message)",
                                 context: ["project_id": projectId, "attempts": "\(ideSetAttempt)"])
                        warnings.append("IDE positioning failed: \(fallbackError.message)")
                        break ideSetLoop
                    }
                } else {
                    logEvent("position.ide_set_failed", level: .warn, message: error.message)
                    warnings.append("IDE positioning failed: \(error.message)")
                    break ideSetLoop
                }
            }
        }

        // Position Chrome windows (retry briefly — Chrome title may not be visible to AX immediately)
        let maxChromeSetRetries = 5
        var chromeSetAttempt = 0
        chromeSetLoop: while true {
            chromeSetAttempt += 1
            switch positioner.setWindowFrames(
                bundleId: ApChromeLauncher.bundleId,
                projectId: projectId,
                primaryFrame: targetLayout.chromeFrame,
                cascadeOffsetPoints: cascadeOffsetPoints
            ) {
            case .success(let result):
                if chromeSetAttempt > 1 {
                    logEvent("position.chrome_set_retried", context: [
                        "project_id": projectId,
                        "attempts": "\(chromeSetAttempt)"
                    ])
                }
                if result.positioned < 1 {
                    logEvent("position.chrome_set_none", level: .warn)
                    warnings.append("Chrome: no windows were positioned")
                } else if result.hasPartialFailure {
                    logEvent("position.chrome_partial", level: .warn, context: ["positioned": "\(result.positioned)", "matched": "\(result.matched)"])
                    warnings.append("Chrome: positioned \(result.positioned) of \(result.matched) windows")
                } else {
                    logEvent("position.chrome_positioned", context: ["count": "\(result.positioned)"])
                }
                break chromeSetLoop
            case .failure(let error):
                let isTransient = error.isWindowTokenNotFound
                if isTransient && chromeSetAttempt < maxChromeSetRetries {
                    Thread.sleep(forTimeInterval: frameRetryInterval)
                    continue
                }
                // Retry exhausted or permanent error — try fallback
                if isTransient {
                    switch positioner.setFallbackWindowFrames(
                        bundleId: ApChromeLauncher.bundleId,
                        primaryFrame: targetLayout.chromeFrame,
                        cascadeOffsetPoints: cascadeOffsetPoints
                    ) {
                    case .success(let result):
                        logEvent("position.chrome_set_fallback_used", level: .warn, context: [
                            "project_id": projectId,
                            "attempts": "\(chromeSetAttempt)",
                            "positioned": "\(result.positioned)"
                        ])
                        if result.positioned < 1 {
                            warnings.append("Chrome: no windows were positioned")
                        }
                        break chromeSetLoop
                    case .failure(let fallbackError):
                        logEvent("position.chrome_set_failed", level: .warn,
                                 message: "Token retry exhausted and fallback failed: \(fallbackError.message)",
                                 context: ["project_id": projectId, "attempts": "\(chromeSetAttempt)"])
                        warnings.append("Chrome positioning failed: \(fallbackError.message)")
                        break chromeSetLoop
                    }
                } else {
                    logEvent("position.chrome_set_failed", level: .warn, message: error.message)
                    warnings.append("Chrome positioning failed: \(error.message)")
                    break chromeSetLoop
                }
            }
        }

        return warnings.isEmpty ? nil : warnings.joined(separator: "; ")
    }
}
