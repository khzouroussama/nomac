import Testing
@testable import NomacDeviceTest

/// XCTest writes `XCTestOutputBarrier` between its lines; xcodebuild's output has none
/// (`xctest_experiments.py` `test-pass`, and nomac's first run on the iPhone, 2026-11-03).
@Suite struct OutputBarrierTests {
    @Test func removesMarkersEvenWhenSplitBetweenReads() {
        var filter = OutputBarrierFilter()
        let reads = ["XCTestOutputBarrierTest Suite 'All tests' started.\nXCTestOutput", "BarrierTest Case passed.\nXC", "Tool says XC"]
        let output = reads.map { String(decoding: filter.filter(Array($0.utf8)), as: UTF8.self) }.joined()
            + String(decoding: filter.finish(), as: UTF8.self)
        #expect(output == "Test Suite 'All tests' started.\nTest Case passed.\nXCTool says XC")
    }
}
