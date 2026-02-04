# AgentPanelCore Public API

This document defines the public API boundaries of `AgentPanelCore`. The App and CLI are presentation layers; all business logic lives in Core.

## Design Principles

1. **Core owns business logic** — Config validation, Doctor checks, AeroSpace orchestration, state persistence
2. **App/CLI are thin** — Parse input, call Core, format output
3. **Dependency injection** — Core types accept protocol dependencies for testability
4. **Result types for errors** — Functions return `Result<T, Error>` rather than throwing

---

## Module: Configuration

### Types

| Type | Description |
|------|-------------|
| `Config` | Validated configuration with projects list |
| `ProjectConfig` | Single project definition (name, path, color, useAgentLayer) |
| `ProjectColorRGB` | RGB color values (0.0–1.0) |
| `ProjectColorPalette` | Named color resolution (indigo, blue, etc.) |
| `ConfigError` | Parse/validation error with message |
| `ConfigLoadResult` | Load result containing config (if valid) and findings |
| `ConfigFinding` | Individual validation finding (pass/warn/fail) |
| `ConfigFindingSeverity` | Severity enum (pass, warn, fail) |
| `ConfigLoader` | Loads and validates config from disk |
| `IdNormalizer` | Normalizes project names to stable IDs |

### ConfigLoader

```swift
public struct ConfigLoader {
    /// Loads config from the default path (~/.config/agent-panel/config.toml).
    static func loadDefault() -> Result<ConfigLoadResult, ConfigError>

    /// Loads config from a specific URL.
    static func load(from url: URL) -> Result<ConfigLoadResult, ConfigError>
}
```

### IdNormalizer

```swift
public enum IdNormalizer {
    /// Normalizes a name to a stable identifier.
    /// - Lowercases
    /// - Replaces non-alphanumeric with hyphens
    /// - Collapses multiple hyphens
    /// - Trims leading/trailing hyphens
    static func normalize(_ name: String) -> String

    /// Reserved IDs that cannot be used.
    static let reservedIds: Set<String>
}
```

---

## Module: Doctor

### Types

| Type | Description |
|------|-------------|
| `Doctor` | Runs diagnostic checks |
| `DoctorReport` | Complete report with findings, metadata, actions |
| `DoctorFinding` | Single diagnostic finding |
| `DoctorSeverity` | Severity enum (pass, warn, fail) |
| `DoctorMetadata` | Report metadata (timestamp, version, paths) |
| `DoctorActionAvailability` | Available remediation actions |

### Doctor

```swift
public struct Doctor {
    init(
        runningApplicationChecker: RunningApplicationChecking,
        hotkeyStatusProvider: HotkeyStatusProviding? = nil,
        hotkeyChecker: HotkeyChecking = CarbonHotkeyChecker(),
        dateProvider: DateProviding = SystemDateProvider(),
        aerospace: ApAeroSpace = ApAeroSpace(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery(),
        executableResolver: ExecutableResolver = ExecutableResolver(),
        dataStore: DataPaths = .default()
    )

    /// Runs all diagnostic checks.
    func run() -> DoctorReport

    /// Installs AeroSpace via Homebrew.
    func installAeroSpace() -> DoctorReport

    /// Starts AeroSpace.
    func startAeroSpace() -> DoctorReport

    /// Reloads AeroSpace configuration.
    func reloadAeroSpaceConfig() -> DoctorReport
}
```

### DoctorReport

```swift
public struct DoctorReport {
    let findings: [DoctorFinding]
    let metadata: DoctorMetadata
    let actions: DoctorActionAvailability

    /// True if any finding has severity .fail
    var hasFailures: Bool

    /// Renders the report as CLI-friendly text.
    func rendered() -> String
}
```

---

## Module: AeroSpace

### Types

| Type | Description |
|------|-------------|
| `ApAeroSpace` | AeroSpace CLI wrapper |
| `AeroSpaceConfigManager` | Manages ~/.aerospace.toml |
| `AeroSpaceConfigStatus` | Config file status enum |

### ApAeroSpace

```swift
public struct ApAeroSpace {
    /// Bundle identifier for AeroSpace.app
    static let bundleIdentifier = "bobko.aerospace"

    /// Path to AeroSpace.app if installed, nil otherwise.
    var appPath: String?

    /// Whether AeroSpace.app is installed.
    func isAppInstalled() -> Bool

    /// Whether the aerospace CLI is available.
    func isCliAvailable() -> Bool

    /// Checks CLI compatibility (required commands/flags).
    func checkCompatibility() -> Result<Void, ApCoreError>

    /// Installs AeroSpace via Homebrew.
    func installViaHomebrew() -> Result<Void, ApCoreError>

    /// Starts AeroSpace.app.
    func start() -> Result<Void, ApCoreError>

    /// Reloads AeroSpace configuration.
    func reloadConfig() -> Result<Void, ApCoreError>

    // Window management
    func listWorkspacesFocused() -> Result<[String], ApCoreError>
    func listAllWindows() -> Result<[ApWindow], ApCoreError>
    func listWindowsFocused() -> Result<[ApWindow], ApCoreError>
    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError>
    func listWindowsApp(bundleId: String) -> Result<[ApWindow], ApCoreError>
    func focusedWindow() -> Result<ApWindow, ApCoreError>
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError>
    func summonWorkspace(_ workspace: String) -> Result<Void, ApCoreError>
    func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError>
    func closeWindow(windowId: Int) -> Result<Void, ApCoreError>
}
```

