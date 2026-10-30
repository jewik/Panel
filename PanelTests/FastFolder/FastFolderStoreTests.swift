//
//  FastFolderStoreTests.swift
//  PanelTests
//

import Foundation
import XCTest
@testable import Panel

@MainActor
final class FastFolderStoreTests: XCTestCase {

    func testLoadedFoldersStartUnknownAndVisible() {
        let first = makeFolder(name: "First")
        let second = makeFolder(name: "Second")
        let storage = FastFolderStorageDouble(folders: [first, second])
        let store = makeStore(storage: storage)

        XCTAssertEqual(store.availability(of: first.id), .unknown)
        XCTAssertEqual(store.availability(of: second.id), .unknown)
        XCTAssertEqual(store.availableFolders.map(\.id), [first.id, second.id])
        XCTAssertFalse(store.isRefreshing)
    }

    func testRefreshPublishesEachFolderAsSoonAsItFinishes() async {
        let fast = makeFolder(name: "Fast")
        let slow = makeFolder(name: "Slow")
        let service = FastFolderBookmarkServiceDouble(entriesByBookmark: [
            fast.bookmark: .init(
                url: folderURL("fast"),
                snapshot: snapshot("Fast Updated"),
                resolveDelay: .milliseconds(10)
            ),
            slow.bookmark: .init(
                url: folderURL("slow"),
                snapshot: snapshot("Slow Updated"),
                resolveDelay: .milliseconds(150)
            ),
        ])
        let storage = FastFolderStorageDouble(folders: [fast, slow])
        let store = makeStore(storage: storage, service: service)

        store.refresh()

        XCTAssertEqual(store.availability(of: fast.id), .refreshing)
        XCTAssertEqual(store.availability(of: slow.id), .refreshing)

        await assertEventually {
            store.availability(of: fast.id) == .available
        }
        XCTAssertEqual(store.availability(of: slow.id), .refreshing)
        XCTAssertTrue(store.isRefreshing)
        XCTAssertEqual(store.folders.first(where: { $0.id == fast.id })?.name, "Fast Updated")

        await assertEventually {
            store.availability(of: slow.id) == .available
        }
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(storage.savedFolders.count, 2)
    }

    func testFailedFolderDoesNotWaitForSlowFolder() async {
        let failed = makeFolder(name: "Failed")
        let slow = makeFolder(name: "Slow")
        let service = FastFolderBookmarkServiceDouble(entriesByBookmark: [
            failed.bookmark: .init(
                url: folderURL("failed"),
                snapshot: snapshot("Failed"),
                resolveDelay: .milliseconds(10),
                resolveFails: true
            ),
            slow.bookmark: .init(
                url: folderURL("slow"),
                snapshot: snapshot("Slow"),
                resolveDelay: .milliseconds(150)
            ),
        ])
        let store = makeStore(
            storage: FastFolderStorageDouble(folders: [failed, slow]),
            service: service
        )

        store.refresh()

        await assertEventually {
            store.availability(of: failed.id) == .unavailable
        }
        XCTAssertEqual(store.availability(of: slow.id), .refreshing)
        XCTAssertEqual(store.availableFolders.map(\.id), [slow.id])

        await assertEventually {
            store.availability(of: slow.id) == .available
        }
    }

    func testTimeoutMarksFolderUnavailableAndDiscardsLateResult() async {
        let folder = makeFolder(name: "Network")
        let service = FastFolderBookmarkServiceDouble(entriesByBookmark: [
            folder.bookmark: .init(
                url: folderURL("network"),
                snapshot: snapshot("Late Result"),
                resolveDelay: .milliseconds(120)
            ),
        ])
        let store = makeStore(
            storage: FastFolderStorageDouble(folders: [folder]),
            service: service,
            refreshTimeout: .milliseconds(20)
        )

        store.refresh()

        await assertEventually {
            store.availability(of: folder.id) == .unavailable
        }
        XCTAssertFalse(store.isRefreshing)

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(store.availability(of: folder.id), .unavailable)
        XCTAssertEqual(store.folders.first?.name, "Network")
    }

