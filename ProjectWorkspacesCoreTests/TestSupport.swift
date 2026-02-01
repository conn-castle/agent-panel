import Foundation
import XCTest

@testable import ProjectWorkspacesCore

// MARK: - AeroSpace Command Test Infrastructure

/// Signature for matching stubbed AeroSpace command responses.
struct AeroSpaceCommandSignature: Hashable {
    let path: String
    let arguments: [String]
}

/// Recorded AeroSpace command call with timing information.
struct AeroSpaceCommandCall: Equatable {
    let path: String
    let arguments: [String]
    let timeoutSeconds: TimeInterval
}

/// Type alias for mapping command signatures to sequenced responses.
typealias AeroSpaceCommandResponses = [AeroSpaceCommandSignature: [Result<CommandResult, AeroSpaceCommandError>]]

/// Test command runner that returns pre-configured responses in sequence.
final class SequencedAeroSpaceCommandRunner: AeroSpaceCommandRunning {
    private var responses: AeroSpaceCommandResponses
    private(set) var invocations: [AeroSpaceCommandSignature] = []
    private(set) var calls: [AeroSpaceCommandCall] = []

    init(responses: AeroSpaceCommandResponses) {
        self.responses = responses
    }

    func run(
        executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        let signature = AeroSpaceCommandSignature(path: executable.path, arguments: arguments)
        invocations.append(signature)
        calls.append(
            AeroSpaceCommandCall(
                path: executable.path,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds
            )
        )

        guard var queue = responses[signature], !queue.isEmpty else {
            preconditionFailure("Missing stubbed response for \(signature.path) \(signature.arguments).")
        }
        let result = queue.removeFirst()
        responses[signature] = queue
        return result
    }
}

// MARK: - Window Payload Helpers

/// Encodable window payload for stubbing AeroSpace list-windows output.
struct WindowPayload: Encodable {
    let windowId: Int
    let workspace: String
    let appBundleId: String
    let appName: String
    let windowTitle: String
    let windowLayout: String
    let monitorAppkitNSScreenScreensId: Int?

    enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case workspace
        case appBundleId = "app-bundle-id"
        case appName = "app-name"
        case windowTitle = "window-title"
        case windowLayout = "window-layout"
        case monitorAppkitNSScreenScreensId = "monitor-appkit-nsscreen-screens-id"
    }
}

/// Creates a Chrome window payload for testing.
/// - Parameters:
///   - id: Window ID.
///   - workspace: Workspace name.
/// - Returns: Window payload configured as a Chrome window.
func chromeWindowPayload(
    id: Int,
    workspace: String,
    windowTitle: String = "Chrome",
    windowLayout: String = "tiling",
    monitorAppkitNSScreenScreensId: Int? = 1
) -> WindowPayload {
    WindowPayload(
        windowId: id,
        workspace: workspace,
        appBundleId: ChromeApp.bundleId,
        appName: "Google Chrome",
        windowTitle: windowTitle,
        windowLayout: windowLayout,
        monitorAppkitNSScreenScreensId: monitorAppkitNSScreenScreensId
    )
}

/// Creates a window payload with custom app identity.
/// - Parameters:
///   - id: Window ID.
///   - workspace: Workspace name.
///   - bundleId: Application bundle identifier.
///   - appName: Application name.
/// - Returns: Window payload with specified identity.
func windowPayload(
    id: Int,
    workspace: String,
    bundleId: String,
    appName: String,
    windowTitle: String = "",
    windowLayout: String = "tiling",
    monitorAppkitNSScreenScreensId: Int? = 1
) -> WindowPayload {
    WindowPayload(
        windowId: id,
        workspace: workspace,
        appBundleId: bundleId,
        appName: appName,
        windowTitle: windowTitle,
        windowLayout: windowLayout,
        monitorAppkitNSScreenScreensId: monitorAppkitNSScreenScreensId
    )
}

/// Encodes window payloads to JSON string for stubbing list-windows output.
/// - Parameter windows: Array of window payloads to encode.
/// - Returns: JSON string representation.
func windowsJSON(_ windows: [WindowPayload]) -> String {
    guard let data = try? JSONEncoder().encode(windows),
          let json = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return json
}

// MARK: - Date Provider

/// Fixed date provider for deterministic tests.
struct FixedDateProvider: DateProviding {
    let date: Date

    init(date: Date = Date(timeIntervalSince1970: 0)) {
        self.date = date
    }

    func now() -> Date {
        date
    }
}

// MARK: - Test File System

