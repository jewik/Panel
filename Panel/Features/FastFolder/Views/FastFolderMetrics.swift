//
//  FastFolderMetrics.swift
//  Panel
//
//  Created by Codex on 29.10.2026.
//

import CoreGraphics

enum FastFolderMetrics {
    static let itemWidth: CGFloat = 76
    static let itemHeight: CGFloat = 96
    static let itemSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 4
    static var shelfHeight: CGFloat { itemHeight + verticalPadding}

    static let placeholderWidth: CGFloat = 400
    static let maximumShelfWidth: CGFloat = 900

    enum Settings {
        static let itemWidth: CGFloat = 86
        static let itemHeight: CGFloat = 84
        static let iconWidth: CGFloat = 70
        static let iconHeight: CGFloat = 54
        static let captionWidth: CGFloat = 72
    }
}
