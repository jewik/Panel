//
//  FastFolderItemView.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import SwiftUI

struct FastFolderItemView: View {

    let folder: FastFolder
    let isRefreshing: Bool
    let onOpen: () -> Void

    @State private var isHovered = false

    private var tagColor: Color {
        folder.tagColor.color
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 4) {
                ZStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 50, weight: .regular))
                        .foregroundStyle(tagColor)
                        .opacity(isRefreshing ? 0.35 : 1)
                        .shadow(color: tagColor.opacity(isHovered ? 0.7 : 0), radius: 6)

                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .transition(.opacity)
                            .offset(y: 4)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isRefreshing)

                Text(folder.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: FastFolderMetrics.itemWidth)
            }
            .frame(
                width: FastFolderMetrics.itemWidth,
                height: FastFolderMetrics.itemHeight
            )
            .offset(y: isHovered ? -3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help(folder.name)
        .accessibilityLabel(folder.name)
        .accessibilityValue(isRefreshing ? "Refreshing" : "")
        .accessibilityHint("Opens the folder in a new Finder window")
    }
}
