import Foundation

/// Runs external programs. nomac uses this only for pinned subprocess dependencies
/// (see docs/adr/0001-language.md); everything else is linked Swift code.
public enum Subprocess {
    /// The result of a finished process.
    public struct Result: Sendable {
        public var exitStatus: Int32
        public var standardOutput: Data
        public var standardError: Data

        public var outputString: String { String(decoding: standardOutput, as: UTF8.self) }
        public var errorString: String { String(decoding: standardError, as: UTF8.self) }
    }

    /// Finds an executable by name on `PATH`, or returns `name` itself if it contains a `/`
    /// and is executable.
    public static func locate(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for dir in (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Runs `executable` with `arguments` and captures its output.
    ///
    /// When `passthrough` is `true` the child's output goes straight to this process's
    /// standard output and error instead of being captured (for long-running tools whose
    /// progress the user should see).
    public static func run(_ executable: String, _ arguments: [String], currentDirectory: String? = nil, environment: [String: String]? = nil, passthrough: Bool = false) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        if let environment {
            process.environment = environment
        }
        let pipes = passthrough ? nil : (out: Pipe(), err: Pipe())
        if let pipes {
            process.standardOutput = pipes.out
            process.standardError = pipes.err
        }
        // A file another thread has just written may still be open for writing in a child that
        // is between fork and exec, or for the child's whole life when the writer's descriptor
        // was not close-on-exec (Foundation's Data.write): ETXTBSY, "Text file busy". Starting
        // again succeeds once that child has exec'd or exited; the attempts span 5.25 seconds.
        var attempt = 0
        while true {
            do {
                try process.run()
                break
            } catch let error as NSError where attempt < 20 && (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(ETXTBSY) {
                attempt += 1
                usleep(UInt32(25_000 * attempt))
            } catch {
                throw NomacError("could not launch \(executable): \(error.localizedDescription)")
            }
        }
        // Drain both pipes concurrently so a chatty child cannot fill one and deadlock.
        let collected = CollectedOutput()
        let group = DispatchGroup()
        if let pipes {
            group.enter()
            DispatchQueue.global().async {
                collected.setOut(pipes.out.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                collected.setErr(pipes.err.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }
        process.waitUntilExit()
        group.wait()
        // The read ends stay open until Foundation releases the pipes, which in a long run of
        // subprocesses comes too late: firefox's `nomac verify` held 2,210 pipes and could launch
        // no more ("Bad file descriptor").
        try? pipes?.out.fileHandleForReading.close()
        try? pipes?.err.fileHandleForReading.close()
        return Result(exitStatus: process.terminationStatus, standardOutput: collected.out, standardError: collected.err)
    }
}

private final class CollectedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var _out = Data()
    private var _err = Data()
    var out: Data { lock.withLock { _out } }
    var err: Data { lock.withLock { _err } }
    func setOut(_ data: Data) { lock.withLock { _out = data } }
    func setErr(_ data: Data) { lock.withLock { _err = data } }
}
