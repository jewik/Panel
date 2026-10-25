import SwiftUI
import os

enum HelloAnimationPhase: CaseIterable {
    case reset     // Линии нет (0% -> 0%)
    case drawing   // Линия рисуется (0% -> 100%)
    case erasing   // Линия стирается с начала (100% -> 100%)
    
    // Откуда начинается линия в текущей фазе
    var start: CGFloat {
        switch self {
        case .reset, .drawing: return 0.0
        case .erasing: return 1.0
        }
    }
    
    // Где заканчивается линия в текущей фазе
    var end: CGFloat {
        switch self {
        case .reset: return 0.0
        case .drawing, .erasing: return 1.0
        }
    }
}

struct AppleHelloView: View {
    // Состояния для управления обрезкой контура (.trim)
    @State private var lineStart: CGFloat = 0.0
    @State private var lineEnd: CGFloat = 0.0
    
    // Сюда подставьте вашу оригинальную кривую
    var originalAppleCurve: some Shape {
        HelloShape() // Замените на вашу оригинальную форму Apple Hello
    }

    var body: some View {
        VStack {
            originalAppleCurve
                // Привязываем параметры к нашим переменным состояния
                .trim(from: lineStart, to: lineEnd)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 200, height: 80)
        }
        .task {
            do {
                // 1. Задержка ПЕРЕД началом всей анимации (например, 1.5 секунды)
//                try await Task.sleep(for: .seconds(0.5)) 
                
                // 2. Фаза рисования: линия плавно появляется от 0 до 1
                withAnimation(.easeInOut(duration: 1.5)) {
                    lineEnd = 1.0
                }
                
                // 3. Пауза, пока слово полностью отображается (например, 1 секунда)
                try await Task.sleep(for: .seconds(1)) // длительность анимации + пауза
                
                // 4. Фаза стирания: начало линии догоняет конец (от 0 до 1)
                withAnimation(.easeInOut(duration: 1)) {
                    lineStart = 1.0
                }
                
            } catch {
                // Обработка отмены задачи (если пользователь закрыл экран раньше времени)
                Log.ui.info("Greeting animation terminated before ended")
            }
        }
    }
}
