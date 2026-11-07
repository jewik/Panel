import Foundation

nonisolated protocol SystemNowPlayingProviding: Sendable {
    nonisolated func updates() -> AsyncStream<SystemNowPlayingEvent>
    func current() async -> SystemNowPlayingState
    func start() async
    func retry() async
    func stop() async
}

nonisolated protocol SystemPlaybackControlling: Sendable {
    func send(_ command: PlaybackCommand) async throws
}
