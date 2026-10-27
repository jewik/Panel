//
//  PanelController.swift
//  Notch
//
//  Created by Usanin Ivan on 10.08.2026.
//


import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class PanelController {
    
    private let panelState: PanelState
    
    
    init(
        panelState: PanelState
    ) {
        self.panelState = panelState
        
    }
    private func setPanelMode(_ mode: PanelMode) {
        withAnimation (.custsmooth) {
            panelState.panelMode = mode
        }
    }
    
    private func setExpandedPreset(_ preset: ExpandedPreset) {
        withAnimation (.custsmooth) {
            panelState.expandedPreset = preset
        }
    }
    
    func getPanelMode() -> PanelMode {
        panelState.panelMode
    }
    
    func getExpandedPreset() -> ExpandedPreset {
        panelState.expandedPreset
    }
    
    func showCollapsedPreset() {
        if !panelState.isPanelPinned {
            setPanelMode(.collapsed)
        }
    }
    
    func showExpandedPreset(_ preset: ExpandedPreset) {
        setPanelMode(.expanded)
        setExpandedPreset(preset)
    }
    
    func expandedPresetIs(_ preset: ExpandedPreset) -> Bool {
        preset == panelState.expandedPreset
    }
    
    func togglePinned(){
        panelState.isPanelPinned.toggle()
    }
    func pinPanel(){
        panelState.isPanelPinned = true
    }
    func unpinPanel(){
        panelState.isPanelPinned = false
    }
    
    func isPanelPinned() -> Bool {
        panelState.isPanelPinned
    }
    
    func triggerMacHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    
}
