//
//  FastFolderBookmarkService.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import Foundation
import os

struct FolderSnapshot: Equatable, Sendable {
    let name: String
    let tags: [String]
    let tagColorIndex: Int
}

enum FastFolderBookmarkError: LocalizedError {
    case notDirectory(URL)

    var errorDescription: String? {
        switch self {
        case .notDirectory(let url):
            return "Selected item is not a folder: \(url.lastPathComponent)"
        }
    }
}

protocol FastFolderBookmarkServiceProtocol: Sendable {
    func makeBookmark(for url: URL) async throws -> Data
    func resolve(_ bookmark: Data) async throws -> (url: URL, isStale: Bool)
    func snapshot(of url: URL) async throws -> FolderSnapshot
}

/// Runs blocking bookmark and filesystem calls on a concurrent dispatch queue.
/// A stalled network volume therefore does not serialize checks for other folders.
struct FastFolderBookmarkService: FastFolderBookmarkServiceProtocol {

    private let queue = DispatchQueue(
        label: "com.panel.fastfolder.bookmark",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func makeBookmark(for url: URL) async throws -> Data {
        try await perform {
            try Self.makeBookmarkSync(for: url)
        }
    }

    func resolve(_ bookmark: Data) async throws -> (url: URL, isStale: Bool) {
        try await perform {
            try Self.resolveSync(bookmark)
        }
    }

    func snapshot(of url: URL) async throws -> FolderSnapshot {
        try await perform {
            try Self.snapshotSync(of: url)
        }
    }

    private func perform<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    nonisolated private static func makeBookmarkSync(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    nonisolated private static func resolveSync(
        _ bookmark: Data
    ) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return (url, isStale)
    }

    nonisolated private static func snapshotSync(of url: URL) throws -> FolderSnapshot {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .nameKey,
            .tagNamesKey,
        ])

        guard values.isDirectory == true else {
            throw FastFolderBookmarkError.notDirectory(url)
        }

        let name = values.name ?? url.lastPathComponent

        guard let finderTags = Self.finderTags(of: url), !finderTags.isEmpty else {
            return FolderSnapshot(
                name: name,
                tags: values.tagNames ?? [],
                tagColorIndex: 0
            )
        }

        return FolderSnapshot(
            name: name,
            tags: finderTags.map(\.name),
            tagColorIndex: finderTags.first?.colorIndex ?? 0
        )
    }

    // MARK: - Finder tags

    nonisolated private static let userTagsAttribute = "com.apple.metadata:_kMDItemUserTags"

    nonisolated private static func finderTags(
        of url: URL
    ) -> [(name: String, colorIndex: Int)]? {
        let path = url.path
        let attribute = userTagsAttribute

        let dataSize = getxattr(path, attribute, nil, 0, 0, 0)
        guard dataSize > 0 else {
            return nil
        }

        var data = Data(count: dataSize)
        let readSize = data.withUnsafeMutableBytes { buffer in
            getxattr(path, attribute, buffer.baseAddress, dataSize, 0, 0)
        }

        guard readSize == dataSize else {
            Log.service.error(
                "FastFolder xattr read failed for \(path, privacy: .public)"
            )
            return nil
        }

        guard let propertyList = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ),
        let rawTags = propertyList as? [String] else {
            Log.service.error(
                "FastFolder xattr decode failed for \(path, privacy: .public)"
            )
            return nil
        }

        return rawTags.map { rawTag in
            let components = rawTag.split(
                separator: "\n",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )

            let name = components.first.map(String.init) ?? rawTag
            let colorIndex = components.count > 1
                ? Int(components[1].trimmingCharacters(in: .whitespaces)) ?? 0
                : 0

            return (name: name, colorIndex: colorIndex)
        }
    }
}
