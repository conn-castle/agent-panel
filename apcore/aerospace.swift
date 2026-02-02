import Foundation

/// AeroSpace CLI wrapper for ap.
struct ApAeroSpace {
    private let commandRunner = ApSystemCommandRunner()

    /// Returns a list of AeroSpace workspaces.
    /// - Returns: Workspace names on success, or an error.
    func getWorkspaces() -> Result<[String], ApCoreError> {
        switch commandRunner.run(executable: "aerospace", arguments: ["list-workspaces", "--all"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmed.isEmpty ? "" : "\n\(trimmed)"
                return .failure(
                    ApCoreError(
                        message: "aerospace list-workspaces --all failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }

            let workspaces = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return .success(workspaces)
        }
    }

    /// Checks whether a workspace name exists.
    /// - Parameter name: Workspace name to look up.
    /// - Returns: True if the workspace exists, or an error.
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> {
        switch getWorkspaces() {
        case .failure(let error):
            return .failure(error)
        case .success(let workspaces):
            return .success(workspaces.contains(name))
        }
    }

    /// Creates a new workspace with the provided name.
    /// - Parameter name: Workspace name to create.
    /// - Returns: Success or an error.
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ApCoreError(message: "Workspace name cannot be empty."))
        }

        switch workspaceExists(trimmed) {
        case .failure(let error):
            return .failure(error)
        case .success(true):
            return .failure(ApCoreError(message: "Workspace already exists: \(trimmed)"))
        case .success(false):
            break
        }

        switch commandRunner.run(executable: "aerospace", arguments: ["summon-workspace", trimmed]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    ApCoreError(
                        message: "aerospace summon-workspace failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }
            return .success(())
        }
    }

    /// Moves a window into the provided workspace.
    /// - Parameters:
    ///   - workspace: Destination workspace name.
    ///   - windowId: AeroSpace window id to move.
    /// - Returns: Success or an error.
    func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError> {
        let trimmed = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ApCoreError(message: "Workspace name cannot be empty."))
        }

        switch commandRunner.run(
            executable: "aerospace",
            arguments: ["move-node-to-workspace", "--window-id", "\(windowId)", trimmed]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    ApCoreError(
                        message: "aerospace move-node-to-workspace failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }
            return .success(())
        }
    }

    /// Focuses a window by its AeroSpace window id.
    /// - Parameter windowId: AeroSpace window id to focus.
    /// - Returns: Success or an error.
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        switch commandRunner.run(
            executable: "aerospace",
            arguments: ["focus", "--window-id", "\(windowId)"]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    ApCoreError(
                        message: "aerospace focus --window-id failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }
            return .success(())
        }
    }

