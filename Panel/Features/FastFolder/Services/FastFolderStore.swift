//
//  FastFolderStore.swift
//  Notch
//
//  Created by Usanin Ivan on 09.08.2026.
//

import AppKit
import Observation
import UniformTypeIdentifiers


@Observable
final class FastFolderStore {

    static let maximumFolderCount = 8
    
    private(set) var folders: [FastFolder] = []

    @ObservationIgnored
    private var iconCache: [FastFolder.ID: NSImage] = [:]
    
    private let storageKey = "fastFolders"

    var canAddFolder: Bool {
        folders.count < Self.maximumFolderCount
    }
    
    init() {
        load()
    }
    
    func refreshFolders(forceIconReload: Bool = false) {
            if forceIconReload {
                iconCache.removeAll()
            }

            var updatedFolders: [FastFolder] = []
            var needsSave = false
            
            for folder in folders {
                do {
                    var isStale = false
                    // 1. Пытаемся разрешить закладку
                    let url = try URL(
                        resolvingBookmarkData: folder.bookmark,
                        options: [.withSecurityScope],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    
                    // 2. Запрашиваем доступ к ресурсу
                    guard url.startAccessingSecurityScopedResource() else {
                        // Если доступ получить не удалось, сохраняем папку как есть до следующего раза
                        updatedFolders.append(folder)
                        continue
                    }
                    
                    // Используем defer, чтобы гарантированно закрыть доступ к ресурсу
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    // 3. Проверяем, существует ли папка физически на диске
                    var isDirectory: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    
                    // Если папка удалена, мы просто НЕ добавляем её в updatedFolders (пропускаем / удаляем из хранилища)
                    guard exists && isDirectory.boolValue else {
                        print("Папка \(folder.name) была удалена с диска. Удаляем из списка.")
                        needsSave = true
                        continue
                    }
                    
                    // 4. Считываем актуальные теги Finder с диска
                    let resourceValues = try url.resourceValues(forKeys: [.tagNamesKey])
                    let currentTags = resourceValues.tagNames ?? []
                    
                    // 5. Проверяем, обновились ли теги или сама закладка (isStale)
                    var currentBookmark = folder.bookmark
                    if isStale {
                        // Пересоздаем закладку, если система пометила её как устаревшую (например, папку переместили)
                        if let newBookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                            currentBookmark = newBookmark
                            needsSave = true
                        }
                    }
                    
                    // Если теги изменились, фиксируем необходимость сохранения
                    if currentTags != folder.tags {
                        needsSave = true
                    }

                    if currentTags != folder.tags ||
                        currentBookmark != folder.bookmark ||
                        url.lastPathComponent != folder.name {
                        iconCache.removeValue(forKey: folder.id)
                    }
                    
                    // Создаем обновленный экземпляр папки (если модель FastFolder — это struct)
                    let refreshedFolder = FastFolder(
                        id: folder.id,
                        name: url.lastPathComponent, // Имя тоже могло измениться, если папку переименовали
                        bookmark: currentBookmark,
                        tags: currentTags
                    )
                    
                    updatedFolders.append(refreshedFolder)
                    
                } catch {
                    // Если вызвана ошибка (например, исходный файл удален и закладка не разрешается)
                    print("Не удалось разрешить или обновить папку \(folder.name):", error)
                    // В случае критической ошибки (удаления) папка будет удалена из списка
                    needsSave = true
                }
            }
            
            // Перезаписываем массив папок и сохраняем в UserDefaults только если были изменения
            self.folders = updatedFolders
            let existingFolderIDs = Set(updatedFolders.map(\.id))
            iconCache = iconCache.filter { existingFolderIDs.contains($0.key) }
            if needsSave {
                save()
            }
        }
    
    func addFolder(url: URL) {
        guard canAddFolder else { return }

        do {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            // 1. Получаем теги Finder из URL
            let resourceValues = try url.resourceValues(forKeys: [.tagNamesKey])
            let finderTags = resourceValues.tagNames ?? [] // Массив строк тегов
            
            let folder = FastFolder(
                id: UUID(),
                name: url.lastPathComponent,
                bookmark: bookmark,
                tags: finderTags // 2. Сохраняем теги
            )
            
            folders.append(folder)
            iconCache[folder.id] = systemIcon(for: url)
            save()
            
        } catch {
            print("Failed to create bookmark:", error)
        }
    }
    
    func removeFolder(_ folder: FastFolder) {
        folders.removeAll {
            $0.id == folder.id
        }
        iconCache.removeValue(forKey: folder.id)
        save()
    }
    
    func resolve(_ folder: FastFolder) -> URL? {
        do {
            var isStale = false
            
            let url = try URL(
                resolvingBookmarkData: folder.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("Bookmark is stale:", folder.name)
            }
            
            return url
            
        } catch {
            print("Failed to resolve bookmark:", error)
            return nil
        }
    }

    func icon(for folder: FastFolder) -> NSImage {
        if let cachedIcon = iconCache[folder.id] {
            return cachedIcon
        }

        guard let url = resolve(folder),
              url.startAccessingSecurityScopedResource()
        else {
            return NSWorkspace.shared.icon(for: .folder)
        }

        defer { url.stopAccessingSecurityScopedResource() }
        let icon = systemIcon(for: url)
        iconCache[folder.id] = icon
        return icon
    }

    private func systemIcon(for url: URL) -> NSImage {
        let workspaceIcon = NSWorkspace.shared.icon(forFile: url.path)
        let icon = (workspaceIcon.copy() as? NSImage) ?? workspaceIcon
        icon.size = NSSize(width: 128, height: 128)
        return icon
    }
    
    func open(_ folder: FastFolder) {
        guard let url = resolve(folder) else {
            return
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }

        let openedInNewViewer = NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: url.path
        )

        if !openedInNewViewer {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(folders)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save folders:", error)
        }
    }
    
    func clearFolders() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        folders.removeAll()
        iconCache.removeAll()
    }
    
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        
        do {
            folders = try JSONDecoder().decode(
                [FastFolder].self,
                from: data
            )
        } catch {
            print("Failed to load folders:", error)
        }
    }
}
