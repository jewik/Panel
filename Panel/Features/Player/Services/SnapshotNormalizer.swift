import Foundation
import ImageIO

nonisolated struct SnapshotNormalizer: Sendable {
    nonisolated enum NormalizationError: Error, LocalizedError, Equatable {
        case unsupportedProtocol(Int)
        case unexpectedDiff
        case missingSessionIdentity
        case invalidArtwork

        var errorDescription: String? {
            switch self {
            case .unsupportedProtocol(let version):
                "Unsupported helper protocol version \(version)."
            case .unexpectedDiff:
                "The helper emitted a partial update where a full snapshot was required."
            case .missingSessionIdentity:
                "The helper returned a session without a valid source or playback state."
            case .invalidArtwork:
                "The helper returned artwork that failed safety validation."
            }
        }
    }

    private(set) var previous: NowPlayingSnapshot?
    private(set) var lastSequence: UInt64?
    private let maximumArtworkBytes = 6 * 1_024 * 1_024
    private let maximumArtworkDimension = 16_384
    private let maximumArtworkPixels = 64_000_000

    mutating func normalize(
        _ envelope: AdapterEnvelope,
        receivedAt: Date = .now
    ) throws -> SystemNowPlayingState? {
        if let version = envelope.protocolVersion, version != 1 {
            throw NormalizationError.unsupportedProtocol(version)
        }
        if let sequence = envelope.sequence {
            if let lastSequence, sequence <= lastSequence {
                return nil
            }
            lastSequence = sequence
        }

        switch envelope.type {
        case "idle":
            previous = nil
            return .idle

        case "fatal", "error":
            throw NowPlayingFailure(
                kind: .helperExited,
                message: envelope.error?.message ?? "The helper reported a fatal error.",
                recoverySuggestion: "Retry and verify compatibility with this macOS version."
            )

        case "snapshot", "data":
            if envelope.diff == true {
                throw NormalizationError.unexpectedDiff
            }
            guard let payload = envelope.payload, !payload.isEmpty else {
                previous = nil
                return .idle
            }
            let snapshot = try makeSnapshot(from: payload, receivedAt: receivedAt)
            if snapshot == previous {
                return nil
            }
            previous = snapshot
            return .active(snapshot)

        case "diagnostic", "heartbeat":
            return nil

        default:
            return nil
        }
    }

    mutating func reset() {
        previous = nil
        lastSequence = nil
    }

    private func makeSnapshot(
        from payload: AdapterPayload,
        receivedAt: Date
    ) throws -> NowPlayingSnapshot {
        let pid = payload.processIdentifier
            .flatMap(Int32.init(exactly:))
            .flatMap { $0 > 0 ? $0 : nil }
        let source = PlaybackSource(
            processIdentifier: pid,
            bundleIdentifier: clean(payload.bundleIdentifier),
            parentApplicationBundleIdentifier: clean(
                payload.parentApplicationBundleIdentifier
            )
        )
        guard payload.playing != nil,
              source.processIdentifier != nil || source.preferredIdentifier != nil else {
            throw NormalizationError.missingSessionIdentity
        }

        let duration = seconds(payload.durationMicros)
        let elapsed = seconds(payload.elapsedTimeMicros).map { value in
            duration.map { min(value, $0) } ?? value
        }
        let isPlaying = payload.playing ?? false
        let reportedRate = payload.playbackRate.flatMap {
            $0.isFinite && $0 >= 0 ? $0 : nil
        }
        let playbackRate = isPlaying ? (reportedRate ?? 1) : 0
        let itemIdentifier = clean(payload.contentItemIdentifier?.stringValue)
            ?? clean(payload.uniqueIdentifier?.stringValue)

        var artworkData = try validatedArtwork(
            base64: payload.artworkData,
            mimeType: payload.artworkMimeType
        )
        var artworkMIMEType = artworkData == nil ? nil : clean(payload.artworkMimeType)

        let candidate = NowPlayingSnapshot(
            source: source,
            isPlaying: isPlaying,
            title: clean(payload.title),
            artist: clean(payload.artist),
            album: clean(payload.album),
            duration: duration,
            elapsedTime: elapsed,
            refreshedAt: timestamp(payload.timestampEpochMicros, receivedAt: receivedAt),
            playbackRate: playbackRate,
            artworkData: artworkData,
            artworkMIMEType: artworkMIMEType,
            mediaType: clean(payload.mediaType?.stringValue),
            contentItemIdentifier: itemIdentifier
        )

        if artworkData == nil, let previous, candidate.isSameTrack(as: previous) {
            artworkData = previous.artworkData
            artworkMIMEType = previous.artworkMIMEType
        }

        return NowPlayingSnapshot(
            source: candidate.source,
            isPlaying: candidate.isPlaying,
            title: candidate.title,
            artist: candidate.artist,
            album: candidate.album,
            duration: candidate.duration,
            elapsedTime: candidate.elapsedTime,
            refreshedAt: candidate.refreshedAt,
            playbackRate: candidate.playbackRate,
            artworkData: artworkData,
            artworkMIMEType: artworkMIMEType,
            mediaType: candidate.mediaType,
            contentItemIdentifier: candidate.contentItemIdentifier
        )
    }

    private func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func seconds(_ microseconds: Int64?) -> TimeInterval? {
        guard let microseconds, microseconds >= 0 else { return nil }
        let value = Double(microseconds) / 1_000_000
        return value.isFinite ? value : nil
    }

    private func timestamp(_ microseconds: Int64?, receivedAt: Date) -> Date {
        guard let seconds = seconds(microseconds) else { return receivedAt }
        let remote = Date(timeIntervalSince1970: seconds)
        return abs(remote.timeIntervalSince(receivedAt)) <= 300 ? remote : receivedAt
    }

    private func validatedArtwork(base64: String?, mimeType: String?) throws -> Data? {
        guard let base64, !base64.isEmpty else { return nil }
        guard base64.utf8.count <= maximumArtworkBytes * 4 / 3 + 8,
              let data = Data(base64Encoded: base64),
              data.count <= maximumArtworkBytes else {
            throw NormalizationError.invalidArtwork
        }

        if let mime = clean(mimeType)?.lowercased(),
           !["image/jpeg", "image/png", "image/heic", "image/heif", "image/webp", "image/tiff"].contains(mime) {
            throw NormalizationError.invalidArtwork
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0,
              width <= maximumArtworkDimension,
              height <= maximumArtworkDimension,
              width <= maximumArtworkPixels / height else {
            throw NormalizationError.invalidArtwork
        }
        return data
    }
}

nonisolated private extension AdapterPayload {
    var isEmpty: Bool {
        processIdentifier == nil
            && bundleIdentifier == nil
            && parentApplicationBundleIdentifier == nil
            && playing == nil
            && title == nil
            && artist == nil
            && album == nil
    }
}