### AeroSpaceConfigManager

```swift
public struct AeroSpaceConfigManager {
    /// Path to ~/.aerospace.toml
    let configPath: URL

    /// Path to backup file
    let backupPath: URL

    /// Whether config file exists.
    func configExists() -> Bool

    /// Whether config is managed by AgentPanel.
    func configIsManagedByAgentPanel() -> Result<Bool, ApCoreError>

    /// Current config status.
    func configStatus() -> AeroSpaceConfigStatus

    /// Backs up existing config to .agentpanel-backup.
    func backupExistingConfig() -> Result<Void, ApCoreError>

    /// Writes the AgentPanel-managed safe config.
    func writeSafeConfig() -> Result<Void, ApCoreError>

    /// Loads safe config content from bundle.
    func loadSafeConfigFromBundle() -> String?
}
```

---

## Module: Core Commands

### Types

| Type | Description |
|------|-------------|
| `AgentPanel` | Namespace with version constant |
| `ApCore` | Main command executor |
| `ApWindow` | Window summary (id, bundleId, workspace, title) |

### AgentPanel

```swift
public enum AgentPanel {
    /// Current version string.
    static var version: String
}
```

### ApCore

```swift
public struct ApCore {
    init(config: Config, aerospace: ApAeroSpace = ApAeroSpace())

    // Workspace commands
    func listWorkspaces() -> Result<Void, ApCoreError>
    func newWorkspace(name: String) -> Result<Void, ApCoreError>
    func closeWorkspace(name: String) -> Result<Void, ApCoreError>

    // Config
    func showConfig() -> Result<Void, ApCoreError>

    // IDE/Chrome
    func newIde(identifier: String) -> Result<Void, ApCoreError>
    func newChrome(identifier: String) -> Result<Void, ApCoreError>
    func listIdeTitles() -> Result<[String], ApCoreError>
    func listIdeWindows() -> Result<[ApWindow], ApCoreError>
    func listChromeWindows() -> Result<[ApWindow], ApCoreError>

    // Window management
    func listWindowsWorkspace(_ workspace: String) -> Result<[ApWindow], ApCoreError>
    func focusedWindow() -> Result<ApWindow, ApCoreError>
    func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError>
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError>
}
```

### ApWindow

```swift
public struct ApWindow: Equatable {
    let windowId: Int
    let appBundleId: String
    let workspace: String
    let windowTitle: String
}
```

---

## Module: State Persistence

### Types

| Type | Description |
|------|-------------|
| `StateStore` | Read/write app state to disk |
| `AppState` | Persisted state (version, lastLaunchedAt, focusStack) |
| `FocusedWindowEntry` | Single focus stack entry |
| `StateStoreError` | Load/save errors |

### StateStore

```swift
public struct StateStore {
    /// Max focus stack entries (20)
    static let maxFocusStackSize: Int

    /// Max age for focus entries (7 days)
    static let maxFocusStackAge: TimeInterval

    init(
        dataStore: DataPaths = .default(),
        fileSystem: FileSystem = DefaultFileSystem(),
        dateProvider: DateProviding = SystemDateProvider()
    )

    /// Loads state from disk (returns empty state if no file).
    func load() -> Result<AppState, StateStoreError>

    /// Saves state to disk (prunes stale entries).
    func save(_ state: AppState) -> Result<Void, StateStoreError>

    /// Pushes a window onto the focus stack.
    func pushFocus(window: FocusedWindowEntry, state: AppState) -> AppState

    /// Pops the most recent window from the focus stack.
    func popFocus(state: AppState) -> (FocusedWindowEntry?, AppState)

    /// Removes entries for windows that no longer exist.
    func pruneDeadWindows(state: AppState, existingWindowIds: Set<Int>) -> AppState
}
```

### AppState

```swift
public struct AppState: Codable, Equatable, Sendable {
    /// Current schema version (increment for breaking changes)
    static let currentVersion: Int

    var version: Int
    var lastLaunchedAt: Date?
    var focusStack: [FocusedWindowEntry]
}
```

---

## Module: System

### Types

