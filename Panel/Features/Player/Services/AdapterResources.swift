import Foundation

nonisolated struct AdapterResources: Sendable {
    let scriptURL: URL
    let frameworkURL: URL

    static func bundled(in bundle: Bundle = .main) throws -> AdapterResources {
        guard let scriptURL = bundle.url(
            forResource: "mediaremote-adapter",
            withExtension: "pl"
        ) else {
            throw NowPlayingFailure(
                kind: .missingResource,
                message: "mediaremote-adapter.pl is missing from the app bundle.",
                recoverySuggestion: "Rebuild the app and verify Copy Bundle Resources."
            )
        }
        guard let frameworkURL = bundle.url(
            forResource: "MediaRemoteAdapter",
            withExtension: "bundle"
        ) else {
            throw NowPlayingFailure(
                kind: .missingResource,
                message: "MediaRemoteAdapter.bundle is missing from the app bundle.",
                recoverySuggestion: "Rebuild the native adapter and the app."
            )
        }

        let resources = AdapterResources(
            scriptURL: scriptURL.resolvingSymlinksInPath().standardizedFileURL,
            frameworkURL: frameworkURL.resolvingSymlinksInPath().standardizedFileURL
        )
        try resources.validate()
        return resources
    }

    func validate() throws {
        let frameworkName = frameworkURL.deletingPathExtension().lastPathComponent
        let binaryURL = frameworkURL.appendingPathComponent(frameworkName)
        guard FileManager.default.isReadableFile(atPath: scriptURL.path),
              FileManager.default.isReadableFile(atPath: binaryURL.path) else {
            throw NowPlayingFailure(
                kind: .missingResource,
                message: "The MediaRemote adapter resources are incomplete or unreadable.",
                recoverySuggestion: "Rebuild the native adapter and the app."
            )
        }
        guard MachOArchitectureVerifier.supportsCurrentArchitecture(binaryAt: binaryURL) else {
            throw NowPlayingFailure(
                kind: .incompatibleArchitecture,
                message: "The MediaRemote adapter does not support this Mac architecture.",
                recoverySuggestion: "Rebuild the universal adapter bundle."
            )
        }
    }
}

nonisolated private enum MachOArchitectureVerifier {
    static func supportsCurrentArchitecture(binaryAt url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let header = try? handle.read(upToCount: 4_096),
              header.count >= 8 else { return false }
        try? handle.close()

        let bytes = [UInt8](header)
        let magic = readUInt32(bytes, at: 0, bigEndian: true)
        let expectedCPU: UInt32
        #if arch(arm64)
        expectedCPU = 0x0100_000C
        #elseif arch(x86_64)
        expectedCPU = 0x0100_0007
        #else
        return false
        #endif

        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            let count = Int(readUInt32(bytes, at: 4, bigEndian: true))
            let stride = magic == 0xCAFE_BABF ? 32 : 20
            return (0..<count).contains { index in
                let offset = 8 + index * stride
                return offset + 4 <= bytes.count
                    && readUInt32(bytes, at: offset, bigEndian: true) == expectedCPU
            }
        }

        let littleMagic = readUInt32(bytes, at: 0, bigEndian: false)
        if [0xFEED_FACE, 0xFEED_FACF].contains(littleMagic) {
            return readUInt32(bytes, at: 4, bigEndian: false) == expectedCPU
        }
        return false
    }

    private static func readUInt32(
        _ bytes: [UInt8],
        at offset: Int,
        bigEndian: Bool
    ) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        let values = bytes[offset..<(offset + 4)].map(UInt32.init)
        if bigEndian {
            return values[0] << 24 | values[1] << 16 | values[2] << 8 | values[3]
        }
        return values[3] << 24 | values[2] << 16 | values[1] << 8 | values[0]
    }
}
