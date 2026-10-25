
//
//  Untitled.swift
//  UITests
//
//  Created by Usanin Ivan on 24.07.2026.
//



import SwiftUI

struct NavigationRowView: View {
    
    let terminateApplication: @MainActor () -> Void
    
    var body: some View {
        HStack (alignment: .center, spacing: 4) {
            DotButton(
                color: .red,
                showUnsavedDot: true,
                action: {
                    terminateApplication()
                },
                innerContent: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                }
            )
            
//            DotButton(
//                color: .yellow,
//                action: {
//                    
//                },
//                innerContent: {
//                    Image(systemName: "house.fill")
//                        .font(.system(size: 14, weight: .bold))
//                        .foregroundStyle(.yellow)
//                }
//            )
//            
//            DotButton(
//                color: .green,
//                action: {
//                },
//                innerContent: {
//                    Image(systemName: "square.on.square.intersection.dashed")
//                        .font(.system(size: 14, weight: .bold))
//                        .foregroundStyle(.green)
//                }
//            )
//            
            
            DotButton(
                color: .indigo,
                action: {},
                innerContent: {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.indigo)
                }
            )
            
            DotButton(
                color: .cyan,
                action: {
                    
                },
                innerContent: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.cyan)
                }
            )
        }
        
    }
}

#Preview {
    NavigationRowView(terminateApplication: {})
        .background(.red.opacity(0.4))
        .frame(width: 200, height: 30)
}
