import Foundation

nonisolated struct AdapterEnvelope: Decodable, Sendable {
    let protocolVersion: Int?
    let type: String
    let sequence: UInt64?
    let diff: Bool?
    let payload: AdapterPayload?
    let error: AdapterErrorPayload?
}

nonisolated struct AdapterErrorPayload: Decodable, Sendable {
    let code: String?
    let message: String?
}

nonisolated struct AdapterPayload: Decodable, Sendable {
    let processIdentifier: Int?
    let bundleIdentifier: String?
    let parentApplicationBundleIdentifier: String?
    let playing: Bool?
    let title: String?
    let artist: String?
    let album: String?
    let durationMicros: Int64?
    let elapsedTimeMicros: Int64?
    let timestampEpochMicros: Int64?
    let playbackRate: Double?
    let artworkMimeType: String?
    let artworkData: String?
    let mediaType: FlexibleString?
    let contentItemIdentifier: FlexibleString?
    let uniqueIdentifier: FlexibleString?
}

nonisolated enum FlexibleString: Decodable, Sendable {
    case string(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .number(try container.decode(Double.self))
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value): value
        case .number(let value): String(value)
        }
    }
}
