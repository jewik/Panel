//
//  GlassView.swift
//  Notch
//
//  Created by Usanin Ivan on 26.10.2026.
//



import SwiftUI


struct GlassView: View {
    
    var body: some View{
        Color.clear
            .glassEffect(.clear, in: Capsule())
            .environment(\.appearsActive, true)
            .materialActiveAppearance(.active)
        
    
    }
}

#Preview {
    GlassView()
        .frame(width: 100, height: 40)
        .frame(width: 200, height: 100, alignment: .center)
}
