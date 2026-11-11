import AppKit
import os

/// Keeps application windows in an app-owned Space that does not participate
/// in the system Space switching animation.
///
/// SkyLight is a private framework, so every symbol is resolved at runtime.
/// When an API is unavailable, callers keep the regular AppKit behaviour.
@MainActor
final class SkyLightSpace {
    static let shared = SkyLightSpace()

    private typealias ConnectionID = UInt32
    private typealias SpaceID = UInt64
    private typealias WindowID = Int

    private typealias MainConnectionFunction = @convention(c) () -> ConnectionID
    private typealias CreateSpaceFunction = @convention(c) (
        ConnectionID,
        Int32,
        CFDictionary?
    ) -> SpaceID
    private typealias SpacesFunction = @convention(c) (
        ConnectionID,
        CFArray
    ) -> Void
    private typealias WindowsFunction = @convention(c) (
        ConnectionID,
        CFArray,
        CFArray
    ) -> Void
    private typealias DestroySpaceFunction = @convention(c) (
        ConnectionID,
        SpaceID
    ) -> Void

    private struct API {
        let connection: ConnectionID
        let createSpace: CreateSpaceFunction
        let showSpaces: SpacesFunction
        let hideSpaces: SpacesFunction
        let addWindows: WindowsFunction
        let removeWindows: WindowsFunction
        let destroySpace: DestroySpaceFunction
    }

    private static let api: API? = loadAPI()

    private var spaceID: SpaceID?
    private var windowIDs = Set<WindowID>()

    private init() {}

    /// Moves a window to a stationary, application-owned overlay Space.
    @discardableResult
    func add(_ window: NSWindow) -> Bool {
        guard let api = Self.api else {
            Log.service.error("SkyLight stationary Space API is unavailable.")
            return false
        }

        guard window.windowNumber > 0 else {
            Log.service.error("SkyLight cannot attach a window without a valid number.")
            return false
        }
        let windowID = window.windowNumber

        guard !windowIDs.contains(windowID) else {
            return true
        }

        window.collectionBehavior.formUnion([
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ])

        guard let spaceID = stationarySpace(using: api) else {
            return false
        }

        api.addWindows(
            api.connection,
            [NSNumber(value: windowID)] as CFArray,
            [NSNumber(value: spaceID)] as CFArray
        )

        windowIDs.insert(windowID)

        Log.service.info(
            "SkyLight attached window \(windowID) to stationary Space \(spaceID)."
        )
        return true
    }

    /// Hides and destroys the app-owned Space. Safe to call more than once.
    func stop() {
        guard let api = Self.api, let spaceID else {
            windowIDs.removeAll()
            return
        }

        let spaces = [NSNumber(value: spaceID)] as CFArray
        if !windowIDs.isEmpty {
            api.removeWindows(
                api.connection,
                windowIDs.map { NSNumber(value: $0) } as CFArray,
                spaces
            )
        }

        api.hideSpaces(api.connection, spaces)
        api.destroySpace(api.connection, spaceID)

        self.spaceID = nil
        windowIDs.removeAll()
    }

    private func stationarySpace(using api: API) -> SpaceID? {
        if let spaceID {
            return spaceID
        }

        // The creation flag must be 1 for an application-level overlay Space.
        let newSpaceID = api.createSpace(api.connection, 1, nil)
        guard newSpaceID != 0 else {
            Log.service.error("SkyLight failed to create a stationary Space.")
            return nil
        }

        api.showSpaces(
            api.connection,
            [NSNumber(value: newSpaceID)] as CFArray
        )

        spaceID = newSpaceID
        Log.service.info("SkyLight created stationary Space \(newSpaceID).")
        return newSpaceID
    }

    nonisolated private static func loadAPI() -> API? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW | RTLD_LOCAL
        ),
        let mainConnectionSymbol = dlsym(handle, "CGSMainConnectionID"),
        let createSpaceSymbol = dlsym(handle, "CGSSpaceCreate"),
        let showSpacesSymbol = dlsym(handle, "CGSShowSpaces"),
        let hideSpacesSymbol = dlsym(handle, "CGSHideSpaces"),
        let addWindowsSymbol = dlsym(handle, "CGSAddWindowsToSpaces"),
        let removeWindowsSymbol = dlsym(handle, "CGSRemoveWindowsFromSpaces"),
        let destroySpaceSymbol = dlsym(handle, "CGSSpaceDestroy") else {
            return nil
        }

        let mainConnection = unsafeBitCast(
            mainConnectionSymbol,
            to: MainConnectionFunction.self
        )
        let connection = mainConnection()
        guard connection != 0 else {
            return nil
        }

        return API(
            connection: connection,
            createSpace: unsafeBitCast(
                createSpaceSymbol,
                to: CreateSpaceFunction.self
            ),
            showSpaces: unsafeBitCast(
                showSpacesSymbol,
                to: SpacesFunction.self
            ),
            hideSpaces: unsafeBitCast(
                hideSpacesSymbol,
                to: SpacesFunction.self
            ),
            addWindows: unsafeBitCast(
                addWindowsSymbol,
                to: WindowsFunction.self
            ),
            removeWindows: unsafeBitCast(
                removeWindowsSymbol,
                to: WindowsFunction.self
            ),
            destroySpace: unsafeBitCast(
                destroySpaceSymbol,
                to: DestroySpaceFunction.self
            )
        )
    }
}
