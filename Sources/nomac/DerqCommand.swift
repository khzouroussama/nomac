import ArgumentParser
import Foundation
import NomacCore
import NomacSigning

/// `nomac derq`: macOS's `/usr/bin/derq` for the form Swift Build's `ProcessProductPackagingDER`
/// task runs, `query -f xml -i <entitlements> -o <der> --raw` (an app signed with entitlements).
struct DerqCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "derq",
        abstract: "Encode an XML entitlements file as DER, as macOS's derq does for builds.",
        discussion: "Takes 'query -f xml -i <entitlements> -o <der> [--raw]' (.github/scripts/derq_experiments.py).",
        shouldDisplay: false
    )

    @Argument(parsing: .captureForPassthrough, help: "derq's arguments.")
    var arguments: [String] = []

    func run() throws {
        var input: String?, output: String?, format: String?
        var rest = arguments.dropFirst()
        guard arguments.first == "query" else { throw refusal() }
        while let argument = rest.popFirst() {
            switch argument {
            case "-i", "--input": input = rest.popFirst()
            case "-o", "--output": output = rest.popFirst()
            case "-f", "--format": format = rest.popFirst()
            case "-r", "--raw": continue
            default:
                if argument.hasPrefix("--input=") { input = String(argument.dropFirst(8)) }
                else if argument.hasPrefix("--output=") { output = String(argument.dropFirst(9)) }
                else if argument.hasPrefix("--format=") { format = String(argument.dropFirst(9)) }
                else { throw refusal() }
            }
        }
        guard format == "xml", let input, let output, input != "-", output != "-" else { throw refusal() }
        let path = FileSystem.absolute(input)
        guard let xml = FileSystem.contents(atPath: path) else { throw NomacError("cannot read the entitlements file", path: path) }
        try FileSystem.write(Data(try EntitlementsDER.encode(xml: [UInt8](xml), path: path)), to: FileSystem.absolute(output))
    }

    private func refusal() -> NomacError {
        NomacError("nomac derq takes 'query -f xml -i <entitlements> -o <der> [--raw]', not 'derq \(arguments.joined(separator: " "))'")
    }
}
