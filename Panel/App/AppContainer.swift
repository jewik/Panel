//
//  AppContainer.swift
//  UITests
//
//  Created by Usanin Ivan on 04.08.2026.
//

import os
import Observation

@MainActor @Observable
final class AppContainer {
    private let panelState: PanelState
    private let nowPlayingProvider: SystemNowPlayingProvider

    let controller: PanelController
    let airDropService: AirDropService
    let fastFolderStore: FastFolderStore
    let playerStore: PlayerStore

    @ObservationIgnored private var playerStartTask: Task<Void, Never>?
    
    init() {
        self.panelState = PanelState()
        self.airDropService = AirDropService()

        self.controller = PanelController(
            panelState: panelState
        )

        let finder = FinderPresenter()
        let picker = FolderPicker()
        
        self.fastFolderStore = FastFolderStore(
            storage: UserDefaultsFastFolderStorage(),
            bookmarkService: FastFolderBookmarkService(),
            finder: finder,
            picker: picker
        )

        let nowPlayingProvider = SystemNowPlayingProvider()
        self.nowPlayingProvider = nowPlayingProvider
        self.playerStore = PlayerStore(
            provider: nowPlayingProvider,
            playbackController: MediaRemotePlaybackController()
        )

        Log.general.info("AppContainer init finished")
    }

    func start() {
        guard playerStartTask == nil else { return }
        playerStore.startMonitoring()
        let provider = nowPlayingProvider
        playerStartTask = Task {
            await provider.start()
        }
    }

    func stop() async {
        playerStartTask?.cancel()
        playerStartTask = nil
        playerStore.stopMonitoring()
        await nowPlayingProvider.stop()
    }
}
