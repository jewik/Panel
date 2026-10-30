//
//  FastFolderModelTests.swift
//  PanelTests
//

import Foundation
import XCTest
@testable import Panel

final class FastFolderModelTests: XCTestCase {

    func testLegacyPayloadGetsDefaultTagsAndColor() throws {
        let id = UUID()
        let bookmark = Data("bookmark".utf8)
        let payload: [String: Any] = [
            "id": id.uuidString,
            "name": "Legacy",
            "bookmark": bookmark.base64EncodedString(),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let folder = try JSONDecoder().decode(FastFolder.self, from: data)

        XCTAssertEqual(folder.id, id)
        XCTAssertEqual(folder.name, "Legacy")
        XCTAssertEqual(folder.bookmark, bookmark)
        XCTAssertEqual(folder.tags, [])
        XCTAssertEqual(folder.tagColorIndex, FinderTagColor.none.rawValue)
    }

    func testUnknownTagColorFallsBackToNone() {
        let folder = FastFolder(
            name: "Folder",
            bookmark: Data(),
            tagColorIndex: 999
        )

        XCTAssertEqual(folder.tagColor, .none)
    }

    func testUserDefaultsStorageRoundTripsFolders() throws {
        let suiteName = "PanelTests.FastFolder.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expected = FastFolder(
            name: "Projects",
            bookmark: Data("bookmark".utf8),
            tags: ["Work"],
            tagColorIndex: FinderTagColor.blue.rawValue
        )
        let storage = UserDefaultsFastFolderStorage(defaults: defaults)

        storage.save([expected])

        XCTAssertEqual(storage.load(), [expected])
    }
}
