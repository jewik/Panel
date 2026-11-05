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

    func testRejectsDiffAndUnsupportedProtocol() throws {
        var normalizer = SnapshotNormalizer()
        XCTAssertThrowsError(try normalizer.normalize(
            decode(#"{"type":"data","diff":true,"payload":{}}"#)
        ))
        XCTAssertThrowsError(try normalizer.normalize(
            decode(#"{"protocolVersion":99,"type":"idle"}"#)
        ))
    }

    private func decode(_ json: String) throws -> AdapterEnvelope {
        try JSONDecoder().decode(AdapterEnvelope.self, from: Data(json.utf8))
    }
}
