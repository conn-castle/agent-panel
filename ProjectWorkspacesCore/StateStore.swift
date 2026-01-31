import Foundation

/// Result of loading the state file.
enum StateStoreLoadOutcome: Equatable {
    case missing
    case loaded(LayoutState)
    case recovered(LayoutState, backupPath: String)
}

/// Errors surfaced by state load/save operations.
enum StateStoreError: Error, Equatable {
    case readFailed(String)
    case decodeFailed(String)
    case writeFailed(String)
    case backupFailed(String)
}

/// Persists and retrieves the ProjectWorkspaces layout state.
protocol StateStoring {
    /// Loads the state file if present.
    /// - Returns: Load outcome or a structured error.
    func load() -> Result<StateStoreLoadOutcome, StateStoreError>
    /// Saves the provided state payload atomically.
    /// - Parameter state: State payload to persist.
    /// - Returns: Success or a structured error.
    func save(_ state: LayoutState) -> Result<Void, StateStoreError>
}

/// Provides serialized access to the ProjectWorkspaces state file.
final class StateStore: StateStoring {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let dateProvider: DateProviding
    private let queue: DispatchQueue

    /// Creates a state store.
    /// - Parameters:
    ///   - paths: File system paths for ProjectWorkspaces.
    ///   - fileSystem: File system accessor.
    ///   - dateProvider: Date provider for backup naming.
    init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.dateProvider = dateProvider
        self.queue = DispatchQueue(label: "com.projectworkspaces.state.store")
    }

    /// Loads the state file if present.
    /// - Returns: Load outcome or a structured error.
    func load() -> Result<StateStoreLoadOutcome, StateStoreError> {
        queue.sync {
            let stateURL = paths.stateFile
            guard fileSystem.fileExists(at: stateURL) else {
                return .success(.missing)
            }

            let data: Data
            do {
                data = try fileSystem.readFile(at: stateURL)
            } catch {
                return .failure(.readFailed("\(stateURL.path): \(error)"))
            }

            let decoder = JSONDecoder()
            do {
                let state = try decoder.decode(LayoutState.self, from: data)
                guard state.version == .current else {
                    return recoverCorruptState(
                        stateURL: stateURL,
                        reason: "Unsupported state version: \(state.version.rawValue)"
                    )
                }
                return .success(.loaded(state))
            } catch {
                return recoverCorruptState(stateURL: stateURL, reason: "\(error)")
            }
        }
    }

    /// Saves the provided state payload atomically.
    /// - Parameter state: State payload to persist.
    /// - Returns: Success or a structured error.
    func save(_ state: LayoutState) -> Result<Void, StateStoreError> {
        queue.sync {
            let stateURL = paths.stateFile
            let directoryURL = stateURL.deletingLastPathComponent()

            if !fileSystem.directoryExists(at: directoryURL) {
                do {
                    try fileSystem.createDirectory(at: directoryURL)
                } catch {
                    return .failure(.writeFailed("Failed to create state directory: \(error)"))
                }
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data: Data
            do {
                data = try encoder.encode(state)
            } catch {
                return .failure(.writeFailed("Failed to encode state: \(error)"))
            }

            // Write atomically: write to temp file, sync, then atomic move to prevent corruption
            let tempURL = stateURL.deletingLastPathComponent().appendingPathComponent("state.\(UUID().uuidString).tmp")
            do {
                try fileSystem.writeFile(at: tempURL, data: data)
                try fileSystem.syncFile(at: tempURL)
                try fileSystem.moveItem(at: tempURL, to: stateURL)
            } catch {
                // Clean up the temporary file if any step fails
                _ = try? fileSystem.removeItem(at: tempURL)
                return .failure(.writeFailed("Failed to write state: \(error)"))
            }

            return .success(())
        }
    }

    private func recoverCorruptState(
        stateURL: URL,
        reason: String
    ) -> Result<StateStoreLoadOutcome, StateStoreError> {
        let backupURL = makeBackupURL(for: stateURL)
        do {
            if fileSystem.fileExists(at: backupURL) {
                try fileSystem.removeItem(at: backupURL)
            }
            try fileSystem.moveItem(at: stateURL, to: backupURL)
            let emptyState = LayoutState.empty()
            return .success(.recovered(emptyState, backupPath: backupURL.path))
        } catch {
            return .failure(.backupFailed("Failed to back up corrupt state: \(reason); \(error)"))
        }
    }

    private func makeBackupURL(for stateURL: URL) -> URL {
        let timestamp = Int(dateProvider.now().timeIntervalSince1970)
        let backupName = "state.json.bak.\(timestamp)"
        return stateURL.deletingLastPathComponent().appendingPathComponent(backupName, isDirectory: false)
    }
}
