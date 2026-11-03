/// The test process's standard output without the `XCTestOutputBarrier` markers XCTest writes
/// between its lines, which xcodebuild's output does not have (`xctest_experiments.py`
/// `test-pass`, docs/formats/xctest-device.md). A marker can be split between two reads: the
/// bytes that may start one wait for the next read.
public struct OutputBarrierFilter {
    static let marker = Array("XCTestOutputBarrier".utf8)
    private var pending: [UInt8] = []

    public init() {}

    public mutating func filter(_ bytes: [UInt8]) -> [UInt8] {
        var input = pending + bytes
        pending = []
        var output: [UInt8] = []
        var index = 0
        while index < input.count {
            if input[index] == Self.marker[0] {
                let available = min(Self.marker.count, input.count - index)
                if Array(input[index..<index + available]) == Array(Self.marker[0..<available]) {
                    if available == Self.marker.count {
                        index += available
                        continue
                    }
                    pending = Array(input[index...])
                    input.removeAll()
                    break
                }
            }
            output.append(input[index])
            index += 1
        }
        return output
    }

    /// What is held back at the end of the output.
    public mutating func finish() -> [UInt8] {
        defer { pending = [] }
        return pending
    }
}
