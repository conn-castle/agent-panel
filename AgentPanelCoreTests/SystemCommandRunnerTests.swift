import XCTest
import Darwin
@testable import AgentPanelCore

final class SystemCommandRunnerTests: XCTestCase {

    // MARK: - buildAugmentedEnvironment

    func testAugmentedEnvironmentContainsStandardPaths() {
        // Resolver with login shell disabled — only standard paths + current process PATH
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = ApSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let path = env["PATH"] else {
            XCTFail("PATH should be present in augmented environment")
            return
        }

        let components = path.split(separator: ":").map(String.init)

        // Standard paths should appear at the start (in order)
        for standardPath in ExecutableResolver.standardSearchPaths {
            XCTAssertTrue(
                components.contains(standardPath),
                "Standard path \(standardPath) should be in augmented PATH"
            )
        }

        // First entries should be the standard search paths
        for (index, standardPath) in ExecutableResolver.standardSearchPaths.enumerated() {
            guard index < components.count else {
                XCTFail("Not enough PATH entries to match standard paths")
                return
            }
            XCTAssertEqual(
                components[index],
                standardPath,
                "Standard path at index \(index) should be \(standardPath)"
            )
        }
    }

    func testAugmentedEnvironmentPreservesProcessPATH() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = ApSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let augmentedPath = env["PATH"] else {
            XCTFail("PATH should be present")
            return
        }

        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let currentComponents = currentPath.split(separator: ":").map(String.init)
        let augmentedComponents = Set(augmentedPath.split(separator: ":").map(String.init))

        // All non-empty entries from the current process PATH should be in the augmented PATH
        for component in currentComponents where !component.isEmpty {
            XCTAssertTrue(
                augmentedComponents.contains(component),
                "Current process PATH entry '\(component)' should be preserved in augmented PATH"
            )
        }
    }

    func testAugmentedEnvironmentDeduplicatesPaths() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = ApSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let path = env["PATH"] else {
            XCTFail("PATH should be present")
            return
        }

        let components = path.split(separator: ":").map(String.init)
        let unique = Set(components)

        // Every entry should be unique (no duplicates)
        XCTAssertEqual(
            components.count,
            unique.count,
            "Augmented PATH should have no duplicate entries"
        )
    }

    func testAugmentedEnvironmentHasNoConsecutiveColons() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = ApSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let path = env["PATH"] else {
            XCTFail("PATH should be present")
            return
        }

        // Consecutive colons (::) indicate empty PATH entries, which cause
        // shells to interpret "" as the current directory — a security concern.
        XCTAssertFalse(path.contains("::"), "PATH should not contain consecutive colons (empty entries)")
        XCTAssertFalse(path.hasPrefix(":"), "PATH should not start with a colon")
        XCTAssertFalse(path.hasSuffix(":"), "PATH should not end with a colon")
    }

    func testAugmentedEnvironmentPreservesNonPATHVariables() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = ApSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        // HOME should be preserved from the process environment
        let expectedHome = ProcessInfo.processInfo.environment["HOME"]
        XCTAssertEqual(env["HOME"], expectedHome, "Non-PATH environment variables should be preserved")
    }

    // MARK: - resolveLoginShellPath

    func testResolveLoginShellPathReturnsNonNilPathWhenEnabled() throws {
        // Avoid relying on the developer's real shell init files (which may be slow or fail).
        // Instead, point $SHELL at a tiny script that prints a deterministic PATH.
        let expectedPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellPathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\necho \"\(expectedPath)\"\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        let originalShell = ProcessInfo.processInfo.environment["SHELL"]
        defer {
            if let originalShell {
                setenv("SHELL", originalShell, 1)
            } else {
                unsetenv("SHELL")
            }
            try? FileManager.default.removeItem(at: tempDir)
        }
        setenv("SHELL", shellURL.path, 1)

        let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
        let path = resolver.resolveLoginShellPath()
        XCTAssertEqual(path, expectedPath)
    }

    func testResolveLoginShellPathReturnsNilWhenDisabled() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let path = resolver.resolveLoginShellPath()

        XCTAssertNil(path, "Login shell PATH should be nil when fallback is disabled")
    }
}