| Type | Description |
|------|-------------|
| `ExecutableResolver` | Finds executables in PATH |
| `ApSystemCommandRunner` | Runs shell commands |
| `ApCommandResult` | Command execution result |
| `ApVSCodeLauncher` | Launches VS Code windows |
| `ApChromeLauncher` | Launches Chrome windows |

### ExecutableResolver

```swift
public struct ExecutableResolver {
    /// Standard paths searched for executables.
    static let standardPaths: [String]

    /// Resolves an executable name to its full path.
    func resolve(_ name: String) -> String?
}
```

### ApSystemCommandRunner

```swift
public struct ApSystemCommandRunner {
    /// Runs a command with the given arguments.
    func run(
        executable: String,
        arguments: [String] = [],
        timeoutSeconds: TimeInterval? = 5
    ) -> ApCommandResult
}
```

---

## Module: Data Paths

### Types

| Type | Description |
|------|-------------|
| `DataPaths` | Canonical filesystem paths |

### DataPaths

```swift
public struct DataPaths: Sendable {
    let homeDirectory: URL

    /// Creates store rooted at user's home directory.
    static func `default`(fileManager: FileManager = .default) -> DataPaths

    // Config paths
    var configFile: URL  // ~/.config/agent-panel/config.toml

    // State paths
    var stateFile: URL  // ~/.local/state/agent-panel/state.json
    var vscodeWorkspaceDirectory: URL  // ~/.local/state/agent-panel/vscode
    func vscodeWorkspaceFile(projectId: String) -> URL

    // Log paths
    var logsDirectory: URL  // ~/.local/state/agent-panel/logs
    var primaryLogFile: URL  // ~/.local/state/agent-panel/logs/agent-panel.log
}
```

---

## Module: Logging

### Types

| Type | Description |
|------|-------------|
| `AgentPanelLogger` | Structured JSON logger |
| `LogEntry` | Single log entry |
| `LogLevel` | Log severity (debug, info, warn, error) |
| `LogWriteError` | Write failure reasons |
| `AgentPanelLogging` | Logger protocol |

### AgentPanelLogger

```swift
public struct AgentPanelLogger {
    init(
        logDirectory: URL,
        fileSystem: FileSystem = DefaultFileSystem(),
        dateProvider: DateProviding = SystemDateProvider()
    )

    /// Logs an event with optional context.
    func log(
        event: String,
        level: LogLevel = .info,
        context: [String: String] = [:]
    ) -> Result<Void, LogWriteError>

    /// Logs a pre-built entry.
    func log(entry: LogEntry) -> Result<Void, LogWriteError>
}
```

---

## Module: Errors

### Types

| Type | Description |
|------|-------------|
| `ApCoreError` | Standard error type |
| `ApCoreErrorCategory` | Error category enum |

### ApCoreError

```swift
public struct ApCoreError: Error, Equatable, Sendable {
    let category: ApCoreErrorCategory
    let message: String
    let detail: String?
    let commandOutput: String?
}

public enum ApCoreErrorCategory: String, Sendable {
    case aerospace
    case config
    case fileSystem
    case validation
    case system
}
```

### Error Factories

```swift
func commandError(_ commandDescription: String, result: ApCommandResult) -> ApCoreError
func validationError(_ message: String) -> ApCoreError
func fileSystemError(_ message: String, detail: String? = nil) -> ApCoreError
func parseError(_ message: String, detail: String? = nil) -> ApCoreError
```

---

## Module: Dependencies (Protocols)

These protocols enable dependency injection for testing.

| Protocol | Description | Default Implementation |
|----------|-------------|----------------------|
| `FileSystem` | File operations | `DefaultFileSystem` |
| `DateProviding` | Current time | `SystemDateProvider` |
| `AppDiscovering` | Find apps by bundle ID | `LaunchServicesAppDiscovery` |
| `RunningApplicationChecking` | Check if app is running | (AppKit, in App/CLI) |
| `HotkeyChecking` | Check hotkey conflicts | `CarbonHotkeyChecker` |
| `HotkeyStatusProviding` | Current hotkey status | (App only) |
| `EnvironmentProviding` | Environment variables | `ProcessEnvironment` |

---

## Usage Patterns

### App

```swift
// Onboarding
let doctor = Doctor(runningApplicationChecker: AppKitRunningApplicationChecker())
let report = doctor.run()
if report.hasFailures { /* show onboarding */ }

// Switcher
let result = ConfigLoader.loadDefault()
let projects = result.config?.projects ?? []

// State
let stateStore = StateStore()
var state = stateStore.load().get() ?? AppState()
state.lastLaunchedAt = Date()
stateStore.save(state)
```

### CLI

```swift
// Doctor
let report = Doctor(runningApplicationChecker: checker).run()
print(report.rendered())

// Commands
let config = ConfigLoader.loadDefault().get()!.config!
let core = ApCore(config: config)
core.listWorkspaces()
```
