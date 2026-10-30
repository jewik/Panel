//
//  FinderTagColor+SwiftUI.swift
//  Panel
//
//  Created by Codex on 29.10.2026.
//

import SwiftUI

extension FinderTagColor {
    var color: Color {
        switch self {
        case .none: .cyan
        case .gray: .gray
        case .green: .green
        case .purple: .purple
        case .blue: .blue
        case .yellow: .yellow
        case .red: .red
        case .orange: .orange
        }
    }
}
