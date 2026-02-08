# AgentPanelCore Public API

The public API of `AgentPanelCore` has these main concerns:

1. **ProjectManager** — Project listing, sorting, selection, and focus management
2. **Doctor** — Diagnostics and remediation
3. **Config** — Configuration loading and project definitions
4. **Logging** — Structured JSON logging
5. **Onboarding Support** — AeroSpace installation and configuration

## Design Principles

1. **Core owns business logic** — Config validation, Doctor checks, AeroSpace orchestration
2. **App is thin** — Parse input, call Core, format output
3. **Minimal public surface** — Only expose what App actually needs

---

## Version & Identity

```swift
public enum AgentPanel {
    /// Current version string (e.g., "1.0.0").
    public static var version: String
}
```

## Errors

```swift
public struct ApCoreError: Error, Equatable, Sendable {
    public let message: String
}
```

---

## Configuration

```swift
public struct Config: Equatable, Sendable {
    public let projects: [ProjectConfig]

    /// Loads and validates configuration from the default path.
    public static func loadDefault() -> Result<Config, ConfigLoadError>
}

public struct ProjectConfig: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let color: String  // Named color or hex (#RRGGBB)
    public let useAgentLayer: Bool
}

public enum ConfigLoadError: Error, Equatable, Sendable {
    case fileNotFound(path: String)
    case readFailed(path: String, detail: String)
    case parseFailed(detail: String)
    case validationFailed(findings: [ConfigFinding])
}
```

### Config Findings

```swift
public enum ConfigFindingSeverity: String, CaseIterable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"
}

public struct ConfigFinding: Equatable, Sendable {
    public let severity: ConfigFindingSeverity
    public let title: String
}
```

### Project Colors

```swift
public struct ProjectColorRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
}

public enum ProjectColorPalette {
    public static func resolve(_ value: String) -> ProjectColorRGB?
}
```

---

## Data Paths

```swift
public struct DataPaths: Sendable {
    public static func `default`(fileManager: FileManager) -> DataPaths

    public var configFile: URL
    public var primaryLogFile: URL
}
```

---

## ProjectManager

Single point of entry for all project operations.

The activation sequence is **strictly sequential** and mirrors the proven shell-script
flow (see `docs/using_aerospace.md` § "Project Activation Command Sequence"):

1. Find or launch tagged Chrome window
2. Find or launch tagged VS Code window
3. Move Chrome to workspace (no focus follow)
4. Move VS Code to workspace (with focus follow)
5. Verify both windows arrived in workspace
6. Focus workspace (`summon-workspace` with fallback)
7. Focus IDE window
8. Verify focus stability (poll)

```swift
public final class ProjectManager {
    /// Prefix for all AgentPanel workspaces.
    public static let workspacePrefix: String  // "ap-"

    /// All projects from config, or empty if config not loaded.
    public var projects: [ProjectConfig] { get }

    /// The currently active project, derived from the focused workspace.
    public var activeProject: ProjectConfig? { get }

    /// Returns project IDs that currently have open AgentPanel workspaces.
    public func openProjectIds() -> Result<Set<String>, ProjectError>

    /// Creates a ProjectManager with default dependencies.
    public init()

    /// Loads configuration from the default path.
    @discardableResult
    public func loadConfig() -> Result<Config, ConfigLoadError>

    /// Captures the currently focused window for later restoration.
    public func captureCurrentFocus() -> CapturedFocus?

    /// Restores focus to a previously captured window.
    @discardableResult
    public func restoreFocus(_ focus: CapturedFocus) -> Bool

    /// Focuses a workspace by name.
    /// Uses `summon-workspace` (preferred, pulls workspace to current monitor)
    /// with fallback to `workspace` (switches to workspace wherever it is).
    @discardableResult
    public func focusWorkspace(name: String) -> Bool

    /// Focuses a window by its AeroSpace window ID.
    @discardableResult
    public func focusWindow(windowId: Int) -> Bool

    /// Focuses a window and polls until focus is stable.
    /// Re-asserts focus if macOS steals it during the polling window.
    /// - Parameters:
    ///   - windowId: AeroSpace window ID to focus.
    ///   - timeout: Maximum time to wait for stable focus (default: 10s).
    ///   - pollInterval: Interval between focus checks (default: 100ms).
    /// - Returns: True if focus is stable within the timeout.
    @discardableResult
    public func focusWindowStable(
        windowId: Int,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) async -> Bool

    /// Returns projects sorted and filtered for display.
    public func sortedProjects(query: String) -> [ProjectConfig]

    /// Activates a project by ID (sequential flow).
    ///
    /// Runs the full activation sequence: find/launch Chrome → find/launch VS Code
    /// → move Chrome to workspace → move VS Code to workspace (focus follows)
    /// → verify workspace membership → focus workspace → focus IDE
    /// → verify focus stability.
    ///
    /// - Parameters:
    ///   - projectId: The project ID to activate.
    ///   - preCapturedFocus: Focus state captured before showing UI, used for restoring
    ///     focus when exiting the project later.
    /// - Returns: The IDE window ID on success, for post-dismissal focusing.
    public func selectProject(projectId: String, preCapturedFocus: CapturedFocus) async -> Result<Int, ProjectError>

    /// Closes a project by ID and restores focus to the previous non-project window.
    public func closeProject(projectId: String) -> Result<Void, ProjectError>

    /// Exits to the last non-project window without closing the project.
    public func exitToNonProjectWindow() -> Result<Void, ProjectError>
}

public enum ProjectError: Error, Equatable, Sendable {
    case projectNotFound(projectId: String)
    case configNotLoaded
    case aeroSpaceError(detail: String)
    case ideLaunchFailed(detail: String)
    case chromeLaunchFailed(detail: String)
    case noActiveProject
    case noPreviousWindow
    case windowNotFound(detail: String)
    case focusUnstable(detail: String)
}
```