    func testRetryWinsOverLateResultFromTimedOutAttempt() async {
        let folder = makeFolder(name: "Network")
        let url = folderURL("network")
        let service = FastFolderBookmarkServiceDouble(entriesByBookmark: [
            folder.bookmark: .init(
                url: url,
                snapshot: snapshot("Old Late Result"),
                resolveDelay: .milliseconds(150)
            ),
        ])
        let store = makeStore(
            storage: FastFolderStorageDouble(folders: [folder]),
            service: service,
            refreshTimeout: .milliseconds(20)
        )

        store.refresh()
        await assertEventually {
            store.availability(of: folder.id) == .unavailable
        }

        await service.setEntry(
            .init(
                url: url,
                snapshot: snapshot("Recovered"),
                resolveDelay: .milliseconds(1)
            ),
            for: folder.bookmark
        )
        store.refresh(folderID: folder.id)

        await assertEventually {
            store.availability(of: folder.id) == .available
        }
        XCTAssertEqual(store.folders.first?.name, "Recovered")

        try? await Task.sleep(for: .milliseconds(170))

        XCTAssertEqual(store.availability(of: folder.id), .available)
        XCTAssertEqual(store.folders.first?.name, "Recovered")
    }

    func testRepeatedRefreshCoalescesInFlightAttempt() async {
        let folder = makeFolder(name: "Folder")
        let service = FastFolderBookmarkServiceDouble(entriesByBookmark: [
            folder.bookmark: .init(
                url: folderURL("folder"),
                snapshot: snapshot("Folder"),
                resolveDelay: .milliseconds(80)
            ),
        ])
        let store = makeStore(
            storage: FastFolderStorageDouble(folders: [folder]),
            service: service
        )

        store.refresh()
        store.refresh()
        try? await Task.sleep(for: .milliseconds(10))

        let firstCallCount = await service.resolveCallCount(for: folder.bookmark)
        XCTAssertEqual(firstCallCount, 1)

        await assertEventually {
            store.availability(of: folder.id) == .available
        }
        store.refresh()
        await assertEventuallyAsync {
            await service.resolveCallCount(for: folder.bookmark) == 2
        }
        await assertEventually {
            store.availability(of: folder.id) == .available
        }
    }

    func testRemovingFolderDuringRefreshClearsAllState() async {
        let folder = makeFolder(name: "Folder")
        let storage = FastFolderStorageDouble(folders: [folder])
        let service = FastFolderBookmarkServiceDouble(entriesByBookmark: [
            folder.bookmark: .init(
                url: folderURL("folder"),
                snapshot: snapshot("Late"),
                resolveDelay: .milliseconds(100)
            ),
        ])
        let store = makeStore(storage: storage, service: service)

        store.refresh()
        store.removeFolder(id: folder.id)

        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertTrue(store.statuses.isEmpty)
        XCTAssertTrue(store.refreshingIDs.isEmpty)
        XCTAssertEqual(storage.savedFolders.last, [])

        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertTrue(store.statuses.isEmpty)
        XCTAssertFalse(store.isRefreshing)
    }

    func testAddFoldersUsesNameFallbackForUnresolvedExistingFolder() async {
        let existing = makeFolder(name: "Archive")
        let archiveURL = folderURL("Archive")
        let projectsURL = folderURL("Projects")
        let projectsBookmark = FastFolderBookmarkServiceDouble.bookmark(for: projectsURL)
        let service = FastFolderBookmarkServiceDouble(entriesByBookmark: [
            existing.bookmark: .init(
                url: folderURL("offline-archive"),
                snapshot: snapshot("Archive"),
                resolveFails: true
            ),
            projectsBookmark: .init(
                url: projectsURL,
                snapshot: snapshot("Projects")
            ),
        ])
        let storage = FastFolderStorageDouble(folders: [existing])
        let store = makeStore(storage: storage, service: service)

        let outcome = await store.addFolders([archiveURL, projectsURL])

        XCTAssertEqual(outcome.added, 1)
        XCTAssertEqual(outcome.skippedDuplicates, 1)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(store.folders.map(\.name), ["Archive", "Projects"])
        XCTAssertEqual(store.availability(of: store.folders[1].id), .available)
        XCTAssertEqual(storage.savedFolders.count, 1)
    }

