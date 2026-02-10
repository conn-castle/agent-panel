//
//  AeroSpaceConfigManager.swift
//  AgentPanelCore
//
//  Manages the AeroSpace configuration file (~/.aerospace.toml).
//  Handles config status detection, backup creation, and writing
//  the AgentPanel-managed safe configuration.
//

import Foundation

/// Status of the AeroSpace configuration file.
public enum AeroSpaceConfigStatus: String, Sendable {
    /// No config file exists.
    case missing
    /// Config exists and is managed by AgentPanel.
    case managedByAgentPanel
    /// Config exists but was created externally (not by AgentPanel).
    case externalConfig
    /// Could not determine config status.
    case unknown
}

/// Manages the AeroSpace configuration file.
public struct AeroSpaceConfigManager {
    /// Marker comment that identifies configs managed by AgentPanel.
    static let managedByMarker = "# Managed by AgentPanel - do not edit manually"

    /// Resource name for the safe config template.
    private static let safeConfigResourceName = "aerospace-safe"

    /// Default path to the AeroSpace config file.
    public static var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aerospace.toml")
            .path
    }

    /// Path for backing up existing configs before overwriting.
    private static var backupPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aerospace.toml.agentpanel-backup")
            .path
    }

    private let fileManager: FileManager
    private let configPath: String
    private let backupPath: String
    private let safeConfigLoader: () -> String?

    /// Creates a config manager.
    public init() {
        self.fileManager = .default
        self.configPath = Self.configPath
        self.backupPath = Self.backupPath
        self.safeConfigLoader = {
            guard let url = Bundle.main.url(forResource: Self.safeConfigResourceName, withExtension: "toml") else {
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    /// Creates a config manager with a custom file manager.
    /// - Parameter fileManager: File manager to use for file operations.
    init(
        fileManager: FileManager,
        configPath: String = AeroSpaceConfigManager.configPath,
        backupPath: String = AeroSpaceConfigManager.backupPath,
        safeConfigLoader: @escaping () -> String? = {
            guard let url = Bundle.main.url(forResource: AeroSpaceConfigManager.safeConfigResourceName, withExtension: "toml") else {
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    ) {
        self.fileManager = fileManager
        self.configPath = configPath
        self.backupPath = backupPath
        self.safeConfigLoader = safeConfigLoader
    }

    /// Loads the safe AeroSpace config from the app bundle.
    /// - Returns: The config content, or nil if not found.
    private func loadSafeConfigFromBundle() -> String? {
        safeConfigLoader()
    }

    /// Returns true if the AeroSpace config file exists.
    private func configExists() -> Bool {
        fileManager.fileExists(atPath: configPath)
    }

    /// Returns true if the existing config is managed by AgentPanel.
    /// - Returns: True if the config starts with the managed-by marker, false otherwise.
    private func configIsManagedByAgentPanel() -> Result<Bool, ApCoreError> {
        guard configExists() else {
            return .success(false)
        }

        do {
            let contents = try String(contentsOfFile: configPath, encoding: .utf8)
            return .success(contents.hasPrefix(Self.managedByMarker))
        } catch {
            return .failure(fileSystemError(
                "Failed to read AeroSpace config.",
                detail: error.localizedDescription
            ))
        }
    }

    /// Backs up the existing config file if it exists.
    /// - Returns: Success, or an error if backup fails.
    private func backupExistingConfig() -> Result<Void, ApCoreError> {
        guard configExists() else {
            return .success(())
        }

        do {
            // Remove old backup if it exists
            if fileManager.fileExists(atPath: backupPath) {
                try fileManager.removeItem(atPath: backupPath)
            }
            try fileManager.copyItem(atPath: configPath, toPath: backupPath)
            return .success(())
        } catch {
            return .failure(fileSystemError(
                "Failed to backup AeroSpace config.",
                detail: error.localizedDescription
            ))
        }
    }

    /// Writes the safe AeroSpace config, backing up any existing config first.
    /// - Returns: Success, or an error if writing fails.
    public func writeSafeConfig() -> Result<Void, ApCoreError> {
        // Load the safe config from bundle
        guard let safeConfig = loadSafeConfigFromBundle() else {
            return .failure(fileSystemError(
                "Failed to load aerospace-safe.toml from app bundle.",
                detail: "The app may be corrupted."
            ))
        }

        // Backup existing config if it exists and isn't ours
        switch configIsManagedByAgentPanel() {
        case .failure(let error):
            return .failure(error)
        case .success(let isOurs):
            if !isOurs && configExists() {
                switch backupExistingConfig() {
                case .failure(let error):
                    return .failure(error)
                case .success:
                    break
                }
            }
        }

        // Write the safe config
        do {
            try safeConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
            return .success(())
        } catch {
            return .failure(fileSystemError(
                "Failed to write AeroSpace config.",
                detail: error.localizedDescription
            ))
        }
    }

    /// Returns the status of the AeroSpace config for diagnostic purposes.
    public func configStatus() -> AeroSpaceConfigStatus {
        guard configExists() else {
            return .missing
        }

        switch configIsManagedByAgentPanel() {
        case .failure:
            return .unknown
        case .success(true):
            return .managedByAgentPanel
        case .success(false):
            return .externalConfig
        }
    }
}
