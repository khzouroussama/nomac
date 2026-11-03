import ArgumentParser
import Foundation
import NomacCore
import NomacDevice

/// `nomac run`: archive a scheme, install its app on a device and launch it.
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Archive, install and launch on a device.",
        discussion: """
        xcodebuild has no such action; this is 'nomac archive' into a temporary archive, then \
        'nomac install' of the archived .app (checked as 'nomac device check' does) and \
        'nomac launch' of its bundle identifier. Before archiving it checks what 'nomac device \
        status' does: usbmuxd lists the device, this host is paired with it and Developer Mode is \
        on; unless --no-launch, it mounts the Developer Disk Image when it is not ('nomac device \
        mount'). To install on a device the archive must be \
        signed for it: pass --keychain and --provisioning-profiles with CODE_SIGN_STYLE=Manual, \
        CODE_SIGN_IDENTITY, DEVELOPMENT_TEAM and PROVISIONING_PROFILE_SPECIFIER.

        Example:
          nomac run -project App.xcodeproj -scheme App -destination generic/platform=iOS \\
              --device <UDID> --keychain identity.pem --provisioning-profiles profiles \\
              CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Development" \\
              DEVELOPMENT_TEAM=<team> "PROVISIONING_PROFILE_SPECIFIER=<profile name>"
        """
    )

    @OptionGroup var options: BuildOptions

    @Option(help: "The UDID of the device.")
    var device: String

    @Flag(help: "Install the app without launching it, which needs no Developer Disk Image.")
    var noLaunch = false

    @Option(help: "\(DeveloperDiskImage.optionHelp)")
    var ddi: String?

    @Flag(help: "Print the app's standard output and error until it exits.")
    var console = false

    func run() async throws {
        guard options.scheme != nil else { throw ValidationError("running needs a scheme (-scheme)") }
        try checkDevice()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-run-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: work) }
        let archive = work + "/Run.xcarchive"
        try await options.run(archivePath: archive)
        let applications = archive + "/Products/Applications"
        guard let app = try FileSystem.sortedContents(of: applications).first(where: { $0.hasSuffix(".app") }) else {
            throw NomacError("the archive holds no application", path: applications)
        }
        let path = applications + "/" + app
        guard let bundleIdentifier = try PropertyLists.readDictionary(at: path + "/Info.plist")["CFBundleIdentifier"] as? String else {
            throw NomacError("the app's Info.plist has no CFBundleIdentifier", path: path)
        }
        try install(path, on: device)
        if !noLaunch { try launch(bundleIdentifier, arguments: [], on: device, ddi: ddi, console: console) }
    }

    private func checkDevice() throws {
        let usbmux = USBMuxClient(address: try USBMux.address(environment: ProcessInfo.processInfo.environment))
        _ = try usbmux.device(udid: device)
        let session = try DeviceSession(usbmux: usbmux, udid: device)
        _ = try session.checkDeveloperMode()
        if !noLaunch { try mountDeveloperDiskImageIfNeeded(session, ddi: ddi) }
    }
}
