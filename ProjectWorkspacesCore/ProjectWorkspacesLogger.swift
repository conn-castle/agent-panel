import Foundation

/// Logging interface for ProjectWorkspaces components.
public protocol ProjectWorkspacesLogging {
    /// Writes a structured log entry with a fresh timestamp.
    /// - Parameters:
    ///   - event: Event name to categorize the entry.
    ///   - level: Severity level for the entry.
    ///   - message: Optional human-readable message.
    ///   - context: Optional structured context values.
    /// - Returns: Success or a log write error.
    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError>
}

/// Log severity levels for ProjectWorkspaces.
public enum LogLevel: String, Codable, Sendable {
    case info
    case warn
    case error
}

/// Structured log entry encoded as a single JSON line.
public struct LogEntry: Codable, Equatable, Sendable {
    public let timestamp: String
    public let level: LogLevel
    public let event: String
    public let message: String?
    public let context: [String: String]?

    /// Creates a log entry.
    /// - Parameters:
    ///   - timestamp: UTC timestamp in ISO-8601 format.
    ///   - level: Severity level for the entry.
    ///   - event: Event name to categorize the entry.
    ///   - message: Optional human-readable message.
    ///   - context: Optional structured context values.
    public init(
        timestamp: String,
        level: LogLevel,
        event: String,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        self.timestamp = timestamp
        self.level = level
        self.event = event
        self.message = message
        self.context = context
    }
}

/// Log write failures surfaced by the logger.
public enum LogWriteError: Error, Equatable, Sendable {
    case invalidEvent
    case encodingFailed(String)
    case createDirectoryFailed(String)
    case fileSizeFailed(String)
    case rotationFailed(String)
    case writeFailed(String)

    /// Human-readable summary for the log write failure.
    public var message: String {
        switch self {
        case .invalidEvent:
            return "Log event is empty."
        case .encodingFailed(let detail):
            return "Failed to encode log entry: \(detail)"
        case .createDirectoryFailed(let detail):
            return "Failed to create log directory: \(detail)"
        case .fileSizeFailed(let detail):
            return "Failed to read log file size: \(detail)"
        case .rotationFailed(let detail):
            return "Failed to rotate logs: \(detail)"
        case .writeFailed(let detail):
            return "Failed to write log entry: \(detail)"
        }
    }
}

/// JSON Lines logger for ProjectWorkspaces.
public struct ProjectWorkspacesLogger {
    private static let defaultMaxLogSizeBytes: UInt64 = 10 * 1024 * 1024
    private static let defaultMaxArchives: Int = 5

    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let maxLogSizeBytes: UInt64
    private let maxArchives: Int

