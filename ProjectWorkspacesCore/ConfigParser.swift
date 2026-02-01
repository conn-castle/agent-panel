import Foundation
import TOMLDecoder

/// Parsed configuration outcome used by Doctor.
struct ConfigParseOutcome: Sendable {
    let config: Config?
    let findings: [DoctorFinding]
    let effectiveIdeKinds: Set<IdeKind>
    let ideConfig: IdeConfig
    let projects: [ProjectConfig]
}

/// Parses `config.toml` into typed models and diagnostics.
struct ConfigParser {
    /// Parses a TOML string into configuration models and findings.
    /// - Parameter toml: TOML document as a string.
    /// - Returns: Parsed configuration outcome with findings.
    func parse(toml: String) -> ConfigParseOutcome {
        do {
            let table = try TOMLTable(source: toml)
            return parse(table: table)
        } catch {
            return ConfigParseOutcome(
                config: nil,
                findings: [
                    DoctorFinding(
                        severity: .fail,
                        title: "Config TOML parse error",
                        detail: String(describing: error),
                        fix: "Fix the TOML syntax in config.toml and re-run pwctl doctor."
                    )
                ],
                effectiveIdeKinds: [],
                ideConfig: IdeConfig(vscode: nil, antigravity: nil),
                projects: []
            )
        }
    }

    /// Parses a TOML table into configuration models and findings.
    /// - Parameter table: Root TOML table.
    /// - Returns: Parsed configuration outcome with findings.
    func parse(table: TOMLTable) -> ConfigParseOutcome {
        var findings: [DoctorFinding] = []
        var unknownKeyPaths: [String] = []
        var effectiveIdeKinds = Set<IdeKind>()

        unknownKeyPaths.append(contentsOf: collectUnknownKeys(
            in: table,
            allowedKeys: ["global", "ide", "project"],
            prefix: nil
        ))

        let globalOutcome = parseGlobal(table: table, findings: &findings, unknownKeyPaths: &unknownKeyPaths)
        let ideOutcome = parseIdeConfig(table: table, findings: &findings, unknownKeyPaths: &unknownKeyPaths)

        let projectOutcomes = parseProjects(
            table: table,
            defaultIde: globalOutcome.defaultIde,
            findings: &findings,
            unknownKeyPaths: &unknownKeyPaths
        )

        for projectOutcome in projectOutcomes {
            if let ide = projectOutcome.effectiveIde {
                effectiveIdeKinds.insert(ide)
            }
        }

        if !unknownKeyPaths.isEmpty {
            let sortedKeys = Array(Set(unknownKeyPaths)).sorted()
            let detail = sortedKeys.map { "- \($0)" }.joined(separator: "\n")
            findings.append(
                DoctorFinding(
                    severity: .warn,
                    title: "Unknown config keys",
                    detail: detail,
                    fix: "Remove unsupported keys or update the config to match the documented schema."
                )
            )
        }

        let validationFailed = findings.contains { $0.severity == .fail }
        let parsedProjects = projectOutcomes.compactMap { $0.config }

        let config: Config?
        if validationFailed {
            config = nil
        } else {
            guard let global = globalOutcome.config else {
                config = nil
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "Config defaults incomplete",
                        detail: "Global defaults could not be resolved.",
                        fix: "Ensure global.defaultIde is valid."
                    )
                )
                return ConfigParseOutcome(
                    config: nil,
                    findings: findings,
                    effectiveIdeKinds: effectiveIdeKinds,
                    ideConfig: ideOutcome,
                    projects: parsedProjects
                )
            }

