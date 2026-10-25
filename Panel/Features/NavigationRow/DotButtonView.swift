//
//  DotButtonView.swift
//  Notch
//
//  Created by Usanin Ivan on 20.10.2026.
//

import SwiftUI

struct DotButton<InnerContent: View>: View {
    
    let color: Color?
    var showUnsavedDot: Bool = false
    let action: () -> Void
    
    @ViewBuilder
    let innerContent: () -> InnerContent
    
    @State private var isHovered = false
    
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .center){
                
                innerContent()
                    .opacity(isHovered ? 1.0 : 0.0)
                    .blur(radius: isHovered ? 0.0 : 8.0)
                    .scaleEffect(isHovered ? 1.0 : 0.5)
                
                dotView
                    .opacity(isHovered ? 0.0 : 1.0)
                    .blur(radius: isHovered ? 4.0 : 0.0)
                    .scaleEffect(isHovered ? 0.3 : 1.0)
                
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.3), value: isHovered)
        .frame(width: 20, height: 20, alignment: .center)
        
    }
    
    
    @ViewBuilder
    var dotView: some View{
        ZStack(alignment: .center){
            Circle()
                .fill(color ?? .white)
                .frame(width: 14, height: 14)
            if showUnsavedDot {
                Circle()
                    .fill(.black.opacity(0.6))
                    .frame(width: 5, height: 5)
            }
        }
    }
}



#Preview {
    HStack (spacing:3){
        DotButton(
            color: .red,
            action: { print("pressed") },
            innerContent: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.red)
            },
        )
        DotButton(
            color: .yellow,
            action: {

            },
            innerContent: {
                Image(systemName: "house.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.yellow)
            }
        )
        DotButton(
            color: .green,
            action: {

            },
            innerContent: {
                Image(systemName: "house.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
            }
        )
    }
    .background(.black)
    .frame(width: 100, height: 100)
}
