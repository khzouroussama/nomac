import NomacEnvelope

/// The `assets:` features nomac's actool reproduces byte for byte, with the
/// `.github/scripts/assets_experiments.py` experiments that compared them with Xcode 27.0's
/// actool, and the ones it does not reproduce yet (docs/formats/asset-catalog.md).
public enum AssetsEnvelope {
    static let colorSpaces = ["srgb", "display-p3", "extended-srgb", "extended-linear-srgb", "gray-gamma-22", "extended-gray"]
    static let colorIdioms = ["universal", "iphone", "ipad", "mac", "tv", "watch"]
    static let imageEntries = ["universal-2x", "universal-3x", "iphone-1x", "iphone-2x", "iphone-3x", "ipad-1x", "ipad-2x"]

    public static let envelope = Envelope(domain: "assets", entries: verified + unverified)

    static let verified: [EnvelopeEntry] = [
        .verified("assets:catalog", "assets-experiments:colors"),
        .verified("assets:folder=group", "assets-experiments:colors"),
        .verified("assets:folder=namespace", "assets-experiments:colors"),
        .verified("assets:name=non-ascii", "assets-experiments:identifiers"),
        .verified("assets:identifiers=collision", "assets-experiments:collisions"),
        .verified("assets:colorset", "assets-experiments:colors"),
        .verified("assets:colorset.color=none", "assets-experiments:colors"),
        .verified("assets:colorset.component=decimal", "assets-experiments:colors"),
        .verified("assets:colorset.component=integer", "assets-experiments:colors"),
        .verified("assets:colorset.component=hexadecimal", "assets-experiments:colors"),
        .verified("assets:colorset.appearance=luminosity:dark", "assets-experiments:colors", "assets-experiments:appearance-order"),
        .verified("assets:colorset.appearance=luminosity:light", "assets-experiments:colors", "assets-experiments:appearance-order"),
        .verified("assets:colorset.appearance=contrast:high", "assets-experiments:colors", "assets-experiments:appearance-order"),
        .verified("assets:colorset.display-gamut=sRGB", "assets-experiments:colors"),
        .verified("assets:colorset.display-gamut=display-P3", "assets-experiments:colors"),
        .verified("assets:dataset", "assets-experiments:data"),
        .verified("assets:appiconset", "assets-experiments:app-icons"),
        .verified("assets:appiconset.images=none", "assets-experiments:app-icons"),
        .verified("assets:appiconset.images=multi-size", "assets-experiments:app-icons"),
        .verified("assets:appiconset.images=single-size", "assets-experiments:single-size-icons"),
        .verified("assets:launchimage", "assets-experiments:app-icons"),
        .verified("assets:launchimage.images=none", "assets-experiments:app-icons"),
        .verified("assets:spriteatlas", "assets-experiments:sprites"),
        .verified("assets:stickersiconset", "assets-experiments:stickers"),
        .verified("assets:stickerpack", "assets-experiments:stickers"),
        .verified("assets:stickerpack.key=stickers", "assets-experiments:stickers"),
        .verified("assets:stickerpack.properties.grid-size", "assets-experiments:stickers"),
        .verified("assets:dataset.idiom=universal", "assets-experiments:data"),
        .verified("assets:dataset.type=explicit", "assets-experiments:data"),
        .verified("assets:dataset.type=from-extension", "assets-experiments:data"),
        .verified("assets:imageset", "assets-experiments:images", "assets-experiments:packing"),
        .verified("assets:imageset.image=none", "assets-experiments:images"),
        .verified("assets:imageset.image=universal-1x", "assets-experiments:images", "assets-experiments:packing"),
        .verified("assets:imageset.images=several", "assets-experiments:images"),
        .verified("assets:colorset.color=reference", "assets-experiments:colors"),
        .verified("assets:imageset.file=png", "assets-experiments:images", "assets-experiments:packing"),
        .verified("assets:imageset.file=jpg", "assets-experiments:vector-images"),
        .verified("assets:imageset.file=jpeg", "assets-experiments:vector-images"),
        .verified("assets:imageset.file=svg", "assets-experiments:vector-images"),
        .verified("assets:imageset.file=heic", "assets-experiments:heic"),
        .verified("assets:imageset.properties.preserves-vector-representation", "assets-experiments:vector-images"),
        .verified("assets:imageset.pixels=gray", "assets-experiments:images"),
        .verified("assets:imageset.contents=missing", "assets-experiments:images"),
        .verified("assets:imageset.properties.template-rendering-intent", "assets-experiments:images"),
        .verified("assets:symbolset", "assets-experiments:symbol-sets"),
        .verified("assets:symbolset.template=glyphs", "assets-experiments:symbol-sets"),
        .verified("assets:symbolset.properties.symbol-rendering-intent", "assets-experiments:symbol-sets"),
        .verified("assets:solidimagestack", "assets-experiments:images"),
        .verified("assets:imageset.png=color-profile", "assets-experiments:profiles"),
    ]
        + imageEntries.map { .verified("assets:imageset.image=\($0)", "assets-experiments:images") }
        + colorSpaces.map { .verified("assets:colorset.color-space=\($0)", "assets-experiments:colors") }
        + colorIdioms.map { .verified("assets:colorset.idiom=\($0)", "assets-experiments:colors") }

    static let unverified: [EnvelopeEntry] = [
        .unverified("assets:imageset.file=missing", "image sets naming a missing file are not observed", backlog: "B-200"),
        .unverified("assets:imageset.png=unsupported", "16-bit PNGs and gammas other than 1/2.2 are not read yet", backlog: "B-209"),
        .unverified("assets:imageset.png=color-profile-other", "color profiles other than matrix/TRC ones are not read yet", backlog: "B-213"),
        .unverified("assets:appiconset.images=other", "other platforms' icon sizes are not observed", backlog: "B-211"),
        .unverified("assets:launchimage.images=files", "launch images are not written yet", backlog: "B-202"),
        .unverified("assets:symbolset.template=layer-tree", "template 6's layer trees are not written yet", backlog: "B-202"),
        .unverified("assets:colorset.color=reference-other", "system colors actool does not know, iOS-only ones for universal, other platforms and appearances", backlog: "B-203"),
        .unverified("assets:colorset.component=hexadecimal-long", "hexadecimal components of more than two digits are not observed", backlog: "B-203"),
        .unverified("assets:colorset.color-space=none", "colors without a color space are not observed", backlog: "B-203"),
        .unverified("assets:dataset.type=unknown-extension", "dynamic type identifiers are not known", backlog: "B-208"),
        .unverified("assets:names=same-name-several-types", "one observation only", backlog: "B-208"),
        .unverified("assets:identifiers=more-than-126", "BITMAPKEYS leaves split beyond 126 entries", backlog: "B-201"),
    ]
}
