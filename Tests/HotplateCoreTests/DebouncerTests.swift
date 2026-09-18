import XCTest
@testable import HotplateCore

final class DebouncerTests: XCTestCase {
    func testBurstFiresOnce() {
        let exp = expectation(description: "fired")
        let counter = Counter()
        let d = Debouncer(interval: 0.1, queue: DispatchQueue(label: "t")) { counter.increment(); exp.fulfill() }
        for _ in 0..<5 { d.trigger() }
        wait(for: [exp], timeout: 1)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(counter.value, 1)
    }

    func testSeparateBurstsFireTwice() {
        let exp = expectation(description: "fired"); exp.expectedFulfillmentCount = 2
        let d = Debouncer(interval: 0.05, queue: DispatchQueue(label: "t")) { exp.fulfill() }
        d.trigger()
        Thread.sleep(forTimeInterval: 0.2)
        d.trigger()
        wait(for: [exp], timeout: 1)
    }

    func testCancelPreventsFire() {
        let exp = expectation(description: "not fired"); exp.isInverted = true
        let d = Debouncer(interval: 0.05, queue: DispatchQueue(label: "t")) { exp.fulfill() }
        d.trigger(); d.cancel()
        wait(for: [exp], timeout: 0.3)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var v = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return v }
    func increment() { lock.lock(); v += 1; lock.unlock() }
}
