import Foundation

nonisolated struct JSONLineDecoder: Sendable {
    nonisolated enum DecoderError: Error, Equatable {
        case lineTooLarge(limit: Int)
    }

    private(set) var buffer = Data()
    let maximumLineSize: Int

    init(maximumLineSize: Int = 8 * 1_024 * 1_024) {
        self.maximumLineSize = maximumLineSize
    }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var line = buffer[..<newlineIndex]
            if line.last == 0x0D {
                line = line.dropLast()
            }
            if line.count > maximumLineSize {
                throw DecoderError.lineTooLarge(limit: maximumLineSize)
            }
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer.removeSubrange(...newlineIndex)
        }

        if buffer.count > maximumLineSize {
            throw DecoderError.lineTooLarge(limit: maximumLineSize)
        }
        return lines
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}
