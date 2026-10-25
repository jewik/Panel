//
//  TimeRow.swift
//  Notch
//
//  Created by Usanin Ivan on 19.10.2026.
//

import SwiftUI

struct CustomTimeView: View {
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            TimeRowView(date: context.date)
        }
    }
}

private struct TimeRowView: View {
    let date: Date
    
    // Separate layout properties extracted from the current date
    private var timeComponents: (year: Int, week: Int, day: Int, hour: Int, min: Int, sec: Int) {
        var calendar = Calendar.current
        // Force Monday to be the first day of the week (1 = Sunday, 2 = Monday, etc.)
        calendar.firstWeekday = 2
        
        let rawWeekday = calendar.component(.weekday, from: date)
        
        // Shift the math so Monday = 1, Tuesday = 2 ... Sunday = 7
        // (If you want Monday = 0, remove the '+ 1')
        let mondayFirstDay = ((rawWeekday - calendar.firstWeekday + 7) % 7) + 1

        return (
            calendar.component(.year, from: date),
            calendar.component(.weekOfYear, from: date),
            mondayFirstDay, // Now properly ordered with Monday as 1
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date),
            calendar.component(.second, from: date)
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            // 1. Year (0000)
            AnimatedUnitView(value: timeComponents.year, digits: 4)
            Text(":")
            
            // 2. Week (00)
            AnimatedUnitView(value: timeComponents.week, digits: 2)
            Text(":")
            
            // 3. Day (0)
            AnimatedUnitView(value: timeComponents.day, digits: 1)
            Text(":")
            
            // 4. Hour (00)
            AnimatedUnitView(value: timeComponents.hour, digits: 2)
            Text(":")
            
            // 5. Minute (00)
            AnimatedUnitView(value: timeComponents.min, digits: 2)
            Text(":")
            
            // 6. Second (00)
            AnimatedUnitView(value: timeComponents.sec, digits: 2)
        }
        .font(.system(size: 14, design: .monospaced)) // Keeps sizing consistent
        .foregroundStyle(.green)
        .shadow(color: .green ,radius: 2)
    }
}

// Reusable component that targets individual value changes
private struct AnimatedUnitView: View {
    let value: Int
    let digits: Int

    var body: some View {
        Text(formatValue(value))
            // Triggers individual digit roll animations when the value increments
            .contentTransition(.numericText(value: Double(value)))
            .animation(.snappy, value: value)
            
    }

    private func formatValue(_ input: Int) -> String {
        String(format: "%0\(digits)d", input)
    }
}


#Preview {
    CustomTimeView()
        .frame(width: 200)
}
