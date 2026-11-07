

import SwiftUI
import UniformTypeIdentifiers
import os

struct RootView: View {
    
    @Environment(PanelController.self) private var controller
    
    @State private var contentSize: CGSize = .zero
    @State private var isDragging: Bool = false
    
    @State private var sliderBarValue: Double = 1
    @State private var isSliderActive: Bool = false
    
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
                        
                        withAnimation(selectAnimation(from: contentSize, to: size)) {
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
                    controller.showPreset(.share)
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
            
            if controller.isGlassInterface() {
                Color.clear
                    .glassEffect(.clear, in: UnionPanelShape(radiusRules: panelRadiusRules)
                        .rotation(.degrees(180)))
                    .shadow(color: !controller.checkPreset(.collapsed) ? .black : .clear, radius: 20)
                
                //                UnionPanelShape(radiusRules: panelRadiusRules)
                //                    .rotation(.degrees(180))
                //                    .fill(.black)
                //                    .shadow(color: !controller.checkPreset(.collapsed) ? .black : .clear, radius: 20)
                
                AnimatedPanelBackground(
                    height: contentSize.height,
                    radiusRules: panelRadiusRules
                )
            } else {
                UnionPanelShape(radiusRules: panelRadiusRules)
                    .rotation(.degrees(180))
                    .fill(.black)
                    .shadow(color: !controller.checkPreset(.collapsed) ? .black : .clear, radius: 20)
            }
            
            
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
            case .share:
                ShareUI()
                    .transition(.collapseExpandTransition)
            case .fastfolder:
                FastFolderUI()
                    .transition(.collapseExpandTransition)
            case .airdrop:
                AirDropUI()
                    .transition(.collapseExpandTransition)
            case .player:
                PlayerUI()
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
            
            if controller.isGlassInterface() {
                Color.clear
                    .glassEffect(.clear, in: Capsule())
                    .shadow(color: !controller.checkPreset(.collapsed) ? .black : .clear, radius: 20)
                
            } else {
                Capsule()
                    .fill(.black)
                    .shadow(color: !controller.checkPreset(.collapsed) ? .black : .clear, radius: 20)
            }
            
            
            
            
            NavigationRowView(
                terminateApplication: { NSApp.terminate(nil) }
            )
            
        }
        .frame(width: 215, height: 30)
    }
    
    
    private var bar: some View {
        BarView(
            value: $sliderBarValue,
            isSliderActive: $isSliderActive,
            action: {
                controller.showPreset(.home)
            }
        )
    }
    
    
    private func selectAnimation(from previous: CGSize, to current: CGSize) -> Animation {
        if (
            current.width >= previous.width &&
            current.height >= previous.height
        ){
            return .custbounsy
        }
        return .custsmooth
    }
    
}



#if DEBUG
#Preview {
    RootView()
        .environment(PanelController(panelState: PanelState()))
        .environment(AirDropService())
        .environment(makePreviewFastFolderStore([]))
        .environment(makePreviewPlayerStore())
        .background(.gray.opacity(0.1))
}
#endif

