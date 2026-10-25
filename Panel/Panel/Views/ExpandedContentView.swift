import SwiftUI
import UniformTypeIdentifiers
import os

struct ExpandedContentView: View {
    
    @Environment(PanelController.self) private var controller
    
    @State private var isDragging: Bool = false
    
    var body: some View {
        
        VStack (alignment: .center){
            content
        }
        
        
    }
    
    @ViewBuilder
    private var content: some View {
        
        switch controller.getExpandedPreset() {
        case .home:
            HomeUI()
        case .airdrop:
            AirDropUI()
        case .settings:
            SettingsUI()
        }
        
    }
    
}

#Preview {
    ExpandedContentView()
        .environment(AppContainer().controller)
        .environment(AppContainer().airDropService)
}
