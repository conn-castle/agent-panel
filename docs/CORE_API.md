# AgentPanelCore Public API

This document defines the public API boundaries of `AgentPanelCore`. The App and CLI are presentation layers; all business logic lives in Core.

## Design Principles

1. **Core owns business logic** — Config validation, Doctor checks, AeroSpace orchestration, state persistence
2. **App/CLI are thin** — Parse input, call Core, format output
3. **Dependency injection** — Core types accept protocol dependencies for testability
4. **Explicit error handling** — Functions return `Result<T, Error>`, optionals, or `Bool` rather than throwing

---

## Shared Surface (App + CLI)

### Version & Identity

```swift
public enum AgentPanel {
    /// Current version string (e.g., "1.0.0").
    public static var version: String

    /// Bundle identifier for the AgentPanel app.
    public static let appBundleIdentifier: String
}
```

### Errors

| Type | Description |
|------|-------------|
| `ApCoreError` | Standard error type for Core operations |
| `ApCoreErrorCategory` | Error category enum for programmatic handling |

```swift
public struct ApCoreError: Error, Equatable, Sendable {
    public let category: ApCoreErrorCategory
    public let message: String
    public let detail: String?
    public let command: String?
    public let exitCode: Int32?
}

public enum ApCoreErrorCategory: String, Sendable {
    case command        // External command execution failures
    case validation     // Input validation failures
    case fileSystem     // File system operation failures
    case configuration  // Configuration loading/parsing failures
    case parse          // Output parsing failures
}
```

---

## App (UI) Surface

### Required Protocols (Implemented by App)

These protocols are public because the App must provide implementations. Core cannot import AppKit.

| Protocol | Description |
|----------|-------------|
| `RunningApplicationChecking` | Checks if an application is running (requires AppKit) |
| `HotkeyStatusProviding` | Provides hotkey registration status (optional) |
| `FocusOperationsProviding` | Captures and restores window focus (requires AeroSpace) |

```swift
/// Running application lookup interface for Doctor policies.
public protocol RunningApplicationChecking {
    /// Returns true when an application with the given bundle identifier is running.
    func isApplicationRunning(bundleIdentifier: String) -> Bool
}

/// Provides the last known hotkey registration status.
public protocol HotkeyStatusProviding {
    /// Returns the current hotkey registration status, or nil if unknown.
    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus?
}

public enum HotkeyRegistrationStatus: Equatable, Sendable {
    case registered
    case failed(osStatus: Int32)
}

/// Protocol for window focus operations.
/// Core treats CapturedFocus as an opaque token; the App implementation
/// knows how to create and consume it via AeroSpace.
public protocol FocusOperationsProviding {
    /// Captures the currently focused window for later restoration.
    func captureCurrentFocus() -> CapturedFocus?

    /// Restores focus to a previously captured window.
    func restoreFocus(_ focus: CapturedFocus) -> Bool
}

/// Captured window focus state. Created by App, stored by Core, consumed by App.
public struct CapturedFocus: Sendable, Equatable {
    public let windowId: Int
    public let appBundleId: String

    public init(windowId: Int, appBundleId: String)
}
```

### Configuration

| Type | Description |
|------|-------------|
| `Config` | Validated configuration with projects list |
| `ProjectConfig` | Single project definition (name, path, color, useAgentLayer) |
| `ProjectColorRGB` | RGB color values (0.0–1.0) |
| `ProjectColorPalette` | Named color resolution (indigo, blue, etc.) |
| `ConfigLoadError` | Error type for configuration loading failures |
| `ConfigFinding` | Diagnostic finding from config validation |
| `ConfigFindingSeverity` | Severity level for config findings |

```swift
public struct Config: Equatable, Sendable {
    public let projects: [ProjectConfig]
}

public struct ProjectConfig: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let color: String // Named color or hex (#RRGGBB)
    public let useAgentLayer: Bool
}

public struct ProjectColorRGB: Equatable, Sendable {
    public let red: Double    // 0.0–1.0
    public let green: Double  // 0.0–1.0
    public let blue: Double   // 0.0–1.0
}

extension Config {
    /// Loads and validates configuration from the default path.
    public static func loadDefault() -> Result<Config, ConfigLoadError>
}

public enum ConfigLoadError: Error, Equatable, Sendable {
    case fileNotFound(path: String)
    case readFailed(path: String, detail: String)
    case parseFailed(detail: String)
    case validationFailed(findings: [ConfigFinding])
}

public struct ConfigFinding: Equatable, Sendable {
    public let severity: ConfigFindingSeverity
    public let title: String
    public let detail: String?
    public let fix: String?
}

public enum ConfigFindingSeverity: String, Sendable {
    case pass
    case warn
    case fail
}
```

### Session Management

| Type | Description |
|------|-------------|
| `SessionManager` | Manages app session lifecycle, state persistence, and focus history |
| `StateHealthIssue` | Reason why state is unhealthy (blocking saves) |
| `FocusEvent` | A recorded focus history event |
| `FocusEventKind` | Type of focus event |

**Two-phase initialization:** SessionManager requires `setFocusOperations()` to be called after construction before focus capture/restore will work. Config must be loaded first to create the `FocusOperationsProviding` implementation.

**Thread safety:** SessionManager is not thread-safe. All methods must be called from the main thread.

