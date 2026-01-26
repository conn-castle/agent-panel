import Foundation

/// Sets executable permissions on files.
public protocol FilePermissionsSetting {
    /// Marks the file at the given URL as executable.
    /// - Parameter url: File URL to update.
    /// - Throws: Error when permissions cannot be updated.
    func setExecutable(at url: URL) throws
}

/// Default file permissions setter using `FileManager`.
public struct DefaultFilePermissions: FilePermissionsSetting {
    private let fileManager: FileManager

    /// Creates a permissions setter.
    /// - Parameter fileManager: File manager used for updates.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Marks the file at the given URL as executable.
    /// - Parameter url: File URL to update.
    /// - Throws: Error when permissions cannot be updated.
    public func setExecutable(at url: URL) throws {
        try fileManager.setAttributes([
            .posixPermissions: 0o755
        ], ofItemAtPath: url.path)
    }
}
