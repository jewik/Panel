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
        // 1. Статический холст градиента фиксированного размера
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.3), location: 1),
                .init(color: .black, location: 0.175),
                .init(color: .black, location: 0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        // Задаем жесткие размеры статического прямоугольника-подложки
        .frame(width: 1000, height: 200)
        
        // 2. Используем динамическую фигуру как clipShape
        .clipShape(
            UnionPanelShape(radiusRules: radiusRules)
                .rotation(.degrees(180))
        )

    }
}
