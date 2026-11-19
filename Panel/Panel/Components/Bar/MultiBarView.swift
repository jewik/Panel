//
//  MultiBarView.swift
//  Panel
//
//  Created by Usanin Ivan on 13.11.2026.
//

import SwiftUI

struct MultiBarView: View {

    @Environment(PanelController.self) private var controller

    @State private var barValue: Double = 1
    @State private var isBarSliderActive: Bool = false
    @State private var barAccentColor: Color = .white
    @State private var isBarSliderDragging: Bool = false

    var body: some View {
        SliderBarView(
            value: $barValue,
            isSliderActive: $isBarSliderActive,
            accentColor: $barAccentColor,
            isSliderDragging: $isBarSliderDragging,
            action: {
                controller.showPreset(.home)
            }
        )
    }
}
