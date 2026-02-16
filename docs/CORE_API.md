# AgentPanelCore Public API

The public API of `AgentPanelCore` has these main concerns:

1. **ProjectManager** — Project listing, sorting, selection, and focus management
2. **Doctor** — Diagnostics and remediation
3. **Config** — Configuration loading and project definitions
4. **Window Layout** — Layout engine, position store, and positioning protocols
5. **Window Recovery** — Recover misplaced windows to correct positions
6. **VS Code Color** — Project color differentiation via Peacock extension
7. **Error Context** — Structured error context for auto-doctor
8. **Logging** — Structured JSON logging
9. **Window Cycling** — Workspace-scoped window focus cycling
10. **Onboarding Support** — AeroSpace installation and configuration

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
public enum ApCoreErrorCategory: String, Sendable {
    case command
    case validation
    case fileSystem
    case configuration
    case parse
    case window
    case system
}

public struct ApCoreError: Error, Equatable, Sendable {
    public let message: String

    /// Full init with structured error fields.
    public init(
        category: ApCoreErrorCategory,
        message: String,
        detail: String? = nil,
        command: String? = nil,
        exitCode: Int32? = nil
    )

    /// Convenience init (defaults to .command category).
    init(message: String)
}
```

---

## Configuration

```swift
public struct Config: Equatable, Sendable {
    public let projects: [ProjectConfig]
    public let chrome: ChromeConfig
    public let agentLayer: AgentLayerConfig
    public let layout: LayoutConfig
    public let app: AppConfig

    /// Loads and validates configuration from the default path.
    public static func loadDefault() -> Result<ConfigLoadSuccess, ConfigLoadError>
}

public struct AppConfig: Equatable, Sendable {
    public let autoStartAtLogin: Bool
    public init(autoStartAtLogin: Bool = false)
}

public struct AgentLayerConfig: Equatable, Sendable {
    /// Global default for `useAgentLayer` across all projects. Default: false.
    public let enabled: Bool
}

public struct ChromeConfig: Equatable, Sendable {
    public let pinnedTabs: [String]
    public let defaultTabs: [String]
    public let openGitRemote: Bool
}

public struct ProjectConfig: Equatable, Sendable {
    public let id: String
    public let name: String
    public let remote: String?  // Optional VS Code SSH remote authority (e.g., "ssh-remote+user@host")
    public let path: String
    public let color: String  // Named color or hex (#RRGGBB)
    public let useAgentLayer: Bool  // Resolved: global default + per-project override
    public let chromePinnedTabs: [String]
    public let chromeDefaultTabs: [String]

    /// True when `remote` is set (SSH remote project).
    public var isSSH: Bool
}

