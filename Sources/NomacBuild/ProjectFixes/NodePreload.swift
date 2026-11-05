import Foundation
import NomacCore

/// How the table's in-memory edits reach Node: a CommonJS preload that script phases' `NODE_OPTIONS`
/// requires. An ES module that imports a CommonJS file also reaches `Module.prototype._compile`
/// (Node 20.20.2, 22.23.4, 24.22.2 and 26.13.0 with Expo's real `apple.js`, ADR 0184).
enum NodePreload {
    /// Where the preload records the fixes that applied, for the end of the build.
    static let recordVariable = "NOMAC_PROJECT_FIXES_RECORD"

    struct Entry: Encodable, Sendable {
        var id: String
        var file: String
        var old: String
        var new: String
    }

    static var entries: [Entry] {
        ProjectFixes.all.compactMap { fix in
            guard case .inMemoryEdit(let file, let old, let new) = fix.change else { return nil }
            return Entry(id: fix.id, file: file, old: old, new: new)
        }
    }

    static func source(_ entries: [Entry]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let table = String(decoding: try encoder.encode(entries), as: UTF8.self)
        return #"""
            'use strict';
            const fs = require('fs');
            const Module = require('module');
            const entries = \#(table);
            const compile = Module.prototype._compile;
            Module.prototype._compile = function (content, filename, ...rest) {
              if (typeof content === 'string' && typeof filename === 'string') {
                for (const { id, file, old, new: replacement } of entries) {
                  if (filename.endsWith('/' + file) && content.includes(old)) {
                    content = content.replace(old, () => replacement);
                    process.stderr.write(`note: project fix ${id}: changed in memory, not on disk: ${file}: "${old}" is now "${replacement}"\n`);
                    const record = process.env.\#(recordVariable);
                    if (record) {
                      try { fs.appendFileSync(record, id + '\n'); } catch {}
                    }
                  }
                }
              }
              return compile.call(this, content, filename, ...rest);
            };

            """#
    }

    /// Writes the preload into `folder`, named by its contents so that builds can share it.
    static func write(in folder: String) throws -> String {
        let text = try source(entries)
        let path = folder + "/project-fixes-" + MD5.hex(text) + ".cjs"
        try FileSystem.write(Data(text.utf8), to: path)
        return path
    }

    /// Adds the preload to script phases' `NODE_OPTIONS`, after any value of the environment or the
    /// project (`$(inherited)`) or of the command line, which takes precedence over synthesized values.
    static func apply(preload: String, record: String, to overrides: inout [String: String], synthesized: inout [String: String]) {
        let option = "--require \"\(preload)\""
        if let commandLine = overrides["NODE_OPTIONS"] {
            overrides["NODE_OPTIONS"] = commandLine + " " + option
        } else {
            synthesized["NODE_OPTIONS"] = "$(inherited) " + option
        }
        synthesized[recordVariable] = record
    }
}
