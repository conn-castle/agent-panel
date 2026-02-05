import Carbon
import CoreServices
import Foundation

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
public protocol FileSystem {
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
public struct DefaultFileSystem: FileSystem {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func isExecutableFile(at url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }

    public func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func fileSize(at url: URL) throws -> UInt64 {
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

    public func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    public func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    public func appendFile(at url: URL, data: Data) throws {
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    public func writeFile(at url: URL, data: Data) throws {
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - AeroSpace Health Checking

/// Result of an AeroSpace installation check.
public struct AeroSpaceInstallStatus: Equatable, Sendable {
    /// True if AeroSpace.app is installed.
    public let isInstalled: Bool
    /// Path to AeroSpace.app, if installed.
    public let appPath: String?

    public init(isInstalled: Bool, appPath: String?) {
        self.isInstalled = isInstalled
        self.appPath = appPath
    }
}

/// Result of an AeroSpace compatibility check.
public enum AeroSpaceCompatibility: Equatable, Sendable {
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
public protocol AeroSpaceHealthChecking {
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

// MARK: - App Discovery

/// Application discovery interface for Launch Services lookups.
public protocol AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL?
    func applicationURL(named appName: String) -> URL?
    func bundleIdentifier(forApplicationAt url: URL) -> String?
}

/// Launch Services-backed application discovery implementation.
public struct LaunchServicesAppDiscovery: AppDiscovering {
    public init() {}

    public func applicationURL(bundleIdentifier: String) -> URL? {
        guard let unmanaged = LSCopyApplicationURLsForBundleIdentifier(bundleIdentifier as CFString, nil) else {
            return nil
        }
        let urls = unmanaged.takeRetainedValue() as NSArray
        return urls.firstObject as? URL
    }

    public func applicationURL(named appName: String) -> URL? {
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

    public func bundleIdentifier(forApplicationAt url: URL) -> String? {
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
public struct HotkeyCheckResult: Equatable, Sendable {
    public let isAvailable: Bool
    public let errorCode: Int32?

    public init(isAvailable: Bool, errorCode: Int32?) {
        self.isAvailable = isAvailable
        self.errorCode = errorCode
    }
}

/// Hotkey availability checker used by Doctor.
public protocol HotkeyChecking {
    func checkCommandShiftSpace() -> HotkeyCheckResult
}

/// Carbon-based hotkey checker for Cmd+Shift+Space.
public struct CarbonHotkeyChecker: HotkeyChecking {
    public init() {}

    public func checkCommandShiftSpace() -> HotkeyCheckResult {
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
public protocol DateProviding {
    func now() -> Date
}

/// Default date provider backed by Date().
public struct SystemDateProvider: DateProviding {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

// MARK: - Environment Providing

/// Environment accessor used by Doctor.
public protocol EnvironmentProviding {
    func value(forKey key: String) -> String?
    func allValues() -> [String: String]
}

/// Default environment provider backed by the current process environment.
public struct ProcessEnvironment: EnvironmentProviding {
    public init() {}

    public func value(forKey key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    public func allValues() -> [String: String] {
        ProcessInfo.processInfo.environment
    }
}
