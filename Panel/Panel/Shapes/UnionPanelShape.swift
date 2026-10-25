//
//  UnionPanelShape.swift
//  Notch
//
//  Created by Usanin Ivan on 25.10.2026.
//

import SwiftUI

struct UnionPanelShape: Shape {
    struct RadiusRules: Sendable {
        private let earRule: @Sendable (CGFloat) -> CGFloat
        private let angleRule: @Sendable (CGFloat) -> CGFloat

        init(
            ear: @escaping @Sendable (CGFloat) -> CGFloat,
            angle: @escaping @Sendable (CGFloat) -> CGFloat
        ) {
            self.earRule = ear
            self.angleRule = angle
        }

        func earRadius(for height: CGFloat) -> CGFloat {
            earRule(height)
        }

        func angleRadius(for height: CGFloat) -> CGFloat {
            angleRule(height)
        }
    }

    private let radiusRules: RadiusRules

    init(radiusRules: RadiusRules) {
        self.radiusRules = radiusRules
    }
    
    func path(in rect: CGRect) -> Path {
        var path: Path = Path()
        
        let width: CGFloat = rect.size.width
        let height: CGFloat = rect.size.height
        
        let earRadius = radiusRules.earRadius(for: height)
        let angleRadius = radiusRules.angleRadius(for: height)
        
        path.move(to: CGPoint(x: 0, y: 0))
//        path.addLine(to: CGPoint(x: 0, y: 1))
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: -earRadius, y: earRadius),
            radius: earRadius,
            angleType: .bottomLeft,
            inversion: true
        )
        
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: earRadius, y: height - angleRadius),
            radius: angleRadius,
            angleType: .bottomLeft
        )
        
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: width - angleRadius - earRadius, y: height),
            radius: angleRadius,
            angleType: .bottomRight
        )
        
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: width, y: 0),
            radius: earRadius,
            angleType: .topLeft,
            inversion: true
        )
//        path.addLine(to: CGPoint(x: width, y: 0))

        path.closeSubpath()
        
        return path
    }
}


struct UnionPanelShape_one_px_offset: Shape {
    
    
    private var botMaxRadius: CGFloat { 50 }
    private var topMaxRadius: CGFloat { 30 }
    
    func path(in rect: CGRect) -> Path {
        var path: Path = Path()
        
        let width: CGFloat = rect.size.width
        let height: CGFloat = rect.size.height
        
        let topRadius: CGFloat = min(height / 4, topMaxRadius)
        let botRadius: CGFloat = min(height / 2, botMaxRadius)
        
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 1))
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: -topRadius, y: topRadius + 1),
            radius: topRadius,
            angleType: .bottomLeft,
            inversion: true
        )
        
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: topRadius, y: height - botRadius + 1),
            radius: botRadius,
            angleType: .bottomLeft
        )
        
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: width - botRadius - topRadius, y: height + 1),
            radius: botRadius,
            angleType: .bottomRight
        )
        
        ContinuousCornerPath.add(
            addTo: &path,
            startPoint: CGPoint(x: width, y: 1),
            radius: topRadius,
            angleType: .topLeft,
            inversion: true
        )
        path.addLine(to: CGPoint(x: width, y: 0))

        path.closeSubpath()
        
        return path
    }
}

#Preview {
    VStack {
        Spacer()
        
        UnionPanelShape(
            radiusRules: .init(
                ear: { min($0 / 3, 30) },
                angle: { min($0 / 3 * 2, 50) }
            )
        )
            .fill(.blue.opacity(0.35))
            .frame(width: 300, height: 220)
        
        Spacer()
    }
    .frame(width: 400, height: 400)
    .background(.background)
}
