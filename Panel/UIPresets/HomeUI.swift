//
//  Home.swift
//  UITests
//
//  Created by Usanin Ivan on 17.07.2026.
//
import SwiftUI

struct HomeUI: View {

    var body: some View {
        HStack(alignment: .center , spacing: 0){
            FastFolderView()
            
            Divider()
                .padding(.vertical, 10)
                .frame(height: 100)
            
            PlayerUI()
        }
//        FastFolderView()
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
