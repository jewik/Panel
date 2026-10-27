//
//  FastFolderStore.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import Foundation
import Observation
import os

struct FastFolderAddOutcome: Equatable {
    var added: Int = 0
    var skippedDuplicates: Int = 0
    var rejectedByLimit: Int = 0
    var failed: Int = 0
}

@MainActor
@Observable
final class FastFolderStore {

    static let maximumFolderCount = 8

    private(set) var folders: [FastFolder] = []
    private(set) var unavailableFolderIDs: Set<FastFolder.ID> = []

    @ObservationIgnored private let storage: FastFolderStorage
    @ObservationIgnored private let bookmarkService: FastFolderBookmarkServiceProtocol

    var canAddFolder: Bool {
        folders.count < Self.maximumFolderCount
    }

    var availableFolders: [FastFolder] {
        folders.filter { !unavailableFolderIDs.contains($0.id) }
    }

    var unavailableCount: Int {
        unavailableFolderIDs.count
    }

    init(
        storage: FastFolderStorage,
        bookmarkService: FastFolderBookmarkServiceProtocol
    ) {
        self.storage = storage
        self.bookmarkService = bookmarkService
        self.folders = storage.load()
    }

    func refresh() {
        guard !folders.isEmpty else { return }

        var didChange = false
        var unavailableIDs: Set<FastFolder.ID> = []
        var availableCount = 0

        for index in folders.indices {
            let folder = folders[index]

            do {
                let resolved = try bookmarkService.resolve(folder.bookmark)

                if resolved.isStale {
                    folders[index].bookmark = try bookmarkService.makeBookmark(for: resolved.url)
                    didChange = true
                }

                let snapshot = try bookmarkService.snapshot(of: resolved.url)
                availableCount += 1

                if folders[index].name != snapshot.name {
                    folders[index].name = snapshot.name
                    didChange = true
                }

                if folders[index].tags != snapshot.tags {
                    folders[index].tags = snapshot.tags
                    didChange = true
                }

                if folders[index].tagColorIndex != snapshot.tagColorIndex {
                    folders[index].tagColorIndex = snapshot.tagColorIndex
                    didChange = true
                }
            } catch {
                unavailableIDs.insert(folder.id)
                Log.service.error(
                    "FastFolder refresh failed for \(folder.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        unavailableFolderIDs = unavailableIDs

        if didChange {
            storage.save(folders)
        }

        Log.service.info(
            "FastFolder refresh finished: \(availableCount) available, \(unavailableIDs.count) unavailable, saved: \(didChange)"
        )
    }

    @discardableResult
    func addFolders(_ urls: [URL]) -> FastFolderAddOutcome {
        var outcome = FastFolderAddOutcome()
        var knownPaths = Set(
            folders.compactMap { folder in
                try? bookmarkService.resolve(folder.bookmark).url.standardizedFileURL.path
            }
        )

        for url in urls {
            let path = url.standardizedFileURL.path

            if knownPaths.contains(path) {
                outcome.skippedDuplicates += 1
                continue
            }

            guard folders.count < Self.maximumFolderCount else {
                outcome.rejectedByLimit += 1
                continue
            }

            do {
                let bookmark = try bookmarkService.makeBookmark(for: url)
                let snapshot = try bookmarkService.snapshot(of: url)

                folders.append(
                    FastFolder(
                        name: snapshot.name,
                        bookmark: bookmark,
                        tags: snapshot.tags,
                        tagColorIndex: snapshot.tagColorIndex
                    )
                )
                knownPaths.insert(path)
                outcome.added += 1
            } catch {
                outcome.failed += 1
                Log.service.error(
                    "FastFolder add failed for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        if outcome.added > 0 {
            storage.save(folders)
            Log.ui.info("FastFolder added \(outcome.added) folder(s)")
        }

        return outcome
    }

    func removeFolder(id: FastFolder.ID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removed = folders.remove(at: index)
        unavailableFolderIDs.remove(id)
        storage.save(folders)

        Log.ui.info("FastFolder removed \(removed.name, privacy: .public)")
    }

    func removeAll() {
        guard !folders.isEmpty else { return }

        folders.removeAll()
        unavailableFolderIDs.removeAll()
        storage.save(folders)

        Log.ui.info("FastFolder removed all folders")
    }

    func open(_ folder: FastFolder) {
        do {
            let resolved = try bookmarkService.resolve(folder.bookmark)

            if resolved.isStale,
               let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index].bookmark = try bookmarkService.makeBookmark(for: resolved.url)
                storage.save(folders)
            }

            bookmarkService.openInNewFinderWindow(resolved.url)
            Log.ui.info("FastFolder opened \(folder.name, privacy: .public)")
        } catch {
            unavailableFolderIDs.insert(folder.id)
            Log.service.error(
                "FastFolder open failed for \(folder.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
