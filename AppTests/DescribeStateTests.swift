import IntervalCore
import XCTest
@testable import IntervalTracker

/// Where the Describe sheet goes when a request ends or is cancelled.
final class DescribeStateTests: XCTestCase {
    private let earlier = GeneratedWorkout(workout: .hiit2020, note: nil)
    private let newer = GeneratedWorkout(workout: .norwegian4x4, note: "Four rounds.")

    func testAFirstRequestShowsItsAnswerOrItsFailure() {
        let asking = DescribeState.generating(keeping: nil)
        XCTAssertEqual(asking.ended(with: .success(newer)), .result(newer, retryFailure: nil))
        XCTAssertEqual(asking.ended(with: .failure(.busy)), .failed(.busy))
        XCTAssertEqual(asking.cancelled, .idle, "Cancel goes back to the description")
    }

    func testARetryThatSucceedsReplacesTheEarlierAnswer() {
        let retrying = DescribeState.generating(keeping: earlier)
        XCTAssertEqual(retrying.ended(with: .success(newer)), .result(newer, retryFailure: nil))
    }

    func testARetryThatFailsOrIsCancelledKeepsTheEarlierAnswer() {
        let retrying = DescribeState.generating(keeping: earlier)
        XCTAssertEqual(retrying.ended(with: .failure(.unreachable)), .result(earlier, retryFailure: .unreachable))
        XCTAssertEqual(retrying.cancelled, .result(earlier, retryFailure: nil))
    }

    func testAnotherRetryAfterAFailedOneClearsTheFailureWhenItSucceeds() {
        let failed = DescribeState.generating(keeping: earlier).ended(with: .failure(.busy))
        guard case .result(let kept, _) = failed else { return XCTFail("\(failed)") }
        XCTAssertEqual(DescribeState.generating(keeping: kept).ended(with: .success(newer)), .result(newer, retryFailure: nil))
    }
}
