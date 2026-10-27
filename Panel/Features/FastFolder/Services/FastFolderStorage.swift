//
//  FastFolderStorage.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//

import Foundation
import os

protocol FastFolderStorage {
    func load() -> [FastFolder]
    func save(_ folders: [FastFolder])
}

@MainActor
final class UserDefaultsFastFolderStorage: FastFolderStorage {

    private static let storageKey = "fastFolders"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [FastFolder] {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([FastFolder].self, from: data)
        } catch {
            Log.service.error(
                "FastFolder storage decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    func save(_ folders: [FastFolder]) {
        do {
            let data = try JSONEncoder().encode(folders)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            Log.service.error(
                "FastFolder storage encode failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
