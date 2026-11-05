import Foundation
import XCTest
@testable import Panel

final class JSONLineDecoderTests: XCTestCase {
    func testDecodesLineAtEveryPossibleByteBoundary() throws {
        let first = #"{"type":"data","diff":false,"payload":{}}"#
        let second = #"{"type":"idle","sequence":2}"#
        let bytes = Data("\(first)\n\(second)\n".utf8)

        for split in 0...bytes.count {
            var decoder = JSONLineDecoder()
            var lines: [Data] = []
            lines += try decoder.append(bytes.prefix(split))
            lines += try decoder.append(bytes.suffix(bytes.count - split))
            XCTAssertEqual(
                lines.compactMap { String(data: $0, encoding: .utf8) },
                [first, second]
            )
        }
    }

    func testRejectsOversizedUnterminatedLine() throws {
        var decoder = JSONLineDecoder(maximumLineSize: 4)
        XCTAssertThrowsError(try decoder.append(Data("12345".utf8))) { error in
            XCTAssertEqual(
                error as? JSONLineDecoder.DecoderError,
                .lineTooLarge(limit: 4)
            )
        }
    }

    func testHandlesBlankAndCRLFLines() throws {
        var decoder = JSONLineDecoder()
        let lines = try decoder.append(Data("\r\n{}\r\n\n".utf8))
        XCTAssertEqual(lines, [Data("{}".utf8)])
    }
}
