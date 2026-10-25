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
        let blackStop = min(1, 35 / height)
        
        
        UnionPanelShape(radiusRules: radiusRules)
            .rotation(.degrees(180))
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.3), location: 1),
                        .init(color: .black, location: blackStop),
                        .init(color: .black, location: 0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        
    }
}
