//
//  FastFolderBookmarkService.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import AppKit
import Foundation
import os

struct FolderSnapshot: Equatable {
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

@MainActor
protocol FastFolderBookmarkServiceProtocol {
    func makeBookmark(for url: URL) throws -> Data
    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool)
    func snapshot(of url: URL) throws -> FolderSnapshot
    func openInNewFinderWindow(_ url: URL)
}

@MainActor
final class FastFolderBookmarkService: FastFolderBookmarkServiceProtocol {

    private static let userTagsAttribute = "com.apple.metadata:_kMDItemUserTags"

    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return (url, isStale)
    }

    func snapshot(of url: URL) throws -> FolderSnapshot {
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

        if let finderTags = Self.finderTags(of: url), !finderTags.isEmpty {
            return FolderSnapshot(
                name: name,
                tags: finderTags.map(\.name),
                tagColorIndex: finderTags.first?.colorIndex ?? 0
            )
        }

        return FolderSnapshot(
            name: name,
            tags: values.tagNames ?? [],
            tagColorIndex: 0
        )
    }

    func openInNewFinderWindow(_ url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path) {
            return
        }

        NSWorkspace.shared.open(url)
    }

    // MARK: - Finder tags

    private static func finderTags(
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
