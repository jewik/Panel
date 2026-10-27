//
//  extansion+Transition.swift
//  UITests
//
//  Created by Usanin Ivan on 04.08.2026.
//

import SwiftUI

extension AnyTransition {

    static var collapseExpandTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: TopCollapseModifier(
                    scale: 0.1,
                    opacity: 0,
                    blur: 50
                ),
                identity: TopCollapseModifier(
                    scale: 1,
                    opacity: 1,
                    blur: 0
                )
            ),
            removal: .modifier(
                active: TopCollapseModifier(
                    scale: 0.1,
                    opacity: 0,
                    blur: 50
                ),
                identity: TopCollapseModifier(
                    scale: 1,
                    opacity: 1,
                    blur: 0
                )
            )
        )
    }
    static var changePresetTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: TopCollapseModifier(
                    scale: 1,
                    opacity: 0,
                    blur: 10
                ),
                identity: TopCollapseModifier(
                    scale: 1,
                    opacity: 1,
                    blur: 0
                )
            ),
            removal: .modifier(
                active: TopCollapseModifier(
                    scale: 1,
                    opacity: 0,
                    blur: 10
                ),
                identity: TopCollapseModifier(
                    scale: 1,
                    opacity: 1,
                    blur: 0
                )
            )
        )
    }
}

struct TopCollapseModifier: ViewModifier {

    let scale: CGFloat
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                scale,
                anchor: .bottom
            )
            .opacity(opacity)
            .blur(radius: blur)
            .offset(y: scale == 1 ? 0 : 20)
    }
}