/// In-memory file system for testing.
final class TestFileSystem: FileSystem {
    private var files: [String: Data]
    private var directories: Set<String>
    private var executableFiles: Set<String>

    init(
        files: [String: Data] = [:],
        directories: Set<String> = [],
        executableFiles: Set<String> = []
    ) {
        self.files = files
        self.directories = directories
        self.executableFiles = executableFiles
    }

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        executableFiles.contains(url.path)
    }

    func readFile(at url: URL) throws -> Data {
        if let data = files[url.path] {
            return data
        }
        throw NSError(domain: "TestFileSystem", code: 1)
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = files[url.path] else {
            throw NSError(domain: "TestFileSystem", code: 2)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url.path)
        directories.remove(url.path)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        guard let data = files.removeValue(forKey: sourceURL.path) else {
            throw NSError(domain: "TestFileSystem", code: 3)
        }
        files[destinationURL.path] = data
    }

    func appendFile(at url: URL, data: Data) throws {
        if var existing = files[url.path] {
            existing.append(data)
            files[url.path] = existing
        } else {
            files[url.path] = data
        }
    }

    func writeFile(at url: URL, data: Data) throws {
        files[url.path] = data
    }

    func syncFile(at url: URL) throws {
        if files[url.path] == nil {
            throw NSError(domain: "TestFileSystem", code: 4)
        }
    }

    @discardableResult
    func replaceItemAt(_ originalURL: URL, withItemAt newItemURL: URL) throws -> URL? {
        guard let data = files.removeValue(forKey: newItemURL.path) else {
            throw NSError(domain: "TestFileSystem", code: 5, userInfo: [NSLocalizedDescriptionKey: "Source file not found"])
        }
        files[originalURL.path] = data
        return originalURL
    }

    /// Adds a file to the test file system.
    func addFile(at path: String, data: Data) {
        files[path] = data
    }

    /// Adds a file with string content to the test file system.
    func addFile(at path: String, content: String) {
        files[path] = Data(content.utf8)
    }

    /// Returns file data at the given path, or nil if not present.
    func fileData(atPath path: String) -> Data? {
        files[path]
    }
}

// MARK: - Test App Discovery

/// Configurable app discovery for testing.
struct TestAppDiscovery: AppDiscovering {
    let bundleIds: [String: URL]
    let names: [String: URL]
    let bundleIdForPath: [String: String]

    init(bundleIds: [String: URL] = [:]) {
        self.bundleIds = bundleIds
        self.names = [:]
        var reverse: [String: String] = [:]
        for (bundleId, url) in bundleIds {
            reverse[url.path] = bundleId
        }
        self.bundleIdForPath = reverse
    }

    init(bundleIds: [String: URL], names: [String: URL]) {
        self.bundleIds = bundleIds
        self.names = names
        var reverse: [String: String] = [:]
        for (bundleId, url) in bundleIds {
            reverse[url.path] = bundleId
        }
        self.bundleIdForPath = reverse
    }

    /// Full initializer for DoctorTests compatibility.
    init(bundleIdMap: [String: String], nameMap: [String: String], bundleIdForPath: [String: String]) {
        var ids: [String: URL] = [:]
        for (bundleId, path) in bundleIdMap {
            ids[bundleId] = URL(fileURLWithPath: path, isDirectory: true)
        }
        self.bundleIds = ids
        var nameURLs: [String: URL] = [:]
        for (name, path) in nameMap {
            nameURLs[name] = URL(fileURLWithPath: path, isDirectory: true)
        }
        self.names = nameURLs
        self.bundleIdForPath = bundleIdForPath
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        bundleIds[bundleIdentifier]
    }

    func applicationURL(named appName: String) -> URL? {
        names[appName]
    }

    func bundleIdentifier(forApplicationAt url: URL) -> String? {
        bundleIdForPath[url.path]
    }
}

// MARK: - Test Sleeper

/// Non-blocking sleeper that records sleep calls for testing.
final class TestSleeper: AeroSpaceSleeping {
    private(set) var sleepCalls: [TimeInterval] = []

    func sleep(seconds: TimeInterval) {
        sleepCalls.append(seconds)
    }
}

// MARK: - Test Clock

