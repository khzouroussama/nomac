import Foundation
import NomacCore

/// Symbolic links that make the paths a project spells in another case than the disk exist as
/// spelled, for `nomac build --case-aliases` (BACKLOG B-062). Without them a build on a
/// case-sensitive file system gives Swift Build the disk's spelling, which the compilers then
/// record in debug information and `.swiftsourceinfo` files where Xcode's record the project's;
/// with them the build uses the project's paths (observed on Linux: a `PDFGeneration` link to
/// `PdfGeneration` makes `Gen.o` and the `.swiftsourceinfo` files record `PDFGeneration` only).
/// The links go into the checkout, so they are made only on request and removed after the build.
public struct CaseAliases {
    /// A link to make: `path`, the project's spelling, naming its sibling `destination`.
    public struct Link: Hashable, Sendable {
        public var path: String
        public var destination: String
    }

    public let links: [Link]
    private var made: [Link] = []

    /// The links that make each of `paths` exist as spelled: one for each component that is
    /// missing as given but present in another case, in the folder it resolves to. A component
    /// present only in another normalization form, or not at all, gets none, nor do those after it.
    public init(paths: [String]) {
        var links: [Link] = []
        var seen: Set<String> = []
        for path in paths {
            var real = ""
            for component in path.split(separator: "/").map(String.init) {
                let candidate = real + "/" + component
                if component == "." || component == ".." || FileManager.default.fileExists(atPath: candidate) {
                    real = candidate
                    continue
                }
                let entries = ((try? FileManager.default.contentsOfDirectory(atPath: real.isEmpty ? "/" : real)) ?? [])
                    .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
                guard !entries.contains(where: { $0 == component }),
                      let entry = entries.first(where: { $0.caseInsensitiveCompare(component) == .orderedSame }) else { break }
                if seen.insert(candidate).inserted {
                    links.append(Link(path: candidate, destination: entry))
                }
                real = real + "/" + entry
            }
        }
        self.links = links
    }

    /// Makes the links, all or none: refused when a folder that would hold one is not writable.
    public mutating func make() throws {
        for link in links {
            let folder = (link.path as NSString).deletingLastPathComponent
            guard FileManager.default.isWritableFile(atPath: folder) else {
                throw NomacError("--case-aliases links the project's spelling of a path into the checkout, and this folder is not writable", path: folder)
            }
        }
        for link in links {
            do {
                try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: link.destination)
            } catch {
                remove()
                throw NomacError("could not link the project's spelling to '\(link.destination)': \(error.localizedDescription)", path: link.path)
            }
            made.append(link)
        }
    }

    /// Removes the links ``make()`` made that still name what it made them name.
    public mutating func remove() {
        for link in made.reversed() where (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == link.destination {
            try? FileManager.default.removeItem(atPath: link.path)
        }
        made = []
    }
}