### Focus Types

```swift
public struct CapturedFocus: Sendable, Equatable {
    public let windowId: Int
    public let appBundleId: String
}
```

---

## Doctor

```swift
public struct Doctor {
    public init(
        runningApplicationChecker: RunningApplicationChecking,
        hotkeyStatusProvider: HotkeyStatusProviding? = nil
    )

    /// Runs all diagnostic checks.
    public func run() -> DoctorReport

    /// Installs AeroSpace via Homebrew.
    public func installAeroSpace() -> DoctorReport

    /// Starts AeroSpace.
    public func startAeroSpace() -> DoctorReport

    /// Reloads AeroSpace configuration.
    public func reloadAeroSpaceConfig() -> DoctorReport
}

public struct DoctorReport: Equatable, Sendable {
    public let findings: [DoctorFinding]
    public let actions: DoctorActionAvailability

    public var hasFailures: Bool { get }
    public func rendered() -> String
}

public struct DoctorFinding: Equatable, Sendable {
    public let severity: DoctorSeverity
}

public enum DoctorSeverity: String, CaseIterable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"
}

public struct DoctorActionAvailability: Equatable, Sendable {
    public let canInstallAeroSpace: Bool
    public let canStartAeroSpace: Bool
    public let canReloadAeroSpaceConfig: Bool
}
```

### Doctor Protocol Requirements

The App must provide implementations since Core cannot import AppKit.

```swift
public protocol RunningApplicationChecking {
    func isApplicationRunning(bundleIdentifier: String) -> Bool
}

public protocol HotkeyStatusProviding {
    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus?
}

public enum HotkeyRegistrationStatus: Equatable, Sendable {
    case registered
    case failed(osStatus: Int32)
}
```

---

## Logging

```swift
public protocol AgentPanelLogging {
    @discardableResult
    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError>
}

public enum LogLevel: String, Codable, Sendable {
    case info, warn, error
}

public struct AgentPanelLogger: AgentPanelLogging {
    public init()
    public init(dataStore: DataPaths)

    public func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError>
}

public enum LogWriteError: Error, Equatable, Sendable {
    case invalidEvent
    case encodingFailed(String)
    case createDirectoryFailed(String)
    case fileSizeFailed(String)
    case rotationFailed(String)
    case writeFailed(String)

    public var message: String { get }
}
```

---

## Onboarding Support

For first-launch setup, the App uses these types directly.

### AeroSpace

```swift
public struct ApAeroSpace {
    public init()

    /// Returns true when AeroSpace.app is installed.
    public func isAppInstalled() -> Bool

    /// Returns true when the aerospace CLI is available.
    public func isCliAvailable() -> Bool

    /// Installs AeroSpace via Homebrew.
    public func installViaHomebrew() -> Result<Void, ApCoreError>

    /// Starts AeroSpace.
    public func start() -> Result<Void, ApCoreError>
}
```

#### Internal AeroSpace Operations (used by ProjectManager)

These methods are internal to `AgentPanelCore` and not part of the public API. They are
documented here because they implement the activation command sequence.

```swift
// Window resolution — global search with fallback to focused monitor.
// Matches: aerospace list-windows --app-bundle-id <id> --format <fmt>
//          || aerospace list-windows --monitor focused --app-bundle-id <id> --format <fmt>
func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError>

// Workspace focus — summon-workspace with fallback to workspace.
// Matches: aerospace summon-workspace <name>
//          || aerospace workspace <name>
func focusWorkspace(name: String) -> Result<Void, ApCoreError>

// Move window with optional focus-follows.
// Matches: aerospace move-node-to-workspace [--focus-follows-window] --window-id <id> <ws>
func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError>

// Focused window query (used for stability polling).
// Matches: aerospace list-windows --focused --format <fmt>
func focusedWindow() -> Result<ApWindow, ApCoreError>
```

### AeroSpace Config Manager

```swift
public enum AeroSpaceConfigStatus: String, Sendable {
    case missing
    case managedByAgentPanel
    case externalConfig
    case unknown
}

public struct AeroSpaceConfigManager {
    public static var configPath: String { get }

    public init()

    public func writeSafeConfig() -> Result<Void, ApCoreError>
    public func configStatus() -> AeroSpaceConfigStatus
}
```
