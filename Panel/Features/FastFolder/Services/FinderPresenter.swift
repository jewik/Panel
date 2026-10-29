//
//  FinderPresenter.swift
//  Panel
//
//  Created by Codex on 29.10.2026.
//

import AppKit
import Foundation

@MainActor
protocol FinderPresenting {
    func openInNewFinderWindow(_ url: URL)
}

@MainActor
final class FinderPresenter: FinderPresenting {

    func openInNewFinderWindow(_ url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let selected = NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: url.path
        )

        if !selected {
            NSWorkspace.shared.open(url)
        }
    }
}
