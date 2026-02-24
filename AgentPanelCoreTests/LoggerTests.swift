import XCTest
@testable import AgentPanelCore

final class LoggerTests: XCTestCase {

    func testLoggerInitWithCustomDataStoreWritesToDiskAtExpectedPath() throws {
        let tmpHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpanel-logger-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpHome) }
        try FileManager.default.createDirectory(at: tmpHome, withIntermediateDirectories: true)

        let dataStore = DataPaths(homeDirectory: tmpHome)
        let logger = AgentPanelLogger(dataStore: dataStore)

        switch logger.log(event: "disk.write.test") {
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        case .success:
            break
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: dataStore.primaryLogFile.path))
    }

    func testLoggerLogWritesWithGeneratedTimestamp() throws {
        let fileSystem = InMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        switch logger.log(event: "test.event", level: .warn, message: "hello", context: ["k": "v"]) {
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        case .success:
            break
        }

        let logData = try fileSystem.readFile(at: dataStore.primaryLogFile)
        XCTAssertEqual(logData.last, 0x0A)

        let line = String(data: logData.dropLast(), encoding: .utf8)
        XCTAssertNotNil(line)

        let decoded = try JSONDecoder().decode(LogEntry.self, from: Data(line!.utf8))
        XCTAssertEqual(decoded.event, "test.event")
        XCTAssertEqual(decoded.level, .warn)
        XCTAssertEqual(decoded.message, "hello")
        XCTAssertEqual(decoded.context, ["k": "v"])
        XCTAssertTrue(decoded.timestamp.contains("T"), "Expected ISO-8601 timestamp")
        XCTAssertTrue(decoded.timestamp.hasSuffix("Z"), "Expected UTC timestamp ending in Z")
    }

    func testLogEntryRejectsEmptyEvent() {
        let fileSystem = InMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "  ")
        let result = logger.log(entry: entry)

        switch result {
        case .failure(.invalidEvent):
            break
        case .failure(let error):
            XCTFail("Expected invalidEvent, got \(error)")
        case .success:
            XCTFail("Expected failure for empty event")
        }
    }

    func testLogEntryAppendsJsonLine() throws {
        let fileSystem = InMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(
            timestamp: "2024-01-01T00:00:00.000Z",
            level: .info,
            event: "test.event",
            message: "hello",
            context: ["k": "v"]
        )

        let result = logger.log(entry: entry)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(fileSystem.directories.contains(dataStore.logsDirectory.path))

        let logData = try fileSystem.readFile(at: dataStore.primaryLogFile)
        XCTAssertEqual(logData.last, 0x0A, "Expected newline-terminated JSON line.")

        let line = String(data: logData.dropLast(), encoding: .utf8)
        XCTAssertNotNil(line)

        let decoded = try JSONDecoder().decode(LogEntry.self, from: Data(line!.utf8))
        XCTAssertEqual(decoded, entry)
    }

    func testRotationShiftsArchivesAndMovesActiveLog() throws {
        let fileSystem = InMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))

        // Small max size to force rotation deterministically.
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 20,
            maxArchives: 2
        )

        let logURL = dataStore.primaryLogFile
        let archive1 = dataStore.logsDirectory.appendingPathComponent("agent-panel.log.1")
        let archive2 = dataStore.logsDirectory.appendingPathComponent("agent-panel.log.2")

        // Existing files before rotation.
        try fileSystem.writeFile(at: logURL, data: Data(repeating: 0x41, count: 15)) // "AAAA..."
        try fileSystem.writeFile(at: archive1, data: Data("old-1".utf8))
        try fileSystem.writeFile(at: archive2, data: Data("old-2".utf8))

        // This entry should trigger rotation.
        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "rotate")
        switch logger.log(entry: entry) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }

        // archive2 should now contain prior archive1 contents.
        let newArchive2 = try String(data: fileSystem.readFile(at: archive2), encoding: .utf8)
        XCTAssertEqual(newArchive2, "old-1")

        // archive1 should now contain prior active log contents (15 bytes of 'A').
        let newArchive1 = try fileSystem.readFile(at: archive1)
        XCTAssertEqual(newArchive1, Data(repeating: 0x41, count: 15))

        // active log should be recreated and contain the new entry.
        let newActive = try fileSystem.readFile(at: logURL)
        XCTAssertFalse(newActive.isEmpty)
        XCTAssertEqual(newActive.last, 0x0A)
    }

    func testCreateDirectoryFailureReturnsCreateDirectoryFailed() {
        let fileSystem = ConfigurableFileSystem()
        fileSystem.createDirectoryError = NSError(domain: "test", code: 1)

        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.createDirectoryFailed):
            break
        case .failure(let error):
            XCTFail("Expected createDirectoryFailed, got: \(error)")
        }
    }

    func testFileSizeFailureReturnsFileSizeFailed() throws {
        let fileSystem = ConfigurableFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))

        // Ensure log file exists so rotateIfNeeded checks size.
        try fileSystem.writeFile(at: dataStore.primaryLogFile, data: Data(repeating: 0x41, count: 10))
        fileSystem.fileSizeError = NSError(domain: "test", code: 2)

        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.fileSizeFailed):
            break
        case .failure(let error):
            XCTFail("Expected fileSizeFailed, got: \(error)")
        }
    }

    func testRotationFailureReturnsRotationFailed() throws {
        let fileSystem = ConfigurableFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))

        // Ensure log file exists and size will exceed maxLogSizeBytes.
        try fileSystem.writeFile(at: dataStore.primaryLogFile, data: Data(repeating: 0x41, count: 10))
        fileSystem.moveItemError = NSError(domain: "test", code: 3)

        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.rotationFailed):
            break
        case .failure(let error):
            XCTFail("Expected rotationFailed, got: \(error)")
        }
    }

    func testAppendFailureReturnsWriteFailed() {
        let fileSystem = ConfigurableFileSystem()
        fileSystem.appendFileError = NSError(domain: "test", code: 4)

        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.writeFailed):
            break
        case .failure(let error):
            XCTFail("Expected writeFailed, got: \(error)")
        }
    }

    func testLockFailureReturnsLockFailed() {
        let fileSystem = ConfigurableFileSystem()
        fileSystem.fileLockError = NSError(domain: "test", code: 5)

        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.lockFailed):
            break
        case .failure(let error):
            XCTFail("Expected lockFailed, got: \(error)")
        }
    }

    func testLogWriteErrorMessageCoverage() {
        XCTAssertEqual(LogWriteError.invalidEvent.message, "Log event is empty.")
        XCTAssertTrue(LogWriteError.encodingFailed("x").message.contains("encode"))
        XCTAssertTrue(LogWriteError.createDirectoryFailed("x").message.contains("directory"))
        XCTAssertTrue(LogWriteError.lockFailed("x").message.contains("lock"))
        XCTAssertTrue(LogWriteError.fileSizeFailed("x").message.contains("size"))
        XCTAssertTrue(LogWriteError.rotationFailed("x").message.contains("rotate"))
        XCTAssertTrue(LogWriteError.writeFailed("x").message.contains("write"))
    }

    func testConcurrentWritesRemainValidJsonLinesWithInterleavingFileSystem() throws {
        let fileSystem = InterleavingAppendFileSystem(interleaveDelaySeconds: 0.05)
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = AgentPanelLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024 * 1024,
            maxArchives: 2
        )

        let queue = DispatchQueue(label: "com.agentpanel.tests.logger.concurrent", attributes: .concurrent)
        let startGate = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let resultLock = NSLock()
        var results: [Result<Void, LogWriteError>] = []

        for index in 0..<2 {
            group.enter()
            queue.async {
                startGate.wait()
                let result = logger.log(
                    event: "concurrent.event.\(index)",
                    level: .info,
                    message: String(repeating: "payload-", count: 40),
                    context: ["writer": "\(index)"]
                )
                resultLock.lock()
                results.append(result)
                resultLock.unlock()
                group.leave()
            }
        }

        startGate.signal()
        startGate.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)

        XCTAssertEqual(results.count, 2)
        for result in results {
            if case .failure(let error) = result {
                XCTFail("Unexpected log failure: \(error)")
            }
        }

        let data = try fileSystem.readFile(at: dataStore.primaryLogFile)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)

        for line in lines {
            do {
                _ = try JSONDecoder().decode(LogEntry.self, from: Data(line.utf8))
            } catch {
                XCTFail("Corrupted JSONL line: \(line)\nError: \(error)")
            }
        }
    }

    func testConcurrentWritesAcrossProcessesRemainValidJsonLines() throws {
        let tmpHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpanel-logger-multiprocess-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpHome) }
        try FileManager.default.createDirectory(at: tmpHome, withIntermediateDirectories: true)

        let projectPath = tmpHome
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("sample", isDirectory: true)
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)

        let configDir = tmpHome
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("agent-panel", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let configPath = configDir.appendingPathComponent("config.toml", isDirectory: false)
        let config = """
        [[project]]
        name = "Sample"
        path = "\(projectPath.path)"
        color = "blue"
        """
        try config.write(to: configPath, atomically: true, encoding: .utf8)

        let cliURL = try resolveCLIBinaryURLOrSkip()

        // Warm up to ensure the shared log file exists before high-contention appends.
        let warmupStatus = try runCLIListProjects(cliURL: cliURL, homeDirectory: tmpHome)
        XCTAssertEqual(warmupStatus, 0)

        let workerCount = 6
        let runsPerWorker = 20
        let failureLock = NSLock()
        var failures: [String] = []

        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            for run in 0..<runsPerWorker {
                do {
                    let status = try runCLIListProjects(cliURL: cliURL, homeDirectory: tmpHome)
                    if status != 0 {
                        failureLock.lock()
                        failures.append("worker=\(worker) run=\(run) status=\(status)")
                        failureLock.unlock()
                    }
                } catch {
                    failureLock.lock()
                    failures.append("worker=\(worker) run=\(run) error=\(error)")
                    failureLock.unlock()
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "CLI subprocess failures: \(failures.joined(separator: "; "))")

        let dataStore = DataPaths(homeDirectory: tmpHome)
        let minimumExpectedLineCount = workerCount * runsPerWorker

        let fileData = try Data(contentsOf: dataStore.primaryLogFile)
        let text = try XCTUnwrap(String(data: fileData, encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertGreaterThanOrEqual(lines.count, minimumExpectedLineCount)

        for line in lines {
            do {
                _ = try JSONDecoder().decode(LogEntry.self, from: Data(line.utf8))
            } catch {
                XCTFail("Corrupted JSONL line: \(line)\nError: \(error)")
            }
        }
    }

    private func runCLIListProjects(cliURL: URL, homeDirectory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = cliURL
        process.arguments = ["list-projects"]
        process.currentDirectoryURL = homeDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = homeDirectory.path
        environment["CFFIXED_USER_HOME"] = homeDirectory.path
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func resolveCLIBinaryURLOrSkip() throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let builtProductsDirectory = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            candidates.append(
                URL(fileURLWithPath: builtProductsDirectory, isDirectory: true)
                    .appendingPathComponent("ap", isDirectory: false)
            )
        }

        let bundleProductsDirectory = Bundle(for: LoggerTests.self).bundleURL.deletingLastPathComponent()
        candidates.append(bundleProductsDirectory.appendingPathComponent("ap", isDirectory: false))

        // Fallback for repo-local `make test` / `make coverage` runs.
        let repositoryRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent() // AgentPanelCoreTests
            .deletingLastPathComponent() // repo root
        let repoDerivedDataCLI = repositoryRoot
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("DerivedData", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("ap", isDirectory: false)
        candidates.append(repoDerivedDataCLI)

        var checkedPaths: [String] = []
        for candidate in candidates {
            guard !checkedPaths.contains(candidate.path) else {
                continue
            }
            checkedPaths.append(candidate.path)

            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw XCTSkip(
            "Skipping multiprocess logger test: CLI binary 'ap' not found in build products. Checked: \(checkedPaths.joined(separator: ", "))"
        )
    }
}

// MARK: - Test Doubles

private final class InMemoryFileSystem: FileSystem {
    enum InMemoryError: Error {
        case missing(String)
    }

    private(set) var directories: Set<String> = []
    private var files: [String: Data] = [:]

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        false
    }

    func readFile(at url: URL) throws -> Data {
        guard let data = files[url.path] else {
            throw InMemoryError.missing(url.path)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = files[url.path] else {
            throw InMemoryError.missing(url.path)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url.path)
        directories.remove(url.path)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        guard let data = files[sourceURL.path] else {
            throw InMemoryError.missing(sourceURL.path)
        }
        files[destinationURL.path] = data
        files.removeValue(forKey: sourceURL.path)
    }

    func appendFile(at url: URL, data: Data) throws {
        if let existing = files[url.path] {
            var merged = existing
            merged.append(data)
            files[url.path] = merged
        } else {
            files[url.path] = data
        }
    }

    func writeFile(at url: URL, data: Data) throws {
        files[url.path] = data
    }
}

private final class ConfigurableFileSystem: FileSystem {
    enum ConfigurableError: Error {
        case injected
    }

    private let base = InMemoryFileSystem()

    var createDirectoryError: Error?
    var fileSizeError: Error?
    var removeItemError: Error?
    var moveItemError: Error?
    var appendFileError: Error?
    var fileLockError: Error?

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func directoryExists(at url: URL) -> Bool { base.directoryExists(at: url) }
    func isExecutableFile(at url: URL) -> Bool { base.isExecutableFile(at: url) }
    func readFile(at url: URL) throws -> Data { try base.readFile(at: url) }

    func createDirectory(at url: URL) throws {
        if let createDirectoryError { throw createDirectoryError }
        try base.createDirectory(at: url)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        if let fileSizeError { throw fileSizeError }
        return try base.fileSize(at: url)
    }

    func removeItem(at url: URL) throws {
        if let removeItemError { throw removeItemError }
        try base.removeItem(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        if let moveItemError { throw moveItemError }
        try base.moveItem(at: sourceURL, to: destinationURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        if let appendFileError { throw appendFileError }
        try base.appendFile(at: url, data: data)
    }

    func withExclusiveFileLock<T>(at url: URL, body: () throws -> T) throws -> T {
        _ = url
        if let fileLockError { throw fileLockError }
        return try body()
    }

    func writeFile(at url: URL, data: Data) throws { try base.writeFile(at: url, data: data) }
}

/// File system test double that deterministically interleaves concurrent append operations.
///
/// When two callers append to the same file concurrently, the second caller writes its full payload
/// while the first caller is paused between writing its first and second halves. This reproduces
/// byte-level write interleaving that can corrupt JSONL when the logger is not single-writer.
private final class InterleavingAppendFileSystem: FileSystem {
    enum InterleavingError: Error {
        case missing(String)
    }

    private let interleaveDelaySeconds: TimeInterval
    private let lock = NSLock()
    private var directories: Set<String> = []
    private var files: [String: Data] = [:]
    private var appendInProgress: Bool = false

    init(interleaveDelaySeconds: TimeInterval) {
        self.interleaveDelaySeconds = interleaveDelaySeconds
    }

    func fileExists(at url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return files[url.path] != nil
    }

    func directoryExists(at url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        false
    }

    func readFile(at url: URL) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let data = files[url.path] else {
            throw InterleavingError.missing(url.path)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        lock.lock()
        directories.insert(url.path)
        lock.unlock()
    }

    func fileSize(at url: URL) throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard let data = files[url.path] else {
            throw InterleavingError.missing(url.path)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        files.removeValue(forKey: url.path)
        directories.remove(url.path)
        lock.unlock()
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        lock.lock()
        guard let data = files[sourceURL.path] else {
            lock.unlock()
            throw InterleavingError.missing(sourceURL.path)
        }
        files[destinationURL.path] = data
        files.removeValue(forKey: sourceURL.path)
        lock.unlock()
    }

    func appendFile(at url: URL, data: Data) throws {
        let shouldInterleave: Bool
        lock.lock()
        shouldInterleave = appendInProgress
        if !appendInProgress {
            appendInProgress = true
        }
        lock.unlock()

        if shouldInterleave {
            appendChunk(data, to: url)
            return
        }

        defer {
            lock.lock()
            appendInProgress = false
            lock.unlock()
        }

        let splitIndex = max(1, data.count / 2)
        let firstHalf = Data(data.prefix(splitIndex))
        let secondHalf = Data(data.suffix(data.count - splitIndex))

        appendChunk(firstHalf, to: url)
        Thread.sleep(forTimeInterval: interleaveDelaySeconds)
        appendChunk(secondHalf, to: url)
    }

    func withExclusiveFileLock<T>(at url: URL, body: () throws -> T) throws -> T {
        _ = url
        return try body()
    }

    func writeFile(at url: URL, data: Data) throws {
        lock.lock()
        files[url.path] = data
        lock.unlock()
    }

    private func appendChunk(_ chunk: Data, to url: URL) {
        lock.lock()
        if let existing = files[url.path] {
            var merged = existing
            merged.append(chunk)
            files[url.path] = merged
        } else {
            files[url.path] = chunk
        }
        lock.unlock()
    }
}
