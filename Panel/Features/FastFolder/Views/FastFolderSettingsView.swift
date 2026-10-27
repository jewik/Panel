//
//  FastFolderSettingsView.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import AppKit
import SwiftUI
import os

struct FastFolderSettingsView: View {

    @Environment(FastFolderStore.self) private var store

    @State private var isClearConfirmationPresented = false

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            list
        }
        .padding(10)
        .frame(width: 600, height: 150)
        .onAppear {
            store.refresh()
        }
        .confirmationDialog(
            "Clear all folders?",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                store.removeAll()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Folders are removed from FastFolders only. Nothing is deleted from disk.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("FastFolders")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("\(store.folders.count)/\(FastFolderStore.maximumFolderCount)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))

            Spacer(minLength: 8)

            FastFolderToolbarButton(
                systemName: "arrow.clockwise",
                helpText: "Refresh folders",
                isDisabled: store.folders.isEmpty
            ) {
                store.refresh()
            }

            FastFolderToolbarButton(
                systemName: "trash",
                helpText: "Clear all folders",
                isDisabled: store.folders.isEmpty
            ) {
                NSApp.activate(ignoringOtherApps: true)
                isClearConfirmationPresented = true
            }

            FastFolderToolbarButton(
                systemName: "plus",
                helpText: "Add folders",
                isDisabled: !store.canAddFolder
            ) {
                presentAddPanel()
            }
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private var list: some View {
        if store.folders.isEmpty {
            Text("No folders added")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.folders) { folder in
                        FastFolderSettingsItemView(
                            folder: folder,
                            isUnavailable: store.unavailableFolderIDs.contains(folder.id),
                            onRemove: {
                                store.removeFolder(id: folder.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func presentAddPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose folders to add to FastFolders"

        guard panel.runModal() == .OK else {
            return
        }

        let outcome = store.addFolders(panel.urls)

        Log.ui.info(
            "FastFolder add finished: added \(outcome.added), duplicates \(outcome.skippedDuplicates), over limit \(outcome.rejectedByLimit), failed \(outcome.failed)"
        )
    }
}

private struct FastFolderToolbarButton: View {

    let systemName: String
    let helpText: String
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isDisabled ? 0.3 : 1))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(isHovered && !isDisabled ? 0.15 : 0))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}