            config = Config(
                global: global,
                ide: ideOutcome,
                projects: parsedProjects
            )
        }

        return ConfigParseOutcome(
            config: config,
            findings: findings,
            effectiveIdeKinds: effectiveIdeKinds,
            ideConfig: ideOutcome,
            projects: parsedProjects
        )
    }

    private struct GlobalOutcome {
        let config: GlobalConfig?
        let defaultIde: IdeKind?
    }

    private struct ProjectOutcome {
        let config: ProjectConfig?
        let effectiveIde: IdeKind?
    }

    /// Represents the outcome of parsing a single config field.
    private enum FieldResult<Value> {
        case missing
        case invalid
        case value(Value)
    }

    /// Parses the global config table and emits findings.
    private func parseGlobal(
        table: TOMLTable,
        findings: inout [DoctorFinding],
        unknownKeyPaths: inout [String]
    ) -> GlobalOutcome {
        var defaultIde: IdeKind?
        var globalChromeUrls: [String]?

        if table.contains(key: "global") {
            guard let globalTable = try? table.table(forKey: "global") else {
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "global must be a table",
                        fix: "Replace global with a TOML table: [global]"
                    )
                )
                return GlobalOutcome(config: nil, defaultIde: nil)
            }

            unknownKeyPaths.append(contentsOf: collectUnknownKeys(
                in: globalTable,
                allowedKeys: ["defaultIde", "globalChromeUrls", "switcherHotkey"],
                prefix: "global"
            ))

            if globalTable.contains(key: "switcherHotkey") {
                findings.append(
                    DoctorFinding(
                        severity: .warn,
                        title: "global.switcherHotkey is ignored",
                        detail: "Hotkey is fixed to Cmd+Shift+Space; the configured value is ignored.",
                        fix: "Remove global.switcherHotkey from config.toml."
                    )
                )
            }

            switch readStringField(from: globalTable, key: "defaultIde", keyPath: "global.defaultIde", findings: &findings) {
            case .value(let rawDefaultIde):
                if let ide = IdeKind(rawValue: rawDefaultIde) {
                    defaultIde = ide
                } else {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "global.defaultIde is invalid",
                            detail: "Value must be one of: vscode, antigravity.",
                            fix: "Set global.defaultIde to \"vscode\" or \"antigravity\"."
                        )
                    )
                }
            case .missing:
                defaultIde = .vscode
                findings.append(defaultFinding(
                    severity: .warn,
                    title: "Default applied: global.defaultIde = \"vscode\"",
                    fix: "Add global.defaultIde to config.toml to make the default explicit."
                ))
            case .invalid:
                break
            }

            switch readStringArrayField(
                from: globalTable,
                key: "globalChromeUrls",
                keyPath: "global.globalChromeUrls",
                findings: &findings
            ) {
            case .value(let urls):
                globalChromeUrls = urls
            case .missing:
                globalChromeUrls = []
                findings.append(defaultFinding(
                    severity: .warn,
                    title: "Default applied: global.globalChromeUrls = []",
                    fix: "Add global.globalChromeUrls to config.toml to make the default explicit."
                ))
            case .invalid:
                break
            }
        } else {
            defaultIde = .vscode
            findings.append(defaultFinding(
                severity: .warn,
                title: "Default applied: global.defaultIde = \"vscode\"",
                fix: "Add [global] with defaultIde to config.toml to make the default explicit."
            ))
            globalChromeUrls = []
            findings.append(defaultFinding(
                severity: .warn,
                title: "Default applied: global.globalChromeUrls = []",
                fix: "Add [global] with globalChromeUrls to config.toml to make the default explicit."
            ))
        }

        let config: GlobalConfig?
        if let defaultIde, let globalChromeUrls {
            config = GlobalConfig(defaultIde: defaultIde, globalChromeUrls: globalChromeUrls)
        } else {
            config = nil
        }

        return GlobalOutcome(config: config, defaultIde: defaultIde)
    }

    /// Parses the IDE config table.
    private func parseIdeConfig(
        table: TOMLTable,
        findings: inout [DoctorFinding],
        unknownKeyPaths: inout [String]
    ) -> IdeConfig {
        var vscodeConfig: IdeAppConfig?
        var antigravityConfig: IdeAppConfig?

        if table.contains(key: "ide") {
            guard let ideTable = try? table.table(forKey: "ide") else {
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "ide must be a table",
                        fix: "Replace ide with a TOML table: [ide]"
                    )
                )
                return IdeConfig(vscode: nil, antigravity: nil)
            }

            unknownKeyPaths.append(contentsOf: collectUnknownKeys(
                in: ideTable,
                allowedKeys: ["vscode", "antigravity"],
                prefix: "ide"
            ))

            if ideTable.contains(key: "vscode") {
                vscodeConfig = parseIdeAppConfig(
                    parent: ideTable,
                    key: "vscode",
                    prefix: "ide.vscode",
                    findings: &findings,
                    unknownKeyPaths: &unknownKeyPaths
                )
            }

            if ideTable.contains(key: "antigravity") {
                antigravityConfig = parseIdeAppConfig(
                    parent: ideTable,
                    key: "antigravity",
                    prefix: "ide.antigravity",
                    findings: &findings,
                    unknownKeyPaths: &unknownKeyPaths
                )
            }
        }

        return IdeConfig(vscode: vscodeConfig, antigravity: antigravityConfig)
    }

    /// Parses a single IDE app table.
    private func parseIdeAppConfig(
        parent: TOMLTable,
        key: String,
        prefix: String,
        findings: inout [DoctorFinding],
        unknownKeyPaths: inout [String]
    ) -> IdeAppConfig? {
        guard let appTable = try? parent.table(forKey: key) else {
            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "\(prefix) must be a table",
                    fix: "Replace \(prefix) with a TOML table."
                )
            )
            return nil
        }

        unknownKeyPaths.append(contentsOf: collectUnknownKeys(
            in: appTable,
            allowedKeys: ["appPath", "bundleId"],
            prefix: prefix
        ))

        let appPath = valueOrNil(readStringField(from: appTable, key: "appPath", keyPath: "\(prefix).appPath", findings: &findings))
        let bundleId = valueOrNil(readStringField(from: appTable, key: "bundleId", keyPath: "\(prefix).bundleId", findings: &findings))

        return IdeAppConfig(appPath: appPath, bundleId: bundleId)
    }

    /// Parses project entries and emits findings.
    private func parseProjects(
        table: TOMLTable,
        defaultIde: IdeKind?,
        findings: inout [DoctorFinding],
        unknownKeyPaths: inout [String]
    ) -> [ProjectOutcome] {
        guard table.contains(key: "project") else {
            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "No [[project]] entries",
                    fix: "Add at least one [[project]] entry to config.toml."
                )
            )
            return []
        }

        guard let projectsArray = try? table.array(forKey: "project") else {
            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "project must be an array of tables",
                    fix: "Use [[project]] entries in config.toml."
                )
            )
            return []
        }

        if projectsArray.count == 0 {
            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "No [[project]] entries",
                    fix: "Add at least one [[project]] entry to config.toml."
                )
            )
            return []
        }

        var outcomes: [ProjectOutcome] = []
        var seenIds: [String: Int] = [:]
        var duplicateIds: [String] = []

        for index in 0..<projectsArray.count {
            guard let projectTable = try? projectsArray.table(atIndex: index) else {
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "project[\(index)] must be a table",
                        fix: "Ensure each [[project]] entry is a TOML table."
                    )
                )
                outcomes.append(ProjectOutcome(config: nil, effectiveIde: nil))
                continue
            }

            unknownKeyPaths.append(contentsOf: collectUnknownKeys(
                in: projectTable,
                allowedKeys: [
                    "id",
                    "name",
                    "path",
                    "colorHex",
                    "ide",
                    "chromeUrls",
                    "chromeProfileDirectory"
                ],
                prefix: "project[\(index)]"
            ))

            let idResult = readStringField(from: projectTable, key: "id", keyPath: "project[\(index)].id", findings: &findings)
            let nameResult = readStringField(from: projectTable, key: "name", keyPath: "project[\(index)].name", findings: &findings)
            let pathResult = readStringField(from: projectTable, key: "path", keyPath: "project[\(index)].path", findings: &findings)
            let colorHexResult = readStringField(from: projectTable, key: "colorHex", keyPath: "project[\(index)].colorHex", findings: &findings)
            let id = valueOrNil(idResult)
            let name = valueOrNil(nameResult)
            let path = valueOrNil(pathResult)
            let colorHex = valueOrNil(colorHexResult)

            enum IdeResolutionStatus {
                case resolved(IdeKind)
                case missing
                case invalid
            }

            let ideStatus: IdeResolutionStatus
            switch readStringField(from: projectTable, key: "ide", keyPath: "project[\(index)].ide", findings: &findings) {
            case .value(let rawIde):
                if let ide = IdeKind(rawValue: rawIde) {
                    ideStatus = .resolved(ide)
                } else {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "project[\(index)].ide is invalid",
                            detail: "Value must be one of: vscode, antigravity.",
                            fix: "Set project.ide to \"vscode\" or \"antigravity\"."
                        )
                    )
                    ideStatus = .invalid
                }
            case .missing:
                if let defaultIde {
                    findings.append(defaultFinding(
                        severity: .warn,
                        title: "Default applied: project[\(index)].ide = \"\(defaultIde.rawValue)\"",
                        fix: "Add project.ide to config.toml to make the default explicit."
                    ))
                    ideStatus = .resolved(defaultIde)
                } else {
                    ideStatus = .missing
                }
            case .invalid:
                ideStatus = .invalid
            }

            let resolvedIde: IdeKind?
            switch ideStatus {
            case .resolved(let ide):
                resolvedIde = ide
            case .missing, .invalid:
                resolvedIde = nil
            }

            let chromeUrls: [String]?
            switch readStringArrayField(
                from: projectTable,
                key: "chromeUrls",
                keyPath: "project[\(index)].chromeUrls",
                findings: &findings
            ) {
            case .value(let urls):
                chromeUrls = urls
            case .missing:
                chromeUrls = []
                findings.append(defaultFinding(
                    severity: .warn,
                    title: "Default applied: project[\(index)].chromeUrls = []",
                    fix: "Add project.chromeUrls to config.toml if you want to override."
                ))
            case .invalid:
                chromeUrls = nil
            }

            let chromeProfileDirectory: String?
            let chromeProfileDirectoryIsValid: Bool
            switch readStringField(
                from: projectTable,
                key: "chromeProfileDirectory",
                keyPath: "project[\(index)].chromeProfileDirectory",
                findings: &findings
            ) {
            case .value(let directory):
                if directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "project[\(index)].chromeProfileDirectory is empty",
                            fix: "Set project.chromeProfileDirectory to a non-empty Chrome profile directory name."
                        )
                    )
                    chromeProfileDirectory = nil
                    chromeProfileDirectoryIsValid = false
                } else {
                    chromeProfileDirectory = directory
                    chromeProfileDirectoryIsValid = true
                }
            case .missing:
                chromeProfileDirectory = nil
                chromeProfileDirectoryIsValid = true
            case .invalid:
                chromeProfileDirectory = nil
                chromeProfileDirectoryIsValid = false
            }

            var projectIsValid = true

            switch idResult {
            case .value(let idValue):
                if idValue == "inbox" {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "project[\(index)].id is reserved",
                            detail: "The id 'inbox' is reserved for the fallback workspace.",
                            fix: "Choose a different project id."
                        )
                    )
                    projectIsValid = false
                } else if !isValidProjectId(idValue) {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "project[\(index)].id is invalid",
                            detail: "Project ids must match ^[a-z0-9-]+$.",
                            fix: "Use lowercase letters, numbers, and hyphens only."
                        )
                    )
                    projectIsValid = false
                } else if let existingIndex = seenIds[idValue] {
                    duplicateIds.append("\(idValue) (indexes \(existingIndex), \(index))")
                    projectIsValid = false
                } else {
                    seenIds[idValue] = index
                }
            case .missing:
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "project[\(index)].id is missing",
                        fix: "Set project.id to a unique value (lowercase letters, numbers, and hyphens)."
                    )
                )
                projectIsValid = false
            case .invalid:
                projectIsValid = false
            }

            switch nameResult {
            case .value(let nameValue):
                if nameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "project[\(index)].name is empty",
                            fix: "Set project.name to a non-empty string."
                        )
                    )
                    projectIsValid = false
                }
            case .missing:
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "project[\(index)].name is missing",
                        fix: "Set project.name to a non-empty string."
                    )
                )
                projectIsValid = false
            case .invalid:
                projectIsValid = false
            }

            switch pathResult {
            case .value(let pathValue):
                if pathValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "project[\(index)].path is empty",
                            fix: "Set project.path to an existing directory."
                        )
                    )
                    projectIsValid = false
                }
            case .missing:
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "project[\(index)].path is missing",
                        fix: "Set project.path to an existing directory."
                    )
                )
                projectIsValid = false
            case .invalid:
                projectIsValid = false
            }

            switch colorHexResult {
            case .value(let colorHexValue):
                if !isValidColorHex(colorHexValue) {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "project[\(index)].colorHex is invalid",
                            detail: "Color must match #RRGGBB.",
                            fix: "Set project.colorHex to a valid hex color like #7C3AED."
                        )
                    )
                    projectIsValid = false
                }
            case .missing:
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "project[\(index)].colorHex is missing",
                        fix: "Set project.colorHex to a valid hex color like #7C3AED."
                    )
                )
                projectIsValid = false
            case .invalid:
                projectIsValid = false
            }

            switch ideStatus {
            case .resolved:
                break
            case .missing:
                findings.append(
                    DoctorFinding(
                        severity: .fail,
                        title: "project[\(index)].ide is unresolved",
                        fix: "Set project.ide explicitly or ensure global.defaultIde is valid."
                    )
                )
                projectIsValid = false
            case .invalid:
                projectIsValid = false
            }

            if chromeUrls == nil {
                projectIsValid = false
            }

            if !chromeProfileDirectoryIsValid {
                projectIsValid = false
            }

            if projectIsValid,
               let id,
               let name,
               let path,
               let colorHex,
               let resolvedIde,
               let chromeUrls {
                let projectConfig = ProjectConfig(
                    id: id,
                    name: name,
                    path: path,
                    colorHex: colorHex,
                    ide: resolvedIde,
                    chromeUrls: chromeUrls,
                    chromeProfileDirectory: chromeProfileDirectory
                )
                outcomes.append(ProjectOutcome(config: projectConfig, effectiveIde: resolvedIde))
            } else {
                outcomes.append(ProjectOutcome(config: nil, effectiveIde: resolvedIde))
            }
        }

        if !duplicateIds.isEmpty {
            let detail = duplicateIds.sorted().map { "- \($0)" }.joined(separator: "\n")
            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "Duplicate project.id values",
                    detail: detail,
                    fix: "Ensure each project.id is unique."
                )
            )
        }

        return outcomes
    }

    /// Converts a field result into an optional value.
    /// - Parameter result: Field result to unwrap.
    /// - Returns: Unwrapped value when present and valid.
    private func valueOrNil<Value>(_ result: FieldResult<Value>) -> Value? {
        switch result {
        case .value(let value):
            return value
        case .missing, .invalid:
            return nil
        }
    }

    /// Parses an optional string field from a TOML table.
    /// - Returns: Field result for the requested key.
    private func readStringField(
        from table: TOMLTable,
        key: String,
        keyPath: String,
        findings: inout [DoctorFinding]
    ) -> FieldResult<String> {
        guard table.contains(key: key) else {
            return .missing
        }

        do {
            return .value(try table.string(forKey: key))
        } catch {
            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "\(keyPath) must be a string",
                    detail: String(describing: error),
                    fix: "Set \(keyPath) to a TOML string."
                )
            )
            return .invalid
        }
    }

    /// Parses an optional array of strings from a TOML table.
    /// - Returns: Field result for the requested key.
    private func readStringArrayField(
        from table: TOMLTable,
        key: String,
        keyPath: String,
        findings: inout [DoctorFinding]
    ) -> FieldResult<[String]> {
        guard table.contains(key: key) else {
            return .missing
        }

        do {
            let array = try table.array(forKey: key)
            var values: [String] = []
            values.reserveCapacity(array.count)
            for index in 0..<array.count {
                do {
                    let value = try array.string(atIndex: index)
                    values.append(value)
                } catch {
                    findings.append(
                        DoctorFinding(
                            severity: .fail,
                            title: "\(keyPath)[\(index)] must be a string",
                            detail: String(describing: error),
                            fix: "Ensure every entry in \(keyPath) is a string."
                        )
                    )
                    return .invalid
                }
            }
            return .value(values)
        } catch {
            findings.append(
                DoctorFinding(
                    severity: .fail,
                    title: "\(keyPath) must be an array",
                    detail: String(describing: error),
                    fix: "Set \(keyPath) to a TOML array of strings."
                )
            )
            return .invalid
        }
    }

    /// Collects unknown keys from a TOML table.
    private func collectUnknownKeys(
        in table: TOMLTable,
        allowedKeys: Set<String>,
        prefix: String?
    ) -> [String] {
        var unknown: [String] = []

        for key in table.keys where !allowedKeys.contains(key) {
            let keyPrefix = prefix.map { "\($0).\(key)" } ?? key
            if let nestedTable = try? table.table(forKey: key) {
                let nestedKeys = collectAllKeyPaths(in: nestedTable, prefix: keyPrefix)
                unknown.append(contentsOf: nestedKeys.isEmpty ? [keyPrefix] : nestedKeys)
                continue
            }

            if let nestedArray = try? table.array(forKey: key) {
                let nestedKeys = collectAllKeyPaths(in: nestedArray, prefix: keyPrefix)
                unknown.append(contentsOf: nestedKeys.isEmpty ? [keyPrefix] : nestedKeys)
                continue
            }

            unknown.append(keyPrefix)
        }

        return unknown
    }

    /// Collects all nested key paths from a TOML table.
    private func collectAllKeyPaths(in table: TOMLTable, prefix: String) -> [String] {
        var paths: [String] = []

        for key in table.keys {
            let nextPrefix = "\(prefix).\(key)"
            if let nestedTable = try? table.table(forKey: key) {
                let nested = collectAllKeyPaths(in: nestedTable, prefix: nextPrefix)
                paths.append(contentsOf: nested.isEmpty ? [nextPrefix] : nested)
                continue
            }

            if let nestedArray = try? table.array(forKey: key) {
                let nested = collectAllKeyPaths(in: nestedArray, prefix: nextPrefix)
                paths.append(contentsOf: nested.isEmpty ? [nextPrefix] : nested)
                continue
            }

            paths.append(nextPrefix)
        }

        return paths
    }

    /// Collects all nested key paths from a TOML array.
    private func collectAllKeyPaths(in array: TOMLArray, prefix: String) -> [String] {
        guard array.count > 0 else {
            return [prefix]
        }

        if (try? array.table(atIndex: 0)) != nil {
            var paths: [String] = []
            for index in 0..<array.count {
                guard let table = try? array.table(atIndex: index) else {
                    return [prefix]
                }
                let tablePrefix = "\(prefix)[\(index)]"
                let nested = collectAllKeyPaths(in: table, prefix: tablePrefix)
                if nested.isEmpty {
                    paths.append(tablePrefix)
                } else {
                    paths.append(contentsOf: nested)
                }
            }
            return paths
        }

        if let _ = try? array.array(atIndex: 0) {
            return [prefix]
        }

        return [prefix]
    }

    /// Returns true when the project id matches the required pattern.
    private func isValidProjectId(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return !value.isEmpty && value.rangeOfCharacter(from: allowed.inverted) == nil
    }

    /// Returns true when the color matches `#RRGGBB`.
    private func isValidColorHex(_ value: String) -> Bool {
        guard value.count == 7, value.hasPrefix("#") else {
            return false
        }

        let hexDigits = value.dropFirst()
        return hexDigits.allSatisfy { character in
            switch character {
            case "0"..."9", "a"..."f", "A"..."F":
                return true
            default:
                return false
            }
        }
    }

    /// Creates a default finding for a missing config value.
    private func defaultFinding(
        severity: DoctorSeverity,
        title: String,
        fix: String
    ) -> DoctorFinding {
        DoctorFinding(
            severity: severity,
            title: title,
            fix: fix
        )
    }
}
