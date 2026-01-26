import Foundation

/// Represents a window returned by `aerospace list-windows --json`.
public struct AeroSpaceWindow: Decodable, Equatable, Sendable {
    public let windowId: Int
    public let workspace: String
    public let appBundleId: String
    public let appName: String
    public let windowTitle: String

    /// Creates a window model.
    /// - Parameters:
    ///   - windowId: AeroSpace window identifier.
    ///   - workspace: Workspace name.
    ///   - appBundleId: App bundle identifier.
    ///   - appName: App display name.
    ///   - windowTitle: Window title (may be empty).
    public init(
        windowId: Int,
        workspace: String,
        appBundleId: String,
        appName: String,
        windowTitle: String
    ) {
        self.windowId = windowId
        self.workspace = workspace
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
    }

    private enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case workspace
        case appBundleId = "app-bundle-id"
        case appName = "app-name"
        case windowTitle = "window-title"
    }
}

/// Decodes AeroSpace list-windows JSON output into typed models.
public struct AeroSpaceWindowDecoder: Sendable {
    /// Creates a window decoder.
    public init() {}

    /// Decodes a JSON payload into window models.
    /// - Parameter json: JSON payload as a string.
    /// - Returns: Decoded windows or a structured error.
    public func decodeWindows(from json: String) -> Result<[AeroSpaceWindow], AeroSpaceCommandError> {
        guard let data = json.data(using: .utf8) else {
            return .failure(
                .decodingFailed(
                    payload: json,
                    underlyingError: "Output was not valid UTF-8."
                )
            )
        }

        do {
            let windows = try JSONDecoder().decode([AeroSpaceWindow].self, from: data)
            return .success(windows)
        } catch {
            return .failure(
                .decodingFailed(
                    payload: json,
                    underlyingError: String(describing: error)
                )
            )
        }
    }
}