    /// Creates a logger that writes to the default log path.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem()
    ) {
        self.init(
            paths: paths,
            fileSystem: fileSystem,
            maxLogSizeBytes: ProjectWorkspacesLogger.defaultMaxLogSizeBytes,
            maxArchives: ProjectWorkspacesLogger.defaultMaxArchives
        )
    }

    /// Creates a logger with explicit rotation settings.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - maxLogSizeBytes: Maximum size in bytes before rotation.
    ///   - maxArchives: Maximum number of rotated archives to keep.
    init(
        paths: ProjectWorkspacesPaths,
        fileSystem: FileSystem,
        maxLogSizeBytes: UInt64,
        maxArchives: Int
    ) {
        precondition(maxLogSizeBytes > 0, "maxLogSizeBytes must be positive")
        precondition(maxArchives > 0, "maxArchives must be positive")
        self.paths = paths
        self.fileSystem = fileSystem
        self.maxLogSizeBytes = maxLogSizeBytes
        self.maxArchives = maxArchives
    }

    /// Writes a structured log entry with a fresh timestamp.
    /// - Parameters:
    ///   - event: Event name to categorize the entry.
    ///   - level: Severity level for the entry.
    ///   - message: Optional human-readable message.
    ///   - context: Optional structured context values.
    /// - Returns: Success or a log write error.
    public func log(
        event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) -> Result<Void, LogWriteError> {
        let entry = LogEntry(
            timestamp: makeTimestamp(),
            level: level,
            event: event,
            message: message,
            context: context
        )
        return log(entry: entry)
    }

    /// Writes a structured log entry to the primary log file.
    /// - Parameter entry: Log entry to encode and append.
    /// - Returns: Success or a log write error.
    public func log(entry: LogEntry) -> Result<Void, LogWriteError> {
        let trimmedEvent = entry.event.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEvent.isEmpty else {
            return .failure(.invalidEvent)
        }

        let encodedLine: Data
        do {
            let data = try JSONEncoder().encode(entry)
            var line = data
            line.append(0x0A)
            encodedLine = line
        } catch {
            return .failure(.encodingFailed(String(describing: error)))
        }

        do {
            try fileSystem.createDirectory(at: paths.logsDirectory)
        } catch {
            return .failure(.createDirectoryFailed(String(describing: error)))
        }

        do {
            try rotateIfNeeded(appendingBytes: UInt64(encodedLine.count))
        } catch let error as LogWriteError {
            return .failure(error)
        } catch {
            return .failure(.rotationFailed(String(describing: error)))
        }

        do {
            try fileSystem.appendFile(at: paths.primaryLogFile, data: encodedLine)
        } catch {
            return .failure(.writeFailed(String(describing: error)))
        }

        return .success(())
    }

    /// Builds a UTC ISO-8601 timestamp string.
    /// - Returns: Timestamp string with fractional seconds.
    private func makeTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    /// Rotates log files when the active log would exceed the size threshold.
    /// - Parameter appendingBytes: Bytes that will be appended to the log.
    /// - Throws: Error when file inspection or rotation fails.
    private func rotateIfNeeded(appendingBytes: UInt64) throws {
        let logURL = paths.primaryLogFile
        guard fileSystem.fileExists(at: logURL) else {
            return
        }

        let size: UInt64
        do {
            size = try fileSystem.fileSize(at: logURL)
        } catch {
            throw LogWriteError.fileSizeFailed(String(describing: error))
        }

        guard size + appendingBytes > maxLogSizeBytes else {
            return
        }

        do {
            try rotateLogs()
        } catch {
            throw LogWriteError.rotationFailed(String(describing: error))
        }
    }

    /// Performs deterministic log rotation.
    /// - Throws: Error when rotation operations fail.
    private func rotateLogs() throws {
        let logURL = paths.primaryLogFile

        if maxArchives > 0 {
            for index in stride(from: maxArchives, through: 1, by: -1) {
                let currentArchiveURL = archiveURL(index: index)
                if fileSystem.fileExists(at: currentArchiveURL) {
                    if index == maxArchives {
                        try fileSystem.removeItem(at: currentArchiveURL)
                    } else {
                        let nextURL = archiveURL(index: index + 1)
                        if fileSystem.fileExists(at: nextURL) {
                            try fileSystem.removeItem(at: nextURL)
                        }
                        try fileSystem.moveItem(at: currentArchiveURL, to: nextURL)
                    }
                }
            }
        }

        if fileSystem.fileExists(at: logURL) {
            let firstArchive = archiveURL(index: 1)
            if fileSystem.fileExists(at: firstArchive) {
                try fileSystem.removeItem(at: firstArchive)
            }
            try fileSystem.moveItem(at: logURL, to: firstArchive)
        }
    }

    /// Returns the archive URL for the given index.
    /// - Parameter index: Archive index starting at 1.
    /// - Returns: Archive file URL.
    private func archiveURL(index: Int) -> URL {
        paths.logsDirectory.appendingPathComponent("workspaces.log.\(index)", isDirectory: false)
    }
}

extension ProjectWorkspacesLogger: ProjectWorkspacesLogging {}
