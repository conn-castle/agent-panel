import Foundation

/// Represents a window returned by `aerospace list-windows --json`.
/// `appName` and `windowTitle` may be empty if the CLI format omits them.
public struct AeroSpaceWindow: Decodable, Equatable, Sendable {
    public let windowId: Int
    public let workspace: String
    public let appBundleId: String
    public let appName: String
    public let windowTitle: String
    public let windowLayout: String
    public let monitorAppkitNSScreenScreensId: Int?

    /// Creates a window model.
    /// - Parameters:
    ///   - windowId: AeroSpace window identifier.
    ///   - workspace: Workspace name.
    ///   - appBundleId: App bundle identifier.
    ///   - appName: App display name.
    ///   - windowTitle: Window title (may be empty).
    ///   - windowLayout: Window layout (may be empty).
    public init(
        windowId: Int,
        workspace: String,
        appBundleId: String,
        appName: String,
        windowTitle: String,
        windowLayout: String,
        monitorAppkitNSScreenScreensId: Int? = nil
    ) {
        self.windowId = windowId
        self.workspace = workspace
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.windowLayout = windowLayout
        self.monitorAppkitNSScreenScreensId = monitorAppkitNSScreenScreensId
    }

    private enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case workspace
        case appBundleId = "app-bundle-id"
        case appName = "app-name"
        case windowTitle = "window-title"
        case windowLayout = "window-layout"
        case monitorAppkitNSScreenScreensId = "monitor-appkit-nsscreen-screens-id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowId = try container.decode(Int.self, forKey: .windowId)
        workspace = try container.decode(String.self, forKey: .workspace)
        appBundleId = try container.decode(String.self, forKey: .appBundleId)
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? ""
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle) ?? ""
        windowLayout = try container.decodeIfPresent(String.self, forKey: .windowLayout) ?? ""
        monitorAppkitNSScreenScreensId = try container.decodeIfPresent(Int.self, forKey: .monitorAppkitNSScreenScreensId)
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
