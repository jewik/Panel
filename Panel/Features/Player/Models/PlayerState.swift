import Foundation

nonisolated enum SystemNowPlayingState: Equatable, Sendable {
    case idle
    case active(NowPlayingSnapshot)
    case unavailable(NowPlayingFailure)
}

nonisolated enum SystemNowPlayingEvent: Equatable, Sendable {
    case stateChanged(SystemNowPlayingState)
    case diagnostic(NowPlayingDiagnostic)
}

nonisolated enum PlaybackCommand: Int, Equatable, Sendable {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

nonisolated struct NowPlayingFailure: Error, Equatable, Sendable {
    nonisolated enum Kind: String, Equatable, Sendable {
        case unsupportedSystem
        case missingResource
        case incompatibleArchitecture
        case launchFailed
        case commandFailed
        case malformedProtocol
        case helperExited
    }

    let kind: Kind
    let message: String
    let recoverySuggestion: String?
}

nonisolated struct NowPlayingDiagnostic: Equatable, Sendable, Identifiable {
    nonisolated enum Severity: String, Equatable, Sendable {
        case info
        case warning
        case error
    }

    let id: UUID
    let date: Date
    let severity: Severity
    let message: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        severity: Severity,
        message: String
    ) {
        self.id = id
        self.date = date
        self.severity = severity
        self.message = message
    }
}
