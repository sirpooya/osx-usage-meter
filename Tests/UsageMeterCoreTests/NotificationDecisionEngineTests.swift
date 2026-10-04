import XCTest
@testable import UsageMeterCore

/// Risk covered: the duplicate and missed notifications the audit report's "6. Test coverage" section called out.
/// A wrong stale flag cleanup, a wrong threshold crossing test or wrong reset detection all show up here.
final class NotificationDecisionEngineTests: XCTestCase {

    private let warningKey = "claude:acc:fiveHour"
    private let earlyKey = "claude:acc:sevenDay:75"

    // MARK: - isReset

    func testIsResetOnLargePercentageDrop() {
        XCTAssertTrue(NotificationDecisionEngine.isReset(
            currentPct: 10, previousPct: 95, currentResetsAt: nil, previousResetsAt: nil
        ))
    }

    func testIsNotResetOnSmallPercentageDrop() {
        XCTAssertFalse(NotificationDecisionEngine.isReset(
            currentPct: 80, previousPct: 95, currentResetsAt: nil, previousResetsAt: nil
        ))
    }

    func testIsResetOnResetsAtChangeWithPercentageDecrease() {
        let previous = Date()
        let current = previous.addingTimeInterval(3600)
        XCTAssertTrue(NotificationDecisionEngine.isReset(
            currentPct: 5, previousPct: 50, currentResetsAt: current, previousResetsAt: previous
        ))
    }

    func testIsNotResetWhenResetsAtChangesButPercentageIncreases() {
        let previous = Date()
        let current = previous.addingTimeInterval(3600)
        XCTAssertFalse(NotificationDecisionEngine.isReset(
            currentPct: 60, previousPct: 50, currentResetsAt: current, previousResetsAt: previous
        ))
    }

    // MARK: - evaluate: no data

