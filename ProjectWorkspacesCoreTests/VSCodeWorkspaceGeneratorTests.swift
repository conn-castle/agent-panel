import XCTest

@testable import ProjectWorkspacesCore

final class VSCodeWorkspaceGeneratorTests: XCTestCase {
    func testWorkspaceGenerationMatchesFixture() throws {
        let project = ProjectConfig(
            id: "codex",
            name: "Codex",
            path: "/Users/tester/src/codex",
            colorHex: "#7C3AED",
            repoUrl: nil,
            ide: .vscode,
            ideUseAgentLayerLauncher: true,
            ideCommand: "",
            chromeUrls: [],
            chromeProfileDirectory: nil
        )

        let generator = VSCodeWorkspaceGenerator()
        let result = generator.generateWorkspaceData(for: project)

        let data: Data
        switch result {
        case .failure(let error):
            XCTFail("Unexpected workspace generation error: \(error)")
            return
        case .success(let payload):
            data = payload
        }

        let expected = try loadFixture(named: "vscode-workspace", extension: "json")
        let normalizedActual = try normalizeJSON(data)
        let normalizedExpected = try normalizeJSON(expected)

        XCTAssertEqual(normalizedActual, normalizedExpected)
    }

    func testInvalidColorHexFailsGeneration() {
        let project = ProjectConfig(
            id: "codex",
            name: "Codex",
            path: "/Users/tester/src/codex",
            colorHex: "#GGGGGG",
            repoUrl: nil,
            ide: .vscode,
            ideUseAgentLayerLauncher: true,
            ideCommand: "",
            chromeUrls: [],
            chromeProfileDirectory: nil
        )

        let generator = VSCodeWorkspaceGenerator()
        let result = generator.generateWorkspaceData(for: project)

        switch result {
        case .success:
            XCTFail("Expected invalid color hex error")
        case .failure(let error):
            XCTAssertEqual(error, .invalidColorHex("#GGGGGG"))
        }
    }

    private func loadFixture(named name: String, extension ext: String) throws -> Data {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let fixturesURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let fixtureURL = fixturesURL.appendingPathComponent("\(name).\(ext)", isDirectory: false)
        return try Data(contentsOf: fixtureURL)
    }

    private func normalizeJSON(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let normalizedString = String(data: normalized, encoding: .utf8) else {
            throw NSError(domain: "VSCodeWorkspaceGeneratorTests", code: 2)
        }
        return normalizedString
    }
}
