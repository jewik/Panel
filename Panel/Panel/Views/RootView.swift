

import SwiftUI
import UniformTypeIdentifiers
import os

struct RootView: View {
    
    @Environment(PanelController.self) private var controller
    
    @State private var contentSize: CGSize = .zero
    @State private var isDragging: Bool = false
    
    private let panelRadiusRules = UnionPanelShape.RadiusRules(
        ear: { height in min(height / 4, 40) },
        angle: { height in min(height / 4 * 3, 50) }
    )
    
    
    init() {}
    
    var body: some View {
        VStack(alignment: .center ,spacing: 10){
            
            
            if !controller.checkPreset(.collapsed) {
                navigation
                    .transition(.collapseExpandTransition)
            }
            
            ZStack (alignment: .bottom){
                
                surface
                
                content
                
                    .onGeometryChange(for: CGSize.self) { geo in
                        geo.size
                    } action: { size in
                        Log.ui.info("PanelView resize to: \(String(describing: size))")
                        
                        withAnimation(.custsmooth) {
                            contentSize = size
                        }
                    }
                

                
            }
            
            
            // handle airdrop
            .onDrop(
                of: [UTType.fileURL],
                isTargeted: $isDragging
            ) {
                providers in
                Log.ui.info("File dragged to panel")
                return true
            }
            .onChange(of: isDragging) {oldValue, newValue in
                if newValue {
                    controller.showPreset(.airdrop)
                }
            }
            
        }
        .onContinuousHover{ phase in
            if phase == .ended {
                controller.collapse()
                Log.ui.info("Hover ended, collapse preset called")
            }
        }
        .frame(width: 1000, height: 400, alignment: .bottom)
        //        .background(.red)
    }
    
    @ViewBuilder
    private var surface : some View {
        ZStack (alignment: .top) {
            
            UnionPanelShape(radiusRules: panelRadiusRules)
                .rotation(.degrees(180))
                .fill(.black)
                .shadow(color: !controller.checkPreset(.collapsed) ? .black : .clear, radius: 20)
            
            
        }
        .frame(
            width: contentSize.width
            + panelRadiusRules.earRadius(for: contentSize.height) * 2,
            height: contentSize.height,
            alignment: .bottom
        )
        
        
    }
    
    @ViewBuilder
    private var content : some View {
        ZStack(alignment: .bottom){
            switch controller.getPreset() {
            case .collapsed:
                EmptyView()
                    .transition(.collapseExpandTransition)
            case .home:
                HomeUI()
                    .transition(.collapseExpandTransition)
            case .fastfolder:
                FastFolderUI()
                    .transition(.collapseExpandTransition)
            case .airdrop:
                AirDropUI()
                    .transition(.collapseExpandTransition)
            case .settings:
                SettingsUI()
                    .transition(.collapseExpandTransition)
            }
            
            bar
        }
    }
    
    private var navigation: some View {
        ZStack(alignment: .center) {
            Capsule()
                .fill(.black)
                .shadow(color: !controller.checkPreset(.collapsed) ? .black : .clear, radius: 20)
 
            
            //            Color.clear
            //                .glassEffect(.clear, in: Capsule())
            //                .frame(width: 80, height: 30)
            
            NavigationRowView(
                terminateApplication: { NSApp.terminate(nil) }
            )
            
        }
        .frame(width: 160, height: 30)
    }
    
    private var bar: some View {
        BarView()
    }
    
}



#Preview {
    RootView()
        .environment(AppContainer().controller)
        .environment(AppContainer().airDropService)
        .background(.gray.opacity(0.1))
}

