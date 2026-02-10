import XCTest

@testable import AgentPanelCore

final class DependenciesTests: XCTestCase {
    func testCapturedFocusEquatable() {
        let a = CapturedFocus(windowId: 1, appBundleId: "com.example.app", workspace: "main")
        let b = CapturedFocus(windowId: 1, appBundleId: "com.example.app", workspace: "main")
        let c = CapturedFocus(windowId: 2, appBundleId: "com.example.app", workspace: "main")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testDefaultFileSystemWriteReadExistsAndSize() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try fs.createDirectory(at: tmp)
        XCTAssertTrue(fs.fileExists(at: tmp))

        let fileURL = tmp.appendingPathComponent("file.txt")
        let data = Data("hello".utf8)
        try fs.writeFile(at: fileURL, data: data)

        XCTAssertTrue(fs.fileExists(at: fileURL))
        XCTAssertEqual(try fs.readFile(at: fileURL), data)
        XCTAssertEqual(try fs.fileSize(at: fileURL), UInt64(data.count))
    }

    func testDefaultFileSystemAppendCreatesFileWhenMissing() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try fs.createDirectory(at: tmp)

        let fileURL = tmp.appendingPathComponent("append.txt")
        XCTAssertFalse(fs.fileExists(at: fileURL))

        try fs.appendFile(at: fileURL, data: Data("a".utf8))
        try fs.appendFile(at: fileURL, data: Data("b".utf8))

        XCTAssertEqual(String(decoding: try fs.readFile(at: fileURL), as: UTF8.self), "ab")
    }

    func testDefaultFileSystemAppendAppendsWhenExisting() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try fs.createDirectory(at: tmp)

        let fileURL = tmp.appendingPathComponent("append-existing.txt")
        try fs.writeFile(at: fileURL, data: Data("x".utf8))

        try fs.appendFile(at: fileURL, data: Data("y".utf8))

        XCTAssertEqual(String(decoding: try fs.readFile(at: fileURL), as: UTF8.self), "xy")
    }

    func testDefaultFileSystemMoveAndRemove() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try fs.createDirectory(at: tmp)

        let src = tmp.appendingPathComponent("src.txt")
        let dst = tmp.appendingPathComponent("dst.txt")
        try fs.writeFile(at: src, data: Data("data".utf8))

        try fs.moveItem(at: src, to: dst)
        XCTAssertFalse(fs.fileExists(at: src))
        XCTAssertTrue(fs.fileExists(at: dst))

        try fs.removeItem(at: dst)
        XCTAssertFalse(fs.fileExists(at: dst))
    }

    func testDefaultFileSystemIsExecutableFileReflectsPermissions() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try fs.createDirectory(at: tmp)

        let fileURL = tmp.appendingPathComponent("tool")
        try fs.writeFile(at: fileURL, data: Data("#!/bin/sh\necho hi\n".utf8))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        XCTAssertFalse(fs.isExecutableFile(at: fileURL))

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
        XCTAssertTrue(fs.isExecutableFile(at: fileURL))
    }

    func testLaunchServicesAppDiscoveryApplicationURLBundleIdentifierUnknownReturnsNil() {
        let discovery = LaunchServicesAppDiscovery()
        XCTAssertNil(discovery.applicationURL(bundleIdentifier: "com.agentpanel.tests.nonexistent.bundle"))
    }

    func testLaunchServicesAppDiscoveryApplicationURLNamedFindsDirectMatchAtRoot() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let appURL = tmp.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        let found = discovery.applicationURL(named: "Foo")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, appURL.resolvingSymlinksInPath().path)
    }

    func testLaunchServicesAppDiscoveryApplicationURLNamedFindsDirectMatchInUtilities() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let utilitiesURL = tmp.appendingPathComponent("Utilities", isDirectory: true)
        try FileManager.default.createDirectory(at: utilitiesURL, withIntermediateDirectories: true)
        let appURL = utilitiesURL.appendingPathComponent("Bar.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        let found = discovery.applicationURL(named: "Bar")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, appURL.resolvingSymlinksInPath().path)
    }

    func testLaunchServicesAppDiscoveryApplicationURLNamedFindsViaShallowSearch() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let nested = tmp.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let appURL = nested.appendingPathComponent("Baz.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        let found = discovery.applicationURL(named: "Baz")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, appURL.resolvingSymlinksInPath().path)
    }

    func testLaunchServicesAppDiscoveryApplicationURLNamedReturnsNilWhenNotFound() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        XCTAssertNil(discovery.applicationURL(named: "DoesNotExist"))
    }

    func testLaunchServicesAppDiscoveryBundleIdentifierReturnsNilForNonBundleDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        XCTAssertNil(discovery.bundleIdentifier(forApplicationAt: tmp))
    }

    func testCarbonHotkeyCheckerReturnsConsistentShape() {
        let checker = CarbonHotkeyChecker()
        let result = checker.checkCommandShiftSpace()

        // Deterministic invariant: success implies nil errorCode; failure implies non-nil errorCode.
        if result.isAvailable {
            XCTAssertNil(result.errorCode)
        } else {
            XCTAssertNotNil(result.errorCode)
        }
    }

    func testSystemDateProviderNowIsCloseToCurrentTime() {
        let provider = SystemDateProvider()
        let before = Date()
        let now = provider.now()
        let after = Date()

        XCTAssertGreaterThanOrEqual(now.timeIntervalSince1970, before.timeIntervalSince1970)
        XCTAssertLessThanOrEqual(now.timeIntervalSince1970, after.timeIntervalSince1970)
    }

    func testProcessEnvironmentReadsValues() {
        setenv("AGENTPANEL_TEST_ENV", "value", 1)

        let env = ProcessEnvironment()
        XCTAssertEqual(env.value(forKey: "AGENTPANEL_TEST_ENV"), "value")
        XCTAssertEqual(env.allValues()["AGENTPANEL_TEST_ENV"], "value")
    }
}
