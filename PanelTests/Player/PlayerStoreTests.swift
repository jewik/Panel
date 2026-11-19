import Foundation
import XCTest
@testable import Panel

@MainActor
final class PlayerStoreTests: XCTestCase {
    func testIsNowPlayingFollowsPresentedSnapshot() async {
        let provider = PlayerProviderDouble(state: .idle)
        let store = PlayerStore(
            provider: provider,
            playbackController: PlaybackControllerDouble(),
            idleTransitionDelay: .milliseconds(20)
        )
        store.startMonitoring()

        XCTAssertFalse(store.isNowPlaying)

        await provider.emit(.active(.fixture))
        await waitForStateChange()
        XCTAssertTrue(store.isNowPlaying)

        await provider.emit(.active(.pausedFixture))
        await waitForStateChange()
        XCTAssertFalse(store.isNowPlaying)

        await provider.emit(.idle)
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(store.isNowPlaying)
        store.stopMonitoring()
    }

    func testPlaybackActionsMapToSupportedCommands() async {
        let provider = PlayerProviderDouble(state: .active(.fixture))
        let controller = PlaybackControllerDouble()
        let store = PlayerStore(provider: provider, playbackController: controller)

        store.togglePlayback()
        await waitForCommandToFinish(store)
        store.playNext()
        await waitForCommandToFinish(store)
        store.playPrevious()
        await waitForCommandToFinish(store)

        let commands = await controller.recordedCommands()
        XCTAssertEqual(commands, [.togglePlayPause, .nextTrack, .previousTrack])
    }

    func testSeekMapsProgressToTrackPosition() async {
        let controller = PlaybackControllerDouble()
        let store = PlayerStore(
            provider: PlayerProviderDouble(state: .active(.fixture)),
            playbackController: controller,
            initialState: .active(.fixture)
        )

        store.seek(toProgress: 0.5)
        await waitForCommandToFinish(store)

        let commands = await controller.recordedCommands()
        XCTAssertEqual(commands, [.seek(to: 60)])
    }

    func testSeekWorksWhilePlaybackIsPaused() async {
        let controller = PlaybackControllerDouble()
        let store = PlayerStore(
            provider: PlayerProviderDouble(state: .active(.pausedFixture)),
            playbackController: controller,
            initialState: .active(.pausedFixture)
        )

        store.seek(toProgress: 0.25)
        await waitForCommandToFinish(store)

        let commands = await controller.recordedCommands()
        XCTAssertEqual(commands, [.seek(to: 30)])
    }

    func testSeekKeepsOptimisticPositionThroughLateHelperSnapshots() async {
        let provider = PlayerProviderDouble(state: .active(.fixture))
        let store = PlayerStore(
            provider: provider,
            playbackController: PlaybackControllerDouble(),
            initialState: .active(.fixture)
        )
        store.startMonitoring()
        await waitForStateChange()

        store.seek(toProgress: 0.75)
        await waitForCommandToFinish(store)

        XCTAssertEqual(
            store.presentedSnapshot?.elapsedTime ?? -1,
            90,
            accuracy: 0.5
        )

        await provider.emit(.active(.fixture(
            isPlaying: true,
            elapsedTime: 12,
            contentItemIdentifier: "stale-id"
        )))
        await waitForStateChange()

        XCTAssertTrue(store.isSynchronizingSeek)
        guard let filteredSnapshot = store.presentedSnapshot else {
            return XCTFail("Expected a presented snapshot")
        }
        XCTAssertEqual(
            filteredSnapshot.elapsed(),
            90,
            accuracy: 0.5
        )

        await provider.emit(.active(.fixture(
            isPlaying: true,
            elapsedTime: 90,
            contentItemIdentifier: "confirmed-id"
        )))
        await waitForStateChange()

        XCTAssertTrue(store.isSynchronizingSeek)

        await provider.emit(.active(.fixture(
            isPlaying: true,
            elapsedTime: 12,
            contentItemIdentifier: "late-stale-id"
        )))
        await waitForStateChange()

        guard let lateFilteredSnapshot = store.presentedSnapshot else {
            return XCTFail("Expected a presented snapshot")
        }
        XCTAssertEqual(lateFilteredSnapshot.elapsed(), 90, accuracy: 0.5)
        store.stopMonitoring()
    }

