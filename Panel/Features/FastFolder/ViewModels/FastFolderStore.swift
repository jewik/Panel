//
//  FastFolderStore.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import Foundation
import Observation
import os

struct FastFolderAddOutcome: Equatable, Sendable {
    var added: Int = 0
    var skippedDuplicates: Int = 0
    var rejectedByLimit: Int = 0
    var failed: Int = 0
}

enum FastFolderAvailability: Equatable, Sendable {
    case unknown
    case refreshing
    case available
    case unavailable
}

enum FastFolderStatus: Equatable, Sendable {
    case available
    case unavailable
}

@MainActor
@Observable
final class FastFolderStore {

    static let maximumFolderCount = 8

    nonisolated private static let defaultRefreshTimeout: Duration = .seconds(10)

    private(set) var folders: [FastFolder] = []
    private(set) var statuses: [FastFolder.ID: FastFolderStatus] = [:]
    private(set) var refreshingIDs: Set<FastFolder.ID> = []

    @ObservationIgnored private let storage: FastFolderStorage
    @ObservationIgnored private let bookmarkService: FastFolderBookmarkServiceProtocol
    @ObservationIgnored private let finder: FinderPresenting
    @ObservationIgnored private let picker: FolderPicking
    @ObservationIgnored private let refreshTimeout: Duration

