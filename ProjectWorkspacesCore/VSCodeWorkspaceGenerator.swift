import Foundation

/// Errors produced while generating or writing VS Code workspace files.
public enum VSCodeWorkspaceError: Error, Equatable, Sendable {
    case invalidColorHex(String)
    case encodeFailed(String)
    case createDirectoryFailed(String)
    case writeFailed(String)
}

/// Generates VS Code workspace files with project-specific identity settings.
public struct VSCodeWorkspaceGenerator {
    private let paths: ProjectWorkspacesPaths
    private let fileSystem: FileSystem
    private let palette: VSCodeColorPalette

    /// Creates a workspace generator.
    /// - Parameters:
    ///   - paths: ProjectWorkspaces filesystem paths.
    ///   - fileSystem: File system accessor.
    ///   - palette: Color palette builder.
    public init(
        paths: ProjectWorkspacesPaths = .defaultPaths(),
        fileSystem: FileSystem = DefaultFileSystem(),
        palette: VSCodeColorPalette = VSCodeColorPalette()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.palette = palette
    }

    /// Builds workspace JSON data for a project.
    /// - Parameter project: Project configuration entry.
    /// - Returns: Encoded JSON data or an error.
    public func generateWorkspaceData(for project: ProjectConfig) -> Result<Data, VSCodeWorkspaceError> {
        switch palette.customizations(for: project.colorHex) {
        case .failure:
            return .failure(.invalidColorHex(project.colorHex))
        case .success(let customizations):
            let workspace = VSCodeWorkspaceFile(
                folders: [VSCodeWorkspaceFolder(path: project.path)],
                settings: VSCodeWorkspaceSettings(colorCustomizations: customizations)
            )
            return encode(workspace: workspace)
        }
    }

    /// Writes the VS Code workspace file for a project.
    /// - Parameter project: Project configuration entry.
    /// - Returns: URL of the written workspace file or an error.
    public func writeWorkspace(for project: ProjectConfig) -> Result<URL, VSCodeWorkspaceError> {
        let dataResult = generateWorkspaceData(for: project)
        switch dataResult {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            let directory = paths.vscodeWorkspaceDirectory
            do {
                try fileSystem.createDirectory(at: directory)
            } catch {
                return .failure(.createDirectoryFailed(String(describing: error)))
            }
            let fileURL = paths.vscodeWorkspaceFile(projectId: project.id)
            do {
                try fileSystem.writeFile(at: fileURL, data: data)
            } catch {
                return .failure(.writeFailed(String(describing: error)))
            }
            return .success(fileURL)
        }
    }

    private func encode(workspace: VSCodeWorkspaceFile) -> Result<Data, VSCodeWorkspaceError> {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(workspace)
            return .success(data)
        } catch {
            return .failure(.encodeFailed(String(describing: error)))
        }
    }
}

private struct VSCodeWorkspaceFile: Encodable, Equatable {
    let folders: [VSCodeWorkspaceFolder]
    let settings: VSCodeWorkspaceSettings
}

private struct VSCodeWorkspaceFolder: Encodable, Equatable {
    let path: String
}

private struct VSCodeWorkspaceSettings: Encodable, Equatable {
    let colorCustomizations: VSCodeColorCustomizations

    enum CodingKeys: String, CodingKey {
        case colorCustomizations = "workbench.colorCustomizations"
    }
}
