import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for segues table view cells trigger and for several segues'
/// order (`.github/scripts/nib_experiments.py` round 31, `cell_segue`): sizes and SHA-256 digests
/// of Xcode's nibs.
@Suite struct CellSegueTests {
    typealias Controllers = TableViewControllerTests
    static let ids = ["Qx4-pp-k2L", "a1B-zz-9Yt", "M0n-ee-T7c", "z9Z-aa-1Ab"]

    static func segue(_ kind: String, _ identifier: String? = nil, id: String = "csg-aa-aaa") -> String {
        "<connections>\n<segue destination=\"vc2-aa-aaa\" kind=\"\(kind)\"\(identifier.map { " identifier=\"\($0)\"" } ?? "") id=\"\(id)\"/>\n</connections>\n"
    }

    static func withConnections(_ cell: String, _ connections: String) -> String {
        cell.replacingOccurrences(of: "</tableViewCell>\n", with: connections + "</tableViewCell>\n")
    }

    static let controllerNib = "UITableViewController-tvc-aa-aaa.nib", viewNib = "tvc-aa-aaa-view-tbv-aa-aaa.nib"
    static func both(_ number: Int, y: Int, reuse: Bool) -> String {
        let attributes = (reuse ? " reuseIdentifier=\"Cell\(number)\"" : "") + " accessoryType=\"detailButton\""
        let segues = "<connections>\n<segue destination=\"vc2-aa-aaa\" kind=\"show\" identifier=\"Pick\(number)\" id=\"cs\(number)-aa-aaa\"/>\n"
            + "<segue destination=\"vc2-aa-aaa\" kind=\"show\" identifier=\"Details\(number)\" trigger=\"accessoryAction\" id=\"as\(number)-aa-aaa\"/>\n</connections>\n"
        return withConnections(Controllers.cell(number, y: y, attributes: attributes), segues)
    }

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-cellseg-accessory-and-selection", Controllers.storyboard(Controllers.scene(Controllers.prototypes(withConnections(
            Controllers.cell(1, attributes: " reuseIdentifier=\"Cell\" accessoryType=\"detailButton\""),
            "<connections>\n<segue destination=\"vc2-aa-aaa\" kind=\"show\" identifier=\"Pick\" id=\"csg-aa-aaa\"/>\n"
                + "<segue destination=\"vc2-aa-aaa\" kind=\"show\" identifier=\"Details\" trigger=\"accessoryAction\" id=\"asg-aa-aaa\"/>\n</connections>\n"))),
            SceneTests.scene(2)),
         [(controllerNib, 1408, "b2c3656082d5107d905a9f7952f290d8337bd3a9f0629208ad50a51c9682a779"),
          (viewNib, 3444, "f5cee4b87a461f0c2806252b4f4f28f100cc0dc52c259aae20b6ed820c9b33c0")]),
        ("sb-cellseg-static-two-both", Controllers.storyboard(Controllers.scene(Controllers.staticSection(both(1, y: 0, reuse: false) + both(2, y: 44, reuse: false)),
                                                                                dataMode: "static"), SceneTests.scene(2)),
         [(controllerNib, 1633, "59106e452c6781b0007612b454c835a84d0df0c3679f80caa158bc9bc57c5ecc"),
          (viewNib, 3050, "ff435af001a0f3b0b9f950ae03354dc367a6d02a2ec87d71f5ef9143794ae48c")]),
        ("sb-cellseg-prototype-showDetail-named", Controllers.storyboard(Controllers.scene(Controllers.prototypes(withConnections(Controllers.cell(1),
                                                                                                                                 segue("showDetail", "showDetail")))),
                                                                         SceneTests.scene(2)),
         [(controllerNib, 1308, "3294b9c9158a6f00c183af9b835343d9b788d661e8977921a70fffbf15931f75")]),
        ("sb-segue-showDetail", SceneTests.storyboard(SceneTests.scene(1, connections: #"<segue destination="vc2-aa-aaa" kind="showDetail" identifier="Open" id="sdg-aa-aaa"/>"# + "\n"),
                                                      SceneTests.scene(2)),
         [("UIViewController-vc1-aa-aaa.nib", 1219, "c0eb57da7f140f9728a1f0969f73798860058a92afbd5df21cf2ccf3ac26eab2")]),
        ("sb-cellseg-static-show", Controllers.storyboard(Controllers.scene(Controllers.staticSection(withConnections(Controllers.cell(1, y: 0, attributes: ""), segue("show"))),
                                                                            dataMode: "static"), SceneTests.scene(2)),
         [(controllerNib, 1267, "439f593d729a99b7a26fa7897f7ce5ba21c616ffb6540df7a4b0331129359ba6"),
          (viewNib, 2458, "419d38f74c47f65b91647edf02eaa0a927e04e4b4794143064fb436098b3a2bf")]),
        ("sb-cellseg-prototype-show-named", Controllers.storyboard(Controllers.scene(Controllers.prototypes(withConnections(Controllers.cell(1), segue("show", "Pick")))),
                                                                   SceneTests.scene(2)),
         [(controllerNib, 1296, "8340841730ffe7f4eabdd7d3098f2891b251d752e37ffee05b0d2c9ff470ad95"),
          (viewNib, 3256, "6a474a8ea4d4abe61fb4ceec98540098813dfd450ea09483b604e5836157ba3e")]),
        ("sb-segorder-mixed", Controllers.storyboard(Controllers.scene(Controllers.staticSection(ids.prefix(2).enumerated().map {
            withConnections(Controllers.cell($0.offset + 1, y: 44 * $0.offset, attributes: ""), segue("show", id: $0.element))
        }.joined()), afterView: "<connections>\n" + ids.suffix(2).enumerated().map {
            "<segue destination=\"vc2-aa-aaa\" kind=\"presentation\" identifier=\"P\($0.offset)\" id=\"\($0.element)\"/>\n"
        }.joined() + "</connections>\n", dataMode: "static"), SceneTests.scene(2)),
         [(controllerNib, 1537, "71cb6629be0eb95e6d0e52bda7537098f2ea9af62b84ed083e465af69ddb0870"),
          (viewNib, 2841, "590f86e92a5ab7b428c8209e5dfc18959e302c94f92ce4433ef7d596101bcf0d")]),
        ("sb-segorder-controller", SceneTests.storyboard(SceneTests.scene(1, connections: ids.enumerated().map {
            "<segue destination=\"vc2-aa-aaa\" kind=\"show\" identifier=\"S\($0.offset)\" id=\"\($0.element)\"/>\n"
        }.joined()), SceneTests.scene(2)),
         [("UIViewController-vc1-aa-aaa.nib", 1415, "0998bbce6a150374500866435ab5b2214bbc5ec314b54d479f93fce480bdcfea")]),
    ]

    /// Cells' segues as templates of their controller, reached through upstream placeholders the
    /// last cell's first; templates' strings shared; the `viewController` outlets of the
    /// controller's segues and then of the cells', each reversed.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }
}
