//
//  CollapsedPanelView.swift
//  Notch
//
//  Created by Usanin Ivan on 08.08.2026.
//


import SwiftUI
import os


struct CollapsedContentView: View {
    
    @Environment(PanelController.self) private var controller
    

    init() {}
    
    
    var body: some View {
            ZStack(alignment: .bottom){
                Button(action: {
                    controller.showExpandedPreset(.home)
                }){
                    Capsule()
                        .fill(.secondary)
                        .frame(width: 200, height: 5)
                        .padding([.horizontal, .top], 4)
                }
                .buttonStyle(.plain)
            }
    }
}


struct CapsuleButton : View {
    
    let action : () -> Void
    
    @State private var isHovering : Bool = false
    
    var body : some View {
        
        Button(action: action){
            Capsule()
                .fill(.secondary)
                .frame(width: isHovering ? 50 : 20, height: 5)
        }
        .buttonStyle(.plain)
        .onHover{ isHovering = $0 }
        .animation(.custsmooth, value: isHovering)

    }
}

#Preview {
    CollapsedContentView()
        .environment(AppContainer().controller)
        .frame(width: 300, height: 140, alignment: .bottom)
}
