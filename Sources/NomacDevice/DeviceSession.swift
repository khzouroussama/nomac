import Foundation
import NomacCore
import NomacSigning

/// A lockdownd session with a device through usbmuxd, as the host of usbmuxd's pair record,
/// and the services it starts (docs/formats/lockdown.md).
public final class DeviceSession {
    private let usbmux: USBMuxClient
    private let device: USBMux.Device
    private let pairRecord: PairRecord
    private let lockdown: LockdownClient

    public init(usbmux: USBMuxClient, udid: String) throws {
        self.usbmux = usbmux
        device = try usbmux.device(udid: udid)
        pairRecord = try usbmux.pairRecord(udid: device.serialNumber)
        lockdown = LockdownClient(stream: try usbmux.connect(deviceID: device.deviceID, port: Lockdown.port))
        try lockdown.startSession(hostID: pairRecord.hostID, systemBUID: pairRecord.systemBUID) { [pairRecord] stream in
            try TLSStream(over: stream, certificate: pairRecord.hostCertificate, privateKey: pairRecord.hostPrivateKey)
        }
    }

    /// A connection to the service `name`, started by lockdownd without the pair record's escrow
    /// bag: with it, iOS 27.0.1 started AFC on a port that refused usbmuxd's connection
    /// (pymobiledevice3 sends it only for backups).
    public func service(_ name: String) throws -> ByteStream {
        let service = try lockdown.startService(name)
        let socket = try usbmux.connect(deviceID: device.deviceID, port: service.port)
        guard service.usesTLS else { return socket }
        return try TLSStream(over: socket, certificate: pairRecord.hostCertificate, privateKey: pairRecord.hostPrivateKey)
    }

    /// Uploads the IPA to the staging folder, installs it and removes the upload.
    public func install(ipa: [UInt8], name: String, progress: (String, Int64?) -> Void) throws {
        let afc = AFCClient(stream: try service(AFC.serviceName))
        let path = InstallationProxy.stagingFolder + "/" + name
        try afc.makeDirectory(InstallationProxy.stagingFolder)
        try afc.upload(ipa, to: path)
        defer { try? afc.remove(path) }
        try InstallationProxyClient(stream: try service(InstallationProxy.serviceName))
            .run(InstallationProxy.install(packagePath: path), progress: progress)
    }

    public func uninstall(bundleIdentifier: String, progress: (String, Int64?) -> Void) throws {
        try InstallationProxyClient(stream: try service(InstallationProxy.serviceName))
            .run(InstallationProxy.uninstall(bundleIdentifier: bundleIdentifier), progress: progress)
    }

    /// A value lockdownd gives in the session (`ProductVersion`, or Developer Mode's
    /// `DeveloperModeStatus` in the `com.apple.security.mac.amfi` domain).
    public func value(domain: String? = nil, key: String) throws -> PropertyListValue {
        try lockdown.value(domain: domain, key: key)
    }

    /// Developer Mode as the `com.apple.security.mac.amfi` domain reports it: true, or nil when
    /// the device does not report it (before iOS 16); off is an error saying how to turn it on.
    public func checkDeveloperMode() throws -> Bool? {
        let status: PropertyListValue
        do {
            status = try value(domain: "com.apple.security.mac.amfi", key: "DeveloperModeStatus")
        } catch let error as NomacError where error.message.hasSuffix(": MissingValue") {
            return nil
        }
        switch status {
        case .boolean(true): return true
        case .boolean(false): throw NomacError("Developer Mode is off", notes: Self.developerModeNotes(udid: device.serialNumber))
        default: return nil
        }
    }

    /// Asks the device to show Developer Mode in Settings, where it may be hidden until a developer
    /// tool has connected: action 0 of the AMFI service (libimobiledevice's `idevicedevmodectl
    /// reveal`, pymobiledevice3's `reveal_developer_mode_option_in_ui`). Turning it on stays the
    /// user's, on the device: with a passcode set, AMFI refuses to do it from the host.
    public func revealDeveloperMode() throws {
        let amfi = try service(Self.amfiServiceName)
        try PropertyListMessages.send(["action": .integer(0)], on: amfi)
        let reply = try PropertyListMessages.receive(from: amfi, source: "AMFI")
        if case .string(let error)? = reply["Error"] { throw NomacError("the device refused to show Developer Mode: \(error)") }
        guard reply["success"] != nil, reply["success"] != .boolean(false) else { throw NomacError("AMFI did not say it showed Developer Mode") }
    }

    public static let amfiServiceName = "com.apple.amfi.lockdown"

    public static func developerModeNotes(udid: String) -> [String] {
        [
            "on the device: Settings > Privacy & Security > Developer Mode, turn it on; it restarts, then confirm Turn On after unlocking it",
            "if Settings does not list it, 'nomac device developer-mode --device \(udid)' makes it appear",
        ]
    }

