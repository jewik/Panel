//
//  TrayUI.swift
//  UITests
//
//  Created by Usanin Ivan on 03.08.2026.
//
import SwiftUI


struct AirDropUI: View {

    var body: some View {
        ZStack(alignment: .bottom) {
            AirDropView()
        }
    }
}



#Preview {
    
    ZStack {
        PanelShape()
            .fill(.black)
        AirDropUI()
            .environment(AppContainer().airDropService)

            .background(Color.cyan.opacity(0.1))
    }
    .frame(width: 500, height: 150, alignment: .top)
}
