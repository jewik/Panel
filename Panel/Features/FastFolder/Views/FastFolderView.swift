//
//  FastFolderView.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import SwiftUI

struct FastFolderView: View {

    @Environment(FastFolderStore.self) private var store
    @Environment(PanelController.self) private var controller

    private var shelfWidth: CGFloat {
        let count = CGFloat(store.availableFolders.count)

        guard count > 0 else {
            return FastFolderMetrics.placeholderWidth
        }

        let contentWidth = count * FastFolderMetrics.itemWidth
            + (count - 1) * FastFolderMetrics.itemSpacing
            + FastFolderMetrics.horizontalPadding * 2
        return min(contentWidth, FastFolderMetrics.maximumShelfWidth)
    }

    var body: some View {
        content
            .frame(width: shelfWidth, height: FastFolderMetrics.shelfHeight)
            .task {
                store.refresh()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.folders.isEmpty {
            placeholder(
                systemName: "folder.badge.plus",
                title: "Add folders in Settings",
                help: "Opens FastFolder settings"
            )
        } else if store.availableFolders.isEmpty && !store.isRefreshing {
            placeholder(
                systemName: "folder.badge.questionmark",
                title: "Folders unavailable",
                help: "Opens FastFolder settings"
            )
        } else {
            shelf
        }
    }

    private var shelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FastFolderMetrics.itemSpacing) {
                ForEach(store.availableFolders) { folder in
                    FastFolderItemView(
                        folder: folder,
                        isRefreshing: store.refreshingIDs.contains(folder.id)
                    ) {
                        Task {
                            await store.open(folder)
                        }
                    }
                }
            }
            .padding(.horizontal, FastFolderMetrics.horizontalPadding)
            .padding(.vertical, FastFolderMetrics.verticalPadding)
            .frame(height: FastFolderMetrics.shelfHeight)
        }
    }

    private func placeholder(
        systemName: String,
        title: String,
        help: String
    ) -> some View {
        Button {
            controller.showPreset(.settings)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.cyan)

                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityHint(help)
    }
}