    /// Whether the personalized Developer Disk Image, which the app service needs, is mounted.
    public func developerDiskImageMounted() throws -> Bool {
        try mountedImageTypes().contains("Personalized")
    }

    /// The types of the disk images mounted on the device.
    public func mountedImageTypes() throws -> [String] {
        try MobileImageMounter.mountedImageTypes(on: try service(MobileImageMounter.serviceName))
    }

    public func personalizationIdentifiers() throws -> [String: PropertyListValue] {
        try MobileImageMounter.personalizationIdentifiers(on: try service(MobileImageMounter.serviceName))
    }

    /// The ticket that personalizes the Developer Disk Image of `image` for this device: the one
    /// the device stores for it, else one from Apple's TSS server for the device's identifiers and
    /// a nonce it gives (ADR 0403).
    public func personalize(_ image: DeveloperDiskImage, progress: (String) -> Void) throws -> [UInt8] {
        let identifiers = try personalizationIdentifiers()
        let identity = try Personalization.buildIdentity(manifest: image.manifest, identifiers: identifiers)
        let files = try image.files(identity: identity)
        if let stored = try MobileImageMounter.storedManifest(forImage: files.image, on: try service(MobileImageMounter.serviceName)) {
            progress("the device stores a personalization for this image")
            return stored
        }
        progress("personalizing the image with Apple's TSS server (\(Personalization.server.host ?? ""))")
        let nonce = try MobileImageMounter.nonce(on: try service(MobileImageMounter.serviceName))
        return try Personalization.fetchTicket(Personalization.request(identity: identity, identifiers: identifiers, nonce: nonce))
    }

    /// Personalizes, uploads and mounts the Developer Disk Image of `image`.
    public func mount(_ image: DeveloperDiskImage, progress: (String) -> Void) throws {
        let identity = try Personalization.buildIdentity(manifest: image.manifest, identifiers: try personalizationIdentifiers())
        let files = try image.files(identity: identity)
        let ticket = try personalize(image, progress: progress)
        let mounter = try service(MobileImageMounter.serviceName)
        progress("uploading \(files.image.count) bytes")
        try MobileImageMounter.upload(image: files.image, ticket: ticket, on: mounter)
        progress("mounting")
        try MobileImageMounter.mount(ticket: ticket, trustCache: files.trustCache, on: mounter)
    }

    /// Unmounts the Developer Disk Image, wherever `CopyDevices` says it is mounted.
    public func unmountDeveloperDiskImage() throws {
        for entry in try mountedImages() where entry["DiskImageType"] == .string("Personalized") {
            guard case .string(let path)? = entry["MountPath"] else { continue }
            try MobileImageMounter.unmount(mountPath: path, on: try service(MobileImageMounter.serviceName))
        }
    }

    /// The crash reports on the device, after crashreportmover has moved the latest ones, and
    /// the AFC connection that reads them.
    public func crashReports() throws -> (reports: [CrashReports.Report], afc: AFCClient) {
        try CrashReports.waitForMover(try service(CrashReports.moverServiceName))
        let afc = AFCClient(stream: try service(CrashReports.copyServiceName))
        return (try CrashReports.reports(afc: afc), afc)
    }

    /// The entries of the disk images mounted on the device.
    public func mountedImages() throws -> [[String: PropertyListValue]] {
        try MobileImageMounter.entries(on: try service(MobileImageMounter.serviceName))
    }

    /// The manifest the device stores for the personalized image `image`, if any.
    public func storedManifest(forImage image: [UInt8]) throws -> [UInt8]? {
        try MobileImageMounter.storedManifest(forImage: image, on: try service(MobileImageMounter.serviceName))
    }

    /// TCP in the CoreDevice tunnel and RemoteServiceDiscovery's ports, by service name
    /// (docs/formats/remotexpc.md).
    public func openCoreDevice() throws -> (network: TunnelNetwork, ports: [String: UInt16]) {
        let tunnel = try service(CoreDeviceTunnel.serviceName)
        let parameters = try CoreDeviceTunnel.handshake(on: tunnel)
        let network = try TunnelNetwork(tunnel: tunnel, parameters: parameters)
        let discovery = try RemoteXPCConnection(stream: try network.connect(port: parameters.serverRSDPort))
        return (network, try RemoteServiceDiscovery.servicePorts(try discovery.receive().payload ?? .null))
    }

    /// Launches the installed app with the app service. Returns the process identifier the device
    /// reports.
    public static let developerDiskImageNote =
        "its Developer Disk Image is not mounted: 'nomac device mount' mounts it"
    static let justMountedNote = "its Developer Disk Image is mounted: if that just happened, run the command again in a few seconds"

