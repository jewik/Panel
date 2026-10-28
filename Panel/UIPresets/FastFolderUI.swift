//
//  FastFolder.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import SwiftUI

struct FastFolderUI: View {
    var body: some View {
        FastFolderView()
    }
}

#Preview("FastFolder — folders") {
    ZStack(alignment: .top) {
        PanelShape()
            .fill(.black)

        FastFolderUI()
    }
    .frame(width: 620, height: 150, alignment: .top)
    .environment(
        makePreviewFastFolderStore([
            PreviewFastFolder(name: "Projects", color: .blue, tags: ["Work"]),
            PreviewFastFolder(name: "Screenshots", color: .orange, tags: ["Design"]),
            PreviewFastFolder(name: "Downloads", color: .none),
        ])
    )
    .environment(PanelController(panelState: PanelState()))
}

#Preview("FastFolder — empty") {
    ZStack(alignment: .top) {
        PanelShape()
            .fill(.black)

        FastFolderUI()
    }
    .frame(width: 620, height: 150, alignment: .top)
    .environment(makePreviewFastFolderStore([]))
    .environment(PanelController(panelState: PanelState()))
}

#Preview("FastFolder — unavailable") {
    ZStack(alignment: .top) {
        PanelShape()
            .fill(.black)

        FastFolderUI()
    }
    .frame(width: 620, height: 150, alignment: .top)
    .environment(
        makePreviewFastFolderStore([
            PreviewFastFolder(name: "Projects", color: .blue, isAvailable: false),
            PreviewFastFolder(name: "Archive", color: .green, isAvailable: false),
        ])
    )
    .environment(PanelController(panelState: PanelState()))
}
