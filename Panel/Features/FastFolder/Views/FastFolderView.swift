////
////  FastFolderView.swift
////  Notch
////
////  Created by Usanin Ivan on 08.08.2026.
////
//
//import AppKit
//import SwiftUI
//import UniformTypeIdentifiers
//
//struct FastFolderView: View {
//
//    private enum Layout {
//        static let horizontalPadding: CGFloat = 8
//        static let itemWidth: CGFloat = 86
//        static let minimumStep: CGFloat = 28
//        static let itemHeight: CGFloat = 116
//    }
//
////    private let container = AppContainer.shared
//
//    @State private var hoveredFolderID: FastFolder.ID?
//    @State private var folderIcons: [FastFolder.ID: NSImage] = [:]
//
//    var body: some View {
//        Group {
//            if container.fastFolderStore.folders.isEmpty {
//                emptyState
//            } else {
//                folderShelf
//            }
//        }
//        .frame(width: 300, height: 150)
//        .onAppear {
//            reloadFolderAppearances()
//        }
//        .onDisappear {
//            hoveredFolderID = nil
//            folderIcons.removeAll()
//        }
//    }
//
//    private var emptyState: some View {
//        Button {
//            container.controller.showExpandedPreset(.settings)
//        } label: {
//            VStack(spacing: 8) {
//                Image(systemName: "folder.badge.plus")
//                    .font(.system(size: 28, weight: .medium))
//
//                Text("Add folders in Settings")
//                    .font(.system(size: 12, weight: .semibold, design: .rounded))
//            }
//            .foregroundStyle(.secondary)
//            .frame(maxWidth: .infinity, maxHeight: .infinity)
//            .contentShape(Rectangle())
//        }
//        .buttonStyle(.plain)
//        .accessibilityHint("Opens FastFolders settings")
//    }
//
//    private var folderShelf: some View {
//        GeometryReader { geometry in
//            let folders = container.fastFolderStore.folders
//            let availableWidth = geometry.size.width - Layout.horizontalPadding * 2
//            let step = shelfStep(folderCount: folders.count, availableWidth: availableWidth)
//            let shelfWidth = Layout.itemWidth + CGFloat(max(0, folders.count - 1)) * step
//
//            ZStack(alignment: .leading) {
//                ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
//                    FastFolderButtonView(
//                        folderName: folder.name,
//                        folderIcon: folderIcons[folder.id] ?? NSWorkspace.shared.icon(for: .folder),
//                        isHovered: hoveredFolderID == folder.id,
//                        action: {
//                            container.fastFolderStore.open(folder)
//                        },
//                        onHoverChange: { hovering in
//                            if hovering {
//                                hoveredFolderID = folder.id
//                            } else if hoveredFolderID == folder.id {
//                                hoveredFolderID = nil
//                            }
//                        }
//                    )
//                    .offset(x: CGFloat(index) * step)
//                    .zIndex(Double(index))
//                }
//            }
//            .frame(width: shelfWidth, height: Layout.itemHeight, alignment: .leading)
//            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
//        }
//    }
//
//    private func shelfStep(folderCount: Int, availableWidth: CGFloat) -> CGFloat {
//        guard folderCount > 1 else { return Layout.itemWidth }
//
//        let fittingStep = (availableWidth - Layout.itemWidth) / CGFloat(folderCount - 1)
//        return min(Layout.itemWidth, max(Layout.minimumStep, fittingStep))
//    }
//
//    private func reloadFolderAppearances() {
////        let store = container.fastFolderStore
//        store.refreshFolders(forceIconReload: true)
//        folderIcons = Dictionary(
//            uniqueKeysWithValues: store.folders.map { folder in
//                (folder.id, store.icon(for: folder))
//            }
//        )
//    }
//}
//
//struct FastFolderButtonView: View {
//
//    let folderName: String
//    let folderIcon: NSImage
//    let isHovered: Bool
//    let action: () -> Void
//    let onHoverChange: (Bool) -> Void
//
//    var body: some View {
//        Button(action: action) {
//            VStack(spacing: 4) {
//                Text(folderName)
//                    .font(.system(size: 12, weight: .semibold, design: .rounded))
//                    .lineLimit(1)
//                    .truncationMode(.middle)
//                    .frame(width: 86)
//                    .opacity(isHovered ? 1 : 0)
//                    .blur(radius: isHovered ? 0 : 4)
//
//                Image(nsImage: folderIcon)
//                    .resizable()
//                    .scaledToFit()
//                    .frame(width: 70, height: 70)
//            }
//            .frame(width: 86, height: 108, alignment: .bottom)
//            .contentShape(Rectangle())
//        }
//        .buttonStyle(.plain)
//        .offset(y: isHovered ? -8 : 0)
//        .onHover(perform: onHoverChange)
//        .animation(.smooth(duration: 0.25), value: isHovered)
//        .accessibilityLabel(folderName)
//        .accessibilityHint("Opens the folder in a new Finder window")
//    }
//}
//
//struct FastFolderSettingsView: View {
//
//    private let container = AppContainer.shared
//
//    @State private var folderIcons: [FastFolder.ID: NSImage] = [:]
//
//    var body: some View {
//        VStack(spacing: 0) {
//            HStack(spacing: 4) {
//                Text("FastFolders")
//                    .font(.system(size: 20, weight: .semibold, design: .rounded))
//                    .lineLimit(1)
//
//                Text("\(container.fastFolderStore.folders.count)/\(FastFolderStore.maximumFolderCount)")
//                    .font(.system(size: 11, weight: .medium, design: .rounded))
//                    .foregroundStyle(.secondary)
//
//                Spacer(minLength: 4)
//
//                NotchButton(
//                    systemName: "arrow.clockwise",
//                    title: nil,
//                    color: .white,
//                    bgSize: CGSize(width: 26, height: 26),
//                    textSize: 13,
//                    isActive: false,
//                    disabled: container.fastFolderStore.folders.isEmpty,
//                    action: {
//                        withAnimation(.smooth) {
//                            reloadFolderAppearances(forceIconReload: true)
//                        }
//                    }
//                )
//                .opacity(container.fastFolderStore.folders.isEmpty ? 0.35 : 1)
//                .help("Refresh folder styles and tags")
//
//                if !container.fastFolderStore.folders.isEmpty {
//                    NotchButton(
//                        systemName: "trash",
//                        title: "All",
//                        color: .red,
//                        bgSize: CGSize(width: 48, height: 26),
//                        textSize: 13,
//                        isActive: false,
//                        action: {
//                            withAnimation(.smooth) {
//                                container.fastFolderStore.clearFolders()
//                                folderIcons.removeAll()
//                            }
//                        }
//                    )
//                }
//
//                NotchButton(
//                    systemName: "plus",
//                    title: "Add",
//                    color: .cyan,
//                    bgSize: CGSize(width: 52, height: 26),
//                    textSize: 13,
//                    isActive: false,
//                    disabled: !container.fastFolderStore.canAddFolder,
//                    action: selectFolder
//                )
//                .opacity(container.fastFolderStore.canAddFolder ? 1 : 0.35)
//            }
//            .padding(.horizontal, 12)
//            .frame(height: 36)
//
//            if container.fastFolderStore.folders.isEmpty {
//                Text("No folders added")
//                    .font(.system(size: 12, weight: .medium, design: .rounded))
//                    .foregroundStyle(.secondary)
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//            } else {
//                ScrollView(.horizontal) {
//                    HStack(spacing: 8) {
//                        ForEach(container.fastFolderStore.folders) { folder in
//                            FastFolderSettingsItem(
//                                folderName: folder.name,
//                                folderIcon: folderIcons[folder.id] ?? NSWorkspace.shared.icon(for: .folder),
//                                removeAction: {
//                                    withAnimation(.smooth) {
//                                        container.fastFolderStore.removeFolder(folder)
//                                        folderIcons.removeValue(forKey: folder.id)
//                                    }
//                                }
//                            )
//                        }
//                    }
//                    .padding(.horizontal, 12)
//                }
//                .scrollIndicators(.hidden)
//                .frame(height: 114)
//            }
//        }
//        .frame(width: 600, height: 150)
//        .onAppear {
//            reloadFolderAppearances(forceIconReload: false)
//        }
//    }
//
//    private func selectFolder() {
//        guard container.fastFolderStore.canAddFolder else { return }
//
//        let panel = NSOpenPanel()
//        panel.canChooseFiles = false
//        panel.canChooseDirectories = true
//        panel.allowsMultipleSelection = false
//
//        guard panel.runModal() == .OK,
//              let url = panel.url
//        else {
//            return
//        }
//
//        container.fastFolderStore.addFolder(url: url)
//        reloadFolderAppearances(forceIconReload: true)
//    }
//
//    private func reloadFolderAppearances(forceIconReload: Bool) {
//        let store = container.fastFolderStore
//        store.refreshFolders(forceIconReload: forceIconReload)
//        folderIcons = Dictionary(
//            uniqueKeysWithValues: store.folders.map { folder in
//                (folder.id, store.icon(for: folder))
//            }
//        )
//    }
//}
//
//private struct FastFolderSettingsItem: View {
//
//    let folderName: String
//    let folderIcon: NSImage
//    let removeAction: () -> Void
//
//    var body: some View {
//        ZStack(alignment: .topTrailing) {
//            VStack(spacing: 2) {
//                Image(nsImage: folderIcon)
//                    .resizable()
//                    .scaledToFit()
//                    .frame(width: 54, height: 54)
//
//                Text(folderName)
//                    .font(.system(size: 11, weight: .semibold, design: .rounded))
//                    .lineLimit(1)
//                    .truncationMode(.middle)
//                    .frame(width: 72)
//            }
//            .frame(width: 76, height: 92, alignment: .center)
//
//            Button(action: removeAction) {
//                Image(systemName: "xmark")
//                    .font(.system(size: 10, weight: .bold))
//                    .foregroundStyle(.white)
//                    .frame(width: 18, height: 18)
//                    .background(.black.opacity(0.65), in: Circle())
//            }
//            .buttonStyle(.plain)
//            .help("Remove \(folderName)")
//        }
//        .frame(width: 76, height: 98)
//    }
//}
//
//#Preview("Home") {
//    ZStack {
//        PanelShape()
//            .fill(.black)
//
//        FastFolderView()
//            .background(Color.blue.opacity(0.2))
//    }
//    .frame(width: 300, height: 150)
//    .frame(width: 400, height: 300, alignment: .top)
//}
//
//#Preview("Settings") {
//    ZStack {
//        PanelShape()
//            .fill(.black)
//
//        FastFolderSettingsView()
//    }
//    .frame(width: 300, height: 150)
//    .frame(width: 400, height: 300, alignment: .top)
//}
