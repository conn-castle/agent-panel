import Foundation

/// Describes a Chrome profile as stored in Chrome's Local State metadata.
struct ChromeProfileDescriptor: Equatable, Sendable {
    /// Profile directory name used by `--profile-directory`.
    let directory: String
    /// Display name shown inside Chrome's profile UI.
    let displayName: String?
    /// Optional user name / email shown for the profile.
    let userName: String?

    /// Creates a Chrome profile descriptor.
    /// - Parameters:
    ///   - directory: Profile directory name (for `--profile-directory`).
    ///   - displayName: Human-readable profile name.
    ///   - userName: Optional user name/email for the profile.
    init(directory: String, displayName: String?, userName: String?) {
        self.directory = directory
        self.displayName = displayName
        self.userName = userName
    }
}

/// Errors returned while reading Chrome profile metadata.
enum ChromeProfileDiscoveryError: Error, Equatable, CustomStringConvertible {
    case localStateMissing(path: String)
    case readFailed(path: String, error: String)
    case malformed(path: String, error: String)

    var description: String {
        switch self {
        case .localStateMissing(let path):
            return "Chrome Local State not found at \(path)"
        case .readFailed(let path, let error):
            return "Chrome Local State could not be read at \(path): \(error)"
        case .malformed(let path, let error):
            return "Chrome Local State is malformed at \(path): \(error)"
        }
    }
}

/// Discovers Chrome profile directories by reading Chrome's Local State file.
struct ChromeProfileDiscovery {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem

    /// Creates a Chrome profile discovery helper.
    /// - Parameters:
    ///   - paths: ProjectWorkspaces filesystem paths.
    ///   - fileSystem: File system accessor.
    init(paths: ProjectWorkspacesPaths, fileSystem: FileSystem) {
        self.paths = paths
        self.fileSystem = fileSystem
    }

    /// Discovers Chrome profiles from Chrome's Local State file.
    /// - Returns: Profile descriptors or a structured error.
    func discoverProfiles() -> Result<[ChromeProfileDescriptor], ChromeProfileDiscoveryError> {
        let localStateURL = paths.chromeLocalStateFile
        guard fileSystem.fileExists(at: localStateURL) else {
            return .failure(.localStateMissing(path: localStateURL.path))
        }

        let data: Data
        do {
            data = try fileSystem.readFile(at: localStateURL)
        } catch {
            return .failure(.readFailed(path: localStateURL.path, error: String(describing: error)))
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            return .failure(.malformed(path: localStateURL.path, error: String(describing: error)))
        }

        guard let root = jsonObject as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return .failure(.malformed(path: localStateURL.path, error: "Missing profile.info_cache"))
        }

        var profiles: [ChromeProfileDescriptor] = []
        for (directory, rawEntry) in infoCache {
            guard let entry = rawEntry as? [String: Any] else {
                continue
            }
            let displayName = entry["name"] as? String
            let userName = entry["user_name"] as? String
            profiles.append(
                ChromeProfileDescriptor(
                    directory: directory,
                    displayName: displayName,
                    userName: userName
                )
            )
        }

        let sorted = profiles.sorted { $0.directory.localizedCaseInsensitiveCompare($1.directory) == .orderedAscending }
        return .success(sorted)
    }
}
