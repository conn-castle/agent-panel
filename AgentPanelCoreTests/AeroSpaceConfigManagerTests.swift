import XCTest

@testable import AgentPanelCore

final class AeroSpaceConfigManagerTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testConfigStatusMissingWhenNoFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configPath = dir.appendingPathComponent(".aerospace.toml").path
        let backupPath = dir.appendingPathComponent(".aerospace.toml.backup").path
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configPath,
            backupPath: backupPath,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configStatus(), .missing)
    }

    func testConfigStatusManagedByAgentPanelWhenMarkerPresent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        try "\(AeroSpaceConfigManager.managedByMarker)\nfoo = 1\n".write(to: configURL, atomically: true, encoding: .utf8)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configStatus(), .managedByAgentPanel)
    }

    func testConfigStatusExternalConfigWhenMarkerMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        try "foo = 1\n".write(to: configURL, atomically: true, encoding: .utf8)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configStatus(), .externalConfig)
    }

    func testConfigStatusUnknownWhenConfigReadFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Point configPath at a directory so reading as a file fails.
        let configDirURL = dir.appendingPathComponent(".aerospace.toml", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configDirURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configStatus(), .unknown)
    }

    func testWriteSafeConfigFailsWhenTemplateMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configPath = dir.appendingPathComponent(".aerospace.toml").path
        let backupPath = dir.appendingPathComponent(".backup").path
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configPath,
            backupPath: backupPath,
            safeConfigLoader: { nil }
        )

        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when safe config template is missing")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    func testWriteSafeConfigFailsWhenTemplateMissingUsingDefaultBundleLoader() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configPath = dir.appendingPathComponent(".aerospace.toml").path
        let backupPath = dir.appendingPathComponent(".backup").path

        // Do not use `AeroSpaceConfigManager()` here; its default config path points at the user's home.
        // This test uses a temp config path but exercises the default bundle-loader closure.
        let manager = AeroSpaceConfigManager(fileManager: .default, configPath: configPath, backupPath: backupPath)

        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when safe config template is missing from bundle")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    func testWriteSafeConfigFailsWhenTemplateMissingUsingPublicInit() {
        // Safety: AeroSpaceConfigManager() points at ~/.aerospace.toml. This test is only safe if the
        // safe template is missing from the test bundle, causing writeSafeConfig() to return early
        // without reading or writing the config file.
        XCTAssertNil(
            Bundle.main.url(forResource: "aerospace-safe", withExtension: "toml"),
            "This test assumes aerospace-safe.toml is missing from the test bundle; if it's present, rewrite the test to avoid touching the user's home directory."
        )

        let manager = AeroSpaceConfigManager()
        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when safe config template is missing from bundle")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    func testWriteSafeConfigWritesConfigWhenMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let backupURL = dir.appendingPathComponent(".backup")
        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nfoo = 1\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: backupURL.path,
            safeConfigLoader: { safeConfig }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))

        switch manager.writeSafeConfig() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), safeConfig)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func testWriteSafeConfigBacksUpExternalConfigAndOverwrites() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let backupURL = dir.appendingPathComponent(".backup")

        let external = "external = true\n"
        try external.write(to: configURL, atomically: true, encoding: .utf8)
        try "old backup".write(to: backupURL, atomically: true, encoding: .utf8)

        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nmanaged = true\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: backupURL.path,
            safeConfigLoader: { safeConfig }
        )

        switch manager.writeSafeConfig() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), safeConfig)
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), external)
    }

    func testWriteSafeConfigDoesNotBackUpWhenAlreadyManaged() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let backupURL = dir.appendingPathComponent(".backup")

        try "\(AeroSpaceConfigManager.managedByMarker)\nold = true\n".write(to: configURL, atomically: true, encoding: .utf8)
        try "keep backup".write(to: backupURL, atomically: true, encoding: .utf8)

        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nnew = true\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: backupURL.path,
            safeConfigLoader: { safeConfig }
        )

        switch manager.writeSafeConfig() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), safeConfig)
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "keep backup")
    }

    func testWriteSafeConfigFailsWhenBackupCopyFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        try "external = true\n".write(to: configURL, atomically: true, encoding: .utf8)

        // Destination directory does not exist, so copyItem should fail.
        let badBackupPath = dir.appendingPathComponent("missing-dir/backup.toml").path

        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nmanaged = true\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: badBackupPath,
            safeConfigLoader: { safeConfig }
        )

        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when backup copy fails")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    // MARK: - configContents()

    func testConfigContentsReturnsContentsWhenFileExists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let expected = "\(AeroSpaceConfigManager.managedByMarker)\nalt-tab = 'focus'\n"
        try expected.write(to: configURL, atomically: true, encoding: .utf8)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configContents(), expected)
    }

    func testConfigContentsReturnsNilWhenFileMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: dir.appendingPathComponent(".aerospace.toml").path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertNil(manager.configContents())
    }

    func testConfigContentsReturnsNilWhenFileUnreadable() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Point configPath at a directory so reading as a file fails.
        let configDirURL = dir.appendingPathComponent(".aerospace.toml", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configDirURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertNil(manager.configContents())
    }

    // MARK: - writeSafeConfig failure cases

    func testWriteSafeConfigFailsWhenWritingConfigFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Point configPath at a directory so writing as a file fails.
        let configDirURL = dir.appendingPathComponent(".aerospace.toml", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)

        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nmanaged = true\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configDirURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { safeConfig }
        )

        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when writing config fails")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }
}
