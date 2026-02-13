//
//  Errors.swift
//  AgentPanelCore
//
//  Typed error system for AgentPanelCore operations.
//  Provides categorized errors with optional command details,
//  and helper functions for common error patterns.
//

import Foundation

/// Categories of errors from AgentPanelCore operations.
public enum ApCoreErrorCategory: String, Sendable {
    /// External command execution failures.
    case command
    /// Input validation failures.
    case validation
    /// File system operation failures.
    case fileSystem
    /// Configuration loading/parsing failures.
    case configuration
    /// Output parsing failures.
    case parse
    /// Window management failures (AX positioning, window resolution).
    case window
    /// System-level failures (display detection, permissions).
    case system
}

/// Errors emitted by AgentPanelCore operations.
public struct ApCoreError: Error, Equatable, Sendable {
    /// Error category for programmatic handling.
    let category: ApCoreErrorCategory
    /// Human-readable error message.
    public let message: String
    /// Additional detail (e.g., stderr output).
    let detail: String?
    /// Command that was executed, if applicable.
    let command: String?
    /// Exit code from command execution, if applicable.
    let exitCode: Int32?

    /// Creates a new ApCoreError with full details.
    /// - Parameters:
    ///   - category: Error category.
    ///   - message: Human-readable error message.
    ///   - detail: Additional detail such as stderr output.
    ///   - command: Command that was executed.
    ///   - exitCode: Exit code from the command.
    public init(
        category: ApCoreErrorCategory,
        message: String,
        detail: String? = nil,
        command: String? = nil,
        exitCode: Int32? = nil
    ) {
        self.category = category
        self.message = message
        self.detail = detail
        self.command = command
        self.exitCode = exitCode
    }

    /// Creates a new ApCoreError with just a message.
    /// Defaults to `.command` category for backward compatibility.
    /// - Parameter message: Error message.
    init(message: String) {
        self.category = .command
        self.message = message
        self.detail = nil
        self.command = nil
        self.exitCode = nil
    }
}

/// Builds an ApCoreError from a failed command result.
///
/// Extracts stderr output (trimmed) as the detail field and formats a consistent error message.
///
/// - Parameters:
///   - commandDescription: Human-readable description of the command (e.g., "aerospace list-workspaces --all").
///   - result: The command result containing exit code and stderr.
/// - Returns: A properly formatted ApCoreError.
func commandError(_ commandDescription: String, result: ApCommandResult) -> ApCoreError {
    let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = trimmed.isEmpty ? nil : trimmed
    return ApCoreError(
        category: .command,
        message: "\(commandDescription) failed with exit code \(result.exitCode).",
        detail: detail,
        command: commandDescription,
        exitCode: result.exitCode
    )
}

/// Builds an ApCoreError for validation failures.
///
/// - Parameters:
///   - message: Description of what validation failed.
/// - Returns: A validation category ApCoreError.
func validationError(_ message: String) -> ApCoreError {
    ApCoreError(
        category: .validation,
        message: message
    )
}

/// Builds an ApCoreError for file system failures.
///
/// - Parameters:
///   - message: Description of what file operation failed.
///   - detail: Additional detail about the failure.
/// - Returns: A fileSystem category ApCoreError.
func fileSystemError(_ message: String, detail: String? = nil) -> ApCoreError {
    ApCoreError(
        category: .fileSystem,
        message: message,
        detail: detail
    )
}

/// Builds an ApCoreError for parse failures.
///
/// - Parameters:
///   - message: Description of what parsing failed.
///   - detail: The content that failed to parse.
/// - Returns: A parse category ApCoreError.
func parseError(_ message: String, detail: String? = nil) -> ApCoreError {
    ApCoreError(
        category: .parse,
        message: message,
        detail: detail
    )
}
