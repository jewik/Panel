import Foundation
import XCTest
@testable import Panel

final class HelperLifecyclePolicyTests: XCTestCase {
    func testRestartPolicyUsesBoundedExponentialBackoff() {
        var policy = HelperRestartPolicy(
            maximumAutomaticRestarts: 7,
            maximumDelay: 15
        )

        XCTAssertEqual(policy.nextDelay(), 0.5)
        XCTAssertEqual(policy.nextDelay(), 1)
        XCTAssertEqual(policy.nextDelay(), 2)
        XCTAssertEqual(policy.nextDelay(), 4)
        XCTAssertEqual(policy.nextDelay(), 8)
        XCTAssertEqual(policy.nextDelay(), 15)
        XCTAssertEqual(policy.nextDelay(), 15)
        XCTAssertNil(policy.nextDelay())
    }

    func testRestartPolicyResetAllowsAutomaticRestartAgain() {
        var policy = HelperRestartPolicy(maximumAutomaticRestarts: 1)

        XCTAssertEqual(policy.nextDelay(), 0.5)
        XCTAssertNil(policy.nextDelay())

        policy.reset()

        XCTAssertEqual(policy.nextDelay(), 0.5)
    }

    func testNonZeroNormalExitIsFatal() {
        XCTAssertEqual(
            HelperLifecyclePolicy.action(status: 2, reason: .exit),
            .fail
        )
    }

    func testCleanExitAndSignalCanRestart() {
        XCTAssertEqual(
            HelperLifecyclePolicy.action(status: 0, reason: .exit),
            .restart
        )
        XCTAssertEqual(
            HelperLifecyclePolicy.action(status: 9, reason: .uncaughtSignal),
            .restart
        )
    }
}
