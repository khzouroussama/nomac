import ArgumentParser
import Foundation
import NomacBuild
import NomacCore

/// `nomac products`: two `Build/Products` folders compared as `nomac verify --build` compares a
/// build with its reference (docs/VERIFICATION.md "Build products").
struct ProductsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "products",
        abstract: "Compare two Build/Products folders.",
        discussion: "Prints one line per product: identical, equivalent with the documented causes, or different. Exits with status 1 if a product differs."
    )

    @Argument(help: "Xcode's products folder.")
    var reference: String

    @Argument(help: "The products folder to compare with it.")
    var other: String

    func run() throws {
        let checks = BuildVerification.productChecks(try BuildProducts.compare(reference: FileSystem.absolute(reference), other: FileSystem.absolute(other)), detailLimit: 20)
        for check in checks {
            print("[\(check.status.rawValue)] \(check.name)")
            for line in check.detail { print("    " + line) }
        }
        if checks.contains(where: { $0.status == .different }) { throw ExitCode(1) }
    }
}