    func testSuccessfulOpenCancelsOlderRefreshResult() async {
        let folder = makeFolder(name: "Folder")
        let url = folderURL("folder")
        let service = FastFolderBookmarkServiceDouble(entriesByBookmark: [
            folder.bookmark: .init(
                url: url,
                snapshot: snapshot("Late Refresh"),
                resolveDelay: .milliseconds(120)
            ),
        ])
        let finder = FinderPresenterDouble()
        let store = makeStore(
            storage: FastFolderStorageDouble(folders: [folder]),
            service: service,
            finder: finder,
            refreshTimeout: .milliseconds(200)
        )

        store.refresh()
        await assertEventuallyAsync {
            await service.resolveCallCount(for: folder.bookmark) == 1
        }
        await service.setEntry(
            .init(
                url: url,
                snapshot: snapshot("Folder"),
                resolveDelay: .milliseconds(1)
            ),
            for: folder.bookmark
        )
        await store.open(folder)

        XCTAssertEqual(store.availability(of: folder.id), .available)
        XCTAssertEqual(finder.openedURLs, [url])

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(store.availability(of: folder.id), .available)
        XCTAssertEqual(store.folders.first?.name, "Folder")
    }

    func testStaleBookmarkIsReplacedWhenOpeningFolder() async {
        let folder = makeFolder(name: "Folder")
        let url = folderURL("folder")
        let refreshedBookmark = FastFolderBookmarkServiceDouble.bookmark(for: url)
        let service = FastFolderBookmarkServiceDouble(entriesByBookmark: [
            folder.bookmark: .init(
                url: url,
                snapshot: snapshot("Folder"),
                isStale: true
            ),
            refreshedBookmark: .init(
                url: url,
                snapshot: snapshot("Folder")
            ),
        ])
        let storage = FastFolderStorageDouble(folders: [folder])
        let finder = FinderPresenterDouble()
        let store = makeStore(storage: storage, service: service, finder: finder)

        await store.open(folder)

        XCTAssertEqual(store.folders.first?.bookmark, refreshedBookmark)
        XCTAssertEqual(storage.savedFolders.count, 1)
        XCTAssertEqual(finder.openedURLs, [url])
        XCTAssertEqual(store.availability(of: folder.id), .available)
    }

    // MARK: - Helpers

    private func makeStore(
        storage: FastFolderStorageDouble? = nil,
        service: FastFolderBookmarkServiceDouble? = nil,
        finder: FinderPresenterDouble? = nil,
        picker: FolderPickerDouble? = nil,
        refreshTimeout: Duration = .seconds(1)
    ) -> FastFolderStore {
        FastFolderStore(
            storage: storage ?? FastFolderStorageDouble(),
            bookmarkService: service ?? FastFolderBookmarkServiceDouble(),
            finder: finder ?? FinderPresenterDouble(),
            picker: picker ?? FolderPickerDouble(),
            refreshTimeout: refreshTimeout
        )
    }

    private func makeFolder(name: String) -> FastFolder {
        FastFolder(
            name: name,
            bookmark: Data("bookmark-\(name)".utf8)
        )
    }

