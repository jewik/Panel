//
//  BarView.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import SwiftUI

struct BarView: View {
    
    @Environment(PanelController.self) private var controller
    
    @State var isHovered: Bool = false
    
    init() {}
    
    var body: some View {
        ZStack(alignment: .bottom){
            Button(action: {
                controller.showPreset(.home)
            }){
                Capsule()
                    .fill(isHovered ? .white : .secondary)
                    .frame(width: 200, height: 5)
                    .padding([.horizontal, .top], isHovered ? 5 : 3)
            }
            .buttonStyle(.plain)
            .onHover{ isHovered = $0 }
        }
        .animation(.custsmooth, value: isHovered)
    }
}

#Preview {
    BarView()
        .environment(AppContainer().controller)
        .frame(width: 300, height: 140, alignment: .bottom)
}
