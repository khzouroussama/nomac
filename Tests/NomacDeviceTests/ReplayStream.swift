import Foundation
import NomacSigning
@testable import NomacDevice

/// A device's side of a connection, recorded: reads get its replies, writes are kept.
final class ReplayStream: ByteStream {
    var written: [UInt8] = []
    var incoming: [UInt8]

    init(replies: [[String: PropertyListValue]]) { incoming = replies.flatMap(PropertyListMessages.frame) }

    init(bytes: [UInt8]) { incoming = bytes }

    func write(_ bytes: [UInt8]) throws { written += bytes }

    func read(_ count: Int) throws -> [UInt8] {
        guard incoming.count >= count else { throw CocoaError(.fileReadCorruptFile) }
        defer { incoming.removeFirst(count) }
        return Array(incoming.prefix(count))
    }
}
