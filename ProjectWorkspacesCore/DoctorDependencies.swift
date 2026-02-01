import Carbon
import CoreServices
import Foundation

/// File system access needed by Doctor checks.
public protocol FileSystem {
    /// Returns true when a file exists at the given URL.
    /// - Parameter url: File URL to check.
    func fileExists(at url: URL) -> Bool

    /// Returns true when a directory exists at the given URL.
    /// - Parameter url: Directory URL to check.
    func directoryExists(at url: URL) -> Bool

    /// Returns true when an executable file exists at the given URL.
    /// - Parameter url: File URL to check.
    func isExecutableFile(at url: URL) -> Bool

    /// Reads file contents at the given URL.
    /// - Parameter url: File URL to read.
    /// - Returns: File contents as Data.
    func readFile(at url: URL) throws -> Data

    /// Creates a directory at the given URL, including intermediate directories.
    /// - Parameter url: Directory URL to create.
    func createDirectory(at url: URL) throws

    /// Returns the file size in bytes at the given URL.
    /// - Parameter url: File URL to inspect.
    /// - Returns: File size in bytes.
    func fileSize(at url: URL) throws -> UInt64

    /// Removes the file or directory at the given URL.
    /// - Parameter url: File or directory URL to remove.
    func removeItem(at url: URL) throws

    /// Moves a file from source to destination.
    /// - Parameters:
    ///   - sourceURL: Existing file URL.
    ///   - destinationURL: Destination URL.
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws

    /// Appends data to a file at the given URL, creating it if needed.
    /// - Parameters:
    ///   - url: File URL to append to.
    ///   - data: Data to append.
    func appendFile(at url: URL, data: Data) throws

    /// Writes data to a file at the given URL, replacing any existing contents.
    /// - Parameters:
    ///   - url: File URL to write.
    ///   - data: Data to write.
    func writeFile(at url: URL, data: Data) throws

    /// Flushes file contents to disk.
    /// - Parameter url: File URL to synchronize.
    func syncFile(at url: URL) throws

    /// Replaces the item at the destination with the item at the source atomically.
    /// Uses Foundation's `replaceItemAt` which handles the case where destination already exists.
    /// - Parameters:
    ///   - originalURL: Destination URL to replace.
    ///   - newItemURL: Source URL containing the new content.
    /// - Returns: The resulting URL (may differ from originalURL on some file systems).
    @discardableResult
    func replaceItemAt(_ originalURL: URL, withItemAt newItemURL: URL) throws -> URL?
}

/// Default file system implementation backed by `FileManager`.
public struct DefaultFileSystem: FileSystem {
    private let fileManager: FileManager

    /// Creates a default file system wrapper.
    /// - Parameter fileManager: File manager used for file access.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Returns true when a file exists at the given URL.
    /// - Parameter url: File URL to check.
    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    /// Returns true when a directory exists at the given URL.
    /// - Parameter url: Directory URL to check.
    public func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Returns true when an executable file exists at the given URL.
    /// - Parameter url: File URL to check.
    public func isExecutableFile(at url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }

    /// Reads file contents at the given URL.
    /// - Parameter url: File URL to read.
    /// - Returns: File contents as Data.
    public func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    /// Creates a directory at the given URL, including intermediate directories.
    /// - Parameter url: Directory URL to create.
    public func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    /// Returns the file size in bytes at the given URL.
    /// - Parameter url: File URL to inspect.
    /// - Returns: File size in bytes.
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

    /// Removes the file or directory at the given URL.
    /// - Parameter url: File or directory URL to remove.
    public func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    /// Moves a file from source to destination.
    /// - Parameters:
    ///   - sourceURL: Existing file URL.
    ///   - destinationURL: Destination URL.
    public func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    /// Appends data to a file at the given URL, creating it if needed.
    /// - Parameters:
    ///   - url: File URL to append to.
    ///   - data: Data to append.
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

    /// Writes data to a file at the given URL, replacing any existing contents.
    /// - Parameters:
    ///   - url: File URL to write.
    ///   - data: Data to write.
    public func writeFile(at url: URL, data: Data) throws {
        try data.write(to: url, options: .atomic)
    }

    /// Flushes file contents to disk.
    /// - Parameter url: File URL to synchronize.
    public func syncFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    /// Replaces the item at the destination with the item at the source atomically.
    /// - Parameters:
    ///   - originalURL: Destination URL to replace.
    ///   - newItemURL: Source URL containing the new content.
    /// - Returns: The resulting URL (may differ from originalURL on some file systems).
    @discardableResult
    public func replaceItemAt(_ originalURL: URL, withItemAt newItemURL: URL) throws -> URL? {
        try fileManager.replaceItemAt(originalURL, withItemAt: newItemURL)
    }
}

/// Environment accessor used by Doctor.
public protocol EnvironmentProviding {
    /// Returns the environment value for the given key.
    /// - Parameter key: Environment variable name.
    func value(forKey key: String) -> String?

    /// Returns a snapshot of the full environment.
    /// - Returns: Environment variables keyed by name.
    func allValues() -> [String: String]
}

/// Default environment provider backed by the current process environment.
public struct ProcessEnvironment: EnvironmentProviding {
    /// Creates a process environment provider.
    public init() {}

    /// Returns the environment value for the given key.
    /// - Parameter key: Environment variable name.
    /// - Returns: Environment variable value if present.
    public func value(forKey key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    /// Returns a snapshot of the current process environment.
    /// - Returns: Environment variables keyed by name.
    public func allValues() -> [String: String] {
        ProcessInfo.processInfo.environment
    }
}

/// Date provider used by Doctor for timestamps.
public protocol DateProviding {
    /// Returns the current date.
    func now() -> Date
}

/// Default date provider backed by `Date()`.
public struct SystemDateProvider: DateProviding {
    /// Creates a system date provider.
    public init() {}

