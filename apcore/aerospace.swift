import Foundation

/// AeroSpace CLI wrapper for ap.
struct ApAeroSpace {
    private let commandRunner = ApSystemCommandRunner()

    /// Returns a list of AeroSpace workspaces.
    /// - Returns: Workspace names on success, or an error.
    func get_workspaces() -> Result<[String], ApCoreError> {
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
    func workspace_exists(_ name: String) -> Result<Bool, ApCoreError> {
        switch get_workspaces() {
        case .failure(let error):
            return .failure(error)
        case .success(let workspaces):
            return .success(workspaces.contains(name))
        }
    }

    /// Creates a new workspace with the provided name.
    /// - Parameter name: Workspace name to create.
    /// - Returns: Success or an error.
    func create_workspace(_ name: String) -> Result<Void, ApCoreError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ApCoreError(message: "Workspace name cannot be empty."))
        }

        switch workspace_exists(trimmed) {
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
    func move_window_to_workspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError> {
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

    /// Returns window titles for AP IDE windows on the focused monitor.
    /// - Returns: Titles or an error.
    func list_ap_ide_titles() -> Result<[String], ApCoreError> {
        switch list_ap_ide_windows() {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            return .success(windows.map { $0.windowTitle })
        }
    }

    /// Returns AP IDE windows on the focused monitor.
    /// - Returns: Window data or an error.
    func list_ap_ide_windows() -> Result<[ApIdeWindow], ApCoreError> {
        switch list_windows_focused_monitor() {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            let filtered = windows.filter {
                $0.appBundleId == ApVSCodeLauncher.bundleId &&
                    $0.windowTitle.contains(ApIdeToken.prefix) &&
                    !$0.windowTitle.isEmpty
            }
            return .success(filtered)
        }
    }

    /// Returns windows on the focused monitor.
    /// - Returns: Window list or an error.
    private func list_windows_focused_monitor() -> Result<[ApIdeWindow], ApCoreError> {
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

    /// Parses window summaries from formatted AeroSpace output.
    /// - Parameter output: Output from `aerospace list-windows --format`.
    /// - Returns: Parsed window summaries or an error.
    private func parseWindowSummaries(output: String) -> Result<[ApIdeWindow], ApCoreError> {
        let lines = output.split(whereSeparator: \.isNewline)
        var windows: [ApIdeWindow] = []
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
                ApIdeWindow(
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
