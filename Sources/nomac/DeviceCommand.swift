import ArgumentParser
import Foundation
import NomacCore
import NomacDevice
import NomacPackaging
import NomacSigning

/// `nomac device`: the devices usbmuxd sees, and whether a signed app can be installed on one.
struct DeviceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "device",
        abstract: "List and check devices, and read crash reports.",
        subcommands: [List.self, Pair.self, DeveloperMode.self, Status.self, Images.self, Personalize.self, Mount.self, Unmount.self, Crashes.self, Symbolicate.self, Query.self, Check.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List the devices usbmuxd sees.",
            discussion: """
            Asks usbmuxd (/var/run/usbmuxd, or USBMUXD_SOCKET_ADDRESS as UNIX:<path> or \
            <host>:<port>) for its devices and prints one line per device: its UDID and \
            connection type (docs/formats/usbmux.md). With no device, says on standard error what \
            to check.
            """
        )

        func run() throws {
            let address = try USBMux.address(environment: ProcessInfo.processInfo.environment)
            let usbmux = USBMuxClient(address: address)
            let devices = try usbmux.devices()
            for device in devices {
                print("\(device.serialNumber)\t\(device.connectionType)")
            }
            if devices.isEmpty {
                FileHandle.standardError.write(Data((usbmux.noDeviceNotes(seen: []).map { "note: \($0)" }.joined(separator: "\n") + "\n").utf8))
            }
        }
    }

    struct Pair: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Pair this host with a device, which asks you to tap Trust on it.",
            discussion: """
            Does nothing when a session already starts with usbmuxd's pair record. Otherwise makes \
            the host's keys and certificates, sends lockdownd's Pair and waits for the Trust \
            dialog's answer on the unlocked device, then gives usbmuxd the record \
            (docs/formats/lockdown.md "Pairing"). On Linux, usbmuxd also pairs by itself when you \
            tap Trust; this command accepts that too.
            """
        )

        @Option(help: "The UDID of the device.")
        var device: String

        @Option(help: "How many seconds to wait for you to unlock the device and tap Trust.")
        var timeout: Int = 120

        func run() throws {
            let usbmux = USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment))
            let outcome = try Pairing.pair(usbmux: usbmux, udid: device, timeout: TimeInterval(timeout)) { line in
                print(line)
                fflush(nil)
            }
            print(outcome == .alreadyPaired ? "already paired with \(device)" : "paired with \(device)")
        }
    }

    struct DeveloperMode: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "developer-mode",
            abstract: "Say whether Developer Mode is on and, when it is off, make it appear in Settings.",
            discussion: """
            Settings may not list Developer Mode on a device that has never met a developer tool. \
            This asks the device's AMFI service to show it, as libimobiledevice's \
            'idevicedevmodectl reveal' does; turning it on stays yours, on the device, which then \
            restarts.
            """
        )

        @Option(help: "The UDID of the device.")
        var device: String

        func run() throws {
            let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
            do {
                print(try session.checkDeveloperMode() == nil ? "the device does not report Developer Mode (before iOS 16 it needs none)" : "Developer Mode is on")
            } catch let error as NomacError where error.message == "Developer Mode is off" {
                try session.revealDeveloperMode()
                print("""
                Developer Mode is off, and Settings now lists it.
                On the device: Settings > Privacy & Security > Developer Mode, turn it on. It restarts; unlock it and confirm Turn On.
                """)
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check, step by step, what installing and launching on a device needs.",
            discussion: """
            Walks the chain nomac install and nomac launch use and prints each step it passes: \
            usbmuxd, the device, this host's pairing ('nomac device pair'), a lockdown session, \
            the iOS version, Developer Mode ('nomac device developer-mode'), the mounted Developer Disk Image, and the CoreDevice tunnel with its \
            app service. Stops at the first step that fails, with what to do about it.
            """
        )

        @Option(help: "The UDID of the device.")
        var device: String

        func run() throws {
            let address = try USBMux.address(environment: ProcessInfo.processInfo.environment)
            let usbmux = USBMuxClient(address: address)
            let listed = try usbmux.device(udid: device)
            print("usbmuxd: \(StreamSocket.describe(address)) lists the device (\(listed.connectionType))")
            let session = try DeviceSession(usbmux: usbmux, udid: device)
            print("lockdown: paired, session started")
            let version = if case .string(let text) = try session.value(key: "ProductVersion") { text } else { "unknown" }
            print("iOS: \(version)")
            print("Developer Mode: \(try session.checkDeveloperMode() == nil ? "not reported" : "enabled")")
            let images = try session.mountedImageTypes()
            print("Developer Disk Image: \(images.contains("Personalized") ? "mounted" : "not mounted ('nomac device mount' mounts it; nomac launch does when it needs it)")\(images.isEmpty ? "" : " [\(images.joined(separator: ", "))]")")
            let (_, ports) = try session.openCoreDevice()
            print("CoreDevice tunnel: RemoteServiceDiscovery lists \(ports.count) services, \(ports[AppService.serviceName] == nil ? "without" : "with") \(AppService.serviceName)")
        }
    }

    struct Images: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show the disk images mounted on a device, read-only.",
            discussion: """
            Prints each image mobile_image_mounter's CopyDevices lists: its type and the other \
            keys of its entry (data by its length, the rest by value). With --image, a \
            personalized Developer Disk Image, also asks whether the device stores a \
            personalization manifest for it. Mounts nothing.
            """
        )

        @Option(help: "The UDID of the device.")
        var device: String

        @Option(help: "A personalized Developer Disk Image (.dmg), to ask whether the device stores its manifest.")
        var image: String?

        func run() throws {
            let address = try USBMux.address(environment: ProcessInfo.processInfo.environment)
            let session = try DeviceSession(usbmux: USBMuxClient(address: address), udid: device)
            for entry in try session.mountedImages() {
                let type = if case .string(let text)? = entry["DiskImageType"] { text } else { "?" }
                let others = entry.keys.sorted().filter { $0 != "DiskImageType" }.map { key in "\(key): \(Self.kind(entry[key]!))" }
                print("\(type): " + others.joined(separator: ", "))
            }
            let identifiers = try session.personalizationIdentifiers()
            print("personalization identifiers: " + identifiers.keys.sorted().map { "\($0): \(Self.kind(identifiers[$0]!))" }.joined(separator: ", "))
            guard let image else { return }
            let path = FileSystem.absolute(image)
            guard let bytes = FileSystem.contents(atPath: path) else { throw NomacError("cannot read the image", path: path) }
            let manifest = try session.storedManifest(forImage: [UInt8](bytes))
            print("stored manifest for \((path as NSString).lastPathComponent): \(manifest.map { "yes, \($0.count) bytes" } ?? "none")")
        }

        /// A value as printed: data by its length, collections by their count, others as they are.
        static func kind(_ value: PropertyListValue) -> String {
            switch value {
            case .boolean(let flag): "\(flag)"
            case .integer(let number): "\(number)"
            case .data(let bytes): "data (\(bytes.count) bytes)"
            case .string(let text): "\"\(text)\""
            case .array(let elements): "array of \(elements.count)"
            case .dictionary(let entries): "dictionary of \(entries.count)"
            case .real: "real"
            case .date: "date"
            }
        }
    }

    struct Personalize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write the ticket that personalizes the Developer Disk Image for a device.",
            discussion: """
            The ticket the device stores for the image, else one Apple's TSS server signs for the \
            device's identifiers and a nonce it gives (ADR 0403). Mounts nothing.
            """
        )

        @Option(help: "The UDID of the device.")
        var device: String

        @Option(help: "\(DeveloperDiskImage.optionHelp)")
        var ddi: String?

        @Option(name: .shortAndLong, help: "Where to write the ticket.")
        var output: String

        func run() throws {
            let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
            let ticket = try session.personalize(try DeveloperDiskImage.locate(developerDiskImagePath(ddi)), progress: { print($0) })
            try FileSystem.write(Data(ticket), to: FileSystem.absolute(output))
            print("wrote a \(ticket.count)-byte ticket to \(output)")
        }
    }

    struct Mount: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Mount the Developer Disk Image on a device.",
            discussion: """
            Personalizes the image for the device as 'nomac device personalize' does, uploads it \
            and mounts it with mobile_image_mounter (ADR 0403). Does nothing when an image is \
            already mounted.
            """
        )

        @Option(help: "The UDID of the device.")
        var device: String

        @Option(help: "\(DeveloperDiskImage.optionHelp)")
        var ddi: String?

        func run() throws {
            let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
            guard try !session.developerDiskImageMounted() else { return print("the Developer Disk Image is already mounted") }
            _ = try session.checkDeveloperMode()
            try session.mount(try DeveloperDiskImage.locate(developerDiskImagePath(ddi)), progress: { print($0) })
            print("mounted the Developer Disk Image on \(device)")
        }
    }

    struct Unmount: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Unmount the Developer Disk Image from a device.",
            discussion: "Asks mobile_image_mounter to unmount the personalized image at the mount path CopyDevices lists."
        )

        @Option(help: "The UDID of the device.")
        var device: String

        func run() throws {
            let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
            try session.unmountDeveloperDiskImage()
            print("the Developer Disk Image is \(try session.developerDiskImageMounted() ? "still mounted" : "unmounted")")
        }
    }

    struct Crashes: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List a device's crash reports, and copy them.",
            discussion: """
            Lets crashreportmover move the latest reports, then lists the .ips files \
            crashreportcopymobile serves over AFC, newest first: their path, size and time \
            (docs/formats/crash-report.md). With --output, copies them there.
            """
        )

        @Option(help: "The UDID of the device.")
        var device: String

        @Option(help: "Only the reports of this process (the name before the date).")
        var process: String?

        @Option(help: "Only the latest N reports.")
        var last: Int?

        @Option(name: .shortAndLong, help: "A folder to copy the reports to.")
        var output: String?

        func run() throws {
            let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
            let (all, afc) = try session.crashReports()
            var reports = all.filter { report in process.map { ((report.path as NSString).lastPathComponent).hasPrefix($0 + "-") } ?? true }
                .sorted { ($0.modified, $0.path) > ($1.modified, $1.path) }
            if let last { reports = Array(reports.prefix(last)) }
            let formatter = ISO8601DateFormatter()
            for report in reports {
                print("\(report.path)\t\(report.size)\t\(formatter.string(from: Date(timeIntervalSince1970: report.modified)))")
            }
            guard let output else { return }
            let folder = FileSystem.absolute(output)
            try FileSystem.createDirectory(folder)
            for report in reports {
                try FileSystem.write(Data(try afc.download(report.path)), to: folder + "/" + (report.path as NSString).lastPathComponent)
            }
            print("copied \(reports.count) reports to \(output)")
        }
    }

    struct Symbolicate: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print a crash report with the app's frames symbolicated.",
            discussion: """
            Prints the report's process, exception and reason, the last exception backtrace and \
            every thread. The device names its own libraries' frames; frames in an image whose \
            UUID matches a given dSYM get the function, inlined calls and source lines 'atos -i' \
            prints ('nomac atos', docs/formats/crash-report.md).
            """
        )

        @Argument(help: "The crash report (.ips).")
        var report: String

        @Option(help: "A .dSYM, a folder of them, or an .xcarchive (repeatable).")
        var dsym: [String] = []

        @Option(help: "An Xcode Contents/Developer directory, for its Swift demangler.")
        var developerDir: String?

        func run() throws {
            let path = FileSystem.absolute(report)
            guard let data = FileSystem.contents(atPath: path) else { throw NomacError("cannot read the report", path: path) }
            let crash = try CrashReport(bytes: [UInt8](data), path: path)
            let developer = try DeveloperDirectory.resolveIfAvailable(option: developerDir, strictXcode: false)
            let demangle = Demangler(toolchain: developer.map { $0 + "/Toolchains/XcodeDefault.xctoolchain/usr" })
            var symbolicators: [String: Symbolicator] = [:]
            for file in try dsym.flatMap({ try Self.dwarfFiles(FileSystem.absolute($0)) }) {
                for slice in try Symbolicator.slices(dwarfFile: file, demangle: { demangle($0) }) where crash.imageUUIDs.contains(slice.uuid) {
                    symbolicators[slice.uuid] = slice
                }
            }
            if !dsym.isEmpty, symbolicators.isEmpty {
                FileHandle.standardError.write(Data("warning: no dSYM matches the report's images' UUIDs\n".utf8))
            }
            print(crash.render(symbolicators: symbolicators), terminator: "")
        }

        /// The DWARF files of a .dSYM, of the .dSYMs in a folder, or of an .xcarchive's dSYMs.
        static func dwarfFiles(_ path: String) throws -> [String] {
            if path.hasSuffix(".dSYM") { return try AtosCommand.dwarfFiles(dsym: path) }
            let folder = path.hasSuffix(".xcarchive") ? path + "/dSYMs" : path
            guard FileSystem.isDirectory(folder) else { return [path] }
            return try FileSystem.sortedContents(of: folder).filter { $0.hasSuffix(".dSYM") }.flatMap { try AtosCommand.dwarfFiles(dsym: folder + "/" + $0) }
        }
    }

    struct Query: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print lockdownd's type and the values it gives before a session.",
            discussion: """
            Connects to lockdownd (port 62078) through usbmuxd and prints its QueryType and the \
            values GetValue answers without a session, as an XML property list \
            (docs/formats/lockdown.md). Needs no pairing.
            """
        )

        @Argument(help: "The UDID of the device.")
        var udid: String

        func run() throws {
            let usbmux = USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment))
            let device = try usbmux.device(udid: udid)
            let lockdown = LockdownClient(stream: try usbmux.connect(deviceID: device.deviceID, port: Lockdown.port))
            print(try lockdown.queryType())
            FileHandle.standardOutput.write(Data(PropertyListValue.xmlDocument(try lockdown.value())))
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check that a signed app can be installed on a device.",
            discussion: """
            Reads the app's bundle identifier and embedded provisioning profile and reports \
            each reason a device would refuse it: no profile (an app signed ad hoc), an expired \
            profile, an App ID that does not cover the bundle identifier, a device the profile \
            does not include; and warns about an app that would stop at launch (no scene \
            manifest under the iOS 27 SDK, TN3187). Exits with status 1 when there is a reason.
            """
        )

        @Argument(help: "A signed .app bundle.")
        var app: String

        @Option(help: "The UDID of the device to install on.")
        var device: String?

        func run() throws {
            for warning in try InstallCheck.warnings(app: FileSystem.absolute(app)) {
                FileHandle.standardError.write(Data("\(app): warning: \(warning)\n".utf8))
            }
            let problems = try InstallCheck.problems(app: FileSystem.absolute(app), device: device, at: Date())
            guard problems.isEmpty else {
                throw NomacError("the app cannot be installed", path: app, notes: problems)
            }
            print("\(app): installable\(device.map { " on \($0)" } ?? "")")
        }
    }
}
