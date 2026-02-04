# AgentPanelCore Public API

This document defines the UI- and CLI-facing public API boundaries of `AgentPanelCore`. The App and CLI are presentation layers; all business logic lives in Core.

## Design Principles

1. **Core owns business logic** — Config validation, Doctor checks, AeroSpace orchestration, state persistence
2. **App/CLI are thin** — Parse input, call Core, format output
3. **Dependency injection** — Core types accept protocol dependencies for testability
4. **Result types for errors** — Functions return `Result<T, Error>` rather than throwing

---

## App (UI) Surface

Only the following modules are intended for the UI.

### Module: Configuration (Data Only)

| Type | Description |
|------|-------------|
| `Config` | Validated configuration with projects list |
| `ProjectConfig` | Single project definition (name, path, color, useAgentLayer) |
| `ProjectColorRGB` | RGB color values (0.0–1.0) |
| `ProjectColorPalette` | Named color resolution (indigo, blue, etc.) |

Config loading, validation, and ID normalization are internal and not exposed to the UI. The UI should receive a validated `Config` from Core.

### Module: Doctor

| Type | Description |
|------|-------------|
| `Doctor` | Runs diagnostic checks |
| `DoctorReport` | Complete report with findings, metadata, actions |
| `DoctorFinding` | Single diagnostic finding |
| `DoctorSeverity` | Severity enum (pass, warn, fail) |
| `DoctorMetadata` | Report metadata (timestamp, version, paths) |
| `DoctorActionAvailability` | Available remediation actions |

```swift
public struct Doctor {
    /// Creates a Doctor instance.
    /// - Parameters:
    ///   - runningApplicationChecker: Running application checker (required, provided by CLI/App).
    ///   - hotkeyStatusProvider: Optional hotkey status provider for hotkey registration checks.
    public init(
        runningApplicationChecker: RunningApplicationChecking,
        hotkeyStatusProvider: HotkeyStatusProviding? = nil
    )

    // Note: A full DI initializer with all dependencies is available internally
    // for testing via @testable import.

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

```swift
public struct DoctorReport {
    let findings: [DoctorFinding]
    let metadata: DoctorMetadata
    let actions: DoctorActionAvailability

    /// True if any finding has severity .fail
    var hasFailures: Bool

    /// Renders the report as a human-readable string for CLI and App display.
    func rendered() -> String
}
```

### Module: Errors (Shared)

| Type | Description |
|------|-------------|
| `ApCoreError` | Standard error type |
| `ApCoreErrorCategory` | Error category enum |

```swift
public struct ApCoreError: Error, Equatable, Sendable {
    let category: ApCoreErrorCategory
    let message: String
    let detail: String?
    let command: String?
    let exitCode: Int32?
}

public enum ApCoreErrorCategory: String, Sendable {
    case command        // External command execution failures
    case validation     // Input validation failures
    case fileSystem     // File system operation failures
    case configuration  // Configuration loading/parsing failures
    case aerospace      // AeroSpace-specific failures
    case parse          // Output parsing failures
}
```

---

## CLI Surface (Not Used by UI)

### AgentPanel

```swift
public enum AgentPanel {
    /// Current version string.
    static var version: String
}
```

### ApCore

```swift
public final class ApCore {
    /// The validated configuration for this instance.
    public let config: Config

    /// Creates an ApCore instance with default dependencies.
    public init(config: Config)

    // Note: A full DI initializer with all dependencies is available internally
    // for testing via @testable import.

    // Workspace commands
    func listWorkspaces() -> Result<[String], ApCoreError>
    func newWorkspace(name: String) -> Result<Void, ApCoreError>
    func closeWorkspace(name: String) -> Result<Void, ApCoreError>

    // IDE/Chrome
    func newIde(identifier: String) -> Result<Void, ApCoreError>
    func newChrome(identifier: String) -> Result<Void, ApCoreError>
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

## Internal (Not Public)

The following modules and helpers are internal implementation details and should not be used directly by the App or CLI.

> **Note:** Some internal types have `public` members to support `@testable import` for unit testing. This does not make them part of the public API; App and CLI should not depend on them.

- Configuration internals: `ConfigLoader`, `ConfigLoadResult`, `ConfigFinding`, `ConfigFindingSeverity`, `ConfigError`, `IdNormalizer`
- AeroSpace internals: `ApAeroSpace`, `AeroSpaceConfigManager`, `AeroSpaceConfigStatus`
- State persistence: `StateStore`, `AppState`, `FocusedWindowEntry`, `StateStoreError`
- System utilities: `ExecutableResolver`, `ApSystemCommandRunner`, `ApCommandResult`, `ApVSCodeLauncher`, `ApChromeLauncher`
- Data paths: `DataPaths`
- Logging: `AgentPanelLogger`, `LogEntry`, `LogLevel`, `LogWriteError`, `AgentPanelLogging`
- Error factory functions: `commandError`, `validationError`, `fileSystemError`, `parseError` (public for Core use, not intended for App/CLI)
- Internal dependency protocols: `FileSystem`, `DateProviding`, `AppDiscovering`, `HotkeyChecking`, `EnvironmentProviding`

### Required Protocols (Public, Implemented by CLI/App)

These protocols are public because CLI and App must provide implementations, but they are not part of the UI-facing API:

| Protocol | Description |
|----------|-------------|
| `RunningApplicationChecking` | Checks if an application is running (requires AppKit) |
| `HotkeyStatusProviding` | Provides hotkey registration status (optional, App only) |
