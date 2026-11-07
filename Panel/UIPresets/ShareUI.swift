//
//  ShareUI.swift
//  Panel
//
//  Created by Usanin Ivan on 31.10.2026.
//

import SwiftUI


struct ShareUI: View {

    var body: some View {
        ZStack(alignment: .bottom) {
            AirDropView()
        }
        .frame(width: 400, height: 100, alignment: .bottom)
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
