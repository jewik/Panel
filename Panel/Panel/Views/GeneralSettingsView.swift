//
//  GeneralSettingsView.swift
//  Panel
//
//  Created by Usanin Ivan on 01.11.2026.
//


import SwiftUI

struct GeneralSettingsView : View {
    
    @Environment(PanelController.self) private var controller
    
    @State var useGlassInterface: Bool = true
    
    var body : some View {
        
//        RoundedRectangle(cornerRadius: 20)
//            .onTapGesture {
//                controller.toggleGlassInterface()
//            }
//            .frame(width: 100, height: 100)
        
        Toggle("Use Glass", isOn: $useGlassInterface)
            .toggleStyle(.switch)
            .onChange(of: useGlassInterface, {controller.toggleGlassInterface()})
    }
}
