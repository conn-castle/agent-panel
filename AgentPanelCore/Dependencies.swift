import Carbon
import CoreServices
import Foundation

// MARK: - Focus Operations

/// Represents a captured window focus state for restoration.
///
/// Used to save the currently focused window before showing UI (like the switcher)
/// and restore it when the UI is dismissed without a selection.
public struct CapturedFocus: Sendable, Equatable {
    /// AeroSpace window ID.
    public let windowId: Int

    /// App bundle identifier of the focused window.
    public let appBundleId: String

    /// Creates a captured focus state.
    init(windowId: Int, appBundleId: String) {
        self.windowId = windowId
        self.appBundleId = appBundleId
    }
}

// MARK: - Running Application Checking

/// Running application lookup interface for Doctor policies.
public protocol RunningApplicationChecking {
    /// Returns true when an application with the given bundle identifier is running.
    func isApplicationRunning(bundleIdentifier: String) -> Bool
}

// MARK: - Hotkey Status

/// Current registration status for the global switcher hotkey.
public enum HotkeyRegistrationStatus: Equatable, Sendable {
    case registered
    case failed(osStatus: Int32)
}

/// Provides the last known hotkey registration status.
public protocol HotkeyStatusProviding {
    /// Returns the current hotkey registration status, or nil if unknown.
    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus?
}

// MARK: - File System

/// File system access protocol for testability.
///
/// This protocol includes only the methods actually used by Core components:
/// - Logger: createDirectory, appendFile, fileExists, fileSize, removeItem, moveItem
/// - ExecutableResolver: isExecutableFile
/// - StateStore: fileExists, readFile, createDirectory, writeFile
protocol FileSystem {
    func fileExists(at url: URL) -> Bool
    func isExecutableFile(at url: URL) -> Bool
    func readFile(at url: URL) throws -> Data
    func createDirectory(at url: URL) throws
    func fileSize(at url: URL) throws -> UInt64
    func removeItem(at url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func appendFile(at url: URL, data: Data) throws
    func writeFile(at url: URL, data: Data) throws
}

/// Default file system implementation backed by FileManager.
struct DefaultFileSystem: FileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }

    func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw NSError(
                domain: "DefaultFileSystem",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File size unavailable for \(url.path)"]
            )
        }
        return size.uint64Value
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func writeFile(at url: URL, data: Data) throws {
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - AeroSpace Health Checking

/// Result of an AeroSpace installation check.
struct AeroSpaceInstallStatus: Equatable, Sendable {
    /// True if AeroSpace.app is installed.
    let isInstalled: Bool
    /// Path to AeroSpace.app, if installed.
    let appPath: String?

    init(isInstalled: Bool, appPath: String?) {
        self.isInstalled = isInstalled
        self.appPath = appPath
    }
}

/// Result of an AeroSpace compatibility check.
enum AeroSpaceCompatibility: Equatable, Sendable {
    /// AeroSpace CLI is compatible.
    case compatible
    /// AeroSpace CLI is not available.
    case cliUnavailable
    /// AeroSpace CLI is missing required commands or flags.
    case incompatible(detail: String)
}

/// Intent-based protocol for AeroSpace health checks and actions.
///
/// Used by Doctor to check AeroSpace status and perform remediation actions.
/// This protocol hides AeroSpace implementation details from Doctor.
///
/// Method names use a `health` prefix to avoid collision with the existing
/// `Result`-returning methods on ApAeroSpace (e.g., `healthStart()` vs `start()`).
protocol AeroSpaceHealthChecking {
    // MARK: - Health Checks

    /// Returns the installation status of AeroSpace.
    func installStatus() -> AeroSpaceInstallStatus

    /// Returns true when the aerospace CLI is available.
    func isCliAvailable() -> Bool

    /// Checks whether the installed aerospace CLI is compatible.
    func healthCheckCompatibility() -> AeroSpaceCompatibility

    // MARK: - Actions

    /// Installs AeroSpace via Homebrew.
    /// - Returns: True if installation succeeded.
    func healthInstallViaHomebrew() -> Bool

    /// Starts AeroSpace.
    /// - Returns: True if start succeeded.
    func healthStart() -> Bool

    /// Reloads the AeroSpace configuration.
    /// - Returns: True if reload succeeded.
    func healthReloadConfig() -> Bool
}

// MARK: - Internal Protocols (for testability)

/// Internal protocol for AeroSpace operations.
protocol AeroSpaceProviding {
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError>
    func listWorkspacesFocused() -> Result<[String], ApCoreError>
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError>
    func closeWorkspace(name: String) -> Result<Void, ApCoreError>
    func listChromeWindowsOnFocusedMonitor() -> Result<[ApWindow], ApCoreError>
    func listVSCodeWindowsOnFocusedMonitor() -> Result<[ApWindow], ApCoreError>
    func moveWindowToWorkspace(workspace: String, windowId: Int) -> Result<Void, ApCoreError>
    func focusedWindow() -> Result<ApWindow, ApCoreError>
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError>
}

/// Internal protocol for IDE launching.
protocol IdeLauncherProviding {
    /// Opens a new VS Code window with a tagged title for precise identification.
    /// - Parameters:
    ///   - identifier: Project identifier embedded in the window title as `AP:<identifier>`.
    ///   - projectPath: Optional path to the project folder. If provided, opens VS Code at this path.
    func openNewWindow(identifier: String, projectPath: String?) -> Result<Void, ApCoreError>
}

/// Internal protocol for Chrome launching.
protocol ChromeLauncherProviding {
    func openNewWindow(identifier: String) -> Result<Void, ApCoreError>
}

extension ApAeroSpace: AeroSpaceProviding {}
extension ApVSCodeLauncher: IdeLauncherProviding {}
extension ApChromeLauncher: ChromeLauncherProviding {}

// MARK: - App Discovery

/// Application discovery interface for Launch Services lookups.
protocol AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL?
    func applicationURL(named appName: String) -> URL?
    func bundleIdentifier(forApplicationAt url: URL) -> String?
}

