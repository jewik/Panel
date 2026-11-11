import AppKit
import Darwin
import Foundation

actor SystemNowPlayingProvider: SystemNowPlayingProviding {
    nonisolated private let stream: AsyncStream<SystemNowPlayingEvent>
    private let continuation: AsyncStream<SystemNowPlayingEvent>.Continuation
    private let injectedResources: AdapterResources?

    private var state: SystemNowPlayingState = .idle
    private var connectionState: SystemNowPlayingConnectionState = .stopped
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutReaderTask: Task<Void, Never>?
    private var stderrReaderTask: Task<Void, Never>?
    private var stdoutDataContinuation: AsyncStream<Data>.Continuation?
    private var stderrDataContinuation: AsyncStream<Data>.Continuation?
    private var launchTimeoutTask: Task<Void, Never>?
    private var stabilityResetTask: Task<Void, Never>?
    private var lineDecoder = JSONLineDecoder()
    private var normalizer = SnapshotNormalizer()
    private var restartTask: Task<Void, Never>?
    private var restartPolicy = HelperRestartPolicy()
    private var launchIdentifier: UUID?
    private var explicitlyStopped = true
    private var recentStandardError = Data()
    private var wakeObserver: NSObjectProtocol?

    private let firstSnapshotTimeout: Duration = .seconds(5)
    private let gracefulStopTimeout: Duration = .seconds(2)
    private let restartStabilityInterval: Duration = .seconds(30)

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

    func connection() -> SystemNowPlayingConnectionState {
        connectionState
    }

    func start() {
        guard explicitlyStopped else { return }

        explicitlyStopped = false
        restartPolicy.reset()
        restartTask?.cancel()
        restartTask = nil
        installWakeObserverIfNeeded()
        publishConnection(.starting)
        launchHelper()
    }

    func retry() async {
        restartTask?.cancel()
        restartTask = nil
        launchTimeoutTask?.cancel()
        launchTimeoutTask = nil

        let stoppedProcess = stopProcess(markExplicit: false)
        await waitForTermination(of: stoppedProcess)

        explicitlyStopped = false
        restartPolicy.reset()
        normalizer.reset()
        lineDecoder.reset()
        publishConnection(.starting)
        launchHelper()
    }

    func stop() async {
        explicitlyStopped = true
        restartTask?.cancel()
        restartTask = nil
        launchTimeoutTask?.cancel()
        launchTimeoutTask = nil

        let stoppedProcess = stopProcess(markExplicit: true)
        await waitForTermination(of: stoppedProcess)

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        lineDecoder.reset()
        normalizer.reset()
        restartPolicy.reset()
        publish(.idle)
        publishConnection(.stopped)
    }

    private func launchHelper() {
        guard !explicitlyStopped, process == nil else { return }

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
            process.arguments = resources.streamArguments()
            process.standardOutput = stdout
            process.standardError = stderr
            process.qualityOfService = .userInitiated
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
            startReaderTasks(
                stdout: stdout.fileHandleForReading,
                stderr: stderr.fileHandleForReading,
                launchIdentifier: identifier
            )
            scheduleFirstSnapshotTimeout(for: identifier)
            emitDiagnostic(
                .info,
                "Now Playing helper started (PID \(process.processIdentifier))."
            )
        } catch {
            clearProcessReferences()
            let failure = (error as? NowPlayingFailure) ?? NowPlayingFailure(
                kind: .launchFailed,
                message: error.localizedDescription,
                recoverySuggestion: "Verify the bundled MediaRemote resources, then retry."
            )
            publish(.unavailable(failure))
            emitDiagnostic(.error, failure.message)

            if failure.isRetryableConnectionFailure {
                scheduleRestart()
            } else {
                publishConnection(.failed)
            }
        }
    }

    private func startReaderTasks(
        stdout: FileHandle,
        stderr: FileHandle,
        launchIdentifier: UUID
    ) {
        let stdoutPair = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        let stderrPair = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        stdoutDataContinuation = stdoutPair.continuation
        stderrDataContinuation = stderrPair.continuation

        // A synchronous read(upToCount:) on a pipe can wait for the requested
        // byte count or EOF. availableData is safe here because the handler is
        // invoked only after the descriptor becomes readable.
        stdout.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdoutPair.continuation.finish()
            } else {
                stdoutPair.continuation.yield(data)
            }
        }
        stderr.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrPair.continuation.finish()
            } else {
                stderrPair.continuation.yield(data)
            }
        }

        stdoutReaderTask = Task { [weak self] in
            for await data in stdoutPair.stream {
                guard !Task.isCancelled else { return }
                await self?.consumeStandardOutput(
                    data,
                    launchIdentifier: launchIdentifier
                )
            }
        }

        stderrReaderTask = Task { [weak self] in
            for await data in stderrPair.stream {
                guard !Task.isCancelled else { return }
                await self?.consumeStandardError(
                    data,
                    launchIdentifier: launchIdentifier
                )
            }
        }
    }

    private func consumeStandardOutput(
        _ data: Data,
        launchIdentifier: UUID
    ) {
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
                markHelperResponsive(launchIdentifier: launchIdentifier)
                if let nextState = try normalizer.normalize(envelope) {
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
            stopAndScheduleRestart()
        }
    }

    private func consumeStandardError(
        _ data: Data,
        launchIdentifier: UUID
    ) {
        guard self.launchIdentifier == launchIdentifier else { return }

        recentStandardError.append(data)
        let limit = 16 * 1_024
        if recentStandardError.count > limit {
            recentStandardError.removeFirst(recentStandardError.count - limit)
        }
    }

    private func markHelperResponsive(launchIdentifier: UUID) {
        launchTimeoutTask?.cancel()
        launchTimeoutTask = nil
        publishConnection(.connected)

        guard stabilityResetTask == nil else { return }
        stabilityResetTask = Task { [weak self] in
            try? await Task.sleep(
                for: self?.restartStabilityInterval ?? .seconds(30)
            )
            guard !Task.isCancelled else { return }
            await self?.markHelperStable(launchIdentifier: launchIdentifier)
        }
    }

    private func markHelperStable(launchIdentifier: UUID) {
        guard self.launchIdentifier == launchIdentifier,
              process?.isRunning == true else { return }
        stabilityResetTask = nil
        restartPolicy.reset()
    }

    private func scheduleFirstSnapshotTimeout(for launchIdentifier: UUID) {
        launchTimeoutTask?.cancel()
        launchTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: self?.firstSnapshotTimeout ?? .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.handleFirstSnapshotTimeout(launchIdentifier: launchIdentifier)
        }
    }

    private func handleFirstSnapshotTimeout(launchIdentifier: UUID) async {
        guard self.launchIdentifier == launchIdentifier else { return }
        launchTimeoutTask = nil

        let failure = NowPlayingFailure(
            kind: .helperUnresponsive,
            message: "The Now Playing helper did not produce an initial snapshot.",
            recoverySuggestion: "Retry. MediaRemote may not have resumed correctly."
        )
        publish(.unavailable(failure))
        emitDiagnostic(.error, failure.message)

        let stoppedProcess = stopProcess(markExplicit: false)
        await waitForTermination(of: stoppedProcess)
        scheduleRestart()
    }

    private func helperTerminated(
        status: Int32,
        reason: Process.TerminationReason,
        launchIdentifier: UUID
    ) {
        guard self.launchIdentifier == launchIdentifier else { return }

        launchTimeoutTask?.cancel()
        launchTimeoutTask = nil
        clearProcessReferences()

        guard !explicitlyStopped else { return }

        let details = String(data: recentStandardError, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch HelperLifecyclePolicy.action(status: status, reason: reason) {
        case .fail:
            let message = details?.isEmpty == false
                ? "Helper exited with status \(status): \(details!)"
                : "Helper reported a fatal error with status \(status)."
            let failure = NowPlayingFailure(
                kind: .helperFatal,
                message: message,
                recoverySuggestion: "Retry manually. This macOS release may be incompatible."
            )
            publish(.unavailable(failure))
            publishConnection(.failed)
            emitDiagnostic(.error, message)

        case .restart:
            emitDiagnostic(
                .warning,
                "Now Playing helper stopped unexpectedly (status \(status)); scheduling restart."
            )
            scheduleRestart()
        }
    }

    private func scheduleRestart() {
        guard !explicitlyStopped, process == nil else { return }

        launchTimeoutTask?.cancel()
        launchTimeoutTask = nil
        restartTask?.cancel()

        guard let delay = restartPolicy.nextDelay() else {
            let failure = NowPlayingFailure(
                kind: .restartLimitReached,
                message: "The Now Playing helper repeatedly stopped and will not restart automatically.",
                recoverySuggestion: "Retry manually after checking macOS compatibility."
            )
            publish(.unavailable(failure))
            publishConnection(.failed)
            emitDiagnostic(.error, failure.message)
            restartTask = nil
            return
        }

        publishConnection(.reconnecting)
        emitDiagnostic(.warning, "Helper stopped; restarting in \(delay) seconds.")
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.restartAfterDelay()
        }
    }

    private func stopAndScheduleRestart() {
        restartTask?.cancel()
        let stoppedProcess = stopProcess(markExplicit: false)
        restartTask = Task { [weak self] in
            await self?.finishRecoverableStop(stoppedProcess)
        }
    }

    private func finishRecoverableStop(_ stoppedProcess: Process?) async {
        await waitForTermination(of: stoppedProcess)
        guard !Task.isCancelled else { return }
        restartTask = nil
        scheduleRestart()
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
        oldProcess?.terminationHandler = nil

        launchTimeoutTask?.cancel()
        launchTimeoutTask = nil
        clearProcessReferences()

        if oldProcess?.isRunning == true {
            oldProcess?.terminate()
        }
        return oldProcess
    }

    private func clearProcessReferences() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutDataContinuation?.finish()
        stderrDataContinuation?.finish()
        stdoutReaderTask?.cancel()
        stderrReaderTask?.cancel()
        stabilityResetTask?.cancel()
        stdoutDataContinuation = nil
        stderrDataContinuation = nil
        stdoutReaderTask = nil
        stderrReaderTask = nil
        stabilityResetTask = nil

        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()

        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        launchIdentifier = nil
        lineDecoder.reset()
    }

    private func waitForTermination(of process: Process?) async {
        guard let process, process.isRunning else { return }

        let pollInterval: Duration = .milliseconds(50)
        let pollCount = 40
        for _ in 0..<pollCount {
            if !process.isRunning { return }
            try? await Task.sleep(for: pollInterval)
        }

        guard process.isRunning else { return }
        let processIdentifier = process.processIdentifier
        if processIdentifier > 0 {
            Darwin.kill(processIdentifier, SIGKILL)
            emitDiagnostic(
                .warning,
                "Helper did not stop within \(gracefulStopTimeout); sent SIGKILL."
            )
        }
    }

    private func publish(_ newState: SystemNowPlayingState) {
        guard newState != state else { return }
        state = newState
        continuation.yield(.stateChanged(newState))
    }

    private func publishConnection(_ newState: SystemNowPlayingConnectionState) {
        guard newState != connectionState else { return }
        connectionState = newState
        continuation.yield(.connectionChanged(newState))
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

    private func handleWake() async {
        guard !explicitlyStopped else { return }

        restartTask?.cancel()
        restartTask = nil
        restartPolicy.reset()
        publishConnection(.starting)

        let stoppedProcess = stopProcess(markExplicit: false)
        await waitForTermination(of: stoppedProcess)
        launchHelper()
    }
}
