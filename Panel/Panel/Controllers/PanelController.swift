//
//  PanelController.swift
//  Notch
//
//  Created by Usanin Ivan on 10.08.2026.
//


import SwiftUI
import AppKit
import Observation
import os

@MainActor
@Observable
final class PanelController {
    
    private let panelState: PanelState
    
    
    init(
        panelState: PanelState
    ) {
        self.panelState = panelState
        
    }
//    private func setPanelMode(_ mode: PanelMode) {
//        withAnimation (.custsmooth) {
//            panelState.panelMode = mode
//        }
//    }
    
    private func setPreset(_ preset: PanelPreset) {
        withAnimation (.custsmooth) {
            panelState.preset = preset
        }
    }
    
    private var autoPinActive: Bool {
        panelState.preset != .collapsed
        && panelState.preset == .settings
        && !panelState.isAutoPinSuppressed
    }
    
    func getPreset() -> PanelPreset {
        panelState.preset
    }
    
    func collapse() {
        if !isPanelPinned() {
            setPreset(.collapsed)
        }
    }
    
    func showPreset(_ preset: PanelPreset) {
        if preset != .settings {
            panelState.isAutoPinSuppressed = false
        }
        setPreset(preset)
    }
    
    func checkPreset(_ preset: PanelPreset) -> Bool {
        preset == panelState.preset
    }
    
    func togglePinned(){
        if autoPinActive {
            panelState.isAutoPinSuppressed = true
            Log.ui.debug("Settings auto-pin suppressed by user")
        } else {
            panelState.isPanelPinned.toggle()
        }
    }
    func pinPanel(){
        panelState.isPanelPinned = true
    }
    func unpinPanel(){
        panelState.isPanelPinned = false
    }
    
    func isPanelPinned() -> Bool {
        panelState.isPanelPinned || autoPinActive
    }
    
    func triggerMacHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    
}
