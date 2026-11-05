import Foundation
import Observation
import os

@MainActor
@Observable
final class PlayerStore {
    private(set) var state: SystemNowPlayingState
    private(set) var isPerformingPlaybackCommand = false
    private(set) var playbackCommandError: String?

    @ObservationIgnored private let provider: any SystemNowPlayingProviding
    @ObservationIgnored private let playbackController: any SystemPlaybackControlling
    @ObservationIgnored private let idleTransitionDelay: Duration
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private var pendingIdleTask: Task<Void, Never>?
    @ObservationIgnored private var playbackCommandTask: Task<Void, Never>?
    @ObservationIgnored private var rawState: SystemNowPlayingState

    init(
        provider: any SystemNowPlayingProviding,
        playbackController: any SystemPlaybackControlling,
        initialState: SystemNowPlayingState = .idle,
        idleTransitionDelay: Duration = .milliseconds(550)
    ) {
        self.provider = provider
        self.playbackController = playbackController
        self.state = initialState
        self.rawState = initialState
        self.idleTransitionDelay = idleTransitionDelay
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        let provider = provider

        monitoringTask = Task { [weak self, provider] in
            let currentState = await provider.current()
            guard let self, !Task.isCancelled else { return }
            self.receive(.stateChanged(currentState))

            for await event in provider.updates() {
                guard !Task.isCancelled else { return }
                self.receive(event)
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        pendingIdleTask?.cancel()
        pendingIdleTask = nil
        playbackCommandTask?.cancel()
        playbackCommandTask = nil
        isPerformingPlaybackCommand = false
    }

    func retry() {
        pendingIdleTask?.cancel()
        pendingIdleTask = nil
        playbackCommandError = nil
        Task { [provider] in
            await provider.retry()
        }
    }

    func togglePlayback() { perform(.togglePlayPause) }
    func playPrevious() { perform(.previousTrack) }
    func playNext() { perform(.nextTrack) }

    private func perform(_ command: PlaybackCommand) {
        guard !isPerformingPlaybackCommand else { return }
        isPerformingPlaybackCommand = true
        playbackCommandError = nil

        playbackCommandTask = Task { [weak self, playbackController] in
            do {
                try await playbackController.send(command)
            } catch is CancellationError {
                // Expected when the composition root stops the feature.
            } catch {
                guard let self else { return }
                let message = (error as? NowPlayingFailure)?.message
                    ?? error.localizedDescription
                self.playbackCommandError = message
                Log.service.error("Player command failed: \(message, privacy: .public)")
            }

            guard let self else { return }
            self.isPerformingPlaybackCommand = false
            self.playbackCommandTask = nil
        }
    }

    private func receive(_ event: SystemNowPlayingEvent) {
        switch event {
        case .diagnostic(let diagnostic):
            log(diagnostic)

        case .stateChanged(let newState):
            rawState = newState
            switch newState {
            case .idle:
                guard case .active = state else {
                    state = .idle
                    return
                }
                pendingIdleTask?.cancel()
                let delay = idleTransitionDelay
                pendingIdleTask = Task { [weak self] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled,
                          let self,
                          self.rawState == .idle else { return }
                    self.state = .idle
                    self.pendingIdleTask = nil
                }

            case .active, .unavailable:
                pendingIdleTask?.cancel()
                pendingIdleTask = nil
                state = newState
            }
        }
    }

    private func log(_ diagnostic: NowPlayingDiagnostic) {
        switch diagnostic.severity {
        case .info:
            Log.service.info("Player: \(diagnostic.message, privacy: .public)")
        case .warning:
            Log.service.warning("Player: \(diagnostic.message, privacy: .public)")
        case .error:
            Log.service.error("Player: \(diagnostic.message, privacy: .public)")
        }
    }
}
