import Foundation

actor MediaRemotePlaybackController: SystemPlaybackControlling {
    private let injectedResources: AdapterResources?

    init(resources: AdapterResources? = nil) {
        injectedResources = resources
    }

    func send(_ command: PlaybackCommand) async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
            throw NowPlayingFailure(
                kind: .unsupportedSystem,
                message: "/usr/bin/perl is unavailable on this Mac.",
                recoverySuggestion: nil
            )
        }

        let resources = try injectedResources ?? AdapterResources.bundled()
        try resources.validate()

        let commandProcess = Process()
        let standardError = Pipe()
        commandProcess.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        commandProcess.arguments = [
            resources.scriptURL.path,
            resources.frameworkURL.path,
            "send",
            String(command.rawValue),
        ]
        commandProcess.standardOutput = FileHandle.nullDevice
        commandProcess.standardError = standardError
        commandProcess.qualityOfService = .userInitiated

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            commandProcess.terminationHandler = { terminatedProcess in
                let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
                let details = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard terminatedProcess.terminationStatus == 0 else {
                    continuation.resume(throwing: NowPlayingFailure(
                        kind: .commandFailed,
                        message: details?.isEmpty == false
                            ? details!
                            : "The active player rejected the command.",
                        recoverySuggestion: "Confirm that the active player supports this command."
                    ))
                    return
                }

                continuation.resume(returning: ())
            }

            do {
                try commandProcess.run()
            } catch {
                commandProcess.terminationHandler = nil
                continuation.resume(throwing: NowPlayingFailure(
                    kind: .commandFailed,
                    message: error.localizedDescription,
                    recoverySuggestion: "Verify the bundled MediaRemote adapter, then retry."
                ))
            }
        }
    }
}
