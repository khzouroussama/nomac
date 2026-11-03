import Foundation

extension ProjectGenerator {
    /// File types whose references lose their `fileEncoding` in the PIF: Xcode 27.0 writes no
    /// `fileTextEncoding` for them (loader-experiments `file-encodings`, every file type of Swift
    /// Build's specifications and the common types they lack, 206 in all; cwa's `.xib` files),
    /// and `file`, whatever the declared type (`declared-encodings`: a declared `file`, a binary
    /// or missing file typed `file` from disk; mattermost's fonts declared `undefined`; no `file`
    /// of the 20 corpus references has one). Every other type keeps it.
    static let typesWithoutTextEncoding: Set<String> = [
        "archive", "archive.ar", "file", "archive.asdictionary", "archive.binhex", "archive.ear", "archive.gzip",
        "archive.jar", "archive.macbinary", "archive.metal-library", "archive.ppob", "archive.rsrc",
        "archive.stuffit", "archive.tar", "archive.war", "archive.zip", "audio", "audio.aiff", "audio.au",
        "audio.midi", "audio.mp3", "audio.wav", "com.apple.instruments.instrdst", "compiled", "compiled.air",
        "compiled.cfm", "compiled.javaclass", "compiled.mach-o", "compiled.mach-o.bundle",
        "compiled.mach-o.corefile", "compiled.mach-o.dylib", "compiled.mach-o.dylinker",
        "compiled.mach-o.executable", "compiled.mach-o.fvmlib", "compiled.mach-o.objfile",
        "compiled.mach-o.preload", "compiled.object-library", "compiled.rcx", "file.bplist",
        "file.playground", "file.scp", "file.sks", "file.skybox", "file.storyboard", "file.uicatalog",
        "file.xcplaygroundpage", "file.xib", "folder", "folder.abstractassetcatalog", "folder.assetcatalog",
        "folder.documentationcatalog", "folder.iconcomposer.icon", "folder.iconset", "folder.imagecatalog",
        "folder.mlpackage", "folder.rkassets", "folder.skatlas", "folder.stickers", "image", "image.bmp",
        "image.gif", "image.icns", "image.ico", "image.jpeg", "image.pdf", "image.pict", "image.png",
        "image.tiff", "video", "video.avi", "video.mpeg", "video.quartz-composer", "video.quicktime",
        "wrapper", "wrapper.app-extension", "wrapper.application", "wrapper.artifactbundle",
        "wrapper.cfbundle", "wrapper.driver-extension", "wrapper.dsym", "wrapper.extensionkit-extension",
        "wrapper.framework", "wrapper.htmld", "wrapper.installer-mpkg", "wrapper.installer-pkg",
        "wrapper.java-classfolder", "wrapper.kernel-extension", "wrapper.nib", "wrapper.pb-project",
        "wrapper.pb-target", "wrapper.plug-in", "wrapper.rtfd", "wrapper.scnassets", "wrapper.scncache",
        "wrapper.spotlight-importer", "wrapper.storyboardc", "wrapper.system-extension", "wrapper.workspace",
        "wrapper.xcclassmodel", "wrapper.xcdatamodel", "wrapper.xcdatamodeld", "wrapper.xcframework",
        "wrapper.xcmappingmodel", "wrapper.xpc-service",
    ]
}