```swift
public final class SessionManager {
    /// Creates a SessionManager with default dependencies.
    public init()

    /// Maximum number of project activation events used for sorting.
    public static let recentProjectActivationSortLimit: Int

    /// If non-nil, state is unhealthy and saves are blocked.
    public private(set) var stateHealthIssue: StateHealthIssue?

    /// Sets the focus operations provider.
    /// Call after loading configuration to enable focus capture/restore.
    public func setFocusOperations(_ provider: FocusOperationsProviding?)

    /// Records session start. Call once when the app launches.
    public func sessionStarted(version: String)

    /// Records session end. Call when the app is about to terminate.
    public func sessionEnded()

    /// Captures the currently focused window for later restoration.
    public func captureCurrentFocus() -> CapturedFocus?

    /// Attempts to restore focus to a previously captured window.
    @discardableResult
    public func restoreFocus(_ captured: CapturedFocus) -> Bool

    /// Records that a project was activated.
    public func projectActivated(projectId: String)

    /// Records that a project was deactivated.
    public func projectDeactivated(projectId: String)

    /// The current focus history for display purposes.
    public var focusHistory: [FocusEvent] { get }

    /// Returns the most recent focus events, newest first.
    public func recentFocusHistory(count: Int) -> [FocusEvent]

    /// Returns the most recent project activation events, newest first.
    public func recentProjectActivations(count: Int) -> [FocusEvent]

    /// Returns the most recent project activation events used for sorting.
    public func recentProjectActivationsForSorting() -> [FocusEvent]
}

public enum StateHealthIssue: Equatable, Sendable {
    case corrupted(detail: String)
    case newerVersion(found: Int, supported: Int)
}

public struct FocusEvent: Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let kind: FocusEventKind
    public let projectId: String?
    public let windowId: Int?
    public let appBundleId: String?
    public let metadata: [String: String]?
}

public enum FocusEventKind: String, Codable, Equatable, Sendable {
    case projectActivated
    case projectDeactivated
    case windowFocused
    case windowDefocused
    case sessionStarted
    case sessionEnded
}
```

### Project Sorting

| Type | Description |
|------|-------------|
| `ProjectSorter` | Sorts and filters projects for switcher display |

Sorting rules:
- **Empty query:** Recently activated projects first (using the most recent 100 activation events; see `SessionManager.recentProjectActivationSortLimit`), then config order for unactivated projects
- **Non-empty query:** Name-prefix matches first, then id-prefix, then infix matches; within each tier, recency (same 100-event activation window) then config order

```swift
public enum ProjectSorter {
    /// Sorts and optionally filters projects based on search query and focus history.
    /// - Parameters:
    ///   - projects: All available projects (in config order)
    ///   - query: Search query (empty = no filter, just sort by recency)
    ///   - recentActivations: Focus events for projectActivated, newest first
    /// - Returns: Filtered (if query non-empty) and sorted projects
    public static func sortedProjects(
        _ projects: [ProjectConfig],
        query: String,
        recentActivations: [FocusEvent]
    ) -> [ProjectConfig]
}
```

### Doctor

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
    public let metadata: DoctorMetadata
    public let actions: DoctorActionAvailability

    /// True if any finding has severity .fail
    public var hasFailures: Bool { get }

    /// Renders the report as a human-readable string.
    public func rendered() -> String
}

public struct DoctorFinding: Equatable, Sendable {
    public let severity: DoctorSeverity
    public let title: String
    public let bodyLines: [String]
    public let snippet: String?
}

public enum DoctorSeverity: String, CaseIterable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"
}

public struct DoctorMetadata: Equatable, Sendable {
    public let timestamp: String
    public let agentPanelVersion: String
    public let macOSVersion: String
    public let aerospaceApp: String
    public let aerospaceCli: String
}

public struct DoctorActionAvailability: Equatable, Sendable {
    public let canInstallAeroSpace: Bool
    public let canStartAeroSpace: Bool
    public let canReloadAeroSpaceConfig: Bool

    public static let none: DoctorActionAvailability
}
```

---

## CLI Surface (Proof-of-Concept — To Be Removed)

> **Note:** The following types exist solely because the CLI serves as a proof-of-concept tester. They are scheduled for removal or internalization in Phase 3. The App should not depend on these types.

### ApWindow

AeroSpace-specific window representation for CLI operations.

```swift
public struct ApWindow: Equatable, Sendable {
    public let windowId: Int
    public let appBundleId: String
    public let workspace: String
    public let windowTitle: String
}
```

### ApCore

```swift
public final class ApCore {
    public let config: Config

    public init(config: Config)

    // Workspace commands
    public func listWorkspaces() -> Result<[String], ApCoreError>
    public func newWorkspace(name: String) -> Result<Void, ApCoreError>
    public func closeWorkspace(name: String) -> Result<Void, ApCoreError>

    // IDE/Chrome
    public func newIde(identifier: String) -> Result<Void, ApCoreError>
    public func newChrome(identifier: String) -> Result<Void, ApCoreError>
    public func listIdeWindows() -> Result<[ApWindow], ApCoreError>
    public func listChromeWindows() -> Result<[ApWindow], ApCoreError>

    // Window management
    public func listWindowsWorkspace(_ workspace: String) -> Result<[ApWindow], ApCoreError>
    public func focusedWindow() -> Result<ApWindow, ApCoreError>
    public func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError>
    public func focusWindow(windowId: Int) -> Result<Void, ApCoreError>
}
```
