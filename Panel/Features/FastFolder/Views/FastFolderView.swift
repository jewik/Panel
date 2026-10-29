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

    private let itemWidth: CGFloat = 76
    private let itemSpacing: CGFloat = 8
    private let horizontalPadding: CGFloat = 10
    private let shelfHeight: CGFloat = 100
    private let placeholderWidth: CGFloat = 400
    private let maximumShelfWidth: CGFloat = 900

    private var shelfWidth: CGFloat {
        let count = CGFloat(store.availableFolders.count)

        guard count > 0 else {
            return placeholderWidth
        }

        let contentWidth = count * itemWidth + (count - 1) * itemSpacing + horizontalPadding * 2
        return min(contentWidth, maximumShelfWidth)
    }

    var body: some View {
        content
            .frame(width: shelfWidth, height: shelfHeight)
            .disabled(store.isRefreshing)
            .overlay {
                if store.isRefreshing {
                    refreshIndicator
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: store.isRefreshing)
            .onAppear {
                Task {
                    await store.refresh()
                }
            }
    }

    private var refreshIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)

            Text("Refreshing…")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.6))
        )
    }

    @ViewBuilder
    private var content: some View {
        if store.folders.isEmpty {
            placeholder(
                systemName: "folder.badge.plus",
                title: "Add folders in Settings",
                help: "Opens FastFolder settings"
            )
        } else if store.availableFolders.isEmpty {
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
            HStack(spacing: itemSpacing) {
                ForEach(store.availableFolders) { folder in
                    FastFolderItemView(folder: folder) {
                        Task {
                            await store.open(folder)
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(height: shelfHeight - horizontalPadding * 2)
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
