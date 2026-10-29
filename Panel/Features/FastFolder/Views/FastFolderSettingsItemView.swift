//
//  FastFolderSettingsItemView.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import SwiftUI

struct FastFolderSettingsItemView: View {

    let folder: FastFolder
    let availability: FastFolderAvailability
    let onRetry: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    private var helpText: String {
        availability == .unavailable ? "Retry" : folder.name
    }

    private var isUnavailable: Bool {
        availability == .unavailable
    }

    private var isRefreshing: Bool {
        availability == .refreshing
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                icon
                    .frame(
                        width: FastFolderMetrics.Settings.iconWidth,
                        height: FastFolderMetrics.Settings.iconHeight
                    )

                removeButton
                    .offset(x: 6, y: -2)
                    .zIndex(1)
            }
            .frame(
                width: FastFolderMetrics.Settings.iconWidth,
                height: FastFolderMetrics.Settings.iconHeight
            )

            Text(folder.name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(isUnavailable ? 0.4 : 1))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: FastFolderMetrics.Settings.captionWidth)
        }
        .frame(
            width: FastFolderMetrics.Settings.itemWidth,
            height: FastFolderMetrics.Settings.itemHeight
        )
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.06 : 0))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if isUnavailable {
                onRetry()
            }
        }
        .help(helpText)
        .accessibilityValue(isRefreshing ? "Refreshing" : "")
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
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
            .opacity(isUnavailable ? 0.4 : (isRefreshing ? 0.4 : 1))

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isRefreshing)
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
