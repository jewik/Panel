//
//  FastFolderPreviewSupport.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import Foundation

// MARK: - Preview storage

@MainActor
final class InMemoryFastFolderStorage: FastFolderStorage {

    private var folders: [FastFolder]

    init(folders: [FastFolder] = []) {
        self.folders = folders
    }

    func load() -> [FastFolder] {
        folders
    }

    func save(_ folders: [FastFolder]) {
        self.folders = folders
    }
}

// MARK: - Preview bookmark service

@MainActor
final class PreviewBookmarkService: FastFolderBookmarkServiceProtocol {

    struct Entry {
        let url: URL
        let snapshot: FolderSnapshot
        let isAvailable: Bool
    }

    private var entriesByBookmark: [Data: Entry] = [:]

    func register(bookmark: Data, entry: Entry) {
        entriesByBookmark[bookmark] = entry
    }

    func makeBookmark(for url: URL) throws -> Data {
        Data(url.absoluteString.utf8)
    }

    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        guard let entry = entriesByBookmark[bookmark], entry.isAvailable else {
            throw PreviewBookmarkError.unavailable
        }

        return (entry.url, false)
    }

    func snapshot(of url: URL) throws -> FolderSnapshot {
        guard let entry = entriesByBookmark.values.first(where: { $0.url == url }) else {
            throw PreviewBookmarkError.unavailable
        }

        return entry.snapshot
    }

    func openInNewFinderWindow(_ url: URL) {}

    private enum PreviewBookmarkError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Preview folder is unavailable"
        }
    }
}

// MARK: - Preview data

struct PreviewFastFolder {
    let name: String
    let color: FinderTagColor
    let tags: [String]
    let isAvailable: Bool

    init(
        name: String,
        color: FinderTagColor = .none,
        tags: [String] = [],
        isAvailable: Bool = true
    ) {
        self.name = name
        self.color = color
        self.tags = tags
        self.isAvailable = isAvailable
    }
}

@MainActor
func makePreviewFastFolderStore(_ previews: [PreviewFastFolder]) -> FastFolderStore {
    let bookmarkService = PreviewBookmarkService()
    var folders: [FastFolder] = []

    for (index, preview) in previews.enumerated() {
        let url = URL(
            fileURLWithPath: "/Preview/FastFolder/\(index)-\(preview.name)",
            isDirectory: true
        )
        let bookmark = Data("preview-bookmark-\(index)".utf8)
        let snapshot = FolderSnapshot(
            name: preview.name,
            tags: preview.tags,
            tagColorIndex: preview.color.rawValue
        )

        bookmarkService.register(
            bookmark: bookmark,
            entry: .init(
                url: url,
                snapshot: snapshot,
                isAvailable: preview.isAvailable
            )
        )

        folders.append(
            FastFolder(
                name: preview.name,
                bookmark: bookmark,
                tags: preview.tags,
                tagColorIndex: preview.color.rawValue
            )
        )
    }

    return FastFolderStore(
        storage: InMemoryFastFolderStorage(folders: folders),
        bookmarkService: bookmarkService
    )
}
