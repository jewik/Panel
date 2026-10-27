//
//  AppDelegate.swift

import os
import AppKit
import SwiftUI
import ApplicationServices
import CoreGraphics
import CoreFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let container = AppContainer()

    private var overlayPanel: FloatingPanel?
    
    private let panelSize = NSSize(
        width: 1000,
        height: 400
    )
    
    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        NSApp.setActivationPolicy(.accessory)
        
        showOverlayPanel()
        observeScreenChanges()
        
        Log.general.info("Application did finished launching.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Log.general.info("Application will terminate.")
    }
    
    // MARK: - Panel
    
    private func showOverlayPanel() {
        // Do not create the panel twice.
        if let panel = overlayPanel {
            repositionPanel(on: panel)
            return
        }
        
        guard let screen = targetScreen() else {
            Log.general.error("No suitable screen found for the overlay panel.")
            return
        }

        let panel = FloatingPanel(frame: frame(for: screen))
        
        panel.contentView = makeHostingView()
        
        overlayPanel = panel
        
        panel.orderFrontRegardless()
    }
    
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func handleScreenParametersChange(_ notification: Notification) {
        guard let panel = overlayPanel else {
            showOverlayPanel()
            return
        }
        
        repositionPanel(on: panel)
    }
    
    private func repositionPanel(on panel: FloatingPanel) {
        // Built-in screen is gone (e.g. clamshell mode) — hide the panel.
        guard let screen = targetScreen() else {
            panel.orderOut(nil)
            return
        }
        
        panel.setFrame(frame(for: screen), display: true)
        panel.orderFrontRegardless()
    }
    
    private func targetScreen() -> NSScreen? {
        // The panel must live on the MacBook's built-in display.
        if let builtInScreen = NSScreen.screens.first(where: { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            
            return CGDisplayIsBuiltin(displayID) != 0
        }) {
            return builtInScreen
        }
        
        // Fallback: primary screen.
        return NSScreen.screens.first
    }
    
    private func frame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        
        return NSRect(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.minY,

            width: panelSize.width,
            height: panelSize.height
        )
    }
    
    private func makeHostingView() -> NSView {
        let rootView = RootView()
            .environment(container.controller)
            .environment(container.airDropService)
        
        let hostingView = NSHostingView(
            rootView: rootView
        )
        
        hostingView.autoresizingMask = [
            .width,
            .height
        ]
        
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor =
        NSColor.clear.cgColor
        
        return hostingView
    }
}
