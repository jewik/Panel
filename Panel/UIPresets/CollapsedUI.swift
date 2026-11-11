//
//  CollapcedUI.swift
//  Panel
//
//  Created by Usanin Ivan on 07.11.2026.
//

import SwiftUI


struct CollapsedUI : View {
    
    @Binding var onAttention: Bool
    
    var body: some View {
        Group {
            if onAttention {
                PlayerCollapsedView()
                    .transition(.collapseExpandTransition)
            }
        }
    }
}

