//
//  ApAeroSpace.swift
//  apcore
//
//  CLI wrapper for the AeroSpace window manager.
//  Provides methods for installing, starting, and controlling AeroSpace,
//  including workspace management, window operations, and compatibility checks.
//

import Foundation

/// AeroSpace CLI wrapper for ap.
public struct ApAeroSpace {
    /// Default AeroSpace app path.
    public static let appPath = "/Applications/AeroSpace.app"

    private let commandRunner = ApSystemCommandRunner()

    /// Creates a new AeroSpace wrapper.
    public init() {}

    // MARK: - App Lifecycle

    /// Installs AeroSpace via Homebrew.
    /// - Returns: Success or an error.
    public func installViaHomebrew() -> Result<Void, ApCoreError> {
        switch commandRunner.run(
            executable: "brew",
            arguments: ["install", "--cask", "nikitabobko/tap/aerospace"],
            timeoutSeconds: 300
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("brew install --cask nikitabobko/tap/aerospace", result: result))
            }
            return .success(())
        }
    }

    /// Starts the AeroSpace application.
    /// - Returns: Success or an error.
    public func start() -> Result<Void, ApCoreError> {
        switch commandRunner.run(executable: "open", arguments: ["-a", "AeroSpace"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("open -a AeroSpace", result: result))
            }
            // Brief delay to let the app start
            Thread.sleep(forTimeInterval: 1.0)
            return .success(())
        }
    }

    /// Reloads the AeroSpace configuration.
    /// - Returns: Success or an error.
    public func reloadConfig() -> Result<Void, ApCoreError> {
        switch commandRunner.run(executable: "aerospace", arguments: ["reload-config"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace reload-config", result: result))
            }
            return .success(())
        }
    }

    /// Returns true when AeroSpace.app is installed.
    /// - Returns: True if AeroSpace.app exists on disk.
    public func isAppInstalled() -> Bool {
        let appURL = URL(fileURLWithPath: Self.appPath, isDirectory: true)
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Returns true when the aerospace CLI is available on PATH.
    /// - Returns: True if `aerospace --help` succeeds.
    public func isCliAvailable() -> Bool {
        switch commandRunner.run(executable: "aerospace", arguments: ["--help"], timeoutSeconds: 2) {
        case .failure:
            return false
        case .success(let result):
            return result.exitCode == 0
        }
    }

    // MARK: - Compatibility

    /// Checks whether the installed aerospace CLI supports required commands and flags.
    /// - Returns: Success when compatible, or an error describing missing support.
    public func checkCompatibility() -> Result<Void, ApCoreError> {
        let checks: [(command: String, requiredFlags: [String])] = [
            ("list-workspaces", ["--all", "--focused"]),
            ("list-windows", ["--monitor", "--workspace", "--focused", "--app-bundle-id", "--format"]),
            ("summon-workspace", []),
            ("move-node-to-workspace", ["--window-id"]),
            ("focus", ["--window-id"]),
            ("close", ["--window-id"])
        ]

        var failures: [String] = []
        failures.reserveCapacity(checks.count)

        for check in checks {
            switch commandHelpOutput(command: check.command) {
            case .failure(let error):
                failures.append("aerospace \(check.command) --help failed: \(error.message)")
            case .success(let output):
                let missing = check.requiredFlags.filter { !output.contains($0) }
                if !missing.isEmpty {
                    failures.append(
                        "aerospace \(check.command) missing flags: \(missing.joined(separator: ", "))"
                    )
                }
            }
        }

        guard failures.isEmpty else {
            return .failure(
                ApCoreError(
                    category: .aerospace,
                    message: "AeroSpace CLI compatibility check failed.",
                    detail: failures.joined(separator: "\n")
                )
            )
        }

        return .success(())
    }

    // MARK: - Workspaces

    /// Returns a list of focused AeroSpace workspaces.
    /// - Returns: Workspace names on success, or an error.
    public func listWorkspacesFocused() -> Result<[String], ApCoreError> {
        switch commandRunner.run(executable: "aerospace", arguments: ["list-workspaces", "--focused"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-workspaces --focused", result: result))
            }

            let workspaces = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return .success(workspaces)
        }
    }

    /// Returns a list of AeroSpace workspaces.
    /// - Returns: Workspace names on success, or an error.
    func getWorkspaces() -> Result<[String], ApCoreError> {
        switch commandRunner.run(executable: "aerospace", arguments: ["list-workspaces", "--all"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-workspaces --all", result: result))
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
            return .failure(validationError("Workspace name cannot be empty."))
        }

        switch workspaceExists(trimmed) {
        case .failure(let error):
            return .failure(error)
        case .success(true):
            return .failure(validationError("Workspace already exists: \(trimmed)"))
        case .success(false):
            break
        }

        switch commandRunner.run(executable: "aerospace", arguments: ["summon-workspace", trimmed]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace summon-workspace \(trimmed)", result: result))
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
            return .failure(validationError("Workspace name cannot be empty."))
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
                return .failure(
                    ApCoreError(
                        category: .aerospace,
                        message: "Failed to close \(failures.count) windows in workspace \(trimmed).",
                        detail: failures.joined(separator: "\n")
                    )
                )
            }

            return .success(())
        }
    }

    // MARK: - Windows

    /// Moves a window into the provided workspace.
    /// - Parameters:
    ///   - workspace: Destination workspace name.
    ///   - windowId: AeroSpace window id to move.
    /// - Returns: Success or an error.
    func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError> {
        let trimmed = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty."))
        }
        guard windowId > 0 else {
            return .failure(validationError("Window ID must be positive."))
        }

        switch commandRunner.run(
            executable: "aerospace",
            arguments: ["move-node-to-workspace", "--window-id", "\(windowId)", trimmed]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace move-node-to-workspace --window-id \(windowId) \(trimmed)", result: result))
            }
            return .success(())
        }
    }

    /// Focuses a window by its AeroSpace window id.
    /// - Parameter windowId: AeroSpace window id to focus.
    /// - Returns: Success or an error.
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        guard windowId > 0 else {
            return .failure(validationError("Window ID must be positive."))
        }

        switch commandRunner.run(
            executable: "aerospace",
            arguments: ["focus", "--window-id", "\(windowId)"]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace focus --window-id \(windowId)", result: result))
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
                return .failure(commandError("aerospace list-windows --monitor focused", result: result))
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
                return .failure(commandError("aerospace list-windows --monitor focused --app-bundle-id \(appBundleId)", result: result))
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
                        category: .aerospace,
                        message: "Expected exactly one focused window, found \(windows.count)."
                    )
                )
            }
            return .success(window)
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
                return .failure(commandError("aerospace list-windows --workspace \(workspace)", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    // MARK: - Private Helpers

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
                return .failure(commandError("aerospace list-windows --focused", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Closes a window by its AeroSpace window id.
    /// - Parameter windowId: AeroSpace window id to close.
    /// - Returns: Success or an error.
    private func closeWindow(windowId: Int) -> Result<Void, ApCoreError> {
        guard windowId > 0 else {
            return .failure(validationError("Window ID must be positive."))
        }

        switch commandRunner.run(
            executable: "aerospace",
            arguments: ["close", "--window-id", "\(windowId)"]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace close --window-id \(windowId)", result: result))
            }
            return .success(())
        }
    }

    /// Parses window summaries from formatted AeroSpace output.
    ///
    /// Expected format: `<window-id>||<app-bundle-id>||<workspace>||<window-title>`
    /// where fields are separated by `||` (double pipe).
    ///
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
                return .failure(parseError(
                    "Unexpected aerospace output format.",
                    detail: "Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                ))
            }

            let idPart = String(trimmed[..<firstSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let windowId = Int(idPart) else {
                return .failure(parseError(
                    "Window id was not an integer.",
                    detail: "Got: \(idPart)"
                ))
            }

            let remainder = trimmed[firstSeparator.upperBound...]
            guard let secondSeparator = remainder.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected aerospace output format.",
                    detail: "Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                ))
            }

            let appBundleId = String(remainder[..<secondSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remainderAfterBundle = remainder[secondSeparator.upperBound...]
            guard let thirdSeparator = remainderAfterBundle.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected aerospace output format.",
                    detail: "Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                ))
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

    /// Returns help output for a CLI command.
    /// - Parameter command: AeroSpace command name to query.
    /// - Returns: Help output or an error.
    private func commandHelpOutput(command: String) -> Result<String, ApCoreError> {
        switch commandRunner.run(executable: "aerospace", arguments: [command, "--help"], timeoutSeconds: 2) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace \(command) --help", result: result))
            }

            let output = [result.stdout, result.stderr]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return .success(output)
        }
    }
}
