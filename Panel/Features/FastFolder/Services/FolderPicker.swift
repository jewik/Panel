//
//  FolderPicker.swift
//  Panel
//
//  Created by Codex on 29.10.2026.
//

import AppKit
import Foundation

@MainActor
protocol FolderPicking {
    func pickFolders() async -> [URL]
}

@MainActor
final class FolderPicker: FolderPicking {

    func pickFolders() async -> [URL] {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose folders to add to FastFolders"

        let response = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
        }

        return response == .OK ? panel.urls : []
    }
}