/// Controllable clock for timing-sensitive tests.
final class TestClock: DateProviding {
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 0)) {
        self.current = start
    }

    func now() -> Date {
        current
    }

    func advance(seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

/// Sleeper that advances a test clock instead of blocking.
final class AdvancingSleeper: AeroSpaceSleeping {
    private let clock: TestClock
    private(set) var sleepCalls: [TimeInterval] = []

    init(clock: TestClock) {
        self.clock = clock
    }

    func sleep(seconds: TimeInterval) {
        sleepCalls.append(seconds)
        clock.advance(seconds: seconds)
    }
}

// MARK: - Test Screen Metrics

/// Screen metrics provider for tests.
struct TestScreenMetricsProvider: ScreenMetricsProviding {
    let widthsByIndex: [Int: Double]

    init(widthsByIndex: [Int: Double]) {
        self.widthsByIndex = widthsByIndex
    }

    func visibleWidth(screenIndex1Based: Int) -> Result<Double, ScreenMetricsError> {
        guard let width = widthsByIndex[screenIndex1Based] else {
            return .failure(.invalidScreenIndex(screenIndex1Based))
        }
        return .success(width)
    }
}

// MARK: - Test Command Runner

/// Signature for matching stubbed open command responses.
struct OpenCommandSignature: Hashable {
    let path: String
    let arguments: [String]
}

/// Recorded command invocation.
struct CommandInvocation: Equatable {
    let path: String
    let arguments: [String]
}

/// Command runner that records invocations and returns stubbed results.
final class RecordingCommandRunner: CommandRunning {
    private(set) var invocations: [CommandInvocation] = []
    private var results: [OpenCommandSignature: [CommandResult]]

    init(results: [OpenCommandSignature: [CommandResult]] = [:]) {
        self.results = results
    }

    func run(
        command: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> CommandResult {
        invocations.append(CommandInvocation(path: command.path, arguments: arguments))
        let signature = OpenCommandSignature(path: command.path, arguments: arguments)
        guard var queue = results[signature], !queue.isEmpty else {
            throw NSError(domain: "RecordingCommandRunner", code: 1)
        }
        let result = queue.removeFirst()
        results[signature] = queue
        return result
    }

    /// Adds a stubbed result for a command signature.
    func addResult(for signature: OpenCommandSignature, result: CommandResult) {
        var queue = results[signature] ?? []
        queue.append(result)
        results[signature] = queue
    }
}

// MARK: - Test Binary Resolver

/// Configurable AeroSpace binary resolver for testing.
final class TestBinaryResolver: AeroSpaceBinaryResolving {
    private let result: Result<URL, AeroSpaceBinaryResolutionError>

    init(result: Result<URL, AeroSpaceBinaryResolutionError>) {
        self.result = result
    }

    static func success(path: String = "/opt/homebrew/bin/aerospace") -> TestBinaryResolver {
        TestBinaryResolver(result: .success(URL(fileURLWithPath: path)))
    }

    static func failure(_ error: AeroSpaceBinaryResolutionError) -> TestBinaryResolver {
        TestBinaryResolver(result: .failure(error))
    }

    func resolve() -> Result<URL, AeroSpaceBinaryResolutionError> {
        result
    }
}

// MARK: - Test Logger

/// Logger that captures log entries for testing.
final class TestLogger: ProjectWorkspacesLogging {
    struct Entry: Equatable {
        let event: String
        let level: LogLevel
        let message: String?
        let context: [String: String]?
    }

    private(set) var entries: [Entry] = []
    var shouldFail: Bool = false
    var failureError: LogWriteError?

    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError> {
        entries.append(Entry(event: event, level: level, message: message, context: context))
        if shouldFail {
            return .failure(failureError ?? .writeFailed("Test log failure"))
        }
        return .success(())
    }
}

// MARK: - Test Constants

/// Common test constants.
enum TestConstants {
    static let aerospacePath = "/opt/homebrew/bin/aerospace"
    static let listWindowsFormat = "%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title} %{window-layout} %{monitor-appkit-nsscreen-screens-id}"
    static let vscodeBundleId = "com.microsoft.VSCode"
    static let vscodeAppURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)
}

// MARK: - Test Config Helpers

/// Creates a minimal valid config TOML for testing.
/// - Parameters:
///   - projectId: Project identifier.
///   - projectName: Project display name.
///   - projectPath: Project file path.
/// - Returns: Valid TOML config string.
func validConfigTOML(
    projectId: String = "codex",
    projectName: String = "Codex",
    projectPath: String = "/Users/tester/src/codex"
) -> String {
    """
    [global]
    defaultIde = "vscode"
    globalChromeUrls = []

    [ide.vscode]
    bundleId = "com.microsoft.VSCode"

    [[project]]
    id = "\(projectId)"
    name = "\(projectName)"
    path = "\(projectPath)"
    colorHex = "#7C3AED"
    ide = "vscode"
    chromeUrls = []
    """
}
