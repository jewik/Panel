import Foundation

nonisolated struct PlaybackSource: Equatable, Hashable, Sendable {
    let processIdentifier: Int32?
    let bundleIdentifier: String?
    let parentApplicationBundleIdentifier: String?

    var preferredIdentifier: String? {
        parentApplicationBundleIdentifier ?? bundleIdentifier
    }

    var displayName: String {
        guard let identifier = preferredIdentifier else {
            return processIdentifier.map { "Process \($0)" } ?? "Unknown source"
        }

        return identifier
            .split(separator: ".")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "-", with: " ")
            .capitalized ?? identifier
    }
}

nonisolated struct NowPlayingSnapshot: Equatable, Sendable, Identifiable {
    let source: PlaybackSource
    let isPlaying: Bool
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let refreshedAt: Date
    let playbackRate: Double
    let artworkData: Data?
    let artworkMIMEType: String?
    let mediaType: String?
    let contentItemIdentifier: String?

    var id: String {
        let components: [String?] = [
            source.preferredIdentifier,
            contentItemIdentifier,
            title,
            artist,
            album,
            duration.map { String($0) },
        ]
        return components.compactMap { $0 }.joined(separator: "|")
    }

    var displayTitle: String {
        title ?? source.displayName
    }

    var displaySubtitle: String? {
        let subtitle = [artist, album]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        return subtitle.isEmpty ? nil : subtitle
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        let base = elapsedTime ?? 0
        let advance = max(0, date.timeIntervalSince(refreshedAt)) * playbackRate
        let value = max(0, base + advance)
        return duration.map { min(value, $0) } ?? value
    }

    func settingElapsedTime(
        _ newElapsedTime: TimeInterval,
        refreshedAt date: Date = .now
    ) -> Self {
        let upperBound = duration.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let elapsedTime = upperBound.map {
            min(max(newElapsedTime, 0), $0)
        } ?? max(newElapsedTime, 0)

        return Self(
            source: source,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedTime: elapsedTime,
            refreshedAt: date,
            playbackRate: playbackRate,
            artworkData: artworkData,
            artworkMIMEType: artworkMIMEType,
            mediaType: mediaType,
            contentItemIdentifier: contentItemIdentifier
        )
    }

    func isSameTrack(as other: NowPlayingSnapshot) -> Bool {
        guard source.preferredIdentifier == other.source.preferredIdentifier else {
            return false
        }
        if let contentItemIdentifier, let otherID = other.contentItemIdentifier {
            return contentItemIdentifier == otherID
        }
        if let title, let otherTitle = other.title {
            return title == otherTitle && artist == other.artist && album == other.album
        }
        return false
    }

    func sharesPlaybackTimeline(with other: NowPlayingSnapshot) -> Bool {
        guard source.preferredIdentifier == other.source.preferredIdentifier else {
            return false
        }
        if let processIdentifier = source.processIdentifier,
           let otherProcessIdentifier = other.source.processIdentifier,
           processIdentifier != otherProcessIdentifier {
            return false
        }

        let metadata = [title, artist, album]
        let otherMetadata = [other.title, other.artist, other.album]
        if metadata.contains(where: { $0 != nil })
            || otherMetadata.contains(where: { $0 != nil }) {
            return metadata == otherMetadata
        }

        if let contentItemIdentifier,
           let otherIdentifier = other.contentItemIdentifier {
            return contentItemIdentifier == otherIdentifier
        }

        return source.processIdentifier == other.source.processIdentifier
    }
}
