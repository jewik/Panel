////
////  ScreenUnlockObserveService.swift
////
////  Created by Usanin Ivan on 20.10.2026.
////
//
//import Cocoa
//import os
//
//class ScreenUnlockObserveService: NSObject {
//    
////    static let shared = ScreenUnlockObserveService()
//    
//    var isLocked = false
//    var isSleeping = false
//        
//        // This initializer runs immediately when ScreenUnlockObserveService.shared is called
//        override private init() {
//            super.init()
//
//        }
//
//    
//    func setupWorkspaceObservers() {
//        let nc = NSWorkspace.shared.notificationCenter
//        
//        // 1. Detect when the Mac wakes up from sleep
//        nc.addObserver(self,
//                       selector: #selector(handleWake),
//                       name: NSWorkspace.didWakeNotification,
//                       object: nil
//        )
//        nc.addObserver(self,
//                       selector: #selector(handleSleep),
//                       name: NSWorkspace.screensDidSleepNotification,
//                       object: nil
//        )
//        
////        // 2. Detect when Fast User Switching switches back to this desktop
////        nc.addObserver(self,
////                       selector: #selector(handleWorkspaceActive),
////                       name: NSWorkspace.sessionDidBecomeActiveNotification,
////                       object: nil)
//        
//        // 3. Detect when the screen is explicitly unlocked
//        DistributedNotificationCenter.default().addObserver(self,
//                       selector: #selector(handleUnlock),
//                       name: NSNotification.Name("com.apple.screenIsUnlocked"),
//                       object: nil
//        )
//        
//        DistributedNotificationCenter.default().addObserver(
//            self,
//            selector: #selector(handleLock),
//            name: NSNotification.Name("com.apple.screenIsLocked"),
//            object: nil
//        )
//        
//        Log.service.info("ScreenUnlockObserveService: setupWorkspaceObservers called")
//    }
//    
//    @objc func handleWake(notification: Notification) {
//        // Ensure UI updates happen on the main thread
//        DispatchQueue.main.async { [weak self] in
//            self?.onWake()
//        }
//    }
//    
//    @objc func handleSleep(notification: Notification) {
//        // Ensure UI updates happen on the main thread
//        DispatchQueue.main.async { [weak self] in
//            self?.onSleep()
//        }
//    }
//    
//    @objc func handleUnlock(notification: Notification) {
//        // Ensure UI updates happen on the main thread
//        DispatchQueue.main.async { [weak self] in
//            self?.onUnlock()
//        }
//    }
//    
//    @objc func handleLock(notification: Notification) {
//        DispatchQueue.main.async { [weak self] in
//            self?.onLock()
//        }
//    }
//    
//    deinit {
//        NSWorkspace.shared.notificationCenter.removeObserver(self)
//        DistributedNotificationCenter.default().removeObserver(self)
//    }
//    
//    func onUnlock(){
//        Log.service.info("Screen unlock event received")
//        isLocked = false
//        PanelNotificationsService.shared.hideCurrent()
//        PanelNotificationsService.shared.post(AppleHelloNotificationView())
//    }
//    
//    func onLock() {
//        Log.service.info("Screen lock event received")
//        isLocked = true
//        AppContainer.shared.controller.showCollapsedPreset()
//        PanelNotificationsService.shared.post(LockedNotificationView())
//    }
//    
//    func onWake(){
//        
//        isSleeping = false
//        if isLocked {
//            PanelNotificationsService.shared.post(LockedNotificationView())
//        }
//        Log.service.info("Screen wake event received")
//    }
//    
//    func onSleep() {
//        isSleeping = true
//        Log.service.info("Screen goes sleep event received")
//    }
//}
