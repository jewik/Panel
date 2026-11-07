import AppKit
import Foundation

actor SystemNowPlayingProvider: SystemNowPlayingProviding {
    nonisolated private let stream: AsyncStream<SystemNowPlayingEvent>
    private let continuation: AsyncStream<SystemNowPlayingEvent>.Continuation
    private let injectedResources: AdapterResources?

    private var state: SystemNowPlayingState = .idle
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var lineDecoder = JSONLineDecoder()
    private var normalizer = SnapshotNormalizer()
    private var restartTask: Task<Void, Never>?
    private var launchIdentifier: UUID?
    private var explicitlyStopped = true
    private var consecutiveRestarts = 0
    private var recentStandardError = Data()
    private var wakeObserver: NSObjectProtocol?

    init(resources: AdapterResources? = nil) {
        let pair = AsyncStream<SystemNowPlayingEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        stream = pair.stream
        continuation = pair.continuation
        injectedResources = resources
    }

    nonisolated func updates() -> AsyncStream<SystemNowPlayingEvent> {
        stream
    }

    func current() -> SystemNowPlayingState {
        state
    }

    func start() {
        guard process == nil else { return }
        explicitlyStopped = false
        restartTask?.cancel()
        restartTask = nil
        installWakeObserverIfNeeded()
        launchHelper()
    }

    func retry() {
        restartTask?.cancel()
        restartTask = nil
        stopProcess(markExplicit: false)
        explicitlyStopped = false
        consecutiveRestarts = 0
        normalizer.reset()
        lineDecoder.reset()
        launchHelper()
    }

    func stop() {
        explicitlyStopped = true
        restartTask?.cancel()
        restartTask = nil
        let stoppedProcess = stopProcess(markExplicit: true)
        stoppedProcess?.waitUntilExit()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func launchHelper() {
        do {
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
                throw NowPlayingFailure(
                    kind: .unsupportedSystem,
                    message: "/usr/bin/perl is unavailable on this Mac.",
                    recoverySuggestion: nil
                )
            }
            let resources = try injectedResources ?? AdapterResources.bundled()
            try resources.validate()

            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let identifier = UUID()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [
                resources.scriptURL.path,
                resources.frameworkURL.path,
                "stream",
                "--no-diff",
                "--debounce=50",
                "--micros",
                "--allow-missing-title",
            ]
            process.standardOutput = stdout
            process.standardError = stderr
            process.qualityOfService = .userInitiated

            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                Task {
                    await self?.consumeStandardOutput(
                        data,
                        launchIdentifier: identifier
                    )
                }
            }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                Task {
                    await self?.consumeStandardError(
                        data,
                        launchIdentifier: identifier
                    )
                }
            }
            process.terminationHandler = { [weak self] process in
                let status = process.terminationStatus
                let reason = process.terminationReason
                Task {
                    await self?.helperTerminated(
                        status: status,
                        reason: reason,
                        launchIdentifier: identifier
                    )
                }
            }

            self.process = process
            stdoutPipe = stdout
            stderrPipe = stderr
            launchIdentifier = identifier
            recentStandardError.removeAll(keepingCapacity: true)
            lineDecoder.reset()
            normalizer.reset()

            try process.run()
            emitDiagnostic(
                .info,
                "Now Playing helper started (PID \(process.processIdentifier))."
            )
        } catch {
            process = nil
            stdoutPipe = nil
            stderrPipe = nil
            launchIdentifier = nil
            let failure = (error as? NowPlayingFailure) ?? NowPlayingFailure(
                kind: .launchFailed,
                message: error.localizedDescription,
                recoverySuggestion: "Verify the bundled MediaRemote resources, then retry."
            )
            publish(.unavailable(failure))
            emitDiagnostic(.error, failure.message)
            if failure.isRetryableConnectionFailure {
                scheduleRestart()
            }
        }
    }

    private func consumeStandardOutput(_ data: Data, launchIdentifier: UUID) {
        guard self.launchIdentifier == launchIdentifier else { return }
        do {
            let lines = try lineDecoder.append(data)
            for line in lines {
                guard String(data: line, encoding: .utf8) != nil else {
                    throw NowPlayingFailure(
                        kind: .malformedProtocol,
                        message: "The helper emitted invalid UTF-8.",
                        recoverySuggestion: "Retry or rebuild the adapter."
                    )
                }
                let envelope = try JSONDecoder().decode(AdapterEnvelope.self, from: line)
                if let nextState = try normalizer.normalize(envelope) {
                    consecutiveRestarts = 0
                    publish(nextState)
                }
            }
        } catch {
            let failure = (error as? NowPlayingFailure) ?? NowPlayingFailure(
                kind: .malformedProtocol,
                message: error.localizedDescription,
                recoverySuggestion: "Retry or rebuild the adapter."
            )
            publish(.unavailable(failure))
            emitDiagnostic(.error, "Protocol failure: \(failure.message)")
            stopProcess(markExplicit: false)
            scheduleRestart()
        }
    }

    private func consumeStandardError(_ data: Data, launchIdentifier: UUID) {
        guard self.launchIdentifier == launchIdentifier else { return }
        recentStandardError.append(data)
        let limit = 16 * 1_024
        if recentStandardError.count > limit {
            recentStandardError.removeFirst(recentStandardError.count - limit)
        }
    }

    private func helperTerminated(
        status: Int32,
        reason: Process.TerminationReason,
        launchIdentifier: UUID
    ) {
        guard self.launchIdentifier == launchIdentifier else { return }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        self.launchIdentifier = nil

        if explicitlyStopped { return }

        let details = String(data: recentStandardError, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if status != 0 || reason == .uncaughtSignal {
            let message = details?.isEmpty == false
                ? "Helper exited with status \(status): \(details!)"
                : "Helper exited unexpectedly with status \(status)."
            publish(.unavailable(NowPlayingFailure(
                kind: .helperExited,
                message: message,
                recoverySuggestion: "Retry. This macOS release may be incompatible."
            )))
            emitDiagnostic(.error, message)
            scheduleRestart()
            return
        }

        scheduleRestart()
    }

    private func scheduleRestart() {
        guard !explicitlyStopped, process == nil else { return }
        consecutiveRestarts += 1
        let exponent = min(consecutiveRestarts - 1, 5)
        let delay = min(pow(2.0, Double(exponent)) * 0.5, 15)
        emitDiagnostic(.warning, "Helper stopped; restarting in \(delay) seconds.")
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.restartAfterDelay()
        }
    }

    private func restartAfterDelay() {
        guard !explicitlyStopped, process == nil else { return }
        restartTask = nil
        launchHelper()
    }

    @discardableResult
    private func stopProcess(markExplicit: Bool) -> Process? {
        if markExplicit {
            explicitlyStopped = true
        }
        let oldProcess = process
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        oldProcess?.terminationHandler = nil
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        launchIdentifier = nil
        if oldProcess?.isRunning == true {
            oldProcess?.terminate()
        }
        return oldProcess
    }

    private func publish(_ newState: SystemNowPlayingState) {
        guard newState != state else { return }
        state = newState
        continuation.yield(.stateChanged(newState))
    }

    private func emitDiagnostic(
        _ severity: NowPlayingDiagnostic.Severity,
        _ message: String
    ) {
        continuation.yield(.diagnostic(NowPlayingDiagnostic(
            severity: severity,
            message: message
        )))
    }

    private func installWakeObserverIfNeeded() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.handleWake() }
        }
    }

    private func handleWake() {
        guard !explicitlyStopped else { return }
        if process?.isRunning != true {
            stopProcess(markExplicit: false)
            launchHelper()
        }
    }
}
