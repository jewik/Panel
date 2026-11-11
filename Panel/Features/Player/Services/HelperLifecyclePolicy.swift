import Foundation

nonisolated struct HelperRestartPolicy: Sendable {
    let maximumAutomaticRestarts: Int
    let maximumDelay: TimeInterval

    private(set) var consecutiveRestarts = 0

    init(
        maximumAutomaticRestarts: Int = 6,
        maximumDelay: TimeInterval = 15
    ) {
        self.maximumAutomaticRestarts = maximumAutomaticRestarts
        self.maximumDelay = maximumDelay
    }

    mutating func nextDelay() -> TimeInterval? {
        guard consecutiveRestarts < maximumAutomaticRestarts else { return nil }

        let exponent = min(consecutiveRestarts, 5)
        consecutiveRestarts += 1
        return min(pow(2, Double(exponent)) * 0.5, maximumDelay)
    }

    mutating func reset() {
        consecutiveRestarts = 0
    }
}

nonisolated enum HelperExitAction: Equatable, Sendable {
    case restart
    case fail
}

nonisolated enum HelperLifecyclePolicy {
    static func action(
        status: Int32,
        reason: Process.TerminationReason
    ) -> HelperExitAction {
        if reason == .exit, status != 0 {
            // The adapter documents non-zero exits as fatal. Reinvoking it would
            // create an endless crash loop on an incompatible macOS release.
            return .fail
        }
        return .restart
    }
}
