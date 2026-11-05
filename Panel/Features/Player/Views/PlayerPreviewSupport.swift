#if DEBUG
import Foundation

nonisolated final class PreviewNowPlayingProvider: SystemNowPlayingProviding, @unchecked Sendable {
    private let initialState: SystemNowPlayingState
    private let stream: AsyncStream<SystemNowPlayingEvent>

    init(state: SystemNowPlayingState) {
        initialState = state
        stream = AsyncStream { continuation in continuation.finish() }
    }

    nonisolated func updates() -> AsyncStream<SystemNowPlayingEvent> { stream }
    func current() async -> SystemNowPlayingState { initialState }
    func start() async {}
    func retry() async {}
    func stop() async {}
}

nonisolated final class PreviewPlaybackController: SystemPlaybackControlling, @unchecked Sendable {
    func send(_ command: PlaybackCommand) async throws {}
}

@MainActor
func makePreviewPlayerStore(
    state: SystemNowPlayingState = .active(.preview)
) -> PlayerStore {
    PlayerStore(
        provider: PreviewNowPlayingProvider(state: state),
        playbackController: PreviewPlaybackController(),
        initialState: state
    )
}

nonisolated private extension NowPlayingSnapshot {
    static let preview = NowPlayingSnapshot(
        source: PlaybackSource(
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Music",
            parentApplicationBundleIdentifier: nil
        ),
        isPlaying: true,
        title: "Midnight Drive",
        artist: "The Notch",
        album: "Panel Sessions",
        duration: 230,
        elapsedTime: 42,
        refreshedAt: .now,
        playbackRate: 1,
        artworkData: nil,
        artworkMIMEType: nil,
        mediaType: "audio",
        contentItemIdentifier: "preview-track"
    )
}
#endif
