//
//  AnimatedPanelBackground.swift
//  Notch
//
//  Created by Usanin Ivan on 25.10.2026.
//

import SwiftUI


struct AnimatedPanelBackground: View, Animatable {
    
    var height: CGFloat
    let radiusRules: UnionPanelShape.RadiusRules
    
    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }
    
    var body: some View {
        let blackStop = min(1, 20 / height)
        
        
        UnionPanelShape(radiusRules: radiusRules)
            .rotation(.degrees(180))
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(blackStop), location: 0.5),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        
    }
}

#Preview {
    AnimatedPanelBackground(
        height: 100,
        radiusRules: UnionPanelShape.RadiusRules(
            ear: { height in min(height / 4, 40) },
            angle: { height in min(height / 4 * 3, 50) }
        )
    )
}
