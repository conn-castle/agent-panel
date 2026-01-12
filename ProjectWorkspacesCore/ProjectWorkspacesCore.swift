import Foundation

/// Core logic shared by `ProjectWorkspacesApp` and `pwctl`.
///
/// This module intentionally contains no UI concerns so it can be unit tested
/// independently from AppKit/SwiftUI.
public enum ProjectWorkspacesCore {
    /// A human-readable version identifier for diagnostic output.
    ///
    /// This is a placeholder until packaging/versioning is implemented.
    public static let version: String = "0.0.0-dev"
}

