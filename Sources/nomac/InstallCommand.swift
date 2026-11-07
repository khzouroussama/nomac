import ArgumentParser
import Foundation
import NomacBuild
import NomacCore
import NomacDevice
import NomacPackaging
import NomacSDK
import NomacSigning

/// `nomac install`, `nomac uninstall` and `nomac launch`: an app on a device through usbmuxd and
/// lockdownd.
struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install an app on a device.",
        discussion: """
        Starts a lockdownd session as the host of usbmuxd's pair record for the device, uploads \
        the IPA with AFC to PublicStaging and installs it with installation_proxy, printing \
        each stage (docs/formats/lockdown.md, docs/formats/afc.md). A signed .app is first \
        checked as 'nomac device check' does, then packed as an IPA. usbmuxd is \
        /var/run/usbmuxd or USBMUXD_SOCKET_ADDRESS; 'nomac device status' checks the way there.
        """
    )

    @Argument(help: "The .ipa file, or a signed .app.")
    var app: String

    @Option(help: "The UDID of the device.")
    var device: String

    func run() throws {
        try install(FileSystem.absolute(app), on: device)
    }

}

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove an app from a device.",
        discussion: "Asks installation_proxy to uninstall the app with the bundle identifier, through usbmuxd and lockdownd."
    )

    @Argument(help: "The app's bundle identifier.")
    var bundleIdentifier: String

    @Option(help: "The UDID of the device.")
    var device: String

    func run() throws {
        let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
        try session.uninstall(bundleIdentifier: bundleIdentifier, progress: printStage)
        print("uninstalled \(bundleIdentifier) from \(device)")
    }
}

struct LaunchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an installed app on a device.",
        discussion: """
        Opens the CoreDevice tunnel through lockdownd (iOS 17.4 and later), finds the app \
        service with RemoteServiceDiscovery and asks it to launch the app, printing the \
        process identifier (docs/formats/remotexpc.md). When the device's Developer Disk Image \
        is not mounted, mounts it first as 'nomac device mount' does. With --console, the app's \
        standard output and error are printed until it exits.
        """
    )

    @Argument(help: "The app's bundle identifier.")
    var bundleIdentifier: String

    @Option(help: "The UDID of the device.")
    var device: String

    @Option(help: "\(DeveloperDiskImage.optionHelp)")
    var ddi: String?

    @Flag(help: "Print the app's standard output and error until it exits.")
    var console = false

    @Argument(parsing: .postTerminator, help: "Arguments for the app, after --.")
    var arguments: [String] = []

    func run() throws {
        try launch(bundleIdentifier, arguments: arguments, on: device, ddi: ddi, console: console)
    }
}

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop an app running on a device.",
        discussion: """
        Finds the app's processes, those whose executable is inside the path installation_proxy \
        gives for the bundle identifier, with the CoreDevice app service's listprocesses, and \
        sends each a signal with sendsignaltoprocess (docs/formats/remotexpc.md).
        """
    )

    @Argument(help: "The app's bundle identifier.")
    var bundleIdentifier: String

    @Option(help: "The UDID of the device.")
    var device: String

    @Option(help: "The signal: TERM (default), KILL, INT, or a number.")
    var signal: String = "TERM"

    func run() throws {
        let names: [String: Int32] = ["HUP": 1, "INT": 2, "QUIT": 3, "KILL": 9, "TERM": 15, "STOP": 17, "CONT": 19]
        let name = signal.uppercased().hasPrefix("SIG") ? String(signal.uppercased().dropFirst(3)) : signal.uppercased()
        guard let number = names[name] ?? Int32(signal) else { throw ValidationError("unknown signal: \(signal)") }
        let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
        let processes = try session.stop(bundleIdentifier: bundleIdentifier, signal: number)
        print(processes.isEmpty ? "\(bundleIdentifier) is not running"
              : "sent signal \(number) to \(bundleIdentifier) (process \(processes.map(String.init).joined(separator: ", ")))")
    }
}

/// Installs an IPA, or a signed .app checked as `nomac device check` does and packed as an IPA
/// (`Payload/<App>.app`).
func install(_ path: String, on device: String) throws {
    let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension + ".ipa"
    let ipa = try ipaBytes(path, device: device)
    let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
    // The device ends the running app while it replaces it, and that can reach a process launched
    // right after the install: the app is stopped first, as Xcode does before it installs.
    if let identifier = try? bundleIdentifier(of: path), let stopped = try? session.stopAndWait(bundleIdentifier: identifier), !stopped.isEmpty {
        print("stopped \(identifier) (process \(stopped.map(String.init).joined(separator: ", "))) before installing")
    }
    do {
        try session.install(ipa: ipa, name: name, progress: printStage)
    } catch var error as NomacError where error.message.hasPrefix("installation_proxy failed") {
        error.notes.append("'nomac device check <App.app> --device \(device)' reports what a device refuses in a signed app")
        throw error
    }
    print("installed \(name) on \(device)")
}

/// The bundle identifier of a .app, or of the app in an IPA's `Payload`.
func bundleIdentifier(of path: String) throws -> String? {
    let plist: Data?
    if FileSystem.isDirectory(path) {
        plist = FileSystem.contents(atPath: path + "/Info.plist")
    } else {
        let entry = try ZipArchive(path: path).entries.first { entry in
            let components = entry.name.split(separator: "/")
            return components.count == 3 && components[0] == "Payload" && components[1].hasSuffix(".app") && components[2] == "Info.plist"
        }
        plist = entry.map { Data($0.contents) }
    }
    guard let plist, let dictionary = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else { return nil }
    return dictionary["CFBundleIdentifier"] as? String
}