public struct ConfigLoadSuccess: Equatable, Sendable {
    public let config: Config
    public let warnings: [ConfigFinding]  // Non-fatal warnings (severity == .warn)
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

1. Check for existing tagged Chrome window
2. If no existing window: resolve initial Chrome tab URLs (from snapshot or cold-start defaults), launch Chrome with URLs (with fallback to empty tabs on failure)
3. Find or launch tagged VS Code window
4. Move Chrome to workspace (no focus follow)
5. Move VS Code to workspace (with focus follow)
6. Verify both windows arrived in workspace
7. Focus workspace (`summon-workspace` with fallback)
8. Focus IDE window
9. Verify focus stability (poll)

```swift
public final class ProjectManager {
    /// Prefix for all AgentPanel workspaces.
    public static let workspacePrefix: String  // "ap-"

    /// All projects from config, or empty if config not loaded.
    public var projects: [ProjectConfig] { get }

    /// Returns open + focused AgentPanel workspace state from one AeroSpace query.
    public func workspaceState() -> Result<ProjectWorkspaceState, ProjectError>

    /// Creates a ProjectManager with default dependencies.
    /// Pass window positioning and screen mode detection implementations from AppKit.
    /// Pass processChecker for AeroSpace auto-recovery (nil disables).
    public init(
        windowPositioner: WindowPositioning? = nil,
        screenModeDetector: ScreenModeDetecting? = nil,
        processChecker: RunningApplicationChecking? = nil
    )

    /// Loads configuration from the default path.
    @discardableResult
    public func loadConfig() -> Result<ConfigLoadSuccess, ConfigLoadError>

    /// Non-fatal warnings from the most recent config load.
    public private(set) var configWarnings: [ConfigFinding]

    /// Returns the current layout config from the last config load, or defaults if not loaded.
    /// Non-mutating — safe for recovery paths that should not trigger config reload.
    public var currentLayoutConfig: LayoutConfig

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
    /// - Returns: Activation success (IDE window ID + optional tab restore warning) or error.
    public func selectProject(projectId: String, preCapturedFocus: CapturedFocus) async -> Result<ProjectActivationSuccess, ProjectError>

    /// Closes a project by ID and restores focus to the previous non-project window.
    public func closeProject(projectId: String) -> Result<ProjectCloseSuccess, ProjectError>

    /// Moves a window to the given project's workspace.
    public func moveWindowToProject(
        windowId: Int,
        projectId: String
    ) -> Result<Void, ProjectError>

    /// Exits to the last non-project window without closing the project.
    public func exitToNonProjectWindow() -> Result<Void, ProjectError>
}

public struct ProjectWorkspaceState: Equatable, Sendable {
    public let activeProjectId: String?
    public let openProjectIds: Set<String>

    public init(activeProjectId: String?, openProjectIds: Set<String>)
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

public struct ProjectActivationSuccess: Equatable, Sendable {
    public let ideWindowId: Int
    public let tabRestoreWarning: String?
    public let layoutWarning: String?
    public init(ideWindowId: Int, tabRestoreWarning: String?, layoutWarning: String? = nil)
}

public struct ProjectCloseSuccess: Equatable, Sendable {
    public let tabCaptureWarning: String?
    public init(tabCaptureWarning: String?)
}
```

### Chrome Tab Types

```swift
public struct ChromeTabSnapshot: Codable, Equatable, Sendable {
    public let urls: [String]
    public let capturedAt: Date
    public init(urls: [String], capturedAt: Date)
}

public struct ResolvedTabs: Equatable, Sendable {
    public let alwaysOpenURLs: [String]
    public let regularURLs: [String]
    public var orderedURLs: [String] { get }  // alwaysOpenURLs + regularURLs
}
```

### Focus Types

```swift
public struct CapturedFocus: Sendable, Equatable {
    public let windowId: Int
    public let appBundleId: String
    public let workspace: String
}
```

### Switcher Dismiss Policy

Pure policy helpers for switcher panel dismiss/restore decisions. Extracted to Core
for testability; no AppKit dependency.

```swift
public enum SwitcherDismissReason: String, CaseIterable, Sendable {
    case toggle
    case escape
    case projectSelected
    case projectClosed
    case exitedToNonProject
    case windowClose
    case unknown
}

public enum DismissDecision: Equatable, Sendable {
    case dismiss
    case suppress(reason: String)
}

public struct SwitcherDismissPolicy: Sendable {
    /// Decides whether to dismiss the panel when it resigns key window status.
    /// Suppresses dismissal during activation (Chrome window steal) or when
    /// the panel is not visible.
    public static func shouldDismissOnResignKey(
        isActivating: Bool,
        isVisible: Bool
    ) -> DismissDecision

    /// Decides whether to restore focus to the previously captured window
    /// when the panel dismisses with the given reason.
    public static func shouldRestoreFocus(reason: SwitcherDismissReason) -> Bool
}
```

---

## Doctor

```swift
public struct Doctor {
    /// Creates a Doctor with production dependencies.
    /// Pass `windowPositioner` from AppKit for Accessibility checks.
    public init(
        runningApplicationChecker: RunningApplicationChecking,
        hotkeyStatusProvider: HotkeyStatusProviding? = nil,
        windowPositioner: WindowPositioning? = nil
    )

    /// Runs all diagnostic checks.
    /// Optionally pass an `ErrorContext` to include auto-doctor trigger info in the report.
    public func run(context: ErrorContext? = nil) -> DoctorReport

    /// Installs AeroSpace via Homebrew.
    public func installAeroSpace() -> DoctorReport

    /// Starts AeroSpace.
    public func startAeroSpace() -> DoctorReport

    /// Reloads AeroSpace configuration.
    public func reloadAeroSpaceConfig() -> DoctorReport

    /// Prompts the user to grant Accessibility permission.
    public func requestAccessibility() -> DoctorReport
}

public struct DoctorReport: Equatable, Sendable {
    public let findings: [DoctorFinding]
    public let actions: DoctorActionAvailability

    public var overallSeverity: DoctorSeverity { get }
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
    public let canRequestAccessibility: Bool
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

## Window Layout

Window positioning protocols are defined in Core using Foundation/CG types.
Concrete implementations (`AXWindowPositioner`, `ScreenModeDetector`) live in the
`AgentPanelAppKit` module since Core cannot import AppKit.

### Protocols

```swift
public protocol WindowPositioning {
    func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, ApCoreError>
    func setWindowFrames(
        bundleId: String,
        projectId: String,
        primaryFrame: CGRect,
        cascadeOffsetPoints: CGFloat
    ) -> Result<WindowPositionResult, ApCoreError>
    func recoverWindow(
        bundleId: String,
        windowTitle: String,
        screenVisibleFrame: CGRect
    ) -> Result<RecoveryOutcome, ApCoreError>
    func isAccessibilityTrusted() -> Bool
    func promptForAccessibility() -> Bool
}

public protocol ScreenModeDetecting {
    func detectMode(containingPoint: CGPoint, threshold: Double) -> Result<ScreenMode, ApCoreError>
    func physicalWidthInches(containingPoint: CGPoint) -> Result<Double, ApCoreError>
    func screenVisibleFrame(containingPoint: CGPoint) -> CGRect?
}
```

### Screen Mode

```swift
public enum ScreenMode: String, Codable, Equatable, Sendable, CaseIterable {
    case small
    case wide
}
```

### Layout Config

```swift
public struct LayoutConfig: Equatable, Sendable {
    public let smallScreenThreshold: Double
    public let windowHeight: Int
    public let maxWindowWidth: Double
    public let idePosition: IdePosition
    public let justification: Justification
    public let maxGap: Int

