//
//  PlayerCollapsedView.swift
//  Panel
//
//  Created by Usanin Ivan on 07.11.2026.
//

import AppKit
import SwiftUI

struct PlayerCollapsedView: View {
    @Environment(PlayerStore.self) private var store

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if store.isNowPlaying, let snapshot = store.presentedSnapshot {
                HStack(alignment: .center, spacing: 10) {
                    
                    artwork(snapshot.artworkData)

                    Text(snapshot.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.custsecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .frame(width: 210, height: 46, alignment: .topLeading)
                .transition(.collapseExpandTransition)
            }
        }
        .animation(.custsmooth, value: store.isNowPlaying)
    }

    @ViewBuilder
    private func artwork(_ data: Data?) -> some View {
        if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.indigo.opacity(0.22))
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .frame(width: 26, height: 26)
        }
    }
}

#Preview("Player — active") {
    ZStack {
        PanelShape()
            .rotation(.degrees(180))
            .fill(.black)
            .frame(width: 210, height: 46)
        PlayerCollapsedView()
            .background(.red.opacity(0.2))
    }
    .frame(width: 300, height: 200, alignment: .bottom)
    .environment(makePreviewPlayerStore())
}
