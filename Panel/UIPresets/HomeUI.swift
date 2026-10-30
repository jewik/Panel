//
//  Home.swift
//  UITests
//
//  Created by Usanin Ivan on 17.07.2026.
//
import SwiftUI

struct HomeUI: View {

    var body: some View {
        FastFolderView()
    }
    
}





#if DEBUG
#Preview {
    ZStack {
        PanelShape()
            .fill(.black)

        HomeUI()
    }
    .frame(width: 600, height: 150, alignment: .top)
    .environment(
        makePreviewFastFolderStore([
            PreviewFastFolder(name: "Projects", color: .blue),
            PreviewFastFolder(name: "Downloads", color: .none),
        ])
    )
    .environment(PanelController(panelState: PanelState()))
}
#endif
