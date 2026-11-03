import Foundation
import NomacCore
import NomacTestSupport

/// Self-authored inputs for the signing tests: a bundle around ``SyntheticMachO`` files.
///
/// The expected values in the tests are what Xcode 27.0's codesign produced for these exact
/// bytes. To observe them again on a Mac, run the tests with `NOMAC_SIGNING_OBSERVE` set to a
/// directory: each test copies its unsigned input there, and
/// `.github/scripts/signing_experiments.py synthetic` signs the copies with codesign and prints
/// the values.
enum SyntheticBundle {
    /// An asset pack of on-demand resources in `directory`, as an archive holds one: an XML
    /// Info.plist with an identifier and tags, no executable, and one resource.
    /// A static framework: its binary an `ar` archive, as `MACH_O_TYPE` `staticlib` makes it.
    static func staticFramework(in directory: URL) throws -> URL {
        let bundle = directory.appendingPathComponent("Kit.framework")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Headers"), withIntermediateDirectories: true)
        try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \t<key>CFBundleExecutable</key>
            \t<string>Kit</string>
            \t<key>CFBundleIdentifier</key>
            \t<string>org.nomac.signing.Kit</string>
            \t<key>CFBundlePackageType</key>
            \t<string>FMWK</string>
            </dict>
            </plist>

            """.utf8).write(to: bundle.appendingPathComponent("Info.plist"))
        let member = Array("nomac static member\n".utf8)
        let header = "Kit.o/          0           0     0     644     \(member.count)".padding(toLength: 58, withPad: " ", startingAt: 0) + "`\n"
        try Data(Array("!<arch>\n".utf8) + Array(header.utf8) + member).write(to: bundle.appendingPathComponent("Kit"))
        try Data("int kit(void);\n".utf8).write(to: bundle.appendingPathComponent("Headers/Kit.h"))
        return bundle
    }

    /// `bundle` with the keys `keys` removed from its Info.plist (an XML one).
    static func removing(_ keys: [String], from bundle: @escaping (URL) throws -> URL) -> (URL) throws -> URL {
        { directory in
            let url = try bundle(directory)
            let info = url.appendingPathComponent("Info.plist")
            var text = try String(contentsOf: info, encoding: .utf8)
            for key in keys {
                guard let range = text.range(of: "\t<key>\(key)</key>\n") else { continue }
                let valueEnd = text[range.upperBound...].range(of: "\n")!.upperBound
                text.removeSubrange(range.lowerBound..<valueEnd)
            }
            try Data(text.utf8).write(to: info)
            return url
        }
    }

    static func assetPack(in directory: URL) throws -> URL {
        let bundle = directory.appendingPathComponent("org.nomac.level1-0f1e2d3c.assetpack")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            	<key>CFBundleIdentifier</key>
            	<string>org.nomac.asset-pack-0f1e2d3c</string>
            	<key>Tags</key>
            	<array>
            		<string>level1</string>
            	</array>
            </dict>
            </plist>

            """.utf8).write(to: bundle.appendingPathComponent("Info.plist"))
        try Data("level1\n".utf8).write(to: bundle.appendingPathComponent("level1.txt"))
        return bundle
    }

    /// An application bundle in `directory`: the executable `Foo`, an XML Info.plist, and
    /// resources that exercise every CodeResources rule.
    static func application(in directory: URL) throws -> URL {
        let bundle = directory.appendingPathComponent("Foo.app")
        let files: [String: String] = [
            "Info.plist": """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            	<key>CFBundleExecutable</key>
            	<string>Foo</string>
            	<key>CFBundleIdentifier</key>
            	<string>org.nomac.foo</string>
            	<key>CFBundlePackageType</key>
            	<string>APPL</string>
            </dict>
            </plist>

            """,
            "PkgInfo": "APPL????",
            "Base.lproj/Main.txt": "base\n",
            "en.lproj/a.txt": "en\n",
            "en.lproj/locversion.plist": "v\n",
            "Sub/de.lproj/b.txt": "de\n",
            "Sub/.DS_Store": "ds\n",
            ".DS_Store": "ds\n",
            ".hidden": "hidden\n",
            "empty.txt": "",
            "version.plist": "v\n",
            "embedded.mobileprovision": "p\n",
            "Res.bundle/r.txt": "r\n",
            "Docs.dSYM/Contents/x": "d\n",
            "with space & <tag>.txt": "sp\n",
            "Zed.txt": "Z\n",
            "Frameworks/Kit.framework/Info.plist": "kit\n",
        ]
        for (path, text) in files {
            let url = bundle.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try Data(SyntheticMachO.machO()).write(to: bundle.appendingPathComponent("Foo"))
        try Data(SyntheticMachO.machO(executable: false, seed: 2)).write(to: bundle.appendingPathComponent("Frameworks/Kit.framework/Kit"))
        try FileManager.default.createSymbolicLink(atPath: bundle.appendingPathComponent("link.txt").path, withDestinationPath: "empty.txt")
        try FileManager.default.createSymbolicLink(atPath: bundle.appendingPathComponent("linkdir").path, withDestinationPath: "Sub")
        for path in ["Foo", "Frameworks/Kit.framework/Kit"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundle.appendingPathComponent(path).path)
        }
        return bundle
    }

    /// With `NOMAC_SIGNING_OBSERVE` set, copies an unsigned input to `$NOMAC_SIGNING_OBSERVE/<name>/input`,
    /// the codesign arguments (the input's file name last) to `arguments`, the entitlements
    /// file, if any, to `entitlements.plist` and the identity file of `--keychain` to `identity.pem`.
    static func observe(_ url: URL, named name: String, arguments: [String], entitlements: URL? = nil) throws {
        guard let directory = ProcessInfo.processInfo.environment["NOMAC_SIGNING_OBSERVE"] else { return }
        let destination = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("input"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: destination.appendingPathComponent("input/\(url.lastPathComponent)"))
        try Data((arguments + [url.lastPathComponent]).joined(separator: "\n").utf8).write(to: destination.appendingPathComponent("arguments"))
        if let entitlements {
            try FileManager.default.copyItem(at: entitlements, to: destination.appendingPathComponent("entitlements.plist"))
        }
        if let index = arguments.firstIndex(of: "--keychain") {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: arguments[index + 1]), to: destination.appendingPathComponent("identity.pem"))
        }
    }

    /// The SHA-256 of every file under `url` (or of `url` itself), by relative path, and the
    /// target of every symbolic link.
    static func digests(of url: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let root = url.resolvingSymlinksInPath().path
        let paths = FileSystem.isDirectory(root) ? try FileManager.default.subpathsOfDirectory(atPath: root).sorted() : [""]
        for path in paths {
            let full = path.isEmpty ? root : root + "/" + path
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: full) {
                result[path] = "-> " + target
            } else if !FileSystem.isDirectory(full) {
                result[path] = hex(SHA256.digest([UInt8](try Data(contentsOf: URL(fileURLWithPath: full)))))
            }
        }
        return result
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
