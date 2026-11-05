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
    var action: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false
    // Храним значение, которое было у слайдера в момент нажатия мышью
    @State private var startValue: Double = 0.0
    
    let backColor: Color = Color.white.opacity(0.12)
    let defaultColor: Color = Color.secondary
    let activeColor: Color = Color.white
    
    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            //        let totalWidth:CGFloat = 200
            let fillWidth = CGFloat(value) * totalWidth
            
            ZStack(alignment: .leading) {
                // Трэк слайдера
                Capsule()
                    .fill(backColor)
                
                // Заполняющая часть
                Rectangle()
                    .fill(isHovered || isDragging ? activeColor : defaultColor)
                    .frame(width: max(0, fillWidth))
            }
            .clipShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            startValue = value
                        }
                        
                        if !isSliderActive { return }
                        
                        let delta = Double(gesture.translation.width / totalWidth)
                        let newValue = startValue + delta
                        
                        // Во время перетаскивания меняем значение жестко и без анимации для отзывчивости
                        self.value = min(max(0.0, newValue), 1.0)
                    }
                    .onEnded { gesture in
                        isDragging = false
                        
                        if abs(gesture.translation.width) < 1 {
                            // Вызываем экшен кнопки
                            action()
                        } else {
                            
                            if !isSliderActive { return }
                            
                            // Иначе обрабатываем инерцию слайдера, как раньше
                            let predictedDelta = Double(gesture.predictedEndTranslation.width / totalWidth)
                            let inertialValue = startValue + predictedDelta
                            
                            withAnimation(.interpolatingSpring(stiffness: 60, damping: 15)) {
                                self.value = min(max(0.0, inertialValue), 1.0)
                            }
                        }
                    }
            )
        }
        .frame(width: 200, height: isSliderActive && (isHovered || isDragging) ? 8 : 5)
        .padding([.horizontal, .top], isHovered ? 5 : 3)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.smooth(duration: 0.2), value: isHovered)
        .animation(.smooth(duration: 0.2), value: isDragging)
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

    BarView(
        value: $sliderBarValue,
        isSliderActive: $isSliderActive,
        action: {}
    )
        .environment(AppContainer().controller)
        .background(.red.opacity(0.1))
        .frame(width: 300, height: 140, alignment: .bottom)
}


