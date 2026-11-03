import Foundation

/// The single error type surfaced by nomac's libraries.
///
/// Every error carries a human-readable message in the style of Xcode's own
/// diagnostics (`error: ...`), an optional file location, and optional notes.
/// The command-line front end prints errors with ``NomacError/rendered``.
public struct NomacError: Error, CustomStringConvertible, Sendable, Equatable {
    /// The primary message, without the `error:` prefix.
    public var message: String
    /// The file the error refers to, if any.
    public var path: String?
    /// Additional lines printed as `note:` diagnostics after the error.
    public var notes: [String]
    /// The status nomac exits with: 1, or the status `xcodebuild` exits with for the same
    /// failure (65 for a missing scheme, for example).
    public var exitStatus: Int32
    /// Further errors of the same failure, printed after this one (xcodebuild reports each
    /// bundle's provisioning problems at once).
    public var following: [NomacError]

    /// Creates an error with a message and optional location, notes and exit status.
    public init(_ message: String, path: String? = nil, notes: [String] = [], exitStatus: Int32 = 1, following: [NomacError] = []) {
        self.message = message
        self.path = path
        self.notes = notes
        self.exitStatus = exitStatus
        self.following = following
    }

    /// The error formatted the way `xcodebuild` formats diagnostics:
    /// `<path>: error: <message>` followed by one `note:` line per note.
    public var rendered: String {
        var lines: [String] = []
        if let path {
            lines.append("\(path): error: \(message)")
        } else {
            lines.append("error: \(message)")
        }
        for note in notes {
            lines.append("note: \(note)")
        }
        lines += following.map(\.rendered)
        return lines.joined(separator: "\n")
    }

    public var description: String { rendered }
}
