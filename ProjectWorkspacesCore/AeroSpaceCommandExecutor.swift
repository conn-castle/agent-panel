import Foundation

/// Serializes all AeroSpace CLI command execution through a single queue.
public final class AeroSpaceCommandExecutor: AeroSpaceCommandRunning {
    public static let shared = AeroSpaceCommandExecutor(wrapped: DefaultAeroSpaceCommandRunner())

    private let wrapped: AeroSpaceCommandRunning
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UUID>()
    private let queueId = UUID()

    /// Creates a serialized executor.
    /// - Parameter wrapped: Underlying command runner.
    public init(wrapped: AeroSpaceCommandRunning) {
        self.wrapped = wrapped
        self.queue = DispatchQueue(label: "com.projectworkspaces.aerospace.executor")
        self.queue.setSpecific(key: queueKey, value: queueId)
    }

    /// Runs an AeroSpace command through the serialized queue.
    public func run(
        executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<CommandResult, AeroSpaceCommandError> {
        if DispatchQueue.getSpecific(key: queueKey) == queueId {
            return wrapped.run(executable: executable, arguments: arguments, timeoutSeconds: timeoutSeconds)
        }
        return queue.sync {
            wrapped.run(executable: executable, arguments: arguments, timeoutSeconds: timeoutSeconds)
        }
    }
}