    /// Returns the current system date.
    public func now() -> Date {
        Date()
    }
}

/// Result of a command execution.
public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    /// Creates a command result payload.
    /// - Parameters:
    ///   - exitCode: Process termination status.
    ///   - stdout: Captured standard output.
    ///   - stderr: Captured standard error.
    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    /// Formats command failure details from stdout/stderr and exit status.
    /// - Parameter prefix: Prefix string to lead the detail text.
    /// - Returns: Formatted failure detail string.
    public func failureDetail(prefix: String) -> String {
        var components: [String] = ["\(prefix). Exit code: \(exitCode)"]
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStdout.isEmpty {
            components.append("Stdout: \(trimmedStdout)")
        }
        if !trimmedStderr.isEmpty {
            components.append("Stderr: \(trimmedStderr)")
        }
        return components.joined(separator: " | ")
    }
}

/// Command runner used by Doctor to invoke external CLIs.
public protocol CommandRunning {
    /// Executes a command and captures stdout/stderr.
    /// - Parameters:
    ///   - command: Executable file URL.
    ///   - arguments: Arguments passed to the command.
    ///   - environment: Environment variables to override; when nil, inherits current environment.
    ///   - workingDirectory: Optional working directory for the process.
    /// - Returns: Command execution result.
    /// - Throws: Error when the process fails to launch.
    func run(
        command: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> CommandResult
}

/// Default command runner backed by `Process`.
public struct DefaultCommandRunner: CommandRunning {
    /// Creates a default command runner.
    public init() {}

    /// Executes a command and captures stdout/stderr.
    /// - Parameters:
    ///   - command: Executable file URL.
    ///   - arguments: Arguments passed to the command.
    ///   - environment: Environment variables to override; when nil, inherits current environment.
    /// - Returns: Command execution result.
    /// - Throws: Error when the process fails to launch.
    public func run(
        command: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = command
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        if let environment {
            process.environment = environment
        } else {
            process.environment = ProcessInfo.processInfo.environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

/// Application discovery interface for Launch Services lookups.
public protocol AppDiscovering {
    /// Resolves an application URL for a bundle identifier.
    /// - Parameter bundleIdentifier: Bundle identifier to resolve.
    /// - Returns: Application URL if found.
    func applicationURL(bundleIdentifier: String) -> URL?

    /// Resolves an application URL for a human-readable app name.
    /// - Parameter appName: Application display name.
    /// - Returns: Application URL if found.
    func applicationURL(named appName: String) -> URL?

    /// Retrieves the bundle identifier for an application URL.
    /// - Parameter url: Application URL.
    /// - Returns: Bundle identifier if available.
    func bundleIdentifier(forApplicationAt url: URL) -> String?
}

/// Launch Services-backed application discovery implementation.
public struct LaunchServicesAppDiscovery: AppDiscovering {
    /// Creates a Launch Services app discovery instance.
    public init() {}

    /// Resolves an application URL for a bundle identifier.
    /// - Parameter bundleIdentifier: Bundle identifier to resolve.
    /// - Returns: Application URL if found.
    public func applicationURL(bundleIdentifier: String) -> URL? {
        guard let unmanaged = LSCopyApplicationURLsForBundleIdentifier(bundleIdentifier as CFString, nil) else {
            return nil
        }
        let urls = unmanaged.takeRetainedValue() as NSArray
        return urls.firstObject as? URL
    }

    /// Resolves an application URL for a human-readable app name.
    ///
    /// Searches common application directories for an app bundle matching the name.
    /// This replaces the deprecated `NSWorkspace.fullPath(forApplication:)` API without
    /// relying on the `mdfind` CLI or deep filesystem scans.
    ///
    /// - Parameter appName: Application display name (without `.app` extension).
    /// - Returns: Application URL if found.
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

    /// Retrieves the bundle identifier for an application URL.
    /// - Parameter url: Application URL.
    /// - Returns: Bundle identifier if available.
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
            if isDirectory(candidate, fileManager: fileManager) {
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

    private func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// Result of a hotkey registration check.
public struct HotkeyCheckResult: Equatable, Sendable {
    public let isAvailable: Bool
    public let errorCode: Int32?

    /// Creates a hotkey check result.
    /// - Parameters:
    ///   - isAvailable: True when the hotkey can be registered.
    ///   - errorCode: Optional OSStatus error code when unavailable.
    public init(isAvailable: Bool, errorCode: Int32?) {
        self.isAvailable = isAvailable
        self.errorCode = errorCode
    }
}

/// Hotkey availability checker used by Doctor.
public protocol HotkeyChecking {
    /// Checks whether Cmd+Shift+Space can be registered.
    /// - Returns: Result of the hotkey availability check.
    func checkCommandShiftSpace() -> HotkeyCheckResult
}

/// Carbon-based hotkey checker for Cmd+Shift+Space.
public struct CarbonHotkeyChecker: HotkeyChecking {
    /// Creates a hotkey checker.
    public init() {}

    /// Checks whether Cmd+Shift+Space can be registered.
    /// - Returns: Result of the hotkey availability check.
    public func checkCommandShiftSpace() -> HotkeyCheckResult {
        let signature = OSType(0x50574354) // "PWCT"
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

/// Accessibility permission checker used by Doctor.
public protocol AccessibilityChecking {
    /// Returns true when the current process is trusted for accessibility.
    func isProcessTrusted() -> Bool
}

/// Running application lookup interface for Doctor policies.
public protocol RunningApplicationChecking {
    /// Returns true when an application with the given bundle identifier is running.
    /// - Parameter bundleIdentifier: Bundle identifier to check.
    func isApplicationRunning(bundleIdentifier: String) -> Bool
}
