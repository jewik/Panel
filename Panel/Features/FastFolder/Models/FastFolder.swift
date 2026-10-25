//
//  FastFolder.swift
//  Notch
//
//  Created by Usanin Ivan on 09.08.2026.
//

import Foundation


struct FastFolder: Identifiable, Codable {
    let id: UUID
    var name: String
    var bookmark: Data
    var tags: [String]
}
