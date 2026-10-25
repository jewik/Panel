//
//  ContiniusShape.swift
//  UITests
//
//  Created by Usanin Ivan on 17.07.2026.
//


import SwiftUI



struct PanelShape: Shape {
    
    private var botMaxRadius: CGFloat { 50 }
    
    func path(in rect: CGRect) -> Path {
        var path: Path = Path()
        
        let width: CGFloat = rect.size.width
        let height: CGFloat = rect.size.height
        
        let botRadius: CGFloat = min(height / 2, botMaxRadius)
                
        path.move(to: CGPoint(x: 0, y: 0))
        
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: 0, y: height - botRadius),
            radius: botRadius,
            angleType: .bottomLeft
        )
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: width - botRadius, y: height),
            radius: botRadius,
            angleType: .bottomRight
        )
        path.addLine(to: CGPoint(x: width, y: 0))
        
        
        path.closeSubpath()
        
        return path
    }
}

#Preview {
    VStack {
        Spacer()
        
        PanelShape()
            .fill(.blue.opacity(0.35))
            .frame(width: 300, height: 100)
        
        Spacer()
    }
    .frame(width: 400, height: 300)
    .background(.background)
}