final class ChromeLauncherTests: XCTestCase {

    func testOpenNewWindowRejectsEmptyIdentifier() {
        let runner = ChromeLauncherCommandRunnerStub(result: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")))
        let launcher = ApChromeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(identifier: "  ")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("Identifier cannot be empty"))
            XCTAssertNil(runner.lastExecutable)
        }
    }

    func testOpenNewWindowRejectsIdentifierWithSlash() {
        let runner = ChromeLauncherCommandRunnerStub(result: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")))
        let launcher = ApChromeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(identifier: "a/b")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("cannot contain"))
            XCTAssertNil(runner.lastExecutable)
        }
    }

    func testOpenNewWindowBuildsAppleScriptWithWindowTitleAndURLs() {
        let runner = ChromeLauncherCommandRunnerStub(result: .success(ApCommandResult(exitCode: 0, stdout: "", stderr: "")))
        let launcher = ApChromeLauncher(commandRunner: runner)

        let urls = [
            "https://example.com?q=\"x\"",
            "https://two.com/path\\\\x"
        ]
        let result = launcher.openNewWindow(identifier: "my-proj", initialURLs: urls)

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        XCTAssertEqual(runner.lastExecutable, "osascript")
        guard let args = runner.lastArguments else {
            XCTFail("Expected osascript args")
            return
        }

        // The arguments should be a sequence of: -e <line>
        XCTAssertTrue(args.count >= 2)
        XCTAssertEqual(args[0], "-e")
        XCTAssertTrue(args.contains("tell application \"Google Chrome\""))
        XCTAssertTrue(args.contains("set newWindow to make new window"))

        // URL lines should include escaped quotes/backslashes.
        let urlLine = args.first { $0.contains("set URL of active tab") }
        XCTAssertNotNil(urlLine)
        XCTAssertTrue(urlLine!.contains("https://example.com?q=\\\"x\\\""))

        let secondTabLine = args.first { $0.contains("make new tab") }
        XCTAssertNotNil(secondTabLine)
        XCTAssertTrue(secondTabLine!.contains("https://two.com/path\\\\\\\\x"))

        // Window title should include AP: token.
        let titleLine = args.first { $0.contains("set given name of newWindow") }
        XCTAssertNotNil(titleLine)
        XCTAssertTrue(titleLine!.contains("AP:my-proj"))
    }

    func testOpenNewWindowNonZeroExitReturnsFailureWithStderr() {
        let runner = ChromeLauncherCommandRunnerStub(
            result: .success(ApCommandResult(exitCode: 2, stdout: "", stderr: "boom"))
        )
        let launcher = ApChromeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(identifier: "x")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("exit code 2"))
            XCTAssertTrue(error.message.contains("boom"))
        }
    }

    func testOpenNewWindowRunnerFailureIsPropagated() {
        let runner = ChromeLauncherCommandRunnerStub(
            result: .failure(ApCoreError(message: "runner failed"))
        )
        let launcher = ApChromeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(identifier: "x")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.message, "runner failed")
        }
    }
}

private final class ChromeLauncherCommandRunnerStub: CommandRunning {
    let result: Result<ApCommandResult, ApCoreError>
    private(set) var lastExecutable: String?
    private(set) var lastArguments: [String]?
    private(set) var lastTimeout: TimeInterval?
    private(set) var lastWorkingDirectory: String?

    init(result: Result<ApCommandResult, ApCoreError>) {
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<ApCommandResult, ApCoreError> {
        lastExecutable = executable
        lastArguments = arguments
        lastTimeout = timeoutSeconds
        lastWorkingDirectory = workingDirectory
        return result
    }
}