    /// Closes all windows in the provided workspace.
    /// - Parameter name: Workspace name to close windows in.
    /// - Returns: Success or an error.
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ApCoreError(message: "Workspace name cannot be empty."))
        }

        switch listWindowsWorkspace(workspace: trimmed) {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            var failures: [String] = []
            failures.reserveCapacity(windows.count)

            for window in windows {
                switch closeWindow(windowId: window.windowId) {
                case .failure(let error):
                    failures.append("window \(window.windowId): \(error.message)")
                case .success:
                    continue
                }
            }

            guard failures.isEmpty else {
                let details = failures.joined(separator: "\n")
                return .failure(
                    ApCoreError(
                        message: "Failed to close \(failures.count) windows in workspace \(trimmed):\n\(details)"
                    )
                )
            }

            return .success(())
        }
    }

    /// Returns windows on the focused monitor.
    /// - Returns: Window list or an error.
    func listWindowsFocusedMonitor() -> Result<[ApWindow], ApCoreError> {
        switch commandRunner.run(
            executable: "aerospace",
            arguments: [
                "list-windows",
                "--monitor",
                "focused",
                "--format",
                "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
            ]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmed.isEmpty ? "" : "\n\(trimmed)"
                return .failure(
                    ApCoreError(
                        message: "aerospace list-windows --monitor focused failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Returns windows on the focused monitor filtered by app bundle id.
    /// - Parameter appBundleId: App bundle identifier to filter.
    /// - Returns: Window list or an error.
    func listWindowsOnFocusedMonitor(appBundleId: String) -> Result<[ApWindow], ApCoreError> {
        switch commandRunner.run(
            executable: "aerospace",
            arguments: [
                "list-windows",
                "--monitor",
                "focused",
                "--app-bundle-id",
                appBundleId,
                "--format",
                "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
            ]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmed.isEmpty ? "" : "\n\(trimmed)"
                return .failure(
                    ApCoreError(
                        message: "aerospace list-windows --monitor focused --app-bundle-id failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Returns VS Code windows on the focused monitor.
    /// - Returns: Window list or an error.
    func listVSCodeWindowsOnFocusedMonitor() -> Result<[ApWindow], ApCoreError> {
        listWindowsOnFocusedMonitor(appBundleId: ApVSCodeLauncher.bundleId)
    }

    /// Returns Chrome windows on the focused monitor.
    /// - Returns: Window list or an error.
    func listChromeWindowsOnFocusedMonitor() -> Result<[ApWindow], ApCoreError> {
        listWindowsOnFocusedMonitor(appBundleId: ApChromeLauncher.bundleId)
    }

    /// Returns the currently focused window.
    /// - Returns: Focused window or an error.
    func focusedWindow() -> Result<ApWindow, ApCoreError> {
        switch listWindowsFocused() {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            guard windows.count == 1, let window = windows.first else {
                return .failure(
                    ApCoreError(
                        message: "Expected exactly one focused window, found \(windows.count)."
                    )
                )
            }
            return .success(window)
        }
    }

    /// Returns windows scoped to the focused window query.
    /// - Returns: Window list or an error.
    private func listWindowsFocused() -> Result<[ApWindow], ApCoreError> {
        switch commandRunner.run(
            executable: "aerospace",
            arguments: [
                "list-windows",
                "--focused",
                "--format",
                "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
            ]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmed.isEmpty ? "" : "\n\(trimmed)"
                return .failure(
                    ApCoreError(
                        message: "aerospace list-windows --focused failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Returns windows for the given workspace.
    /// - Parameter workspace: Workspace name to query.
    /// - Returns: Window list or an error.
    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        switch commandRunner.run(
            executable: "aerospace",
            arguments: [
                "list-windows",
                "--workspace",
                workspace,
                "--format",
                "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
            ]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmed.isEmpty ? "" : "\n\(trimmed)"
                return .failure(
                    ApCoreError(
                        message: "aerospace list-windows --workspace failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }

            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Closes a window by its AeroSpace window id.
    /// - Parameter windowId: AeroSpace window id to close.
    /// - Returns: Success or an error.
    private func closeWindow(windowId: Int) -> Result<Void, ApCoreError> {
        switch commandRunner.run(
            executable: "aerospace",
            arguments: ["close", "--window-id", "\(windowId)"]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    ApCoreError(
                        message: "aerospace close --window-id failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }
            return .success(())
        }
    }

    /// Parses window summaries from formatted AeroSpace output.
    /// - Parameter output: Output from `aerospace list-windows --format`.
    /// - Returns: Parsed window summaries or an error.
    private func parseWindowSummaries(output: String) -> Result<[ApWindow], ApCoreError> {
        let lines = output.split(whereSeparator: \.isNewline)
        var windows: [ApWindow] = []
        windows.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            guard let firstSeparator = trimmed.range(of: "||") else {
                return .failure(
                    ApCoreError(
                        message: "Unexpected aerospace output. Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                    )
                )
            }

            let idPart = String(trimmed[..<firstSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let windowId = Int(idPart) else {
                return .failure(
                    ApCoreError(
                        message: "Unexpected aerospace output. Window id was not an integer: \(idPart)"
                    )
                )
            }

            let remainder = trimmed[firstSeparator.upperBound...]
            guard let secondSeparator = remainder.range(of: "||") else {
                return .failure(
                    ApCoreError(
                        message: "Unexpected aerospace output. Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                    )
                )
            }

            let appBundleId = String(remainder[..<secondSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remainderAfterBundle = remainder[secondSeparator.upperBound...]
            guard let thirdSeparator = remainderAfterBundle.range(of: "||") else {
                return .failure(
                    ApCoreError(
                        message: "Unexpected aerospace output. Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                    )
                )
            }
            let workspace = String(remainderAfterBundle[..<thirdSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let titlePart = remainderAfterBundle[thirdSeparator.upperBound...]
            let windowTitle = String(titlePart).trimmingCharacters(in: .whitespacesAndNewlines)

            windows.append(
                ApWindow(
                    windowId: windowId,
                    appBundleId: appBundleId,
                    workspace: workspace,
                    windowTitle: windowTitle
                )
            )
        }

        return .success(windows)
    }

}
