import Foundation

/// Runs `body` on a thread of its own with a stack of 64 MB. A document nests views as deep as it says,
/// and compiling one recurses through large frames: five levels overflow the 512 KB of a worker
/// thread in a debug build.
func onLargeStack<Value: Sendable>(_ body: @escaping @Sendable () throws -> Value) throws -> Value {
    let outcome = LargeStackOutcome<Value>()
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
        outcome.result = Result { try body() }
        done.signal()
    }
    thread.stackSize = 64 << 20
    thread.start()
    done.wait()
    return try outcome.result!.get()
}

private final class LargeStackOutcome<Value>: @unchecked Sendable {
    var result: Result<Value, Error>?
}
