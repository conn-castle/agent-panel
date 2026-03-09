import XCTest
import Foundation
import Darwin
@testable import AgentPanelCore

let shellEnvLock = NSLock()
final class ChromeLauncherCommandRunnerStub: CommandRunning {
    let result: Result<ApCommandResult, ApCoreError>
    private(set) var lastExecutable: String?
    private(set) var lastArguments: [String]?
    private(set) var lastTimeout: TimeInterval?
    private(set) var lastWorkingDirectory: String?

    init(result: Result<ApCommandResult, ApCoreError>) {
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        lastExecutable = executable
        lastArguments = arguments
        lastTimeout = timeoutSeconds
        lastWorkingDirectory = workingDirectory
        return result
    }
}

func withShell(_ shell: String?, _ body: () throws -> Void) rethrows {
    shellEnvLock.lock()
    defer { shellEnvLock.unlock() }

    let originalShell = ProcessInfo.processInfo.environment["SHELL"]
    defer {
        if let originalShell {
            setenv("SHELL", originalShell, 1)
        } else {
            unsetenv("SHELL")
        }
    }

    if let shell {
        setenv("SHELL", shell, 1)
    } else {
        unsetenv("SHELL")
    }

    try body()
}

struct AlwaysExecutableFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { true }
    func readFile(at url: URL) throws -> Data { Data() }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}
