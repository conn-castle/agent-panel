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
