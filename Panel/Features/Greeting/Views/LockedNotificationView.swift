//
//  LockedView.swift
//  Notch
//
//  Created by Usanin Ivan on 20.10.2026.
//

import SwiftUI


//struct LockedNotificationView : PanelNotification {
//    let id = UUID()
//    let priority = 11 // Высокий приоритет
//    let duration: TimeInterval = 60.0
//    
//    func makeView() -> AnyView {
//        AnyView(LockedView())
//    }
//}

struct LockedView: View{
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                // Иконка отпечатка пальца (SF Symbols)
                Image(systemName: "lock")
                    .font(.system(size: 24, weight: .semibold)) // Оптимальный размер для экрана блокировки
                    .foregroundColor(.secondary)
                
                
                // Текст состояния блокировки
                Text("Touch ID or \nPassword required")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: 184, height: 40, alignment: .top)
        }
    }
}