/// Launch Services-backed application discovery implementation.
struct LaunchServicesAppDiscovery: AppDiscovering {
    init() {}

    func applicationURL(bundleIdentifier: String) -> URL? {
        guard let unmanaged = LSCopyApplicationURLsForBundleIdentifier(bundleIdentifier as CFString, nil) else {
            return nil
        }
        let urls = unmanaged.takeRetainedValue() as NSArray
        return urls.firstObject as? URL
    }

    func applicationURL(named appName: String) -> URL? {
        let bundleName = appName.hasSuffix(".app") ? appName : "\(appName).app"
        let fileManager = FileManager.default
        let searchRoots = applicationSearchRoots(fileManager: fileManager)

        for directory in searchRoots {
            if let directMatch = directMatch(bundleName: bundleName, in: directory, fileManager: fileManager) {
                return directMatch
            }
            if let found = shallowSearch(bundleName: bundleName, in: directory, fileManager: fileManager, maxDepth: 2) {
                return found
            }
        }

        return nil
    }

    func bundleIdentifier(forApplicationAt url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    private func applicationSearchRoots(fileManager: FileManager) -> [URL] {
        var roots = fileManager.urls(for: .applicationDirectory, in: .allDomainsMask)
        let fallbackRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Network/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in fallbackRoots {
            if !roots.contains(where: { $0.standardizedFileURL.path == root.standardizedFileURL.path }) {
                roots.append(root)
            }
        }
        return roots
    }

    private func directMatch(bundleName: String, in directory: URL, fileManager: FileManager) -> URL? {
        let candidates = [
            directory.appendingPathComponent(bundleName, isDirectory: true),
            directory.appendingPathComponent("Utilities", isDirectory: true).appendingPathComponent(bundleName, isDirectory: true)
        ]
        for candidate in candidates {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }
        return nil
    }

    private func shallowSearch(
        bundleName: String,
        in root: URL,
        fileManager: FileManager,
        maxDepth: Int
    ) -> URL? {
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]

        while let next = queue.first {
            queue.removeFirst()
            if next.depth > maxDepth {
                continue
            }
            guard let entries = try? fileManager.contentsOfDirectory(
                at: next.url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for entry in entries {
                let values = try? entry.resourceValues(forKeys: resourceKeys)
                let isDirectory = values?.isDirectory ?? false
                let isPackage = values?.isPackage ?? false
                if isDirectory,
                   entry.lastPathComponent.compare(bundleName, options: [.caseInsensitive]) == .orderedSame {
                    return entry
                }
                if isDirectory, !isPackage, next.depth < maxDepth {
                    queue.append((entry, next.depth + 1))
                }
            }
        }

        return nil
    }
}

// MARK: - Hotkey Checking

/// Result of a hotkey registration check.
struct HotkeyCheckResult: Equatable, Sendable {
    let isAvailable: Bool
    let errorCode: Int32?

    init(isAvailable: Bool, errorCode: Int32?) {
        self.isAvailable = isAvailable
        self.errorCode = errorCode
    }
}

/// Hotkey availability checker used by Doctor.
protocol HotkeyChecking {
    func checkCommandShiftSpace() -> HotkeyCheckResult
}

/// Carbon-based hotkey checker for Cmd+Shift+Space.
struct CarbonHotkeyChecker: HotkeyChecking {
    init() {}

    func checkCommandShiftSpace() -> HotkeyCheckResult {
        let signature = OSType(0x41504354) // "APCT"
        let hotKeyId = EventHotKeyID(signature: signature, id: 1)
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_Space)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyId,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            if let hotKeyRef = hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
            return HotkeyCheckResult(isAvailable: true, errorCode: nil)
        }

        return HotkeyCheckResult(isAvailable: false, errorCode: status)
    }
}

// MARK: - Date Providing

/// Date provider used by Doctor for timestamps.
protocol DateProviding {
    func now() -> Date
}

/// Default date provider backed by Date().
struct SystemDateProvider: DateProviding {
    init() {}

    func now() -> Date {
        Date()
    }
}

// MARK: - Environment Providing

/// Environment accessor used by Doctor.
protocol EnvironmentProviding {
    func value(forKey key: String) -> String?
    func allValues() -> [String: String]
}

/// Default environment provider backed by the current process environment.
struct ProcessEnvironment: EnvironmentProviding {
    init() {}

    func value(forKey key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    func allValues() -> [String: String] {
        ProcessInfo.processInfo.environment
    }
}