    public enum IdePosition: String, Equatable, Sendable, CaseIterable {
        case left
        case right
    }

    public enum Justification: String, Equatable, Sendable, CaseIterable {
        case left
        case right
    }

    public init(
        smallScreenThreshold: Double = Defaults.smallScreenThreshold,
        windowHeight: Int = Defaults.windowHeight,
        maxWindowWidth: Double = Defaults.maxWindowWidth,
        idePosition: IdePosition = Defaults.idePosition,
        justification: Justification = Defaults.justification,
        maxGap: Int = Defaults.maxGap
    )

    public enum Defaults {
        public static let smallScreenThreshold: Double = 24
        public static let windowHeight: Int = 90
        public static let maxWindowWidth: Double = 18
        public static let idePosition: IdePosition = .left
        public static let justification: Justification = .right
        public static let maxGap: Int = 10
    }
}
```

### Layout Engine

Pure geometry computation. No side effects.

```swift
public struct WindowLayout: Equatable, Sendable {
    public let ideFrame: CGRect
    public let chromeFrame: CGRect
    public init(ideFrame: CGRect, chromeFrame: CGRect)
}

public struct WindowLayoutEngine {
    /// Computes IDE + Chrome window frames for the given screen and config.
    /// Small mode: both windows maximized to `screenVisibleFrame`.
    /// Wide mode: side-by-side with configurable height, width cap, justification, and gap.
    public static func computeLayout(
        screenVisibleFrame: CGRect,
        screenPhysicalWidthInches: Double,
        screenMode: ScreenMode,
        config: LayoutConfig
    ) -> WindowLayout

    /// Clamps a frame to fit within the screen visible area (off-screen rescue).
    public static func clampToScreen(
        frame: CGRect,
        screenVisibleFrame: CGRect
    ) -> CGRect
}
```

### Position Store Types

```swift
public struct SavedFrame: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double)
    public init(rect: CGRect)
    public var cgRect: CGRect { get }
}

public struct SavedWindowFrames: Codable, Equatable, Sendable {
    public let ide: SavedFrame
    public let chrome: SavedFrame
    public init(ide: SavedFrame, chrome: SavedFrame)
}
```

### Window Position Result

```swift
public struct WindowPositionResult: Equatable, Sendable {
    public let positioned: Int
    public let matched: Int
    public init(positioned: Int, matched: Int)
    public var hasPartialFailure: Bool { get }
}

public enum RecoveryOutcome: Equatable, Sendable {
    case recovered
    case unchanged
    case notFound
}
```

---

## Window Recovery

Recovers misplaced or oversized windows. Separate from `ProjectManager` — operates
on arbitrary windows, not project lifecycle.

```swift
public struct RecoveryResult: Equatable, Sendable {
    public let windowsProcessed: Int
    public let windowsRecovered: Int
    public let errors: [String]
    public init(windowsProcessed: Int, windowsRecovered: Int, errors: [String])
}

public final class WindowRecoveryManager {
    /// Creates a recovery manager with production AeroSpace dependencies.
    public init(
        windowPositioner: WindowPositioning,
        screenVisibleFrame: CGRect,
        logger: AgentPanelLogging,
        processChecker: RunningApplicationChecking? = nil,
        screenModeDetector: ScreenModeDetecting? = nil,
        layoutConfig: LayoutConfig = LayoutConfig()
    )

