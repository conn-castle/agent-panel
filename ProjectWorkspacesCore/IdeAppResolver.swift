import Foundation

/// Resolved application metadata for an IDE.
public struct IdeAppResolution: Equatable, Sendable {
    public let appURL: URL
    public let bundleId: String?

    /// Creates an app resolution payload.
    /// - Parameters:
    ///   - appURL: Resolved `.app` URL.
    ///   - bundleId: Bundle identifier, if available.
    public init(appURL: URL, bundleId: String?) {
        self.appURL = appURL
        self.bundleId = bundleId
    }
}

/// Errors that occur while resolving IDE applications.
public enum IdeAppResolutionError: Error, Equatable, Sendable {
    case configuredPathMissing(String)
    case configuredBundleIdNotFound(String)
    case configuredValuesMismatch(appPath: String, bundlePath: String)
    case appNotFound(ide: IdeKind)
}

/// Resolves IDE application paths using config and Launch Services.
public struct IdeAppResolver {
    private let fileSystem: FileSystem
    private let appDiscovery: AppDiscovering

    /// Creates an IDE app resolver.
    /// - Parameters:
    ///   - fileSystem: File system accessor.
    ///   - appDiscovery: Application discovery provider.
    public init(
        fileSystem: FileSystem = DefaultFileSystem(),
        appDiscovery: AppDiscovering = LaunchServicesAppDiscovery()
    ) {
        self.fileSystem = fileSystem
        self.appDiscovery = appDiscovery
    }

    /// Resolves the application URL for the requested IDE.
    /// - Parameters:
    ///   - ide: IDE identifier.
    ///   - config: IDE configuration values, if any.
    /// - Returns: Resolved app metadata or an error.
    public func resolve(ide: IdeKind, config: IdeAppConfig?) -> Result<IdeAppResolution, IdeAppResolutionError> {
        let configAppPath = config?.appPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let configBundleId = config?.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines)

        var resolvedAppURL: URL?
        var resolvedBundleId: String?

        if let configAppPath, !configAppPath.isEmpty {
            let appURL = URL(fileURLWithPath: configAppPath, isDirectory: true)
            guard fileSystem.directoryExists(at: appURL) else {
                return .failure(.configuredPathMissing(configAppPath))
            }
            resolvedAppURL = appURL
        }

        if let configBundleId, !configBundleId.isEmpty {
            guard let bundleURL = appDiscovery.applicationURL(bundleIdentifier: configBundleId) else {
                return .failure(.configuredBundleIdNotFound(configBundleId))
            }
            if let resolvedAppURL, resolvedAppURL.standardizedFileURL.path != bundleURL.standardizedFileURL.path {
                return .failure(.configuredValuesMismatch(appPath: resolvedAppURL.path, bundlePath: bundleURL.path))
            }
            resolvedAppURL = bundleURL
            resolvedBundleId = configBundleId
        }

        if resolvedAppURL == nil {
            switch ide {
            case .vscode:
                if let bundleURL = appDiscovery.applicationURL(bundleIdentifier: "com.microsoft.VSCode") {
                    resolvedAppURL = bundleURL
                    resolvedBundleId = "com.microsoft.VSCode"
                }
            case .antigravity:
                if let appURL = appDiscovery.applicationURL(named: "Antigravity") {
                    resolvedAppURL = appURL
                }
            }
        }

        if let resolvedAppURL, resolvedBundleId == nil {
            resolvedBundleId = appDiscovery.bundleIdentifier(forApplicationAt: resolvedAppURL)
        }

        guard let resolvedAppURL else {
            return .failure(.appNotFound(ide: ide))
        }

        return .success(IdeAppResolution(appURL: resolvedAppURL, bundleId: resolvedBundleId))
    }
}