    func testRecentSeekFilterExpiresAndAcceptsServicePosition() async {
        let provider = PlayerProviderDouble(state: .active(.fixture))
        let store = PlayerStore(
            provider: provider,
            playbackController: PlaybackControllerDouble(),
            initialState: .active(.fixture),
            seekGracePeriodDuration: 0.03
        )
        store.startMonitoring()
        await waitForStateChange()

        store.seek(toProgress: 0.75)
        XCTAssertTrue(store.isSynchronizingSeek)

        try? await Task.sleep(for: .milliseconds(60))
        await provider.emit(.active(.fixture(isPlaying: true, elapsedTime: 12)))
        await waitForStateChange()

        XCTAssertFalse(store.isSynchronizingSeek)
        XCTAssertEqual(store.presentedSnapshot?.elapsedTime, 12)
        store.stopMonitoring()
    }

    func testTransientIdleDoesNotDropRecentSeekFilter() async {
        let provider = PlayerProviderDouble(state: .active(.fixture))
        let store = PlayerStore(
            provider: provider,
            playbackController: PlaybackControllerDouble(),
            initialState: .active(.fixture),
            idleTransitionDelay: .milliseconds(100)
        )
        store.startMonitoring()
        await waitForStateChange()

        store.seek(toProgress: 0.75)
        await provider.emit(.idle)
        await provider.emit(.active(.fixture(isPlaying: true, elapsedTime: 12)))
        await waitForStateChange()

        XCTAssertTrue(store.isSynchronizingSeek)
        guard let snapshot = store.presentedSnapshot else {
            return XCTFail("Expected a presented snapshot")
        }
        XCTAssertEqual(snapshot.elapsed(), 90, accuracy: 0.5)
        store.stopMonitoring()
    }

    func testIdleTransitionIsDelayed() async {
        let provider = PlayerProviderDouble(state: .active(.fixture))
        let store = PlayerStore(
            provider: provider,
            playbackController: PlaybackControllerDouble(),
            initialState: .active(.fixture),
            idleTransitionDelay: .milliseconds(40)
        )
        store.startMonitoring()
        await provider.emit(.idle)

        guard case .active = store.state else {
            return XCTFail("Active state should be retained during the idle grace period")
        }

        try? await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(store.state, .idle)
        store.stopMonitoring()
    }

    func testCommandFailureReenablesControlsAndPublishesError() async {
        let provider = PlayerProviderDouble(state: .active(.fixture))
        let controller = PlaybackControllerDouble(shouldFail: true)
        let store = PlayerStore(provider: provider, playbackController: controller)

        store.playNext()
        await waitForCommandToFinish(store)

        XCTAssertFalse(store.isPerformingPlaybackCommand)
        XCTAssertEqual(store.playbackCommandError, "Command failed in test")
    }

    func testRetryableFailureKeepsLastSnapshotVisibleWhileReconnecting() async {
        let provider = PlayerProviderDouble(state: .active(.fixture))
        let store = PlayerStore(
            provider: provider,
            playbackController: PlaybackControllerDouble(),
            initialState: .active(.fixture)
        )
        store.startMonitoring()

        await provider.emit(.unavailable(NowPlayingFailure(
            kind: .helperExited,
            message: "Connection lost",
            recoverySuggestion: nil
        )))
        await waitForStateChange()

        XCTAssertEqual(store.presentedSnapshot, .fixture)
        XCTAssertTrue(store.isReconnecting)
        store.stopMonitoring()
    }

