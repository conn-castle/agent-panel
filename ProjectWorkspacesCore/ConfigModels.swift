import Foundation

/// Supported IDE identifiers for ProjectWorkspaces.
public enum IdeKind: String, CaseIterable, Equatable, Sendable {
    case vscode
    case antigravity
}

/// Full parsed configuration for ProjectWorkspaces.
public struct Config: Equatable, Sendable {
    public let global: GlobalConfig
    public let ide: IdeConfig
    public let projects: [ProjectConfig]

    /// Creates a configuration container.
    /// - Parameters:
    ///   - global: Global configuration values.
    ///   - ide: IDE configuration values.
    ///   - projects: Project definitions.
    public init(
        global: GlobalConfig,
        ide: IdeConfig,
        projects: [ProjectConfig]
    ) {
        self.global = global
        self.ide = ide
        self.projects = projects
    }
}

/// Global configuration values.
public struct GlobalConfig: Equatable, Sendable {
    public let defaultIde: IdeKind
    public let globalChromeUrls: [String]

    /// Creates global configuration values.
    /// - Parameters:
    ///   - defaultIde: Default IDE to use when a project omits `ide`.
    ///   - globalChromeUrls: Chrome URLs opened when a project Chrome window is created.
    public init(defaultIde: IdeKind, globalChromeUrls: [String]) {
        self.defaultIde = defaultIde
        self.globalChromeUrls = globalChromeUrls
    }
}

/// IDE configuration values for supported IDEs.
public struct IdeConfig: Equatable, Sendable {
    public let vscode: IdeAppConfig?
    public let antigravity: IdeAppConfig?

    /// Creates IDE configuration values.
    /// - Parameters:
    ///   - vscode: VS Code configuration values.
    ///   - antigravity: Antigravity configuration values.
    public init(vscode: IdeAppConfig?, antigravity: IdeAppConfig?) {
        self.vscode = vscode
        self.antigravity = antigravity
    }
}

/// IDE app configuration details.
public struct IdeAppConfig: Equatable, Sendable {
    public let appPath: String?
    public let bundleId: String?

    /// Creates an IDE app configuration.
    /// - Parameters:
    ///   - appPath: Full path to the `.app` bundle, if provided.
    ///   - bundleId: Bundle identifier, if provided.
    public init(appPath: String?, bundleId: String?) {
        self.appPath = appPath
        self.bundleId = bundleId
    }
}

/// Project-level configuration values.
public struct ProjectConfig: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let colorHex: String
    public let ide: IdeKind
    public let chromeUrls: [String]
    public let chromeProfileDirectory: String?

    /// Creates a project configuration entry.
    /// - Parameters:
    ///   - id: Project identifier.
    ///   - name: Human-readable project name.
    ///   - path: Path to the project directory.
    ///   - colorHex: Project color in `#RRGGBB` format.
    ///   - ide: IDE selection for this project.
    ///   - chromeUrls: Chrome URLs to open when the project Chrome window is created.
    ///   - chromeProfileDirectory: Optional Chrome profile directory name used for the project.
    public init(
        id: String,
        name: String,
        path: String,
        colorHex: String,
        ide: IdeKind,
        chromeUrls: [String],
        chromeProfileDirectory: String?
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.colorHex = colorHex
        self.ide = ide
        self.chromeUrls = chromeUrls
        self.chromeProfileDirectory = chromeProfileDirectory
    }
}
