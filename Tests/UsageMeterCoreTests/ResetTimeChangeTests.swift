import XCTest
@testable import UsageMeterCore

/// Risk covered: a misjudgment leaving the reset validation timers uncancelled when they should be cancelled, or unscheduled when they should be scheduled.
final class ResetTimeChangeTests: XCTestCase {

    func testBothNilIsNoChange() {
        XCTAssertFalse(hasResetTimeChanged(from: nil, to: nil))
    }

    func testNilToValueIsChange() {
        XCTAssertTrue(hasResetTimeChanged(from: nil, to: Date()))
    }

    func testValueToNilIsChange() {
        XCTAssertTrue(hasResetTimeChanged(from: Date(), to: nil))
    }

    func testSameValueIsNoChange() {
        let date = Date()
        XCTAssertFalse(hasResetTimeChanged(from: date, to: date))
    }

    func testWithinOneSecondToleranceIsNoChange() {
        let old = Date()
        let new = old.addingTimeInterval(0.5)
        XCTAssertFalse(hasResetTimeChanged(from: old, to: new))
    }

    func testBeyondOneSecondToleranceIsChange() {
        let old = Date()
        let new = old.addingTimeInterval(1.5)
        XCTAssertTrue(hasResetTimeChanged(from: old, to: new))
    }

    func testOrderOfArgumentsDoesNotMatter() {
        let old = Date()
        let new = old.addingTimeInterval(120)
        XCTAssertTrue(hasResetTimeChanged(from: new, to: old))
    }
}
