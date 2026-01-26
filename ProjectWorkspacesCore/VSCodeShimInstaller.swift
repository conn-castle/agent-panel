import Foundation

/// Errors returned when installing the VS Code shim script.
public enum VSCodeShimError: Error, Equatable, Sendable {
    case createDirectoryFailed(String)
    case writeFailed(String)
    case permissionsFailed(String)
}

/// Installs the ProjectWorkspaces-managed VS Code shim script.
public struct VSCodeShimInstaller {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let permissions: FilePermissionsSetting

    /// Creates a shim installer.
    /// - Parameters:
    ///   - paths: ProjectWorkspaces filesystem paths.
    ///   - fileSystem: File system accessor.
    ///   - permissions: File permissions setter.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        permissions: FilePermissionsSetting = DefaultFilePermissions()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.permissions = permissions
    }

    /// Ensures the VS Code shim script is installed and executable.
    /// - Returns: URL of the shim script or an error.
    public func ensureShimInstalled() -> Result<URL, VSCodeShimError> {
        let shimURL = paths.codeShimPath
        let shimDirectory = shimURL.deletingLastPathComponent()

        do {
            try fileSystem.createDirectory(at: shimDirectory)
        } catch {
            return .failure(.createDirectoryFailed(String(describing: error)))
        }

        let script = VSCodeShimInstaller.scriptContents()
        guard let data = script.data(using: .utf8) else {
            return .failure(.writeFailed("Unable to encode shim script as UTF-8."))
        }

        if isShimUpToDate(at: shimURL, expectedData: data) {
            do {
                try permissions.setExecutable(at: shimURL)
            } catch {
                return .failure(.permissionsFailed(String(describing: error)))
            }
            return .success(shimURL)
        }

        do {
            try fileSystem.writeFile(at: shimURL, data: data)
        } catch {
            return .failure(.writeFailed(String(describing: error)))
        }

        do {
            try permissions.setExecutable(at: shimURL)
        } catch {
            return .failure(.permissionsFailed(String(describing: error)))
        }

        return .success(shimURL)
    }

    /// Checks whether the existing shim matches the expected content.
    /// - Parameters:
    ///   - url: Shim file URL.
    ///   - expectedData: Expected shim content.
    /// - Returns: True when the existing shim is up to date.
    private func isShimUpToDate(at url: URL, expectedData: Data) -> Bool {
        guard fileSystem.fileExists(at: url),
              fileSystem.isExecutableFile(at: url) else {
            return false
        }
        guard let existingData = try? fileSystem.readFile(at: url) else {
            return false
        }
        return existingData == expectedData
    }

    private static func scriptContents() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        app_path=""

        if [[ -n "${PW_VSCODE_APP_PATH:-}" && -d "${PW_VSCODE_APP_PATH}" ]]; then
          app_path="${PW_VSCODE_APP_PATH}"
        elif [[ -n "${PW_VSCODE_CONFIG_APP_PATH:-}" && -d "${PW_VSCODE_CONFIG_APP_PATH}" ]]; then
          app_path="${PW_VSCODE_CONFIG_APP_PATH}"
        elif [[ -d "/Applications/Visual Studio Code.app" ]]; then
          app_path="/Applications/Visual Studio Code.app"
        else
          bundle_id="${PW_VSCODE_CONFIG_BUNDLE_ID:-com.microsoft.VSCode}"
          if [[ -n "${bundle_id}" ]]; then
            found_path=$(/usr/bin/mdfind "kMDItemCFBundleIdentifier == '${bundle_id}'" | /usr/bin/head -n 1)
            if [[ -n "${found_path}" && -d "${found_path}" ]]; then
              app_path="${found_path}"
            fi
          fi
        fi

        if [[ -z "${app_path}" ]]; then
          echo "error: VS Code app not found" >&2
          exit 1
        fi

        cli_path="${app_path}/Contents/Resources/app/bin/code"
        if [[ ! -x "${cli_path}" ]]; then
          echo "error: VS Code CLI not found at ${cli_path}" >&2
          exit 1
        fi

        exec "${cli_path}" "$@"
        """
    }
}
