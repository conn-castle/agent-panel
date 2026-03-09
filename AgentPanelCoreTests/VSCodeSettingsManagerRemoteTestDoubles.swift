import Foundation

@testable import AgentPanelCore

final class SequentialSSHRunner: CommandRunning {
    struct Call {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    private var results: [Result<ApCommandResult, ApCoreError>]

    init(results: [Result<ApCommandResult, ApCoreError>]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        calls.append(Call(executable: executable, arguments: arguments))
        guard !results.isEmpty else {
            return .failure(ApCoreError(message: "SequentialSSHRunner: no results left"))
        }
        return results.removeFirst()
    }
}

struct RemoteTestFailingFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
    }
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
    }
}
