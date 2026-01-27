import Foundation

@testable import ProjectWorkspacesCore

struct AeroSpaceCommandSignature: Hashable {
    let path: String
    let arguments: [String]
}

struct AeroSpaceCommandCall: Equatable {
    let path: String
    let arguments: [String]
    let timeoutSeconds: TimeInterval
}

final class SequencedAeroSpaceCommandRunner: AeroSpaceCommandRunning {
    private var responses: [AeroSpaceCommandSignature: [Result<CommandResult, AeroSpaceCommandError>]]
    private(set) var invocations: [AeroSpaceCommandSignature] = []
    private(set) var calls: [AeroSpaceCommandCall] = []

    init(responses: [AeroSpaceCommandSignature: [Result<CommandResult, AeroSpaceCommandError>]]) {
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
