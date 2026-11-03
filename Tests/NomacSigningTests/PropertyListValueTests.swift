import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacSigning

/// nomac writes XML property lists as `plutil -convert xml1` does (observed with
/// `signing_experiments.py synthetic`, which converts the document this test leaves in
/// `$NOMAC_SIGNING_OBSERVE/plist-data` with plutil and prints the digest of the result).
@Suite struct PropertyListValueTests {
    @Test func wrapsDataAsPlutilDoes() throws {
        let data = PropertyListValue.data((0..<100).map { UInt8($0 * 7 & 0xff) })
        let document = PropertyListValue.xmlDocument(.dictionary([
            "top": data,
            "nested": .dictionary(["deeper": .array([data, .data([1, 2, 3])])]),
            "real": .real(0.1),
            "text": .string("<&>"),
        ]))
        if let directory = ProcessInfo.processInfo.environment["NOMAC_SIGNING_OBSERVE"] {
            let destination = URL(fileURLWithPath: directory).appendingPathComponent("plist-data")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try Data(document).write(to: destination.appendingPathComponent("input.plist"))
        }
        #expect(SyntheticBundle.hex(SHA256.digest(document)) == "28327ccc8205da175715bf3d7454019571786fc9de52237e258edf88e56de803")
    }
}
