//
//  PlayerView.swift
//  Panel
//
//  Created by Usanin Ivan on 03.11.2026.
//

import SwiftUI


struct PlayerView : View {
    
    var body: some View {
        
        HStack(alignment: .center ,spacing: 0){
            
            artwork
            
            VStack(alignment: .leading , spacing: 6){
                tracklabel
//                    .padding(.horizontal, 6)
//                    .background(.red.opacity(0.2))
                
                playbackControls
//                    .background(.blue.opacity(0.2))
                
            }
        }
        .frame(width: 240, height: 100, alignment: .leading)
//        .background(.orange.opacity(0.2))
        
    }
    
    var artwork: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.indigo.opacity(0.2))
            .frame(width: 70, height: 70)
            .frame(width: 100, height: 100)
    }
    
    var tracklabel: some View {
        VStack (spacing: 0) {
            Text("Name")
                .font(.system(size: 16, weight: .semibold))
            Text("Author")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
//        .frame(width: .infinity, height: .infinity)
        
    }
    
    
    var playbackControls: some View {
        HStack(spacing: 24) {
            controlButton(
                "Previous",
                systemImage: "backward.end.fill",
                action: {}
            )
            
            controlButton(
                "Play",
                systemImage: "play.fill",
                action: {}
            )

            controlButton(
                "Next",
                systemImage: "forward.end.fill",
                action: {}
            )

        }
//        .frame(width: .infinity, height: .infinity)
    }
    
    private func controlButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
//                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}









#Preview {
    
    @Previewable @State var isActive = true
    @Previewable @State var sliderValue: Double = 0.5
    
    ZStack(alignment: .bottom) {
        PanelShape()
            .rotation(.degrees(180))
            .fill(.black)
            .frame(width: 240, height: 100)
        
        BarView(
            value: $sliderValue,
            isSliderActive: $isActive,
            action: {}
        )
        PlayerView()
    }

    .frame(width: 300, height: 200, alignment: .bottom)
    
}