    private func folderURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/Test/FastFolder/\(name)", isDirectory: true)
    }

    private func snapshot(_ name: String) -> FolderSnapshot {
        FolderSnapshot(name: name, tags: [], tagColorIndex: 0)
    }

    private func eventually(
        timeout: Duration = .seconds(1),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let startedAt = ContinuousClock.now

        while !condition() {
            if startedAt.duration(to: .now) >= timeout {
                return false
            }
            try? await Task.sleep(for: .milliseconds(5))
        }

        return true
    }

    private func assertEventually(
        timeout: Duration = .seconds(1),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @MainActor () -> Bool
    ) async {
        let didSatisfyCondition = await eventually(
            timeout: timeout,
            condition: condition
        )
        XCTAssertTrue(didSatisfyCondition, file: file, line: line)
    }

    private func eventuallyAsync(
        timeout: Duration = .seconds(1),
        condition: () async -> Bool
    ) async -> Bool {
        let startedAt = ContinuousClock.now

        while !(await condition()) {
            if startedAt.duration(to: .now) >= timeout {
                return false
            }
            try? await Task.sleep(for: .milliseconds(5))
        }

        return true
    }

    private func assertEventuallyAsync(
        timeout: Duration = .seconds(1),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () async -> Bool
    ) async {
        let didSatisfyCondition = await eventuallyAsync(
            timeout: timeout,
            condition: condition
        )
        XCTAssertTrue(didSatisfyCondition, file: file, line: line)
    }
}

// MARK: - Test doubles

@MainActor
private final class FastFolderStorageDouble: FastFolderStorage {
    private let loadedFolders: [FastFolder]
    private(set) var savedFolders: [[FastFolder]] = []

    init(folders: [FastFolder] = []) {
        self.loadedFolders = folders
    }

    func load() -> [FastFolder] {
        loadedFolders
    }

    func save(_ folders: [FastFolder]) {
        savedFolders.append(folders)
    }
}

private actor FastFolderBookmarkServiceDouble: FastFolderBookmarkServiceProtocol {
    struct Entry: Sendable {
        let url: URL
        let snapshot: FolderSnapshot
        var isStale = false
        var resolveDelay: Duration = .zero
        var resolveFails = false
    }

    private var entriesByBookmark: [Data: Entry]
    private var resolveCallCounts: [Data: Int] = [:]

    init(entriesByBookmark: [Data: Entry] = [:]) {
        self.entriesByBookmark = entriesByBookmark
    }

    func setEntry(_ entry: Entry, for bookmark: Data) {
        entriesByBookmark[bookmark] = entry
    }

    func resolveCallCount(for bookmark: Data) -> Int {
        resolveCallCounts[bookmark, default: 0]
    }

    func makeBookmark(for url: URL) async throws -> Data {
        Self.bookmark(for: url)
    }

    func resolve(_ bookmark: Data) async throws -> (url: URL, isStale: Bool) {
        resolveCallCounts[bookmark, default: 0] += 1

        guard let entry = entriesByBookmark[bookmark] else {
            throw ServiceDoubleError.missingEntry
        }

        if entry.resolveDelay > .zero {
            try await Task.sleep(for: entry.resolveDelay)
        }

        guard !entry.resolveFails else {
            throw ServiceDoubleError.unavailable
        }

        return (entry.url, entry.isStale)
    }

    func snapshot(of url: URL) async throws -> FolderSnapshot {
        guard let entry = entriesByBookmark.values.first(where: { $0.url == url }) else {
            throw ServiceDoubleError.missingEntry
        }

        return entry.snapshot
    }

    nonisolated static func bookmark(for url: URL) -> Data {
        Data("bookmark-for-\(url.standardizedFileURL.path)".utf8)
    }

    private enum ServiceDoubleError: Error {
        case missingEntry
        case unavailable
    }
}

@MainActor
private final class FinderPresenterDouble: FinderPresenting {
    private(set) var openedURLs: [URL] = []

    func openInNewFinderWindow(_ url: URL) {
        openedURLs.append(url)
    }
}

@MainActor
private final class FolderPickerDouble: FolderPicking {
    var urls: [URL]

    init(urls: [URL] = []) {
        self.urls = urls
    }

    func pickFolders() async -> [URL] {
        urls
    }
}
