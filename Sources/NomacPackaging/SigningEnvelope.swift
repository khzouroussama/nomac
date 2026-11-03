import NomacEnvelope

/// The `signing:` features whose signing, archiving and export nomac reproduces, with the
/// `.github/scripts/signing_experiments.py` experiments that compared them with Xcode 27.0
/// (`compare`, `compare-export`, `compare-archive`, `compare-symbols`), and the ones it does not
/// yet (docs/formats/code-signature.md, ipa.md, xcarchive.md).
public enum SigningEnvelope {
    public static let envelope = Envelope(domain: "signing", entries: verified + unverified)

    static let verified: [EnvelopeEntry] = [
        .verified("signing:product=com.apple.product-type.application", "signing-experiments:adhoc", "signing-experiments:archive-products-apps"),
        .verified("signing:product=com.apple.product-type.app-extension", "signing-experiments:adhoc", "signing-experiments:nested"),
        .verified("signing:product=com.apple.product-type.framework", "signing-experiments:adhoc", "signing-experiments:archive-products-framework"),
        .verified("signing:product=com.apple.product-type.bundle", "signing-experiments:archive-products-app"),
        .verified("signing:product=com.apple.product-type.library.static", "signing-experiments:archive-products-library"),
        .verified("signing:product=com.apple.product-type.application@watchos", "signing-experiments:watch", "signing-experiments:watch-appclip-script"),
        .verified("signing:allowed=NO", "signing-experiments:appclip-script"),
        .verified("signing:identity=ad-hoc", "signing-experiments:adhoc"),
        .verified("signing:style=manual", "signing-experiments:adhoc"),
        .verified("signing:embed=frameworks", "signing-experiments:adhoc", "signing-experiments:nested"),
        .verified("signing:embed=plugins", "signing-experiments:adhoc", "signing-experiments:nested"),
        .verified("signing:embed=watch", "signing-experiments:watch"),
        .verified("signing:embed=app-clips", "signing-experiments:appclip-script"),
        .verified("signing:product=com.apple.product-type.extensionkit-extension", "signing-experiments:archive-extensionkit"),
        .verified("signing:embed=extensionkit", "signing-experiments:archive-extensionkit"),
        .verified("signing:product=com.apple.product-type.xpc-service", "signing-experiments:archive-xpc"),
        .verified("signing:embed=xpc-services", "signing-experiments:archive-xpc"),
        .verified("signing:pages=4k", "signing-experiments:span"),
        .verified("signing:code-directory=sha1", "signing-experiments:watch"),
        .verified("signing:dsym=none", "signing-experiments:archive-nodsym"),
        .verified("signing:on-demand-resources", "signing-experiments:odr", "signing-experiments:odr-three"),
    ]

    static let unverified: [EnvelopeEntry] = [
        .unverified("signing:product=com.apple.product-type.tool",
                    "Swift Build signs a tool with the entitlements the IDE gives it (application-identifier \"\", keychain-access-groups [\"\"]), which nomac's build does not answer yet"),
        .unverified("signing:product=com.apple.product-type.application.on-demand-install-capable",
                    "an App Clip's archive needs a provisioning profile", backlog: "B-302"),
        .unverified("signing:product=com.apple.product-type.library.dynamic", "dynamic library targets are not observed"),
        .unverified("signing:identity=apple-development", "Apple Development signing is observed privately for codesign and debugging exports; the build's provisioning inputs on Linux are not answered yet", backlog: "B-302"),
        .unverified("signing:identity=iphone-developer", "development identities need the build's provisioning inputs", backlog: "B-302"),
        .unverified("signing:identity=default", "Xcode's default identity for devices is Apple Development", backlog: "B-302"),
        .unverified("signing:identity=distribution", "distribution identities are not observed", backlog: "B-302"),
        .unverified("signing:style=automatic", "automatic signing asks Apple's services for profiles", backlog: "B-302"),
        .unverified("signing:style=default", "a target without CODE_SIGN_STYLE signs automatically", backlog: "B-302"),
        .unverified("signing:entitlements", "an entitlements file needs a provisioning profile, or ad hoc an observation", backlog: "B-302"),
        .unverified("signing:profile", "provisioning profiles in builds are not answered yet", backlog: "B-302"),
        .unverified("signing:embed=frameworks-without-code-sign-on-copy", "frameworks embedded without code signing on copy are not observed"),
    ]
}
