//
//  FastFolderItemView.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import SwiftUI

extension FinderTagColor {
    var color: Color {
        switch self {
        case .none: .cyan
        case .gray: .gray
        case .green: .green
        case .purple: .purple
        case .blue: .blue
        case .yellow: .yellow
        case .red: .red
        case .orange: .orange
        }
    }
}

struct FastFolderItemView: View {

    let folder: FastFolder
    let action: () -> Void

    @State private var isHovered = false

    private var tagColor: Color {
        folder.tagColor.color
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(tagColor)
                    .shadow(color: tagColor.opacity(isHovered ? 0.7 : 0), radius: 6)

                Text(folder.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 76)
            }
            .frame(width: 76, height: 96)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.08 : 0))
            )
            .shadow(color: .black.opacity(isHovered ? 0.35 : 0), radius: 6, y: 3)
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
        .accessibilityHint("Opens the folder in a new Finder window")
    }
}
