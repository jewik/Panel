//
//  AppContainer.swift
//  UITests
//
//  Created by Usanin Ivan on 04.08.2026.
//

import os
import Observation

@MainActor
@Observable
final class AppContainer {
    
    private let panelState: PanelState
    
    let controller: PanelController
    
    let airDropService: AirDropService
    
//    let fastFolderStore: FastFolderStore
    
    
    init() {
        
        self.panelState = PanelState()
        self.airDropService = AirDropService()
        
        self.controller = PanelController(
            panelState: panelState
        )
        
//        self.fastFolderStore = FastFolderStore()
        
        Log.general.info("AppContainer init finished")
        
    }
    
}
