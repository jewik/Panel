//
//  AirDropService.swift
//  UITests
//
//  Created by Usanin Ivan on 04.08.2026.
//

import UniformTypeIdentifiers
import AppKit
import Observation

@MainActor
@Observable
final class AirDropService {
    func share(_ urls: [URL]) {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    func share(_ providers: [NSItemProvider]) -> Bool {
        let providers = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !providers.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var fileURLs: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = Self.fileURL(from: item) {
                    lock.lock()
                    fileURLs.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.share(fileURLs)
        }

        return true
    }

    private nonisolated static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL, url.isFileURL {
            return url
        }

        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil),
           url.isFileURL {
            return url
        }

        if let string = item as? String,
           let url = URL(string: string),
           url.isFileURL {
            return url
        }

        return nil
    }
}
