import Foundation
import XCTest
@testable import Panel

@MainActor
final class PlayerStoreTests: XCTestCase {
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

    init(state: SystemNowPlayingState) {
        self.state = state
        let pair = AsyncStream<SystemNowPlayingEvent>.makeStream()
        eventStream = pair.stream
        continuation = pair.continuation
    }

    nonisolated func updates() -> AsyncStream<SystemNowPlayingEvent> { eventStream }
    func current() -> SystemNowPlayingState { state }
    func start() {}
    func retry() {}
    func stop() {}

    func emit(_ state: SystemNowPlayingState) {
        self.state = state
        continuation.yield(.stateChanged(state))
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
    static let fixture = NowPlayingSnapshot(
        source: PlaybackSource(
            processIdentifier: 1,
            bundleIdentifier: "test.player",
            parentApplicationBundleIdentifier: nil
        ),
        isPlaying: true,
        title: "Track",
        artist: "Artist",
        album: nil,
        duration: 120,
        elapsedTime: 10,
        refreshedAt: .now,
        playbackRate: 1,
        artworkData: nil,
        artworkMIMEType: nil,
        mediaType: "audio",
        contentItemIdentifier: "fixture"
    )
}
