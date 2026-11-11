//
//  BarView.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import SwiftUI

struct BarView: View {
    
//    @Environment(PanelController.self) private var controller

    @Binding var value: Double
    @Binding var isSliderActive: Bool
    @Binding var accentColor: Color
    @Binding var isSliderDragging: Bool
    var action: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var isPressing: Bool = false
    @State private var startValue: Double = 0.0
    
    var activeColor: Color { accentColor }
    var defaultColor: Color { accentColor.opacity(0.5) }
    var backgroundColor: Color { accentColor.opacity(0.2) }
    
    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            //        let totalWidth:CGFloat = 200
            let fillWidth = CGFloat(value) * totalWidth
            
            ZStack(alignment: .leading) {
                // Трэк слайдера
                Capsule()
                    .fill(backgroundColor)
                
                // Заполняющая часть
                Rectangle()
                    .fill(isHovered || isPressing ? activeColor : defaultColor)
                    .frame(width: max(0, fillWidth))
            }
            .clipShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isPressing {
                            isPressing = true
                            startValue = value
                        }
                        
                        if !isSliderActive { return }

                        guard abs(gesture.translation.width) >= 1 else { return }
                        isSliderDragging = true
                        
                        let delta = Double(gesture.translation.width / totalWidth)
                        let newValue = startValue + delta
                        
                        // Во время перетаскивания меняем значение жестко и без анимации для отзывчивости
                        self.value = min(max(0.0, newValue), 1.0)
                    }
                    .onEnded { gesture in
                        isPressing = false
                        isSliderDragging = false
                        
                        if abs(gesture.translation.width) < 1 {
                            // Вызываем экшен кнопки
                            action()
                        }
                    }
            )
        }
        .frame(width: 200, height: isSliderActive && (isHovered || isPressing) ? 8 : 5)
        .padding([.horizontal, .top], isHovered ? 5 : 3)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.smooth(duration: 0.2), value: value)
        .animation(.smooth(duration: 0.2), value: isHovered)
        .animation(.smooth(duration: 0.2), value: isPressing)
        .animation(.smooth(duration: 0.2), value: isSliderActive)
        .animation(.smooth(duration: 0.2), value: accentColor)

    }
    
    
//    @State var isHovered: Bool = false
//    
//    init() {}
//    
//    var body: some View {
//        ZStack(alignment: .bottom){
//            Button(action: {
//                controller.showPreset(.home)
//            }){
//                Capsule()
//                    .fill(isHovered ? .white : .secondary)
//                    .frame(width: 200, height: 5)
//                    .padding([.horizontal, .top], isHovered ? 5 : 3)
//            }
//            .buttonStyle(.plain)
//            .onHover{ isHovered = $0 }
//        }
//        .animation(.custsmooth, value: isHovered)
//    }
}

#Preview {
    
    @Previewable @State var sliderBarValue: Double = 1
    @Previewable @State var isSliderActive: Bool = true
    @Previewable @State var accentColor: Color = .white
    @Previewable @State var isSliderDragging: Bool = false

    BarView(
        value: $sliderBarValue,
        isSliderActive: $isSliderActive,
        accentColor: $accentColor,
        isSliderDragging: $isSliderDragging,
        action: {}
    )
        .environment(AppContainer().controller)
        .background(.red.opacity(0.1))
        .frame(width: 300, height: 140, alignment: .bottom)
}