    func testConnectionStateShowsReconnectingWithoutDiscardingSnapshot() async {
        let provider = PlayerProviderDouble(state: .active(.fixture))
        let store = PlayerStore(
            provider: provider,
            playbackController: PlaybackControllerDouble(),
            initialState: .active(.fixture)
        )
        store.startMonitoring()

        await provider.emitConnection(.reconnecting)
        await waitForStateChange()

        XCTAssertEqual(store.connectionState, .reconnecting)
        XCTAssertEqual(store.presentedSnapshot, .fixture)
        XCTAssertTrue(store.isReconnecting)
        store.stopMonitoring()
    }

    func testPermanentFailureDoesNotKeepLastSnapshotVisible() async {
        let failure = NowPlayingFailure(
            kind: .missingResource,
            message: "Helper is missing",
            recoverySuggestion: nil
        )
        let store = PlayerStore(
            provider: PlayerProviderDouble(state: .unavailable(failure)),
            playbackController: PlaybackControllerDouble(),
            initialState: .active(.fixture)
        )
        store.startMonitoring()
        await waitForStateChange()

        XCTAssertNil(store.presentedSnapshot)
        XCTAssertFalse(store.isReconnecting)
        store.stopMonitoring()
    }

    private func waitForCommandToFinish(_ store: PlayerStore) async {
        for _ in 0..<50 {
            if !store.isPerformingPlaybackCommand { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Playback command did not finish")
    }

    private func waitForStateChange() async {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

private actor PlayerProviderDouble: SystemNowPlayingProviding {
    nonisolated let eventStream: AsyncStream<SystemNowPlayingEvent>
    nonisolated let continuation: AsyncStream<SystemNowPlayingEvent>.Continuation
    private var state: SystemNowPlayingState
    private var connectionState: SystemNowPlayingConnectionState = .connected

    init(state: SystemNowPlayingState) {
        self.state = state
        let pair = AsyncStream<SystemNowPlayingEvent>.makeStream()
        eventStream = pair.stream
        continuation = pair.continuation
    }

    nonisolated func updates() -> AsyncStream<SystemNowPlayingEvent> { eventStream }
    func current() -> SystemNowPlayingState { state }
    func connection() -> SystemNowPlayingConnectionState { connectionState }
    func start() {}
    func retry() {}
    func stop() {}

    func emit(_ state: SystemNowPlayingState) {
        self.state = state
        continuation.yield(.stateChanged(state))
    }

    func emitConnection(_ state: SystemNowPlayingConnectionState) {
        connectionState = state
        continuation.yield(.connectionChanged(state))
    }
}

private actor PlaybackControllerDouble: SystemPlaybackControlling {
    private var commands: [PlaybackCommand] = []
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func send(_ command: PlaybackCommand) async throws {
        commands.append(command)
        if shouldFail {
            throw NowPlayingFailure(
                kind: .commandFailed,
                message: "Command failed in test",
                recoverySuggestion: nil
            )
        }
    }

    func recordedCommands() -> [PlaybackCommand] { commands }
}

nonisolated private extension NowPlayingSnapshot {
    static let fixture = fixture(isPlaying: true)
    static let pausedFixture = fixture(isPlaying: false)

    static func fixture(
        isPlaying: Bool,
        elapsedTime: TimeInterval = 10,
        contentItemIdentifier: String = "fixture"
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            source: PlaybackSource(
                processIdentifier: 1,
                bundleIdentifier: "test.player",
                parentApplicationBundleIdentifier: nil
            ),
            isPlaying: isPlaying,
            title: "Track",
            artist: "Artist",
            album: nil,
            duration: 120,
            elapsedTime: elapsedTime,
            refreshedAt: .now,
            playbackRate: isPlaying ? 1 : 0,
            artworkData: nil,
            artworkMIMEType: nil,
            mediaType: "audio",
            contentItemIdentifier: contentItemIdentifier
        )
    }
}
