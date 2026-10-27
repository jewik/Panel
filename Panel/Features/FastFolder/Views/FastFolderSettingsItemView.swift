//
//  FastFolderSettingsItemView.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import SwiftUI

struct FastFolderSettingsItemView: View {

    let folder: FastFolder
    let isUnavailable: Bool
    let onRemove: () -> Void

    @State private var isHovered = false

    private var helpText: String {
        isUnavailable ? "Folder is unavailable" : folder.name
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                icon
                    .frame(width: 62, height: 54)

                removeButton
                    .offset(x: 6, y: -2)
            }
            .frame(width: 70, height: 54)

            Text(folder.name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(isUnavailable ? 0.4 : 1))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .frame(width: 86, height: 84)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.06 : 0))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
    }

    @ViewBuilder
    private var icon: some View {
        Group {
            if isUnavailable {
                Image(systemName: "folder.badge.questionmark")
                    .foregroundStyle(.gray)
            } else {
                Image(systemName: "folder.fill")
                    .foregroundStyle(folder.tagColor.color)
            }
        }
        .font(.system(size: 54, weight: .regular))
        .opacity(isUnavailable ? 0.4 : 1)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("Remove \(folder.name)")
        .accessibilityLabel("Remove \(folder.name)")
    }
}
