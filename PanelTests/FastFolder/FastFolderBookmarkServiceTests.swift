//
//  FastFolderBookmarkServiceTests.swift
//  PanelTests
//

import Foundation
import XCTest
@testable import Panel

final class FastFolderBookmarkServiceTests: XCTestCase {

    func testSnapshotReadsDirectoryName() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FastFolderBookmarkService()

        let result = try await service.snapshot(of: directory)

        XCTAssertEqual(result.name, directory.lastPathComponent)
        XCTAssertEqual(result.tags, [])
        XCTAssertEqual(result.tagColorIndex, FinderTagColor.none.rawValue)
    }

    func testSnapshotRejectsRegularFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file.txt", isDirectory: false)
        try Data("content".utf8).write(to: file)
        let service = FastFolderBookmarkService()

        do {
            _ = try await service.snapshot(of: file)
            XCTFail("Expected a non-directory error")
        } catch let error as FastFolderBookmarkError {
            guard case .notDirectory(let rejectedURL) = error else {
                return XCTFail("Unexpected FastFolderBookmarkError: \(error)")
            }
            XCTAssertEqual(rejectedURL, file)
        }
    }

    func testBookmarkRoundTripPreservesURL() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FastFolderBookmarkService()

        let bookmark = try await service.makeBookmark(for: directory)
        let resolved = try await service.resolve(bookmark)

        XCTAssertEqual(
            resolved.url.standardizedFileURL.path,
            directory.standardizedFileURL.path
        )
        XCTAssertFalse(resolved.isStale)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanelTests-FastFolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
