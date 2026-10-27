//
//  Home.swift
//  UITests
//
//  Created by Usanin Ivan on 17.07.2026.
//
import SwiftUI

struct HomeUI: View {

    
    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 30)
                .fill(.blue.opacity(0.1))
                
            
            Text("Home")
        }
        .padding(10)
        .frame(width: 300, height: 100)

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
