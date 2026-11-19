import Foundation
import XCTest
@testable import Panel

final class SnapshotNormalizerTests: XCTestCase {
    func testNormalizesMissingTitleAndUsesParentSource() throws {
        var normalizer = SnapshotNormalizer()
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = try decode(
            #"{"protocolVersion":1,"type":"snapshot","sequence":1,"payload":{"processIdentifier":42,"bundleIdentifier":" com.browser ","parentApplicationBundleIdentifier":" com.video.host ","playing":true,"durationMicros":20000000,"elapsedTimeMicros":3000000}}"#
        )

        let state = try normalizer.normalize(envelope, receivedAt: receivedAt)
        guard case .active(let snapshot) = state else {
            return XCTFail("Expected active state")
        }
        XCTAssertNil(snapshot.title)
        XCTAssertEqual(snapshot.source.preferredIdentifier, "com.video.host")
        XCTAssertEqual(snapshot.playbackRate, 1)
        XCTAssertEqual(snapshot.duration, 20)
        XCTAssertEqual(snapshot.elapsedTime, 3)
        XCTAssertEqual(snapshot.refreshedAt, receivedAt)
    }

    func testPauseForcesRateToZeroAndClampsElapsed() throws {
        var normalizer = SnapshotNormalizer()
        let envelope = try decode(
            #"{"type":"data","diff":false,"payload":{"processIdentifier":7,"playing":false,"title":"Track","durationMicros":5000000,"elapsedTimeMicros":9000000,"playbackRate":2}}"#
        )

        let state = try normalizer.normalize(envelope)
        guard case .active(let snapshot) = state else {
            return XCTFail("Expected active state")
        }
        XCTAssertEqual(snapshot.playbackRate, 0)
        XCTAssertEqual(snapshot.elapsedTime, 5)
    }

    func testDropsStaleSequenceAndDistinguishesIdle() throws {
        var normalizer = SnapshotNormalizer()
        let active = try decode(
            #"{"protocolVersion":1,"type":"snapshot","sequence":4,"payload":{"processIdentifier":7,"playing":true,"title":"Track"}}"#
        )
        let stale = try decode(#"{"protocolVersion":1,"type":"idle","sequence":3}"#)
        let idle = try decode(#"{"protocolVersion":1,"type":"idle","sequence":5}"#)

        XCTAssertNotNil(try normalizer.normalize(active))
        XCTAssertNil(try normalizer.normalize(stale))
        XCTAssertEqual(try normalizer.normalize(idle), .idle)
    }

    func testDropsOlderPlaybackTimestampWithoutSequence() throws {
        var normalizer = SnapshotNormalizer()
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_020)
        let confirmed = try decode(
            #"{"type":"data","diff":false,"payload":{"processIdentifier":7,"playing":true,"title":"Track","contentItemIdentifier":"confirmed-id","durationMicros":120000000,"elapsedTimeMicros":90000000,"timestampEpochMicros":1800000010000000}}"#
        )
        let stale = try decode(
            #"{"type":"data","diff":false,"payload":{"processIdentifier":7,"playing":true,"title":"Track","contentItemIdentifier":"stale-id","durationMicros":120000000,"elapsedTimeMicros":12000000,"timestampEpochMicros":1800000000000000}}"#
        )

        XCTAssertNotNil(try normalizer.normalize(confirmed, receivedAt: receivedAt))
        XCTAssertNil(try normalizer.normalize(stale, receivedAt: receivedAt))
        XCTAssertEqual(normalizer.previous?.elapsedTime, 90)
    }

    func testAcceptsNewerPlaybackTimestampWithoutSequence() throws {
        var normalizer = SnapshotNormalizer()
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_020)
        let first = try decode(
            #"{"type":"data","diff":false,"payload":{"processIdentifier":7,"playing":true,"title":"Track","elapsedTimeMicros":12000000,"timestampEpochMicros":1800000000000000}}"#
        )
        let newer = try decode(
            #"{"type":"data","diff":false,"payload":{"processIdentifier":7,"playing":true,"title":"Track","elapsedTimeMicros":90000000,"timestampEpochMicros":1800000010000000}}"#
        )

        XCTAssertNotNil(try normalizer.normalize(first, receivedAt: receivedAt))
        XCTAssertNotNil(try normalizer.normalize(newer, receivedAt: receivedAt))
        XCTAssertEqual(normalizer.previous?.elapsedTime, 90)
    }

    func testIdleDoesNotDiscardPlaybackTimestampWatermark() throws {
        var normalizer = SnapshotNormalizer()
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_020)
        let confirmed = try decode(
            #"{"type":"data","diff":false,"payload":{"processIdentifier":7,"playing":true,"title":"Track","contentItemIdentifier":"confirmed-id","elapsedTimeMicros":90000000,"timestampEpochMicros":1800000010000000}}"#
        )
        let idle = try decode(#"{"type":"data","diff":false,"payload":{}}"#)
        let stale = try decode(
            #"{"type":"data","diff":false,"payload":{"processIdentifier":7,"playing":true,"title":"Track","contentItemIdentifier":"stale-id","elapsedTimeMicros":12000000,"timestampEpochMicros":1800000000000000}}"#
        )

        XCTAssertNotNil(try normalizer.normalize(confirmed, receivedAt: receivedAt))
        XCTAssertEqual(try normalizer.normalize(idle, receivedAt: receivedAt), .idle)
        XCTAssertNil(try normalizer.normalize(stale, receivedAt: receivedAt))
        XCTAssertNil(normalizer.previous)
    }

    func testRejectsDiffAndUnsupportedProtocol() throws {
        var normalizer = SnapshotNormalizer()
        XCTAssertThrowsError(try normalizer.normalize(
            decode(#"{"type":"data","diff":true,"payload":{}}"#)
        ))
        XCTAssertThrowsError(try normalizer.normalize(
            decode(#"{"protocolVersion":99,"type":"idle"}"#)
        ))
    }

    func testNormalizesActualHelperIdleEnvelope() throws {
        var normalizer = SnapshotNormalizer()
        let envelope = try decode(#"{"type":"data","diff":false,"payload":{}}"#)

        XCTAssertEqual(try normalizer.normalize(envelope), .idle)
    }

    private func decode(_ json: String) throws -> AdapterEnvelope {
        try JSONDecoder().decode(AdapterEnvelope.self, from: Data(json.utf8))
    }
}
