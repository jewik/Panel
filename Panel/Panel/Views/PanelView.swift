

import SwiftUI
import UniformTypeIdentifiers
import os

struct PanelView: View {
    
    @Environment(PanelController.self) private var controller
    
    @State private var contentSize: CGSize = .zero
    @State private var resizeAnimation: Animation = .smooth
    @State private var isPanelHovered: Bool = false
    @State private var isDragging: Bool = false
    
    private let panelRadiusRules = UnionPanelShape.RadiusRules(
        ear: { height in min(height / 3, 30) },
        angle: { height in min(height / 3 * 2, 50) }
    )
    
    
    init() {}
    
    var body: some View {
        VStack(alignment: .center ,spacing: 10){
            
            
            if controller.getPanelMode() == .expanded {
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
                    controller.showExpandedPreset(.airdrop)
                }
            }
            
        }
        .onContinuousHover{ phase in
            if phase == .ended {
                controller.showCollapsedPreset()
                Log.ui.info("Hover ended, collapse preset called")
            }
        }
        .frame(width: 800, height: 300, alignment: .bottom)
        //        .background(.red)
    }
    
    @ViewBuilder
    private var surface : some View {
        ZStack (alignment: .top) {
            UnionPanelShape(radiusRules: panelRadiusRules)
                .rotation(.degrees(180))
                .fill(.black)
            
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
        ZStack(alignment: .top) {
            
            switch controller.getPanelMode() {
            case .collapsed:
                CollapsedContentView()
                    .transition(.collapseExpandTransition)
            case .expanded:
                ExpandedContentView().transition(.collapseExpandTransition)
                
            }
        }
    }
    
    @ViewBuilder
    private var navigation: some View {
        ZStack(alignment: .center) {
            Capsule()
                .fill(.black)
                .frame(width: 80, height: 30)

            NavigationRowView(
                terminateApplication: { NSApp.terminate(nil) }
            )

        }
        
    }
    
}



#Preview {
    PanelView()
        .environment(AppContainer().controller)
        .environment(AppContainer().airDropService)
        .background(.gray.opacity(0.1))
}

