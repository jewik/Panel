//
//  FastFolderPreviewSupport.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

#if DEBUG
import Foundation

// MARK: - Preview storage

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

// MARK: - Preview services

struct PreviewBookmarkService: FastFolderBookmarkServiceProtocol {

    struct Entry: Sendable {
        let url: URL
        let snapshot: FolderSnapshot
        let isAvailable: Bool
        let delay: Duration
    }

    let entriesByBookmark: [Data: Entry]

    func makeBookmark(for url: URL) async throws -> Data {
        Data(url.absoluteString.utf8)
    }

    func resolve(_ bookmark: Data) async throws -> (url: URL, isStale: Bool) {
        guard let entry = entriesByBookmark[bookmark] else {
            throw PreviewBookmarkError.unavailable
        }

        if entry.delay > .zero {
            try await Task.sleep(for: entry.delay)
        }

        guard entry.isAvailable else {
            throw PreviewBookmarkError.unavailable
        }

        return (entry.url, false)
    }

    func snapshot(of url: URL) async throws -> FolderSnapshot {
        guard let entry = entriesByBookmark.values.first(where: { $0.url == url }) else {
            throw PreviewBookmarkError.unavailable
        }

        return entry.snapshot
    }

    private enum PreviewBookmarkError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Preview folder is unavailable"
        }
    }
}

@MainActor
final class PreviewFinderPresenter: FinderPresenting {
    func openInNewFinderWindow(_ url: URL) {}
}

@MainActor
final class PreviewFolderPicker: FolderPicking {
    func pickFolders() async -> [URL] { [] }
}

// MARK: - Preview data

struct PreviewFastFolder {
    let name: String
    let color: FinderTagColor
    let tags: [String]
    let isAvailable: Bool
    let delay: Duration

    init(
        name: String,
        color: FinderTagColor = .none,
        tags: [String] = [],
        isAvailable: Bool = true,
        delay: Duration = .zero
    ) {
        self.name = name
        self.color = color
        self.tags = tags
        self.isAvailable = isAvailable
        self.delay = delay
    }
}

@MainActor
func makePreviewFastFolderStore(_ previews: [PreviewFastFolder]) -> FastFolderStore {
    var entries: [Data: PreviewBookmarkService.Entry] = [:]
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

        entries[bookmark] = .init(
            url: url,
            snapshot: snapshot,
            isAvailable: preview.isAvailable,
            delay: preview.delay
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
        bookmarkService: PreviewBookmarkService(entriesByBookmark: entries),
        finder: PreviewFinderPresenter(),
        picker: PreviewFolderPicker()
    )
}
#endif
