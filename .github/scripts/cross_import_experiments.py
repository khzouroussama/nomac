#!/usr/bin/env python3
"""Whether a Swift compiler loads cross-import overlays unasked (B-154).

A self-written file imports SwiftData and SwiftUI and uses `@Query`, which the cross-import overlay
`_SwiftData_SwiftUI` declares. It is type-checked as is, with `-Xfrontend
-disable-cross-import-overlays` and with `-Xfrontend -enable-cross-import-overlays`, for iOS and
for macOS; each case records the exit status and the first error.

Usage:
  cross_import_experiments.py <output-dir>                          on a Mac, with Xcode's swiftc
                                                                    (DEVELOPER_DIR selects the Xcode)
  cross_import_experiments.py <output-dir> --swiftc <swiftc> --sdk <iPhoneOS.sdk>
                                                                    any compiler, for iOS only
"""

import json
import re
import subprocess
import sys
from pathlib import Path

SOURCE = """import SwiftData
import SwiftUI

@Model final class Item {
    var name: String
    init(name: String) { self.name = name }
}

struct ItemsView: View {
    @Query var items: [Item]
    var body: some View { Text("\\(items.count)") }
}
"""

FLAGS = {"default": [], "disable": ["-Xfrontend", "-disable-cross-import-overlays"],
         "enable": ["-Xfrontend", "-enable-cross-import-overlays"]}


def main(out):
    out.mkdir(parents=True, exist_ok=True)
    (out / "Q.swift").write_text(SOURCE)
    if "--swiftc" in sys.argv:
        swiftc = [sys.argv[sys.argv.index("--swiftc") + 1]]
        targets = {"ios": ("arm64-apple-ios17.0", sys.argv[sys.argv.index("--sdk") + 1])}
        label = "other"
    else:
        swiftc = ["xcrun", "swiftc"]
        sdk = lambda name: subprocess.run(["xcrun", "--sdk", name, "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
        targets = {"ios": ("arm64-apple-ios17.0", sdk("iphoneos")), "macos": ("arm64-apple-macos14.0", sdk("macosx"))}
        label = "xcode"
    record = {}
    for platform, (target, sdk_path) in targets.items():
        for name, flags in FLAGS.items():
            proc = subprocess.run(swiftc + ["-target", target, "-sdk", sdk_path, "-parse-as-library", "-typecheck", str(out / "Q.swift")] + flags,
                                  capture_output=True, text=True)
            errors = re.findall(r"error: (.*)", proc.stderr)
            record[f"{platform}/{name}"] = {"exit": proc.returncode, "first error": errors[0] if errors else None}
    (out / f"{label}.json").write_text(json.dumps(record, indent=1) + "\n")
    for key, value in record.items():
        print(f"{label} {key}: exit {value['exit']} {value['first error'] or ''}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]).resolve())
