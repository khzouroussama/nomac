import Foundation

/// The owner, group and mode an install build (`xcodebuild archive`) sets on its products, off
/// macOS (docs/formats/build.md "Owner, group and mode").
///
/// Swift Build runs `$(CHOWN) -RH $(INSTALL_OWNER):$(INSTALL_GROUP) <product>` and
/// `$(CHMOD) -RH $(INSTALL_MODE_FLAG) <product>` (Xcode 27.0's archives of rn-bare and of
/// `signing_experiments.py`'s app: `/usr/sbin/chown -RH <user>:staff`,
/// `/bin/chmod -RH u+w,go-w,a+rX`). The owner and group default to `$(USER)` and `$(GROUP)`, the
/// building user's, so on the Mac the files keep their owner; off macOS the build takes them from
/// the reference Mac (``HostIdentity``), a user and group the machine lacks, and GNU chmod has no
/// `-H`. So `nomac toolchain install` writes these two scripts, and builds off macOS name them in
/// `CHOWN` and `CHMOD`.
public enum InstallAttributes {
    /// Where the scripts are, in the developer directory.
    public static let chownPath = "usr/libexec/nomac/chown"
    public static let chmodPath = "usr/libexec/nomac/chmod"

    /// Leaves out a user or group the machine does not have, the reference Mac's building user's,
    /// which already owns the files, and changes nothing when neither is left.
    static let chown = """
        #!/bin/sh
        # Written by 'nomac toolchain install' (docs/formats/build.md "Owner, group and mode").
        flags=
        while [ $# -gt 0 ]; do
          case $1 in -*) flags="$flags $1"; shift ;; *) break ;; esac
        done
        spec=$1
        shift
        owner=${spec%%:*}
        group=
        case $spec in *:*) group=${spec#*:} ;; esac
        if [ -n "$owner" ] && ! id -u "$owner" >/dev/null 2>&1; then owner=; fi
        if [ -n "$group" ] && ! getent group "$group" >/dev/null 2>&1; then group=; fi
        [ -n "$owner$group" ] || exit 0
        exec /bin/chown $flags "$owner${group:+:$group}" "$@"

        """

    /// BSD chmod's `-RH` follows the symbolic links named on the command line, as GNU chmod's `-R`
    /// does, which has no `-H`.
    static let chmod = """
        #!/bin/sh
        # Written by 'nomac toolchain install' (docs/formats/build.md "Owner, group and mode").
        if [ "$1" = -RH ]; then
          shift
          set -- -R "$@"
        fi
        exec /bin/chmod "$@"

        """

    /// The settings a build off macOS synthesizes, below the command line's.
    public static func overrides(developerDirectory: String) -> [String: String] {
        ["CHOWN": developerDirectory + "/" + chownPath, "CHMOD": developerDirectory + "/" + chmodPath]
    }
}
