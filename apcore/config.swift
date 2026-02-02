import Foundation

/// Parsed configuration for the ap CLI.
public struct ApConfig: Equatable {
    /// Config file URL.
    public let url: URL
    /// Raw config contents.
    public let raw: String
    /// Entries from the [global] table.
    public let global: [String: String]
    /// Entries from [ide.*] tables keyed by ide name.
    public let ide: [String: [String: String]]
    /// Entries from [[project]] array tables.
    public let projects: [[String: String]]
    /// Entries from other single tables.
    public let extraTables: [String: [String: String]]
    /// Entries from other array tables.
    public let extraArrayTables: [String: [[String: String]]]

    private static let configRelativePath = ".config/project-workspaces/config.toml"

    /// Loads and parses the default config file.
    /// - Returns: Parsed config on success, or an error.
    public static func loadDefault() -> Result<ApConfig, ApCoreError> {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(configRelativePath)
        return load(from: url)
    }

    /// Loads and parses a config file at the given URL.
    /// - Parameter url: File URL to read.
    /// - Returns: Parsed config on success, or an error.
    public static func load(from url: URL) -> Result<ApConfig, ApCoreError> {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(ApCoreError(message: "Config file not found at \(path)"))
        }

        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return .failure(
                ApCoreError(message: "Failed to read file at \(path): \(error.localizedDescription)")
            )
        }

        return parse(raw: raw, url: url)
    }

    /// Parses raw TOML into a structured ApConfig.
    /// - Parameters:
    ///   - raw: Raw TOML contents.
    ///   - url: Source URL for reference in errors.
    /// - Returns: Parsed config on success, or an error.
    private static func parse(raw: String, url: URL) -> Result<ApConfig, ApCoreError> {
        var global: [String: String] = [:]
        var ide: [String: [String: String]] = [:]
        var projects: [[String: String]] = []
        var extraTables: [String: [String: String]] = [:]
        var extraArrayTables: [String: [[String: String]]] = [:]

        enum Section {
            case global
            case ide(String)
            case project(Int)
            case extra(String)
            case extraArray(String, Int)
        }

        var currentSection: Section? = nil

        func setValue(key: String, value: String, section: Section) -> Result<Void, ApCoreError> {
            switch section {
            case .global:
                global[key] = value
            case .ide(let name):
                var table = ide[name] ?? [:]
                table[key] = value
                ide[name] = table
            case .project(let index):
                guard projects.indices.contains(index) else {
                    return .failure(
                        ApCoreError(message: "Project index out of range while parsing \(url.path)")
                    )
                }
                var table = projects[index]
                table[key] = value
                projects[index] = table
            case .extra(let name):
                var table = extraTables[name] ?? [:]
                table[key] = value
                extraTables[name] = table
            case .extraArray(let name, let index):
                guard var tables = extraArrayTables[name], tables.indices.contains(index) else {
                    return .failure(
                        ApCoreError(message: "Array table \(name) index out of range while parsing \(url.path)")
                    )
                }
                var table = tables[index]
                table[key] = value
                tables[index] = table
                extraArrayTables[name] = tables
            }
            return .success(())
        }

        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            if line.hasPrefix("[[") {
                guard line.hasSuffix("]]"), line.count >= 4 else {
                    return .failure(
                        ApCoreError(message: "Invalid array table header at line \(lineNumber): \(line)")
                    )
                }
                let name = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                if name.isEmpty {
                    return .failure(
                        ApCoreError(message: "Empty array table header at line \(lineNumber)")
                    )
                }

                if name == "project" {
                    projects.append([:])
                    currentSection = .project(projects.count - 1)
                } else {
                    var tables = extraArrayTables[name] ?? []
                    tables.append([:])
                    extraArrayTables[name] = tables
                    currentSection = .extraArray(name, tables.count - 1)
                }
                continue
            }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), line.count >= 2 else {
                    return .failure(
                        ApCoreError(message: "Invalid table header at line \(lineNumber): \(line)")
                    )
                }
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if name.isEmpty {
                    return .failure(
                        ApCoreError(message: "Empty table header at line \(lineNumber)")
                    )
                }

                if name == "global" {
                    currentSection = .global
                } else if name.hasPrefix("ide.") {
                    let ideName = String(name.dropFirst(4))
                    if ideName.isEmpty {
                        return .failure(
                            ApCoreError(message: "Invalid ide table name at line \(lineNumber)")
                        )
                    }
                    if ide[ideName] == nil {
                        ide[ideName] = [:]
                    }
                    currentSection = .ide(ideName)
                } else {
                    if extraTables[name] == nil {
                        extraTables[name] = [:]
                    }
                    currentSection = .extra(name)
                }
                continue
            }

            guard let section = currentSection else {
                return .failure(
                    ApCoreError(message: "Key/value found before any table at line \(lineNumber): \(line)")
                )
            }

            guard let equalsIndex = line.firstIndex(of: "=") else {
                return .failure(
                    ApCoreError(message: "Invalid key/value at line \(lineNumber): \(line)")
                )
            }

            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces)

            if key.isEmpty {
                return .failure(
                    ApCoreError(message: "Empty key at line \(lineNumber): \(line)")
                )
            }

            switch setValue(key: key, value: value, section: section) {
            case .failure(let error):
                return .failure(error)
            case .success:
                break
            }
        }

        return .success(
            ApConfig(
                url: url,
                raw: raw,
                global: global,
                ide: ide,
                projects: projects,
                extraTables: extraTables,
                extraArrayTables: extraArrayTables
            )
        )
    }
}