    @ObservationIgnored private var attempts: [FastFolder.ID: UUID] = [:]
    @ObservationIgnored private var tasks: [FastFolder.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var watchdogs: [FastFolder.ID: Task<Void, Never>] = [:]

    private enum LoadResult: Sendable {
        case refreshed(bookmark: Data, snapshot: FolderSnapshot, elapsed: Duration)
        case failed(elapsed: Duration)
        case timedOut
    }

    var canAddFolder: Bool {
        folders.count < Self.maximumFolderCount
    }

    var isRefreshing: Bool {
        !refreshingIDs.isEmpty
    }

    var availableFolders: [FastFolder] {
        folders.filter { statuses[$0.id] != .unavailable }
    }

    var unavailableFolders: [FastFolder] {
        folders.filter { statuses[$0.id] == .unavailable }
    }

    init(
        storage: FastFolderStorage,
        bookmarkService: FastFolderBookmarkServiceProtocol,
        finder: FinderPresenting,
        picker: FolderPicking,
        refreshTimeout: Duration = FastFolderStore.defaultRefreshTimeout
    ) {
        self.storage = storage
        self.bookmarkService = bookmarkService
        self.finder = finder
        self.picker = picker
        self.refreshTimeout = refreshTimeout
        self.folders = storage.load()
    }

    func availability(of id: FastFolder.ID) -> FastFolderAvailability {
        if refreshingIDs.contains(id) {
            return .refreshing
        }

        switch statuses[id] {
        case .available?:
            return .available
        case .unavailable?:
            return .unavailable
        case nil:
            return .unknown
        }
    }

    // MARK: - Refresh

    /// Starts checks for every folder not already being checked and returns immediately.
    func refresh() {
        for folder in folders {
            refresh(folderID: folder.id)
        }
    }

    func refresh(folderID: FastFolder.ID) {
        guard let folder = folders.first(where: { $0.id == folderID }) else {
            return
        }
        guard attempts[folderID] == nil else {
            return
        }

        let token = UUID()
        attempts[folderID] = token
        refreshingIDs.insert(folderID)

        let service = bookmarkService
        let timeout = refreshTimeout

        tasks[folderID] = Task { [weak self] in
            let result = await Self.load(folder, using: service)
            self?.finish(folderID: folderID, token: token, result: result)
        }

        watchdogs[folderID] = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }

            self?.finish(folderID: folderID, token: token, result: .timedOut)
        }
    }

    private func finish(
        folderID: FastFolder.ID,
        token: UUID,
        result: LoadResult
    ) {
        guard attempts[folderID] == token else {
            Log.service.debug(
                "FastFolder refresh discarded late result id=\(folderID.uuidString, privacy: .public)"
            )
            return
        }

        attempts[folderID] = nil
        tasks[folderID] = nil
        watchdogs[folderID]?.cancel()
        watchdogs[folderID] = nil
        refreshingIDs.remove(folderID)

        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            statuses[folderID] = nil
            Log.service.debug(
                "FastFolder refresh discarded result for removed folder id=\(folderID.uuidString, privacy: .public)"
            )
            return
        }

        let name = folders[index].name

        switch result {
        case .refreshed(let bookmark, let snapshot, let elapsed):
            let previous = folders[index]
            folders[index].bookmark = bookmark
            folders[index].name = snapshot.name
            folders[index].tags = snapshot.tags
            folders[index].tagColorIndex = snapshot.tagColorIndex
            statuses[folderID] = .available

            if folders[index] != previous {
                storage.save(folders)
            }

            Log.service.info(
                "FastFolder refresh refreshed id=\(folderID.uuidString, privacy: .public) name=\(snapshot.name, privacy: .public) in \(Self.seconds(elapsed), format: .fixed(precision: 2))s"
            )

        case .failed(let elapsed):
            statuses[folderID] = .unavailable
            Log.service.info(
                "FastFolder refresh unavailable id=\(folderID.uuidString, privacy: .public) name=\(name, privacy: .public) in \(Self.seconds(elapsed), format: .fixed(precision: 2))s"
            )

        case .timedOut:
            statuses[folderID] = .unavailable
            Log.service.info(
                "FastFolder refresh timed out id=\(folderID.uuidString, privacy: .public) name=\(name, privacy: .public) after \(Self.seconds(self.refreshTimeout), format: .fixed(precision: 2))s"
            )
        }
    }

    nonisolated private static func load(
        _ folder: FastFolder,
        using service: FastFolderBookmarkServiceProtocol
    ) async -> LoadResult {
        let startedAt = ContinuousClock.now

        do {
            let resolved = try await service.resolve(folder.bookmark)
            let bookmark = resolved.isStale
                ? try await service.makeBookmark(for: resolved.url)
                : folder.bookmark
            let snapshot = try await service.snapshot(of: resolved.url)

            return .refreshed(
                bookmark: bookmark,
                snapshot: snapshot,
                elapsed: startedAt.duration(to: .now)
            )
        } catch is CancellationError {
            return .failed(elapsed: startedAt.duration(to: .now))
        } catch {
            Log.service.error(
                "FastFolder refresh failed for \(folder.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .failed(elapsed: startedAt.duration(to: .now))
        }
    }

    nonisolated private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    // MARK: - Folder actions

    @discardableResult
    func addFolders(_ urls: [URL]) async -> FastFolderAddOutcome {
        var outcome = FastFolderAddOutcome()
        var knownPaths = Set<String>()
        var unresolvedNames = Set<String>()

        for folder in folders {
            if let resolved = try? await bookmarkService.resolve(folder.bookmark) {
                knownPaths.insert(resolved.url.standardizedFileURL.path)
            } else {
                unresolvedNames.insert(folder.name)
            }
        }

        for url in urls {
            let path = url.standardizedFileURL.path

            if knownPaths.contains(path) || unresolvedNames.contains(url.lastPathComponent) {
                outcome.skippedDuplicates += 1
                Log.service.debug(
                    "FastFolder duplicate skipped for \(path, privacy: .public)"
                )
                continue
            }

            guard folders.count < Self.maximumFolderCount else {
                outcome.rejectedByLimit += 1
                continue
            }

            do {
                let bookmark = try await bookmarkService.makeBookmark(for: url)
                let snapshot = try await bookmarkService.snapshot(of: url)
                let folder = FastFolder(
                    name: snapshot.name,
                    bookmark: bookmark,
                    tags: snapshot.tags,
                    tagColorIndex: snapshot.tagColorIndex
                )

                folders.append(folder)
                statuses[folder.id] = .available
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
        }

        Log.ui.info(
            "FastFolder add finished: added \(outcome.added), duplicates \(outcome.skippedDuplicates), over limit \(outcome.rejectedByLimit), failed \(outcome.failed)"
        )

        return outcome
    }

    @discardableResult
    func addFoldersViaPicker() async -> FastFolderAddOutcome? {
        let urls = await picker.pickFolders()
        guard !urls.isEmpty else {
            return nil
        }

        return await addFolders(urls)
    }

    func removeFolder(id: FastFolder.ID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removed = folders.remove(at: index)
        cancelRefresh(folderID: id)
        statuses[id] = nil
        storage.save(folders)

        Log.ui.info("FastFolder removed \(removed.name, privacy: .public)")
    }

    func removeAll() {
        guard !folders.isEmpty else {
            return
        }

        for id in folders.map(\.id) {
            cancelRefresh(folderID: id)
        }

        folders.removeAll()
        statuses.removeAll()
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

            guard folders.contains(where: { $0.id == folder.id }) else {
                return
            }

            cancelRefresh(folderID: folder.id)
            statuses[folder.id] = .available
            finder.openInNewFinderWindow(resolved.url)
            Log.ui.info("FastFolder opened \(folder.name, privacy: .public)")
        } catch {
            if folders.contains(where: { $0.id == folder.id }) {
                cancelRefresh(folderID: folder.id)
                statuses[folder.id] = .unavailable
            }
            Log.service.error(
                "FastFolder open failed for \(folder.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func cancelRefresh(folderID: FastFolder.ID) {
        attempts[folderID] = nil
        tasks[folderID]?.cancel()
        tasks[folderID] = nil
        watchdogs[folderID]?.cancel()
        watchdogs[folderID] = nil
        refreshingIDs.remove(folderID)
    }
}
