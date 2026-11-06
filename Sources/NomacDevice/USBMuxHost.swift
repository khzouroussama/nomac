import Foundation
import NomacCore

/// What a machine shows about usbmuxd, for saying what to do when it cannot be reached or lists no
/// device. The states and packages are observed with libimobiledevice's usbmuxd on nine Linux
/// distribution releases, with no device (`first_run_experiments.py`, docs/formats/usbmux.md "On Linux").
public struct USBMuxHost: Sendable {
    public var isLinux: Bool
    public var exists: @Sendable (String) -> Bool
    public var isWritable: @Sendable (String) -> Bool
    /// The usbmuxd executable, when installed.
    public var daemon: @Sendable () -> String?
    /// The products of the Apple devices the kernel sees on USB that usbmuxd serves.
    public var appleDevices: @Sendable () -> [String]

    public static var current: USBMuxHost {
        #if os(Linux)
        let isLinux = true
        #else
        let isLinux = false
        #endif
        return USBMuxHost(isLinux: isLinux, exists: { FileSystem.exists($0) }, isWritable: { access($0, W_OK) == 0 }, daemon: { locateDaemon() },
                          appleDevices: { appleDevices(sysfs: "/sys/bus/usb/devices") })
    }

    /// Distributions install usbmuxd in `sbin` folders a user's PATH may not hold.
    static func locateDaemon(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        Subprocess.locate("usbmuxd", environment: environment)
            ?? ["/usr/sbin/usbmuxd", "/usr/bin/usbmuxd", "/sbin/usbmuxd", "/usr/local/sbin/usbmuxd"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The USB devices under `sysfs` that usbmuxd's udev rule takes: vendor 05ac, product 129x, 12ax
    /// or 1901 to 1905.
    static func appleDevices(sysfs: String) -> [String] {
        func value(_ folder: String, _ name: String) -> String? {
            FileSystem.contents(atPath: "\(sysfs)/\(folder)/\(name)").map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let folders = (try? FileSystem.sortedContents(of: sysfs)) ?? []
        return folders.compactMap { folder in
            guard value(folder, "idVendor") == "05ac", let product = value(folder, "idProduct").flatMap({ Int($0, radix: 16) }),
                  (0x1290...0x12af).contains(product) || (0x1901...0x1905).contains(product) else { return nil }
            return value(folder, "product") ?? "Apple device"
        }
    }

    static let installNotes = [
        "usbmuxd is not installed; nomac reaches a device through it. Install it:",
        "  Debian, Ubuntu: sudo apt-get install -y usbmuxd",
        "  Fedora: sudo dnf install -y usbmuxd",
        "  Arch: sudo pacman -S usbmuxd",
        "  openSUSE: sudo zypper install usbmuxd",
    ]

    /// What to do when nothing answers at `address`.
    static func unreachableNotes(address: StreamSocket.Address, host: USBMuxHost) -> [String] {
        guard case .unix(let path) = address else {
            return ["nothing answers at USBMUXD_SOCKET_ADDRESS: start the forward of the Mac's usbmuxd (docs/formats/usbmux.md)"]
        }
        guard host.isLinux else { return ["usbmuxd does not answer at \(path)"] }
        guard host.exists(path) else {
            guard let daemon = host.daemon() else { return installNotes }
            return [
                "usbmuxd (\(daemon)) is installed but not running: it starts when an iPhone is plugged in",
                "plug the iPhone in by USB and unlock it; if this message stays, 'sudo systemctl start usbmuxd', or 'sudo usbmuxd' without systemd",
            ]
        }
        guard host.isWritable(path) else {
            return ["this user may not write to \(path): usbmuxd makes it writable by everyone when it starts, so restart it: 'sudo systemctl restart usbmuxd'"]
        }
        return ["\(path) exists but nothing answers: usbmuxd stopped without removing it. 'sudo systemctl restart usbmuxd', or without systemd 'sudo rm \(path)' and 'sudo usbmuxd'"]
    }

    /// What to do when usbmuxd lists `seen` and not the device wanted.
    static func noDeviceNotes(seen: [String], address: StreamSocket.Address, host: USBMuxHost) -> [String] {
        guard seen.isEmpty else { return ["usbmuxd sees \(seen.joined(separator: ", ")); use one of these UDIDs, or plug the device in by USB and unlock it"] }
        guard host.isLinux, case .unix = address else { return ["usbmuxd sees no device at all: connect the device by USB and unlock it"] }
        let apple = host.appleDevices()
        guard apple.isEmpty else {
            return ["the kernel sees \(apple.joined(separator: ", ")) on USB but usbmuxd lists nothing: unlock it; if that changes nothing, 'sudo systemctl restart usbmuxd', and 'journalctl -u usbmuxd' says why"]
        }
        return ["the kernel sees no iPhone on USB: unlock it and check the cable (some only charge) and the port"]
    }
}
