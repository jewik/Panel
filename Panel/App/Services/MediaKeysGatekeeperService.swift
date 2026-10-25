//import ApplicationServices
//import AppKit
//import CoreAudio
//import Foundation
//import os
//
//public enum InterceptedMediaKey: Int {
//    case volumeUp = 0
//    case volumeDown = 1
//    case volumeMute = 7
//    
//    case brightnessUp = 2
//    case brightnessDown = 3
//}
//
//public final class MediaKeysGatekeeperService {
//    
////    public static let shared = MediaKeysGatekeeperService()
//    
//    /// External HUD callback passing the key triggered and its current hardware integer value (0-100)
////    public var onKeyIntercepted: ((InterceptedMediaKey, Int) -> Void)?
//    
//    private static let systemDefinedEventType = CGEventType(rawValue: 14)!
//    private static let standardStep: Float = 1.0 / 16.0
//    private static let fineStep: Float = 1.0 / 64.0
//    
//    private var eventTap: CFMachPort?
//    private var eventTapSource: CFRunLoopSource?
//    private var permissionRetry: Timer?
//    
//    private var consumedKeys: [Int: Float] = [:]
//    private var nativeKeys = Set<Int>()
//    private var requestedAccessibility = false
//    
//    
//    // For preventing freezing events
//    private let hardwareQueue = DispatchQueue(label: "com.app.keysgatekeeper", qos: .userInteractive)
//    private let processingLock = OSAllocatedUnfairLock(initialState: false)
//    
//    private init() {}
//    
//    public func start() {
//        guard eventTap == nil else { return }
//        guard AXIsProcessTrusted() else {
//            requestAccessibilityIfNeeded()
////            schedulePermissionRetry()
//            return
//        }
//        
//        permissionRetry?.invalidate()
//        permissionRetry = nil
//        installEventTap()
//    }
//    
//    public func stop() {
//        permissionRetry?.invalidate()
//        permissionRetry = nil
//        consumedKeys.removeAll()
//        nativeKeys.removeAll()
//        
//        if let eventTap {
//            CGEvent.tapEnable(tap: eventTap, enable: false)
//        }
//        if let eventTapSource {
//            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
//        }
//        if let eventTap {
//            CFMachPortInvalidate(eventTap)
//        }
//        eventTapSource = nil
//        eventTap = nil
//    }
//    
//    private func requestAccessibilityIfNeeded() {
//        guard !requestedAccessibility else { return }
//        requestedAccessibility = true
//        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
//        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
//        
//        Log.service.info("MediaKeysGatekeeperService accessibility request called")
//    }
//    
//    private func schedulePermissionRetry() {
//        guard permissionRetry == nil else { return }
//        permissionRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
//            guard AXIsProcessTrusted() else { return }
//            timer.invalidate()
//            self?.permissionRetry = nil
//            self?.start()
//        }
//        Log.service.info("MediaKeysGatekeeperService accessibility request retry called")
//    }
//    
//    private func installEventTap() {
//        let callback: CGEventTapCallBack = { _, type, event, context in
//            guard let context else { return Unmanaged.passUnretained(event) }
//            let service = Unmanaged<MediaKeysGatekeeperService>
//                .fromOpaque(context)
//                .takeUnretainedValue()
//            return service.handle(type: type, event: event)
//        }
//        
//        guard let tap = CGEvent.tapCreate(
//            tap: .cgSessionEventTap,
//            place: .headInsertEventTap,
//            options: .defaultTap,
//            eventsOfInterest: CGEventMask(1 << Self.systemDefinedEventType.rawValue),
//            callback: callback,
//            userInfo: Unmanaged.passUnretained(self).toOpaque()
//        ) else {
//            schedulePermissionRetry()
//            return
//        }
//        
//        eventTap = tap
//        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
//        eventTapSource = source
//        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
//        CGEvent.tapEnable(tap: tap, enable: true)
//    }
//    
//    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
//        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
//            if let eventTap, AXIsProcessTrusted() {
//                CGEvent.tapEnable(tap: eventTap, enable: true)
//            }
//            return Unmanaged.passUnretained(event)
//        }
//        
//        guard type == Self.systemDefinedEventType,
//              let nativeEvent = NSEvent(cgEvent: event),
//              nativeEvent.subtype.rawValue == 8 else {
//            return Unmanaged.passUnretained(event)
//        }
//        
//        let data = UInt32(truncatingIfNeeded: nativeEvent.data1)
//        let rawKey = Int((data >> 16) & 0xffff)
//        let state = Int((data >> 8) & 0xff)
//
//        guard let key = InterceptedMediaKey(rawValue: rawKey), state == 0x0a || state == 0x0b else {
//            return Unmanaged.passUnretained(event)
//        }
//        
//        // Key Up State
//        if state == 0x0b {
//            nativeKeys.remove(rawKey)
//            return consumedKeys.removeValue(forKey: rawKey) != nil ? nil : Unmanaged.passUnretained(event)
//        }
//        
//        // Key Repeat State
//        let isRepeat = data & 1 != 0
//        if isRepeat {
//            if let ownedStep = consumedKeys[rawKey] {
//                let busy = processingLock.withLock { $0 }
//                if !busy {
//                    hardwareQueue.async { [weak self] in
//                        self?.asyncExecuteAndNotify(for: key, step: ownedStep)
//                    }
//                }
//                Log.service.info("MediaKeysGatekeeperService overload")
//                return nil
//            }
//            if nativeKeys.contains(rawKey) { return Unmanaged.passUnretained(event) }
//            nativeKeys.insert(rawKey)
//            return Unmanaged.passUnretained(event)
//        }
//        
//        // Key Down State
//        consumedKeys[rawKey] = nil
//        nativeKeys.remove(rawKey)
//        
//        let modifiers = event.flags
//        let commandOrControl = !modifiers.isDisjoint(with: [.maskCommand, .maskControl])
//        let option = modifiers.contains(.maskAlternate)
//        let shift = modifiers.contains(.maskShift)
//        guard !commandOrControl, !option || shift else {
//            nativeKeys.insert(rawKey)
//            return Unmanaged.passUnretained(event)
//        }
//        
//        let step = option && shift ? Self.fineStep : Self.standardStep
//        
//        // ПРОВЕРКА ФИЛЬТРА ДЛЯ НАЖАТИЯ (KEY DOWN):
//        let busy = processingLock.withLock { $0 }
//        if !busy {
//            consumedKeys[rawKey] = step
//            hardwareQueue.async { [weak self] in
//                self?.asyncExecuteAndNotify(for: key, step: step)
//            }
//            
//
//        } else {
//            // Если мы зависли, мы все равно "поглощаем" этот шаг локально, чтобы не дергать macOS,
//            // но вычисления не запускаем.
//            Log.service.info("MediaKeysGatekeeperService overload")
//            consumedKeys[rawKey] = step
//        }
//        return nil
//    }
//    
//    private func asyncExecuteAndNotify(for key: InterceptedMediaKey, step: Float) {
//        Log.service.info("MediaKeysGatekeeperService key: \(key.rawValue) executing")
//        // Устанавливаем флаг занятости перед началом тяжелой работы
//        processingLock.withLock { $0 = true }
//        
//        // Гарантируем сброс флага занятости при любом выходе из функции
//        defer {
//            processingLock.withLock { $0 = false }
//        }
//        
//        // DISABLED: фича HUD временно отключена
//        // switch key {
//        // case .brightnessUp, .brightnessDown, .volumeUp, .volumeDown, .volumeMute:
//        //     HUDService.shared.update(hudKey: key)
//        // }
//    }
//}
