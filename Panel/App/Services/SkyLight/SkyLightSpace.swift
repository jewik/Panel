//import AppKit
//import os
//
//@MainActor
//final class SkyLightSpace {
//    static let shared = SkyLightSpace()
//
//    enum Destination: Hashable {
//        case pinned
//        case lockScreen
//    }
//
//    private typealias ConnectionID = UInt32
//    private typealias SpaceID = UInt64
//    private typealias MainConnectionFunction = @convention(c) () -> ConnectionID
//    private typealias CreateSpaceFunction = @convention(c) (
//        ConnectionID,
//        Int32,
//        CFDictionary?
//    ) -> SpaceID
//    private typealias SetSpaceLevelFunction = @convention(c) (
//        ConnectionID,
//        SpaceID,
//        Int32
//    ) -> Int32
//    private typealias SpacesFunction = @convention(c) (
//        ConnectionID,
//        CFArray
//    ) -> Int32
//    private typealias WindowsFunction = @convention(c) (
//        ConnectionID,
//        CFArray,
//        CFArray
//    ) -> Void
//    private typealias DestroySpaceFunction = @convention(c) (
//        ConnectionID,
//        SpaceID
//    ) -> Void
//
//    private enum SpaceLevel: Int32 {
//        case notificationCenterAtScreenLock = 400
//    }
//
//    private struct API {
//        let connection: ConnectionID
//        let createSpace: CreateSpaceFunction
//        let setSpaceLevel: SetSpaceLevelFunction
//        let showSpaces: SpacesFunction
//        let hideSpaces: SpacesFunction
//        let addWindows: WindowsFunction
//        let removeWindows: WindowsFunction
//        let destroySpace: DestroySpaceFunction
//    }
//
//    private struct ManagedSpace {
//        let id: SpaceID
//        var windowNumbers = Set<Int>()
//    }
//
//    private static let api: API? = {
//        guard let handle = dlopen(
//            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
//            RTLD_NOW | RTLD_LOCAL
//        ),
//        let mainConnectionSymbol = dlsym(handle, "CGSMainConnectionID"),
//        let createSpaceSymbol = dlsym(handle, "CGSSpaceCreate"),
//        let setSpaceLevelSymbol = dlsym(handle, "CGSSpaceSetAbsoluteLevel"),
//        let showSpacesSymbol = dlsym(handle, "CGSShowSpaces"),
//        let hideSpacesSymbol = dlsym(handle, "CGSHideSpaces"),
//        let addWindowsSymbol = dlsym(handle, "CGSAddWindowsToSpaces"),
//        let removeWindowsSymbol = dlsym(handle, "CGSRemoveWindowsFromSpaces"),
//        let destroySpaceSymbol = dlsym(handle, "CGSSpaceDestroy") else {
//            return nil
//        }
//
//        let mainConnection = unsafeBitCast(
//            mainConnectionSymbol,
//            to: MainConnectionFunction.self
//        )
//        let connection = mainConnection()
//
//        guard connection != 0 else {
//            return nil
//        }
//
//        return API(
//            connection: connection,
//            createSpace: unsafeBitCast(
//                createSpaceSymbol,
//                to: CreateSpaceFunction.self
//            ),
//            setSpaceLevel: unsafeBitCast(
//                setSpaceLevelSymbol,
//                to: SetSpaceLevelFunction.self
//            ),
//            showSpaces: unsafeBitCast(
//                showSpacesSymbol,
//                to: SpacesFunction.self
//            ),
//            hideSpaces: unsafeBitCast(
//                hideSpacesSymbol,
//                to: SpacesFunction.self
//            ),
//            addWindows: unsafeBitCast(
//                addWindowsSymbol,
//                to: WindowsFunction.self
//            ),
//            removeWindows: unsafeBitCast(
//                removeWindowsSymbol,
//                to: WindowsFunction.self
//            ),
//            destroySpace: unsafeBitCast(
//                destroySpaceSymbol,
//                to: DestroySpaceFunction.self
//            )
//        )
//    }()
//
//    private var spaces: [Destination: ManagedSpace] = [:]
//
//    private init() {}
//
//    func add(_ window: NSWindow, to destination: Destination) {
//        guard let api = Self.api,
//              window.windowNumber > 0,
//              let spaceID = spaceID(for: destination) else {
//            return
//        }
//
//        configure(window, for: destination)
//
//        var managedSpace = spaces[destination] ?? ManagedSpace(id: spaceID)
//        guard managedSpace.windowNumbers.insert(window.windowNumber).inserted else {
//            return
//        }
//
//        api.addWindows(
//            api.connection,
//            [NSNumber(value: window.windowNumber)] as CFArray,
//            [NSNumber(value: spaceID)] as CFArray
//        )
//        spaces[destination] = managedSpace
//    }
//
//    func remove(_ window: NSWindow, from destination: Destination) {
//        guard let api = Self.api,
//              var managedSpace = spaces[destination],
//              managedSpace.windowNumbers.remove(window.windowNumber) != nil else {
//            return
//        }
//
//        api.removeWindows(
//            api.connection,
//            [NSNumber(value: window.windowNumber)] as CFArray,
//            [NSNumber(value: managedSpace.id)] as CFArray
//        )
//        spaces[destination] = managedSpace
//    }
//
//    func stop() {
//        guard let api = Self.api else {
//            return
//        }
//
//        for managedSpace in spaces.values {
//            if !managedSpace.windowNumbers.isEmpty {
//                api.removeWindows(
//                    api.connection,
//                    managedSpace.windowNumbers.map(NSNumber.init(value:)) as CFArray,
//                    [NSNumber(value: managedSpace.id)] as CFArray
//                )
//            }
//
//            _ = api.hideSpaces(
//                api.connection,
//                [NSNumber(value: managedSpace.id)] as CFArray
//            )
//            api.destroySpace(api.connection, managedSpace.id)
//        }
//
//        spaces.removeAll()
//    }
//
//    private func spaceID(for destination: Destination) -> SpaceID? {
//        if let space = spaces[destination] {
//            return space.id
//        }
//
//        guard let api = Self.api else {
//            Log.service.error("SkyLight private API is unavailable.")
//            return nil
//        }
//
//        let spaceID = api.createSpace(api.connection, 1, nil)
//        guard spaceID != 0 else {
//            Log.service.error("SkyLight failed to create an overlay Space.")
//            return nil
//        }
//
//        if destination == .lockScreen {
//            let levelResult = api.setSpaceLevel(
//                api.connection,
//                spaceID,
//                SpaceLevel.notificationCenterAtScreenLock.rawValue
//            )
//            guard levelResult == 0 else {
//                api.destroySpace(api.connection, spaceID)
//                Log.service.error("SkyLight failed to set the lock-screen level.")
//                return nil
//            }
//        }
//
//        let showResult = api.showSpaces(
//            api.connection,
//            [NSNumber(value: spaceID)] as CFArray
//        )
//        guard showResult == 0 else {
//            api.destroySpace(api.connection, spaceID)
//            Log.service.error("SkyLight failed to show the overlay Space.")
//            return nil
//        }
//
//        spaces[destination] = ManagedSpace(id: spaceID)
//        return spaceID
//    }
//
//    private func configure(_ window: NSWindow, for destination: Destination) {
//        switch destination {
//        case .pinned:
//            window.collectionBehavior.formUnion([
//                .canJoinAllSpaces,
//                .fullScreenAuxiliary,
//                .stationary,
//            ])
//
//        case .lockScreen:
//            window.canBecomeVisibleWithoutLogin = true
//        }
//    }
//}