    /// Sends `signal` to every process of the installed app (its executable inside the app's
    /// path), through the app service's `listprocesses` and `sendsignaltoprocess`; returns the
    /// processes signaled.
    public func stop(bundleIdentifier: String, signal: Int32 = 15) throws -> [Int64] {
        guard let path = try InstallationProxyClient(stream: try service(InstallationProxy.serviceName)).path(of: bundleIdentifier) else {
            throw NomacError("\(bundleIdentifier) is not installed")
        }
        let (network, port) = try appService()
        let listed = try CoreDeviceService.invoke(AppService.listProcessesFeature, input: .dictionary([]),
                                                  on: try RemoteXPCConnection(stream: try network.connect(port: port)))
        let processes = AppService.processes(listed).filter { Self.within($0.executable, path) }.map(\.identifier)
        for process in processes {
            _ = try CoreDeviceService.invoke(AppService.sendSignalFeature, input: AppService.signalInput(process: process, signal: signal),
                                             on: try RemoteXPCConnection(stream: try network.connect(port: port)))
        }
        return processes
    }

    /// Stops the app's running processes before it is replaced: SIGTERM, then SIGKILL to those
    /// still running after `timeout` seconds; returns the processes it stopped.
    public func stopAndWait(bundleIdentifier: String, timeout: TimeInterval = 5) throws -> [Int64] {
        let stopped = try stop(bundleIdentifier: bundleIdentifier, signal: 15)
        guard !stopped.isEmpty else { return [] }
        func remaining() throws -> [Int64] {
            let running = Set(try processes().map(\.identifier))
            return stopped.filter(running.contains)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try remaining().isEmpty { return stopped }
            Thread.sleep(forTimeInterval: 0.5)
        }
        let (network, port) = try appService()
        for process in try remaining() {
            _ = try CoreDeviceService.invoke(AppService.sendSignalFeature, input: AppService.signalInput(process: process, signal: 9),
                                             on: try RemoteXPCConnection(stream: try network.connect(port: port)))
        }
        return stopped
    }

    /// The device's processes, from the app service's `listprocesses`.
    public func processes() throws -> [(identifier: Int64, executable: String)] {
        let (network, port) = try appService()
        return AppService.processes(try CoreDeviceService.invoke(AppService.listProcessesFeature, input: .dictionary([]),
                                                                 on: try RemoteXPCConnection(stream: try network.connect(port: port))))
    }

    /// The CoreDevice tunnel and the app service's port in it.
    private func appService() throws -> (network: TunnelNetwork, port: UInt16) {
        let (network, ports) = try openCoreDevice()
        guard let port = ports[AppService.serviceName] else {
            let mounted = (try? developerDiskImageMounted()) ?? false
            throw NomacError("the device lists no \(AppService.serviceName)", notes: [mounted ? DeviceSession.justMountedNote : DeviceSession.developerDiskImageNote])
        }
        return (network, port)
    }

    /// Whether `executable` is inside the app at `path`, `/private/var` and `/var` alike.
    static func within(_ executable: String, _ path: String) -> Bool {
        func standard(_ text: String) -> String { text.hasPrefix("/private/var/") ? String(text.dropFirst("/private".count)) : text }
        let folder = standard(path).hasSuffix("/") ? standard(path) : standard(path) + "/"
        return standard(executable).hasPrefix(folder)
    }

    /// Launches the app; with `console`, also returns the connection that carries its standard
    /// input and output.
    public func launch(bundleIdentifier: String, arguments: [String], console: Bool = false) throws -> (process: Int64?, console: ProcessConsole?) {
        let (network, ports) = try openCoreDevice()
        guard let port = ports[AppService.serviceName] else {
            let mounted = (try? developerDiskImageMounted()) ?? false
            throw NomacError("the device lists no \(AppService.serviceName)", notes: [mounted ? DeviceSession.justMountedNote : DeviceSession.developerDiskImageNote])
        }
        var standardIO: ProcessConsole?
        if console {
            guard let stdioPort = ports[AppService.standardIOServiceName] else { throw NomacError("the device lists no \(AppService.standardIOServiceName)") }
            let connection = try network.connect(port: stdioPort)
            standardIO = ProcessConsole(network: network, connection: connection, identifier: try connection.read(16))
        }
        let appService = try RemoteXPCConnection(stream: try network.connect(port: port))
        let output = try CoreDeviceService.invoke(AppService.launchFeature,
                                                  input: AppService.launchInput(bundleIdentifier: bundleIdentifier, arguments: arguments,
                                                                                standardIO: standardIO?.identifier),
                                                  on: appService)
        return (AppService.processIdentifier(output), standardIO)
    }
}

/// A launched process's standard input and output, over the tunnel it keeps open.
public final class ProcessConsole {
    private let network: TunnelNetwork
    private let connection: TunnelTCPConnection
    let identifier: [UInt8]

    init(network: TunnelNetwork, connection: TunnelTCPConnection, identifier: [UInt8]) {
        self.network = network
        self.connection = connection
        self.identifier = identifier
    }

    /// The output that arrived, waiting for some; nil once the process closed it.
    public func read() throws -> [UInt8]? { try connection.readAvailable() }
}
