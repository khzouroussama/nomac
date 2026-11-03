import NomacProject

extension LoaderEnvelope {
    /// Features the coverage survey ranks first (BACKLOG B-081), each compared with Xcode in
    /// envelope-experiments (docs/formats/project-file.md).
    static let survey: [EnvelopeEntry] = objectVersions + [
        // GUIDs hash object IDs as written, whatever their shape (docs/formats/pif.md "Identifiers").
        .verified("pbxproj:object-id=not-hexadecimal", "envelope-experiments:object-ids"),
        // Files, folders and missing projects a workspace lists leave no trace in the outputs.
        .verified("workspace:FileRef=other", "envelope-experiments:workspace-refs"),
        .verified("workspace:FileRef=project-missing", "envelope-experiments:workspace-refs"),
        // Missing base xcconfigs and included files are skipped silently.
        .verified("xcconfig:file=missing", "envelope-experiments:xcconfig-missing", "envelope-experiments:workspace-refs"),
        .verified("xcconfig:include=missing", "envelope-experiments:xcconfig-missing"),
        // An untyped reference gets the type its extension names, or its contents give.
        .verified("pbxproj:PBXFileReference.fileType=none", "envelope-experiments:file-type-none"),
        .verified("pbxproj:PBXFileReference.fileType=none-by-contents", "envelope-experiments:file-type-none"),
        // nomac resolves remote packages without a Package.resolved and writes it as Xcode does.
        .verified("package:resolved=missing", "envelope-experiments:package-resolved"),
        // Variant group children outside a `.lproj` folder are lifted out; missing regions are added.
        .verified("pbxproj:PBXVariantGroup.children=outside-lproj", "envelope-experiments:variant-groups"),
        .verified("pbxproj:PBXVariantGroup.children=region-not-in-knownRegions", "envelope-experiments:variant-groups"),
    ] + ["LaunchAction/AdditionalOptions", "TestAction/AdditionalOptions", "AdditionalOptions/AdditionalOption", "AdditionalOption@key",
         "AdditionalOption@value", "AdditionalOption@isEnabled", "AdditionalOption@isEnabled=YES", "AdditionalOption@isEnabled=NO"]
        .map { .verified("scheme:" + $0, "envelope-experiments:additional-options") }

    /// Xcode's outputs do not depend on the version it reads, older formats holding newer objects
    /// included (envelope-experiments `object-versions-newest`), and nomac ignores it; Xcode and
    /// nomac refuse the others alike, from 41 to 111 (``readableObjectVersions``).
    static let objectVersions: [EnvelopeEntry] = (41...111).map { version in
        EnvelopeEntry(feature: "pbxproj:objectVersion=\(version)", status: .verified, evidence: ["envelope-experiments:object-versions"]
            + (readableObjectVersions.contains(version) ? ["envelope-experiments:object-versions-newest"] : []))
    }
}
