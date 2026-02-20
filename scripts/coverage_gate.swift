import Foundation

private func eprintln(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

private func die(_ message: String, exitCode: Int32) -> Never {
    eprintln(message)
    exit(exitCode)
}

struct ParsedArgs {
    let minPercent: Double
    let targetNames: [String]
}

private func parseArgs(_ rawArgs: [String]) -> ParsedArgs {
    var minPercent: Double?
    var targetNames: [String] = []

    var idx = 0
    while idx < rawArgs.count {
        let arg = rawArgs[idx]
        switch arg {
        case "--minPercent":
            let nextIdx = idx + 1
            guard nextIdx < rawArgs.count else {
                die("error: --minPercent requires a value", exitCode: 2)
            }
            guard let v = Double(rawArgs[nextIdx]) else {
                die("error: --minPercent must be a number (got: \(rawArgs[nextIdx]))", exitCode: 2)
            }
            minPercent = v
            idx += 2
        case "--target":
            let nextIdx = idx + 1
            guard nextIdx < rawArgs.count else {
                die("error: --target requires a value", exitCode: 2)
            }
            targetNames.append(rawArgs[nextIdx])
            idx += 2
        case "--help", "-h":
            die(
                """
                Usage:
                  coverage_gate.swift --minPercent <number> --target <name> [--target <name> ...]

                Reads Xcode coverage JSON from stdin (via `xcrun xccov view --report --json <xcresult>`),
                computes weighted coverage across the selected targets, and exits non-zero if below minPercent.
                """,
                exitCode: 0
            )
        default:
            die("error: unrecognized argument: \(arg)", exitCode: 2)
        }
    }

    guard let minPercent else {
        die("error: missing required argument: --minPercent", exitCode: 2)
    }
    guard !targetNames.isEmpty else {
        die("error: missing required argument(s): --target <name>", exitCode: 2)
    }

    return ParsedArgs(minPercent: minPercent, targetNames: targetNames)
}

struct FileCoverage {
    let name: String
    let coveredLines: Int
    let executableLines: Int

    var percent: Double {
        guard executableLines > 0 else { return 0.0 }
        return (Double(coveredLines) / Double(executableLines)) * 100.0
    }
}

struct TargetCoverage {
    let name: String
    let coveredLines: Int
    let executableLines: Int
    let files: [FileCoverage]

    var percent: Double {
        guard executableLines > 0 else { return 0.0 }
        return (Double(coveredLines) / Double(executableLines)) * 100.0
    }
}

let parsed = parseArgs(Array(CommandLine.arguments.dropFirst()))

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard !stdinData.isEmpty else {
    die("error: expected coverage JSON on stdin", exitCode: 2)
}

let rootAny: Any
do {
    rootAny = try JSONSerialization.jsonObject(with: stdinData, options: [])
} catch {
    die("error: failed to parse coverage JSON: \(error)", exitCode: 2)
}

guard let root = rootAny as? [String: Any] else {
    die("error: coverage JSON root is not an object", exitCode: 2)
}

guard let rawTargets = root["targets"] as? [[String: Any]] else {
    die("error: coverage JSON missing 'targets' array", exitCode: 2)
}

var targetsByName: [String: TargetCoverage] = [:]
targetsByName.reserveCapacity(rawTargets.count)
for t in rawTargets {
    guard let name = t["name"] as? String else { continue }
    let covered = (t["coveredLines"] as? NSNumber)?.intValue ?? 0
    let executable = (t["executableLines"] as? NSNumber)?.intValue ?? 0
    var files: [FileCoverage] = []
    if let rawFiles = t["files"] as? [[String: Any]] {
        for f in rawFiles {
            guard let fileName = f["name"] as? String else { continue }
            let fCovered = (f["coveredLines"] as? NSNumber)?.intValue ?? 0
            let fExecutable = (f["executableLines"] as? NSNumber)?.intValue ?? 0
            files.append(FileCoverage(name: fileName, coveredLines: fCovered, executableLines: fExecutable))
        }
    }
    targetsByName[name] = TargetCoverage(name: name, coveredLines: covered, executableLines: executable, files: files)
}

let availableTargetNames = targetsByName.keys.sorted()

var selected: [TargetCoverage] = []
selected.reserveCapacity(parsed.targetNames.count)
for name in parsed.targetNames {
    guard let cov = targetsByName[name] else {
        die(
            """
            error: coverage report missing target: \(name)
            Available targets:
            \(availableTargetNames.map { "- \($0)" }.joined(separator: "\n"))
            """,
            exitCode: 2
        )
    }
    if cov.executableLines == 0 {
        die("error: target has 0 executable lines (cannot compute coverage): \(name)", exitCode: 2)
    }
    selected.append(cov)
}

let totalCovered = selected.reduce(0) { $0 + $1.coveredLines }
let totalExecutable = selected.reduce(0) { $0 + $1.executableLines }
guard totalExecutable > 0 else {
    die("error: selected targets have 0 executable lines in total", exitCode: 2)
}

for cov in selected {
    print("\(cov.name): \(String(format: "%.2f", cov.percent))% (\(cov.coveredLines)/\(cov.executableLines))")
}

let totalPercent = (Double(totalCovered) / Double(totalExecutable)) * 100.0
print("TOTAL (selected): \(String(format: "%.2f", totalPercent))% (\(totalCovered)/\(totalExecutable))")
print("MIN REQUIRED: \(String(format: "%.2f", parsed.minPercent))%")

// Per-file coverage summary (sorted by % ascending — lowest coverage first)
print("")
print("Per-file coverage:")
for cov in selected {
    let sortedFiles = cov.files
        .filter { $0.executableLines > 0 }
        .sorted { $0.percent < $1.percent }
    if sortedFiles.isEmpty { continue }

    print("  \(cov.name):")
    let maxNameLen = sortedFiles.map(\.name.count).max() ?? 0
    for file in sortedFiles {
        let padded = file.name.padding(toLength: maxNameLen, withPad: " ", startingAt: 0)
        print("    \(padded)  \(String(format: "%6.2f", file.percent))% (\(file.coveredLines)/\(file.executableLines))")
    }
}

if totalPercent + 1e-9 < parsed.minPercent {
    die("error: coverage gate failed", exitCode: 1)
}
