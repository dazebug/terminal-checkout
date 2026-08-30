import Foundation
import XCTest
@testable import Core

private enum DeliveryPermitTestFailure: Error {
    case synthetic
}

final class BatchDeliveryTests: XCTestCase {
    func testDeliveryPermitAllowsAtLeastTwoConcurrentCalls() {
        let started = DispatchSemaphore(value: 0)
        let released = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var active = 0
        var maxActive = 0

        let group = DispatchGroup()
        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                withClaudeDeliveryPermit {
                    lock.lock()
                    active += 1
                    maxActive = max(maxActive, active)
                    lock.unlock()

                    started.signal()
                    released.wait()

                    lock.lock()
                    active -= 1
                    lock.unlock()
                }
                group.leave()
            }
        }

        XCTAssertEqual(started.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(started.wait(timeout: .now() + 1), .success)
        released.signal()
        released.signal()

        lock.lock()
        XCTAssertGreaterThanOrEqual(maxActive, 2, "two deliveries did not overlap")
        lock.unlock()

        group.wait()
    }

    func testDeliveryPermitCapsConcurrentCallsToAtMostFour() {
        let lock = NSLock()
        var active = 0
        var maxActive = 0

        let entered = DispatchSemaphore(value: 0)
        let hold = DispatchSemaphore(value: 0)
        let group = DispatchGroup()

        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                withClaudeDeliveryPermit {
                    lock.lock()
                    active += 1
                    maxActive = max(maxActive, active)
                    lock.unlock()

                    entered.signal()
                    hold.wait()

                    lock.lock()
                    active -= 1
                    lock.unlock()
                }
                group.leave()
            }
        }

        for _ in 0..<4 {
            XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        }
        lock.lock()
        XCTAssertLessThanOrEqual(maxActive, claudeDeliveryConcurrencyLimit, "limit was not set to 4")
        XCTAssertEqual(maxActive, claudeDeliveryConcurrencyLimit, "concurrency exceeded 4")
        lock.unlock()

        for _ in 0..<8 { hold.signal() }
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)

        lock.lock()
        XCTAssertLessThanOrEqual(maxActive, claudeDeliveryConcurrencyLimit)
        lock.unlock()
    }

    func testDeliveryPermitReleasesOnFailureSoNextCallCanRun() {
        let lock = NSLock()
        var active = 0
        var maxActive = 0

        let started = DispatchSemaphore(value: 0)
        let releaseOnFailure = DispatchSemaphore(value: 0)
        let releaseLongRunning = DispatchSemaphore(value: 0)
        let fifthStarted = DispatchSemaphore(value: 0)

        let group = DispatchGroup()

        for index in 0..<4 {
            group.enter()
            DispatchQueue.global().async {
                do {
                    try withClaudeDeliveryPermit {
                        lock.lock()
                        active += 1
                        maxActive = max(maxActive, active)
                        started.signal()
                        lock.unlock()

                        if index == 0 {
                            releaseOnFailure.wait()
                            throw DeliveryPermitTestFailure.synthetic
                        }
                        releaseLongRunning.wait()
                    }
                } catch {
                    // A thrown failure should still release the permit via defer in `withClaudeDeliveryPermit`.
                }

                lock.lock()
                if active > 0 { active -= 1 }
                lock.unlock()
                group.leave()
            }
        }

        for _ in 0..<4 { XCTAssertEqual(started.wait(timeout: .now() + 1), .success) }

        group.enter()
        DispatchQueue.global().async {
            withClaudeDeliveryPermit { fifthStarted.signal() }
            group.leave()
        }

        XCTAssertEqual(fifthStarted.wait(timeout: .now() + 0.25), .timedOut)
        releaseOnFailure.signal()
        XCTAssertEqual(fifthStarted.wait(timeout: .now() + 2), .success)

        for _ in 0..<3 { releaseLongRunning.signal() }
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)

        lock.lock()
        XCTAssertLessThanOrEqual(maxActive, claudeDeliveryConcurrencyLimit)
        XCTAssertEqual(maxActive, claudeDeliveryConcurrencyLimit)
        XCTAssertEqual(active, 0)
        lock.unlock()
    }
}