    /// Recovers windows in a workspace. For project workspaces (`ap-<projectId>`),
    /// applies workspace-scoped layout positioning for IDE/Chrome first (only targeting
    /// apps present in the workspace), then generic shrink/center recovery for remaining windows.
    public func recoverWorkspaceWindows(workspace: String) -> Result<RecoveryResult, ApCoreError>

    /// Recovers all windows across all workspaces, reporting progress.
    public func recoverAllWindows(
        progress: @escaping (_ current: Int, _ total: Int) -> Void
    ) -> Result<RecoveryResult, ApCoreError>
}
```

---

## VS Code Color

Resolves project colors to hex values for the Peacock VS Code extension.

```swift
public enum VSCodeColorPalette {
    /// Returns a `#RRGGBB` hex string for the Peacock extension, or nil if the color is unrecognized.
    public static func peacockColorHex(for color: String) -> String?

    /// Converts a ProjectColorRGB to `#RRGGBB` hex string.
    public static func toHex(_ rgb: ProjectColorRGB) -> String
}
```

---

## Error Context

Structured error context used by auto-doctor to trigger background diagnostics.

```swift
public struct ErrorContext: Equatable, Sendable {
    public let category: ApCoreErrorCategory
    public let message: String
    public let trigger: String

    public init(category: ApCoreErrorCategory, message: String, trigger: String)

    /// True for errors that should auto-show Doctor results (e.g., AeroSpace failures).
    public var isCritical: Bool { get }
}
```

---

## Logging

```swift
public protocol AgentPanelLogging {
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

public struct AgentPanelLogger {
    public init()
    public init(dataStore: DataPaths)
}

extension AgentPanelLogger: AgentPanelLogging {
    public func log(
        event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) -> Result<Void, LogWriteError>
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

## Window Cycling

Cycles focus between windows in the focused AeroSpace workspace. The App layer registers global hotkeys (Option-Tab / Option-Shift-Tab) via Carbon API and dispatches to `WindowCycler`.

```swift
public enum CycleDirection: Sendable {
    case next
    case previous
}

public struct WindowCycler {
    public init(processChecker: RunningApplicationChecking? = nil)
    public func cycleFocus(direction: CycleDirection) -> Result<Void, ApCoreError>
}
```

`cycleFocus` calls `focusedWindow()` → `listWindowsWorkspace(workspace:)` → `focusWindow(windowId:)`, wrapping at list boundaries. Returns `.success(())` when there are 0–1 windows or the focused window is not in the list.

---

## Onboarding Support

For first-launch setup, the App uses these types directly.

### AeroSpace

```swift
public struct ApAeroSpace {
    /// AeroSpace app bundle identifier.
    public static let bundleIdentifier: String  // "bobko.aerospace"

    /// Creates a new AeroSpace wrapper.
    /// - Parameter processChecker: Optional process checker for auto-recovery.
    ///   When provided and AeroSpace crashes (circuit breaker open, process dead),
    ///   automatically restarts AeroSpace (max 2 attempts). Pass nil (default) to disable.
    public init(processChecker: RunningApplicationChecking? = nil)

    /// Returns true when AeroSpace.app is installed.
    public func isAppInstalled() -> Bool

    /// Returns true when the aerospace CLI is available.
    public func isCliAvailable() -> Bool

    /// Installs AeroSpace via Homebrew.
    public func installViaHomebrew() -> Result<Void, ApCoreError>

    /// Starts AeroSpace.
    /// Must be called off the main thread.
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

// Workspace summary query (single call for all + focused metadata).
// Matches: aerospace list-workspaces --all --format "%{workspace}||%{workspace-is-focused}"
func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError>

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

public enum ConfigUpdateResult: Equatable, Sendable {
    case freshInstall
    case updated(fromVersion: Int, toVersion: Int)
    case alreadyCurrent
    case skippedExternal
}

public struct AeroSpaceConfigManager {
    public static var configPath: String { get }

    public init()

    public func writeSafeConfig() -> Result<Void, ApCoreError>
    public func configContents() -> String?
    public func configStatus() -> AeroSpaceConfigStatus
    public func templateVersion() -> Int?
    public func currentConfigVersion() -> Int?
    public func updateManagedConfig() -> Result<Void, ApCoreError>
    public func ensureUpToDate() -> Result<ConfigUpdateResult, ApCoreError>
}
```
