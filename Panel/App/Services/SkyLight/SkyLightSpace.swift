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

    private typealias ConnectionID = Int32
    private typealias SpaceID = Int32
    private typealias WindowID = Int32

    private typealias MainConnectionFunction = @convention(c) () -> ConnectionID
    private typealias CreateSpaceFunction = @convention(c) (
        ConnectionID,
        Int32,
        Int32
    ) -> SpaceID
    private typealias SpaceLevelFunction = @convention(c) (
        ConnectionID,
        SpaceID,
        Int32
    ) -> Int32
    private typealias SpacesFunction = @convention(c) (
        ConnectionID,
        CFArray
    ) -> Int32
    private typealias MoveWindowsFunction = @convention(c) (
        ConnectionID,
        SpaceID,
        CFArray,
        Int32
    ) -> Int32
    private typealias DestroySpaceFunction = @convention(c) (
        ConnectionID,
        SpaceID
    ) -> Void

    private struct API {
        let connection: ConnectionID
        let createSpace: CreateSpaceFunction
        let setSpaceLevel: SpaceLevelFunction
        let showSpaces: SpacesFunction
        let hideSpaces: SpacesFunction
        let moveWindows: MoveWindowsFunction
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

        guard window.windowNumber > 0,
              let windowID = WindowID(exactly: window.windowNumber) else {
            Log.service.error("SkyLight cannot attach a window without a valid number.")
            return false
        }

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

        let result = api.moveWindows(
            api.connection,
            spaceID,
            [NSNumber(value: windowID)] as CFArray,
            0x7
        )

        guard result == 0 else {
            Log.service.error(
                "SkyLight failed to move window to stationary Space: \(result)"
            )
            return false
        }

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
        let hideResult = api.hideSpaces(api.connection, spaces)
        if hideResult != 0 {
            Log.service.error(
                "SkyLight failed to hide stationary Space: \(hideResult)"
            )
        }

        api.destroySpace(api.connection, spaceID)

        self.spaceID = nil
        windowIDs.removeAll()
    }

    private func stationarySpace(using api: API) -> SpaceID? {
        if let spaceID {
            return spaceID
        }

        // The creation flag must be 1 for an application-level overlay Space.
        let newSpaceID = api.createSpace(api.connection, 1, 0)
        guard newSpaceID != 0 else {
            Log.service.error("SkyLight failed to create a stationary Space.")
            return nil
        }

        let levelResult = api.setSpaceLevel(api.connection, newSpaceID, 0)
        guard levelResult == 0 else {
            api.destroySpace(api.connection, newSpaceID)
            Log.service.error(
                "SkyLight failed to set stationary Space level: \(levelResult)"
            )
            return nil
        }

        let showResult = api.showSpaces(
            api.connection,
            [NSNumber(value: newSpaceID)] as CFArray
        )
        guard showResult == 0 else {
            api.destroySpace(api.connection, newSpaceID)
            Log.service.error(
                "SkyLight failed to show stationary Space: \(showResult)"
            )
            return nil
        }

        spaceID = newSpaceID
        Log.service.info("SkyLight created stationary Space \(newSpaceID).")
        return newSpaceID
    }

    nonisolated private static func loadAPI() -> API? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW | RTLD_LOCAL
        ),
        let mainConnectionSymbol = dlsym(handle, "SLSMainConnectionID"),
        let createSpaceSymbol = dlsym(handle, "SLSSpaceCreate"),
        let setSpaceLevelSymbol = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
        let showSpacesSymbol = dlsym(handle, "SLSShowSpaces"),
        let hideSpacesSymbol = dlsym(handle, "SLSHideSpaces"),
        let moveWindowsSymbol = dlsym(
            handle,
            "SLSSpaceAddWindowsAndRemoveFromSpaces"
        ),
        let destroySpaceSymbol = dlsym(handle, "SLSSpaceDestroy") else {
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
            setSpaceLevel: unsafeBitCast(
                setSpaceLevelSymbol,
                to: SpaceLevelFunction.self
            ),
            showSpaces: unsafeBitCast(
                showSpacesSymbol,
                to: SpacesFunction.self
            ),
            hideSpaces: unsafeBitCast(
                hideSpacesSymbol,
                to: SpacesFunction.self
            ),
            moveWindows: unsafeBitCast(
                moveWindowsSymbol,
                to: MoveWindowsFunction.self
            ),
            destroySpace: unsafeBitCast(
                destroySpaceSymbol,
                to: DestroySpaceFunction.self
            )
        )
    }
}
