import XCTest
import Foundation
import Darwin
@testable import AgentPanelCore

private let shellEnvLock = NSLock()

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

    func testAugmentedEnvironmentWorksWhenProcessPATHIsMissing() {
        shellEnvLock.lock()
        defer { shellEnvLock.unlock() }

        let originalPath = ProcessInfo.processInfo.environment["PATH"]
        defer {
            if let originalPath {
                setenv("PATH", originalPath, 1)
            } else {
                unsetenv("PATH")
            }
        }

        unsetenv("PATH")

        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = ApSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let path = env["PATH"] else {
            XCTFail("PATH should be present in augmented environment")
            return
        }
        XCTAssertFalse(path.isEmpty)
        XCTAssertFalse(path.contains("::"))
    }

    func testAugmentedEnvironmentIncludesLoginShellPATHWhenAvailable() throws {
        let expectedShellPath = "/custom/bin:/usr/bin:/bin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AugmentedPATHShellTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\necho \"\(expectedShellPath)\"\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            let env = ApSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

            guard let path = env["PATH"] else {
                XCTFail("PATH should be present")
                return
            }

            let components = path.split(separator: ":").map(String.init)
            XCTAssertTrue(components.contains("/custom/bin"))
        }
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

    func testResolveLoginShellPathUsesFallbackWhenShellEnvIsNotAbsolute() throws {
        withShell("zsh") {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            let path = resolver.resolveLoginShellPath()

            XCTAssertNotNil(path)
            XCTAssertFalse(path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    func testResolveLoginShellPathReturnsNilWhenShellExecutableMissing() throws {
        withShell("/this/does/not/exist") {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            XCTAssertNil(resolver.resolveLoginShellPath())
        }
    }

    func testResolveLoginShellPathReturnsNilWhenShellExitsNonZero() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellNonZeroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\nexit 1\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            XCTAssertNil(resolver.resolveLoginShellPath())
        }
    }

    func testResolveLoginShellPathReturnsNilWhenShellOutputsEmptyString() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellEmptyOutputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\nexit 0\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            XCTAssertNil(resolver.resolveLoginShellPath())
        }
    }

    // MARK: - Fish shell PATH resolution

    func testIsFishShellReturnsTrueWhenShellIsFish() {
        withShell("/usr/local/bin/fish") {
            XCTAssertTrue(ExecutableResolver.isFishShell)
        }
    }

    func testIsFishShellReturnsFalseForZsh() {
        withShell("/bin/zsh") {
            XCTAssertFalse(ExecutableResolver.isFishShell)
        }
    }

    func testIsFishShellReturnsFalseForBash() {
        withShell("/bin/bash") {
            XCTAssertFalse(ExecutableResolver.isFishShell)
        }
    }

    func testIsFishShellReturnsFalseForNonAbsolutePath() {
        // Non-absolute SHELL falls back to /bin/zsh, which is not fish
        withShell("fish") {
            XCTAssertFalse(ExecutableResolver.isFishShell)
        }
    }

    func testResolveLoginShellPathUsesStringJoinForFish() throws {
        // Simulate a fish shell that receives "string join : $PATH" and emits colon-separated output.
        // The stub script gates on the command argument: only succeeds if it contains "string join".
        // This ensures a regression back to "echo $PATH" would cause a test failure.
        let expectedPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FishShellPathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Name the stub "fish" so loginShellPath.hasSuffix("/fish") is true
        let shellURL = tempDir.appendingPathComponent("fish", isDirectory: false)
        // The stub receives: -l -c "<command>"
        // $3 is the command. Only succeed if it contains "string join" (fish-specific).
        let script = """
            #!/bin/sh
            case "$3" in
              *"string join"*) echo "\(expectedPath)" ;;
              *) exit 1 ;;
            esac
            """
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            XCTAssertTrue(ExecutableResolver.isFishShell, "Shell path should be detected as fish")
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            let path = resolver.resolveLoginShellPath()
            XCTAssertEqual(path, expectedPath)
        }
    }

    func testAugmentedEnvironmentIncludesFishShellPATH() throws {
        let expectedShellPath = "/fish/custom/bin:/usr/bin:/bin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FishAugmentedPATHTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("fish", isDirectory: false)
        // Gate on "string join" to catch regressions
        let script = """
            #!/bin/sh
            case "$3" in
              *"string join"*) echo "\(expectedShellPath)" ;;
              *) exit 1 ;;
            esac
            """
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            let env = ApSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

            guard let path = env["PATH"] else {
                XCTFail("PATH should be present")
                return
            }

            let components = path.split(separator: ":").map(String.init)
            XCTAssertTrue(components.contains("/fish/custom/bin"),
                          "Augmented PATH should include fish shell's custom path")
        }
    }

    func testResolveLoginShellPathUsesEchoForNonFishShell() throws {
        // With a non-fish shell, resolveLoginShellPath should use "echo $PATH" (default behavior).
        // The stub gates on "echo" to catch regressions that send fish commands to non-fish shells.
        let expectedPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NonFishShellPathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("zsh", isDirectory: false)
        // Gate on "echo" — only succeed if the command contains "echo" (non-fish path)
        let script = """
            #!/bin/sh
            case "$3" in
              *"echo"*) echo "\(expectedPath)" ;;
              *) exit 1 ;;
            esac
            """
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            XCTAssertFalse(ExecutableResolver.isFishShell, "Shell path should not be detected as fish")
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            let path = resolver.resolveLoginShellPath()
            XCTAssertEqual(path, expectedPath)
        }
    }

    func testResolveViaLoginShellReturnsNilWhenShellCommandTimesOut() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellTimeoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\nsleep 10\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            // Force the login-shell fallback path; the stub shell never completes, so it should time out.
            XCTAssertNil(resolver.resolve("this-executable-should-not-exist-abcdef"))
        }
    }

    func testResolveViaLoginShellReturnsNilWhenShellOutputIsNotUTF8() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellBadUTF8Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        // Print a single invalid UTF-8 byte (0xFF) then exit 0.
        let script = "#!/bin/sh\nprintf '\\377'\nexit 0\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            XCTAssertNil(resolver.resolve("this-executable-should-not-exist-badutf8"))
        }
    }

    // MARK: - ApSystemCommandRunner.run

    func testRunRespectsWorkingDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingDirTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let runner = ApSystemCommandRunner(executableResolver: ExecutableResolver(loginShellFallbackEnabled: false))
        let result = runner.run(
            executable: "pwd",
            arguments: [],
            timeoutSeconds: 5,
            workingDirectory: tempDir.path
        )

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error.message)")
        case .success(let output):
            XCTAssertEqual(output.exitCode, 0)
            let actual = (output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).resolvingSymlinksInPath
            let expected = (tempDir.path as NSString).resolvingSymlinksInPath
            XCTAssertEqual(actual, expected)
        }
    }

    func testRunReturnsFailureWhenResolvedExecutableCannotBeLaunched() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let resolver = ExecutableResolver(
            fileSystem: AlwaysExecutableFileSystem(),
            searchPaths: [tempDir.path],
            loginShellFallbackEnabled: false
        )
        let runner = ApSystemCommandRunner(executableResolver: resolver)
        let result = runner.run(executable: "nope", arguments: [], timeoutSeconds: 1)

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("Failed to launch"))
        }
    }

    func testRunReturnsFailureWhenStdoutIsNotUTF8() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BadStdoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let binDir = tempDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let exeURL = binDir.appendingPathComponent("badstdout", isDirectory: false)
        let script = "#!/bin/sh\nprintf '\\377'\nexit 0\n"
        try script.write(to: exeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exeURL.path)

        let resolver = ExecutableResolver(searchPaths: [binDir.path], loginShellFallbackEnabled: false)
        let runner = ApSystemCommandRunner(executableResolver: resolver)

        let result = runner.run(executable: "badstdout", arguments: [], timeoutSeconds: 5, workingDirectory: nil)
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("UTF-8") && error.message.contains("stdout"))
        }
    }

    func testRunReturnsFailureWhenStderrIsNotUTF8() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BadStderrTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let binDir = tempDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let exeURL = binDir.appendingPathComponent("badstderr", isDirectory: false)
        let script = "#!/bin/sh\nprintf '\\377' 1>&2\nexit 0\n"
        try script.write(to: exeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exeURL.path)

        let resolver = ExecutableResolver(searchPaths: [binDir.path], loginShellFallbackEnabled: false)
        let runner = ApSystemCommandRunner(executableResolver: resolver)

        let result = runner.run(executable: "badstderr", arguments: [], timeoutSeconds: 5, workingDirectory: nil)
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("UTF-8") && error.message.contains("stderr"))
        }
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

private func withShell(_ shell: String?, _ body: () throws -> Void) rethrows {
    shellEnvLock.lock()
    defer { shellEnvLock.unlock() }

    let originalShell = ProcessInfo.processInfo.environment["SHELL"]
    defer {
        if let originalShell {
            setenv("SHELL", originalShell, 1)
        } else {
            unsetenv("SHELL")
        }
    }

    if let shell {
        setenv("SHELL", shell, 1)
    } else {
        unsetenv("SHELL")
    }

    try body()
}

private struct AlwaysExecutableFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { true }
    func readFile(at url: URL) throws -> Data { Data() }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}
