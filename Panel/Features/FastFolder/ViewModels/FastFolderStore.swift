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

enum FastFolderRefreshError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Folder did not respond in time"
        }
    }
}

private enum FolderRefreshOutcome: Sendable {
    case refreshed(id: FastFolder.ID, bookmark: Data, snapshot: FolderSnapshot)
    case failed(id: FastFolder.ID)
}

/// Runs the blocking bookmark/filesystem work for one folder with a timeout,
/// so an unavailable (e.g. network) volume cannot stall the whole refresh.
private func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: duration)
            throw FastFolderRefreshError.timedOut
        }

        guard let winner = try await group.next() else {
            throw FastFolderRefreshError.timedOut
        }

        group.cancelAll()

        return winner
    }
}

@MainActor
@Observable
final class FastFolderStore {

    static let maximumFolderCount = 8

    /// Per-folder work must not outlive this: an unresponsive network volume
    /// ends the refresh as "unavailable" instead of spinning forever.
    nonisolated private static let refreshTimeout: Duration = .seconds(15)

    private(set) var folders: [FastFolder] = []
    private(set) var unavailableFolderIDs: Set<FastFolder.ID> = []
    private(set) var isRefreshing = false

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

    func refresh() async {
        guard !isRefreshing, !folders.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        var unavailableIDs = Set<FastFolder.ID>()
        var didChange = false

        let service = bookmarkService

        // Each folder is refreshed by its own child task on the service actor,
        // so one hanging volume cannot delay results of the others.
        await withTaskGroup(of: FolderRefreshOutcome.self) { group in
            for folder in folders {
                group.addTask {
                    await Self.refreshFolder(folder, using: service)
                }
            }

            for await outcome in group {
                switch outcome {
                case .refreshed(let id, let bookmark, let snapshot):
                    guard let index = folders.firstIndex(where: { $0.id == id }) else {
                        continue
                    }

                    let previous = folders[index]
                    folders[index].bookmark = bookmark
                    folders[index].name = snapshot.name
                    folders[index].tags = snapshot.tags
                    folders[index].tagColorIndex = snapshot.tagColorIndex
                    unavailableIDs.remove(id)

                    if folders[index] != previous {
                        didChange = true
                    }

                case .failed(let id):
                    unavailableIDs.insert(id)
                }
            }
        }

        unavailableFolderIDs = unavailableIDs

        if didChange {
            storage.save(folders)
        }

        Log.service.info(
            "FastFolder refresh finished: \(self.folders.count - unavailableIDs.count) available, \(unavailableIDs.count) unavailable, saved: \(didChange)"
        )
    }

    @discardableResult
    func addFolders(_ urls: [URL]) async -> FastFolderAddOutcome {
        var outcome = FastFolderAddOutcome()
        var knownPaths = Set<String>()

        for folder in folders {
            if let resolved = try? await bookmarkService.resolve(folder.bookmark) {
                knownPaths.insert(resolved.url.standardizedFileURL.path)
            }
        }

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
                let bookmark = try await bookmarkService.makeBookmark(for: url)
                let snapshot = try await bookmarkService.snapshot(of: url)

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

    func open(_ folder: FastFolder) async {
        do {
            let resolved = try await bookmarkService.resolve(folder.bookmark)

            if resolved.isStale {
                let refreshedBookmark = try await bookmarkService.makeBookmark(for: resolved.url)

                if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                    folders[index].bookmark = refreshedBookmark
                    storage.save(folders)
                }
            }

            await bookmarkService.openInNewFinderWindow(resolved.url)
            Log.ui.info("FastFolder opened \(folder.name, privacy: .public)")
        } catch {
            unavailableFolderIDs.insert(folder.id)
            Log.service.error(
                "FastFolder open failed for \(folder.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Per-folder refresh

    private nonisolated static func refreshFolder(
        _ folder: FastFolder,
        using service: FastFolderBookmarkServiceProtocol
    ) async -> FolderRefreshOutcome {
        do {
            let result = try await withTimeout(refreshTimeout) {
                let resolved = try await service.resolve(folder.bookmark)

                var bookmark = folder.bookmark
                if resolved.isStale {
                    bookmark = try await service.makeBookmark(for: resolved.url)
                }

                let snapshot = try await service.snapshot(of: resolved.url)
                return (bookmark: bookmark, snapshot: snapshot)
            }

            return .refreshed(
                id: folder.id,
                bookmark: result.bookmark,
                snapshot: result.snapshot
            )
        } catch {
            Log.service.error(
                "FastFolder refresh failed for \(folder.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .failed(id: folder.id)
        }
    }
}
