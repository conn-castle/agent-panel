import XCTest

@testable import ProjectWorkspacesCore

final class AeroSpaceWindowDecoderTests: XCTestCase {
    func testDecodesWindowPayload() {
        let json = """
        [
          {
            "window-id": 1750,
            "workspace": "1",
            "app-bundle-id": "net.kovidgoyal.kitty",
            "app-name": "kitty",
            "window-title": "aerospace",
            "monitor-appkit-nsscreen-screens-id": 2
          },
          {
            "window-id": 1337,
            "workspace": ".scratchpad",
            "app-bundle-id": "com.brave.Browser",
            "app-name": "Brave Browser",
            "window-title": ""
          }
        ]
        """

        let decoder = AeroSpaceWindowDecoder()
        let result = decoder.decodeWindows(from: json)

        switch result {
        case .failure(let error):
            XCTFail("Expected decode success, got error: \(error)")
        case .success(let windows):
            XCTAssertEqual(windows.count, 2)
            XCTAssertEqual(
                windows[0],
                AeroSpaceWindow(
                    windowId: 1750,
                    workspace: "1",
                    appBundleId: "net.kovidgoyal.kitty",
                    appName: "kitty",
                    windowTitle: "aerospace",
                    windowLayout: "",
                    monitorAppkitNSScreenScreensId: 2
                )
            )
            XCTAssertEqual(windows[1].windowTitle, "")
            XCTAssertEqual(windows[1].workspace, ".scratchpad")
        }
    }

    func testDecodeFailsOnMalformedJson() {
        let decoder = AeroSpaceWindowDecoder()
        let result = decoder.decodeWindows(from: "not-json")

        switch result {
        case .success:
            XCTFail("Expected decode failure")
        case .failure(let error):
            guard case .decodingFailed = error else {
                XCTFail("Expected decodingFailed, got \(error)")
                return
            }
        }
    }
}
