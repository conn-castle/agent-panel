import AppKit
import ApplicationServices
import Carbon
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
}

/// Environment accessor used by Doctor.
public protocol EnvironmentProviding {
    /// Returns the environment value for the given key.
    /// - Parameter key: Environment variable name.
    func value(forKey key: String) -> String?
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
}

/// Command runner used by Doctor to invoke external CLIs.
public protocol CommandRunning {
    /// Executes a command and captures stdout/stderr.
    /// - Parameters:
    ///   - command: Executable file URL.
    ///   - arguments: Arguments passed to the command.
    ///   - environment: Environment variables to override; when nil, inherits current environment.
    /// - Returns: Command execution result.
    /// - Throws: Error when the process fails to launch.
    func run(command: URL, arguments: [String], environment: [String: String]?) throws -> CommandResult
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
    public func run(command: URL, arguments: [String], environment: [String: String]?) throws -> CommandResult {
        let process = Process()
        process.executableURL = command
        process.arguments = arguments
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
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    /// Resolves an application URL for a human-readable app name.
    /// - Parameter appName: Application display name.
    /// - Returns: Application URL if found.
    public func applicationURL(named appName: String) -> URL? {
        guard let path = NSWorkspace.shared.fullPath(forApplication: appName) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Retrieves the bundle identifier for an application URL.
    /// - Parameter url: Application URL.
    /// - Returns: Bundle identifier if available.
    public func bundleIdentifier(forApplicationAt url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
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

/// Default Accessibility checker using `AXIsProcessTrustedWithOptions`.
public struct DefaultAccessibilityChecker: AccessibilityChecking {
    /// Creates an Accessibility checker.
    public init() {}

    /// Returns true when the current process is trusted for accessibility.
    public func isProcessTrusted() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// Running application lookup interface for Doctor policies.
public protocol RunningApplicationChecking {
    /// Returns true when an application with the given bundle identifier is running.
    /// - Parameter bundleIdentifier: Bundle identifier to check.
    func isApplicationRunning(bundleIdentifier: String) -> Bool
}

/// Default running application checker backed by AppKit.
public struct DefaultRunningApplicationChecker: RunningApplicationChecking {
    /// Creates a running application checker.
    public init() {}

    /// Returns true when an application with the given bundle identifier is running.
    /// - Parameter bundleIdentifier: Bundle identifier to check.
    public func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
