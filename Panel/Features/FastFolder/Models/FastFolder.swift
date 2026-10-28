//
//  FastFolder.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import Foundation

struct FastFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bookmark: Data
    var tags: [String]
    var tagColorIndex: Int

    var tagColor: FinderTagColor {
        FinderTagColor(rawValue: tagColorIndex) ?? .none
    }

    init(
        id: UUID = UUID(),
        name: String,
        bookmark: Data,
        tags: [String] = [],
        tagColorIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.tags = tags
        self.tagColorIndex = tagColorIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case bookmark
        case tags
        case tagColorIndex
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bookmark = try container.decode(Data.self, forKey: .bookmark)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        tagColorIndex = try container.decodeIfPresent(Int.self, forKey: .tagColorIndex) ?? 0
    }
}

enum FinderTagColor: Int {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7
}
