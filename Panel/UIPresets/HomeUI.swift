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





#Preview {
    ZStack {
        PanelShape()
            .fill(.black)

        HomeUI()
    }
    .frame(width: 600, height: 150, alignment: .top)
}