/// What `nomac device check` reports about the app of an IPA (`Payload/<App>.app`), from its Info.plist
/// and embedded profile: what an ad hoc export gets told without a device being asked.
func ipaProblems(_ path: String, device: String, at date: Date) throws -> [String] {
    func file(_ name: String, in entries: [ZipArchive.Entry]) -> [UInt8]? {
        entries.first { entry in
            let components = entry.name.split(separator: "/")
            return components.count == 3 && components[0] == "Payload" && components[1].hasSuffix(".app") && components[2] == name
        }.map { $0.contents }
    }
    let entries = try ZipArchive(path: path).entries
    guard let information = file("Info.plist", in: entries) else { return [] }
    guard let profile = file("embedded.mobileprovision", in: entries) else {
        return ["the app has no embedded.mobileprovision: an app signed ad hoc installs on no device; sign it with a development identity and profile"]
    }
    let bundleIdentifier = (try PropertyListSerialization.propertyList(from: Data(information), format: nil) as? [String: Any])?["CFBundleIdentifier"] as? String
    return InstallCheck.problems(profile: try ProvisioningProfile(bytes: profile, path: path), bundleIdentifier: bundleIdentifier, device: device, at: date)
}

func ipaBytes(_ path: String, device: String) throws -> [UInt8] {
    guard FileSystem.isDirectory(path) else {
        guard let bytes = FileSystem.contents(atPath: path) else { throw NomacError("cannot read the IPA", path: path) }
        let problems = try ipaProblems(path, device: device, at: Date())
        guard problems.isEmpty else { throw NomacError("the device would refuse the app", path: path, notes: problems) }
        return [UInt8](bytes)
    }
    for warning in try InstallCheck.warnings(app: path) {
        FileHandle.standardError.write(Data("\(path): warning: \(warning)\n".utf8))
    }
    let problems = try InstallCheck.problems(app: path, device: device, at: Date())
    guard problems.isEmpty else { throw NomacError("the device would refuse the app", path: path, notes: problems) }
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-install-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: work) }
    try DittoCopy.copy(path, to: work + "/Payload/Payload/" + (path as NSString).lastPathComponent)
    try DittoArchive.create(from: work + "/Payload", to: work + "/App.ipa")
    guard let bytes = FileSystem.contents(atPath: work + "/App.ipa") else { throw NomacError("cannot read the packed IPA", path: work + "/App.ipa") }
    return [UInt8](bytes)
}

/// Launches an installed app and prints the process the device reports, mounting the Developer
/// Disk Image first when it is not; with `console`, then the app's output until it exits.
func launch(_ bundleIdentifier: String, arguments: [String], on device: String, ddi: String?, console: Bool = false) throws {
    let session = try DeviceSession(usbmux: USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
    try mountDeveloperDiskImageIfNeeded(session, ddi: ddi)
    let (process, output) = try session.launch(bundleIdentifier: bundleIdentifier, arguments: arguments, console: console)
    print("launched \(bundleIdentifier) on \(device)\(process.map { " (process \($0))" } ?? "")")
    // The app's output goes straight to the file descriptor: nomac's own lines are flushed
    // first, or a pipe or file gets them late, or not at all when the command is stopped.
    fflush(nil)
    guard let output else { return }
    do {
        while let bytes = try output.read() { FileHandle.standardOutput.write(Data(bytes)) }
    } catch {
        // The connection failed rather than closed: say whether the app outlived it, asking the
        // device's process list in a new session.
        fflush(nil)
        let reason = (error as? NomacError)?.message ?? "\(error)"
        let session = try? DeviceSession(usbmux: USBMuxClient(address: USBMux.address(environment: ProcessInfo.processInfo.environment)), udid: device)
        guard let process, let processes = try? session?.processes() else {
            throw NomacError("the console of \(bundleIdentifier) closed; whether the app still runs is unknown", notes: [reason])
        }
        guard processes.contains(where: { $0.identifier == process }) else {
            throw NomacError("\(bundleIdentifier) exited (process \(process)) and its console closed", notes: [reason])
        }
        throw NomacError("the device closed \(bundleIdentifier)'s console; the app keeps running (process \(process))",
                         notes: [reason, "'nomac stop \(bundleIdentifier) --device \(device)' stops it"])
    }
    print("\(bundleIdentifier) closed its console")
    fflush(nil)
}

/// Mounts the Developer Disk Image (`ddi`, else the one `DeveloperDiskImage.locate` finds) when
/// the device has none mounted.
func mountDeveloperDiskImageIfNeeded(_ session: DeviceSession, ddi: String?) throws {
    guard try !session.developerDiskImageMounted() else { return }
    // Before a request to Apple and an upload, as pymobiledevice3 and ideviceimagemounter check.
    _ = try session.checkDeveloperMode()
    print("mounting the Developer Disk Image")
    try session.mount(try DeveloperDiskImage.locate(developerDiskImagePath(ddi)), progress: { print($0) })
}

/// `ddi`, else the image 'nomac sdk install' extracted from the selected Xcode, if any.
func developerDiskImagePath(_ ddi: String?) -> String? {
    if let ddi { return FileSystem.absolute(ddi) }
    guard let entry = try? SDKStore.default().resolve(build: nil), FileSystem.exists(entry.developerDiskImage + "/Restore/BuildManifest.plist") else { return nil }
    return entry.developerDiskImage
}

private func printStage(_ status: String, _ percent: Int64?) {
    print(percent.map { "\(status) (\($0)%)" } ?? status)
}