    func testEvaluateReturnsNoActionsWhenCurrentIsNil() {
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: nil, previous: 50,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: ["x": 1]
        )
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(warnings, ["x": 1])
    }

    // MARK: - evaluate: crossing the 90% threshold

    func testEvaluateFiresWarningWhenCrossing90Percent() {
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 92, previous: 80,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [:]
        )
        XCTAssertEqual(actions, [.warning(percentage: 92)])
        XCTAssertEqual(warnings[warningKey], 0)
    }

    func testEvaluateDoesNotDuplicateWarningAlreadyNotified() {
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 95, previous: 92,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [warningKey: 0]
        )
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(warnings[warningKey], 0)
    }

    func testEvaluateFiresExactlyAtThresholdBoundary() {
        let (actions, _) = NotificationDecisionEngine.evaluate(
            current: 90, previous: 89.9,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [:]
        )
        XCTAssertEqual(actions, [.warning(percentage: 90)])
    }

    func testEvaluateDoesNotFireWhenAlreadyAtThresholdWithoutCrossing() {
        // previous is already at or above the threshold, so this is not a crossing, only a repeat reading at the same level
        let (actions, _) = NotificationDecisionEngine.evaluate(
            current: 91, previous: 90,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [:]
        )
        XCTAssertTrue(actions.isEmpty)
    }

    func testEvaluateDoesNotFireWhenStayingAboveThresholdWithoutPreviousData() {
        // A nil previous is treated as 0, and the jump "from 0 to current" must not be misread:
        // as long as current itself is at or above the threshold it should fire; this checks that a current below the threshold does not
        let (actions, _) = NotificationDecisionEngine.evaluate(
            current: 50, previous: nil,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [:]
        )
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - evaluate: the 75% early warning (only the sevenDay and codexSecondary types pass an earlyWarningKey)

    func testEvaluateFiresEarlyWarningWhenCrossing75Percent() {
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 78, previous: 60,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: earlyKey,
            notifiedWarnings: [:]
        )
        XCTAssertEqual(actions, [.warning(percentage: 78)])
        XCTAssertNotNil(warnings[earlyKey])
        XCTAssertNil(warnings[warningKey])
    }

    func testEvaluateFiresBothEarlyAndMainWarningInOrderWhenJumpingPast90() {
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 95, previous: 10,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: earlyKey,
            notifiedWarnings: [:]
        )
        XCTAssertEqual(actions, [.warning(percentage: 95), .warning(percentage: 95)])
        XCTAssertNotNil(warnings[earlyKey])
        XCTAssertNotNil(warnings[warningKey])
    }

    func testEvaluateDoesNotFireEarlyWarningWhenTypeIsIneligible() {
        // earlyWarningKey == nil simulates a type other than sevenDay or codexSecondary: crossing 75% still sends no early warning
        let (actions, _) = NotificationDecisionEngine.evaluate(
            current: 78, previous: 60,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [:]
        )
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - evaluate: reset detection

    func testEvaluateFiresResetAndClearsBothKeysOnPercentageDrop() {
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 5, previous: 95,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: earlyKey,
            notifiedWarnings: [warningKey: 100, earlyKey: 100, "other": 1]
        )
        XCTAssertEqual(actions, [.reset])
        XCTAssertNil(warnings[warningKey])
        XCTAssertNil(warnings[earlyKey])
        XCTAssertEqual(warnings["other"], 1)
    }

    func testEvaluateFiresResetAndClearsBothKeysOnResetsAtChange() {
        // The second reset trigger besides a sharp percentage drop: resetsAt changed and the percentage fell
        let previous = Date()
        let current = previous.addingTimeInterval(3600)
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 5, previous: 50,
            currentResetsAt: current, previousResetsAt: previous,
            warningKey: warningKey, earlyWarningKey: earlyKey,
            notifiedWarnings: [warningKey: 100, earlyKey: 100]
        )
        XCTAssertEqual(actions, [.reset])
        XCTAssertNil(warnings[warningKey])
        XCTAssertNil(warnings[earlyKey])
    }

    func testEvaluateDoesNotFireResetWhenNoPreviousData() {
        let (actions, _) = NotificationDecisionEngine.evaluate(
            current: 5, previous: nil,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [:]
        )
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - evaluate: stale flag cleanup (the quota reset while the app was not running)

    func testEvaluateClearsStaleFlagFromPreviousCycleAndRefires() {
        let oldCycle = Date(timeIntervalSince1970: 1000)
        let newCycle = Date(timeIntervalSince1970: 5000)

        // The flag belongs to oldCycle while the current resetsAt is already newCycle, so a reset happened while the app was not running.
        // isReset's in memory comparison (no previous, or a previous that is already very low) cannot catch it, and the stale flag cleanup is what keeps it from being missed
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 92, previous: 10,
            currentResetsAt: newCycle, previousResetsAt: newCycle,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [warningKey: oldCycle.timeIntervalSince1970]
        )
        XCTAssertEqual(actions, [.warning(percentage: 92)])
        XCTAssertEqual(warnings[warningKey], newCycle.timeIntervalSince1970)
    }

    func testEvaluateKeepsFlagWhenCycleUnchanged() {
        let cycle = Date(timeIntervalSince1970: 5000)
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 95, previous: 92,
            currentResetsAt: cycle, previousResetsAt: cycle,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [warningKey: cycle.timeIntervalSince1970]
        )
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(warnings[warningKey], cycle.timeIntervalSince1970)
    }

    func testEvaluateTreatsExactlyOneSecondApartCycleAsUnchanged() {
        // clearIfStale tests with `> 1` second, so a difference of exactly 1 second must not count as stale (the boundary)
        let oldCycle = Date(timeIntervalSince1970: 5000)
        let newCycle = Date(timeIntervalSince1970: 5001)
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 95, previous: 92,
            currentResetsAt: newCycle, previousResetsAt: newCycle,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [warningKey: oldCycle.timeIntervalSince1970]
        )
        XCTAssertTrue(actions.isEmpty, "A 1 second jitter must not be read as a new window and re-trigger the warning")
        XCTAssertEqual(warnings[warningKey], oldCycle.timeIntervalSince1970)
    }

    func testEvaluateDoesNotClearFlagWhenCurrentResetsAtIsNilLikeExtraUsage() {
        // Types without a resetsAt, such as Extra Usage: a currentCycle of 0 should skip the stale cleanup and keep the existing behavior
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 95, previous: 92,
            currentResetsAt: nil, previousResetsAt: nil,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [warningKey: 12345]
        )
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(warnings[warningKey], 12345)
    }

    func testEvaluateMigratesLegacyBoolFlagAsAlwaysStale() {
        // The legacy [String: Bool] migrates to 1.0 (the conversion in NotificationManager.init),
        // which differs from any real resetsAt epoch, so it should be cleaned up as a stale flag and allow a fresh notification
        let cycle = Date(timeIntervalSince1970: 999_999)
        let (actions, warnings) = NotificationDecisionEngine.evaluate(
            current: 92, previous: 10,
            currentResetsAt: cycle, previousResetsAt: cycle,
            warningKey: warningKey, earlyWarningKey: nil,
            notifiedWarnings: [warningKey: 1.0]
        )
        XCTAssertEqual(actions, [.warning(percentage: 92)])
        XCTAssertEqual(warnings[warningKey], cycle.timeIntervalSince1970)
    }
}
