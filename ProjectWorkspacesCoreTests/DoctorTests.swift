import XCTest

@testable import ProjectWorkspacesCore

final class DoctorTests: XCTestCase {
    func testDoctorFailsWhenHotkeyUnavailable() {
        let config = """
        [global]
        defaultIde = "vscode"
        globalChromeUrls = []

        [display]
        ultrawideMinWidthPx = 5000

        [[project]]
        id = "codex"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#7C3AED"
        """

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: [
                "com.google.Chrome": "/Applications/Google Chrome.app",
                "com.microsoft.VSCode": "/Applications/Visual Studio Code.app"
            ],
            nameMap: [:],
            bundleIdForPath: [
                "/Applications/Google Chrome.app": "com.google.Chrome",
                "/Applications/Visual Studio Code.app": "com.microsoft.VSCode"
            ]
        )

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: false),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true)
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Cmd+Shift+Space hotkey cannot be registered" })
    }

    func testDoctorWarnsOnSwitcherHotkey() {
        let config = """
        [global]
        defaultIde = "vscode"
        globalChromeUrls = []
        switcherHotkey = "Ctrl+Space"

        [display]
        ultrawideMinWidthPx = 5000

        [[project]]
        id = "codex"
        name = "Codex"
        path = "/Users/tester/src/codex"
        colorHex = "#7C3AED"
        """

        let fileSystem = TestFileSystem(files: [
            "/Users/tester/.config/project-workspaces/config.toml": Data(config.utf8)
        ], directories: [
            "/Users/tester/src/codex"
        ])

        let appDiscovery = TestAppDiscovery(
            bundleIdMap: ["com.google.Chrome": "/Applications/Google Chrome.app"],
            nameMap: [:],
            bundleIdForPath: ["/Applications/Google Chrome.app": "com.google.Chrome"]
        )

        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: appDiscovery,
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true)
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains { $0.title == "global.switcherHotkey is ignored" })
    }

    func testDoctorFailsWhenConfigMissing() {
        let fileSystem = TestFileSystem(files: [:], directories: [])
        let doctor = Doctor(
            paths: ProjectWorkspacesPaths(homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)),
            fileSystem: fileSystem,
            appDiscovery: TestAppDiscovery(bundleIdMap: [:], nameMap: [:], bundleIdForPath: [:]),
            hotkeyChecker: TestHotkeyChecker(isAvailable: true),
            accessibilityChecker: TestAccessibilityChecker(isTrusted: true)
        )

        let report = doctor.run()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.findings.contains { $0.title == "Config file missing" })
    }
}

private struct TestFileSystem: FileSystem {
    let files: [String: Data]
    let directories: Set<String>

    init(files: [String: Data], directories: Set<String>) {
        self.files = files
        self.directories = directories
    }

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func readFile(at url: URL) throws -> Data {
        if let data = files[url.path] {
            return data
        }
        throw NSError(domain: "TestFileSystem", code: 1)
    }
}

private struct TestAppDiscovery: AppDiscovering {
    let bundleIdMap: [String: String]
    let nameMap: [String: String]
    let bundleIdForPath: [String: String]

    func applicationURL(bundleIdentifier: String) -> URL? {
        guard let path = bundleIdMap[bundleIdentifier] else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func applicationURL(named appName: String) -> URL? {
        guard let path = nameMap[appName] else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func bundleIdentifier(forApplicationAt url: URL) -> String? {
        bundleIdForPath[url.path]
    }
}

private struct TestHotkeyChecker: HotkeyChecking {
    let isAvailable: Bool

    func checkCommandShiftSpace() -> HotkeyCheckResult {
        HotkeyCheckResult(isAvailable: isAvailable, errorCode: isAvailable ? nil : -9876)
    }
}

private struct TestAccessibilityChecker: AccessibilityChecking {
    let isTrusted: Bool

    func isProcessTrusted() -> Bool {
        isTrusted
    }
}
