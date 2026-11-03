#!/usr/bin/env python3
"""What Xcode 27.0's driver defaults change, Xcode's clang against a developer directory's (B-170).

Each flag case compiles one C, C++ or Objective-C file for arm64 iOS with -Werror and one flag the
compile does not need, and records whether the driver accepts it or reports it unused. Xcode's
accepts -fmodules-cache-path in every case (Swift Build passes it to every compile, modules or
not, so a -Werror target without modules fails otherwise) and reports the other module-only
options. Each source case compiles a self-written file and records the exit status and the warning
and error flags, and for code cases what the code allocates and calls: an undefined TARGET_OS_
macro, an elaborated enum with a fixed type, array bounds Xcode folds to constants, dynamic_cast to
a final class, a local class's elaborated type, operators on fields of a class template,
@import of a framework's own or private module from its implementation, and the doc comments of
methods that a header included in an @implementation defines (swiftlang's clang crashed on them).
The pipeline cases record whether each optimization level lowers matrix intrinsics (Xcode's LLVM
does by default), and which vector types a search loop over a local array becomes at -Os and -O2.

Usage:
  clang_driver_experiments.py xcode <out>                Mac: Xcode's clang (DEVELOPER_DIR); writes
                                                       <out>/xcode.json
  clang_driver_experiments.py run <out> <developer-dir>  the developer directory's clang; writes
                                                       <out>/run.json and prints the differences
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCES = {
    "t.c": "int f(void) { return 0; }\n",
    "t.cpp": "int f() { return 0; }\n",
    "t.m": "int f(void) { return 0; }\n",
    "undef.c": "#if TARGET_OS_NOTREAL\nint a;\n#endif\nint f(void) { return 0; }\n",
    "enumbase.cpp": "typedef enum E : int F;\nint f() { return 0; }\n",
    "vla.c": """void use(void *);
void a1(void) { const int n = 16; char buf[n]; use(buf); }
void a2(void) { int n = 16; char buf[n]; use(buf); }
void a3(void) { char buf[(int)(4.0 * 4)]; use(buf); }
void a4(int m) { const int n = 16; char buf[n][m]; use(buf); }
""",
    "vla.cpp": """void use(void *);
void b1() { const double d = 4.0; char buf[(int)d]; use(buf); }
""",
    "dynamiccast.cpp": """struct A { virtual ~A(); };
struct B final : A { int x; };
int f(A *a) { if (auto *b = dynamic_cast<B *>(a)) return b->x; return 0; }
""",
    "localclass.cpp": """void g() {
  {
    struct X { struct H *f(); };
    using Test_H = H;
  }
}
""",
    "fields.cpp": """template <class T> struct S { int m; void a() { m = "x"; } void b() { this->m = "x"; }
  int c() { return m + "x"; } void d() { S::m = "x"; } };
""",
    "fields-member.cpp": "template <class T> struct S { int m; void b() { m.foo(); } };\n",
    "Foo.framework/Headers/Foo.h": "int foo(void);\n",
    "Foo.framework/PrivateHeaders/FooP.h": "int foo_private(void);\n",
    "Foo.framework/Modules/module.modulemap": "framework module Foo {\n  umbrella header \"Foo.h\"\n  export *\n}\n",
    "Foo.framework/Modules/module.private.modulemap": "framework module Foo_Private {\n  header \"FooP.h\"\n  export *\n}\n",
    "private.m": "@import Foo_Private;\nint foo(void) { return foo_private(); }\n",
    "self.m": "@import Foo;\nint bar(void) { return 0; }\n",
    "comments.m": "/**\n * " + "A long license block. " * 60 + """
 */

#import <Foundation/Foundation.h>

@interface Thing : NSObject
- (void)one;
- (void)two;
@end

/**
 * Documented.
 */
@implementation Thing

/**
 * \\param alsonot Not a parameter.
 */
- (void)one
{
}

#include "comments-impl.h"

@end
""",
    "comments-impl.h": "\n" * 300 + "/**\n * \\param nothere Not a parameter.\n */\n- (void)two\n{\n}\n",
}

SOURCES["scan.c"] = """#include <poll.h>
#include <sys/socket.h>
int use(int);
int scan(struct pollfd *pfds, int nfds, int s0) {
  int sockets[32];
  for (int k = 0; k < 32; k++) sockets[k] = s0 + k;
  int found = 0;
  for (int i = 0; i < nfds; i++) {
    if (pfds[i].revents != 0) {
      int p;
      for (p = 0; p < 32; p++)
        if (sockets[p] == pfds[i].fd)
          break;
      if (p > 7) {
        found += use(p);
      } else {
        int error = 0;
        socklen_t len = sizeof(error);
        getsockopt(sockets[p], SOL_SOCKET, SO_ERROR, &error, &len);
        found += error;
      }
    }
  }
  return found;
}
"""

CASES = [
    ("t.cpp", ["-fmodules-cache-path=/tmp/mc"]),
    ("t.c", ["-fmodules-cache-path=/tmp/mc"]),
    ("t.m", ["-fmodules-cache-path=/tmp/mc"]),
    ("t.cpp", ["-fno-modules", "-fmodules-cache-path=/tmp/mc"]),
    ("t.cpp", ["-fmodules", "-fno-implicit-modules", "-fmodules-cache-path=/tmp/mc"]),
    ("t.cpp", ["-fmodules-prune-interval=86400"]),
    ("t.cpp", ["-fmodules-prune-after=345600"]),
    ("t.cpp", ["-fbuild-session-timestamp=1"]),
    ("t.cpp", ["-fmodules-validate-system-headers"]),
    ("t.cpp", ["-fmodule-name=Foo"]),
    ("t.cpp", ["-fmodules-ignore-macro=FOO"]),
    ("t.cpp", ["-fimplicit-modules-lock-timeout=1"]),
    ("t.cpp", ["-fprebuilt-implicit-modules"]),
    ("t.cpp", ["-fprebuilt-module-path=/tmp"]),
    ("t.cpp", ["-fmodules-validate-input-files-content"]),
    ("t.cpp", ["-fmodules-search-all"]),
    ("t.cpp", ["-fobjc-arc"]),
    ("t.cpp", ["-fobjc-weak"]),
    ("t.cpp", ["-fobjc-exceptions"]),
    ("t.cpp", ["-L/tmp"]),
]

MODULES = ["-fmodules", "-fmodule-name=Foo", "-F", "."]
SOURCE_CASES = [
    ("undef.c", []),
    ("undef.c", ["-Werror"]),
    ("enumbase.cpp", []),
    ("vla.c", ["-Wvla"]),
    ("vla.c", ["-std=c11"]),
    ("vla.cpp", []),
    ("dynamiccast.cpp", ["-O2"]),
    ("localclass.cpp", []),
    ("fields.cpp", []),
    ("fields-member.cpp", []),
    ("private.m", MODULES),
    ("self.m", MODULES),
    ("vla.c", ["-target", "aarch64-linux-gnu"]),
    ("comments.m", ["-fobjc-arc", "-Wdocumentation"]),
    ("localclass.cpp", ["-target", "aarch64-linux-gnu"]),
]


def write_sources(out):
    source = out / "src"
    for name, text in SOURCES.items():
        (source / name).parent.mkdir(parents=True, exist_ok=True)
        (source / name).write_text(text)
    return source


def accepts(clang, sdk, source, flags):
    command = [clang, "-target", "arm64-apple-ios15.1", "-isysroot", sdk, "-Werror", "-c", str(source),
               "-o", "/dev/null"] + flags
    return subprocess.run(command, capture_output=True, text=True).returncode == 0


def compiles(clang, sdk, source, flags, cache):
    """The exit status, the diagnostic flags, and the allocas and calls of the code at -O0 (or the
    case's level)."""
    command = [clang, "-target", "arm64-apple-ios15.1", "-isysroot", sdk]
    if "-fmodules" in flags:
        command.append(f"-fmodules-cache-path={cache}")
    result = subprocess.run(command + flags + ["-S", "-emit-llvm", "-o", "-", source.name], capture_output=True,
                            text=True, cwd=source.parent)
    diagnostics = sorted(set(re.findall(r"(warning|error): .*\[(-W[^\]]*)\]", result.stderr)))
    code = [line.split("=", 1)[-1].split(",")[0].strip() for line in result.stdout.splitlines()
            if " alloca " in line or "@__dynamic_cast" in line and "call" in line]
    errors = result.stderr.count("error: ")
    return (f"rc={result.returncode} errors={errors} {' '.join(f'{kind} {flag}' for kind, flag in diagnostics)} | "
            f"{' ; '.join(code)}")


def matrix_lowering(clang, sdk, source, level):
    """Whether the pipeline at the level lowers matrix intrinsics (LLVM's -enable-matrix)."""
    command = [clang, "-target", "arm64-apple-ios18.0", "-isysroot", sdk, level, "-S", "-emit-llvm", "-o", "/dev/null",
               "-mllvm", "-print-pipeline-passes", str(source)]
    return "lower-matrix-intrinsics" in subprocess.run(command, capture_output=True, text=True).stdout


def vector_types(clang, sdk, source, flags):
    """The vector types of the optimized code: what the vectorizers made of its loops."""
    command = [clang, "-target", "arm64-apple-ios18.0", "-isysroot", sdk, "-S", "-emit-llvm", "-o", "-", str(source)]
    ir = subprocess.run(command + flags, capture_output=True, text=True).stdout
    return " ".join(sorted(set(re.findall(r"<\d+ x i\d+>", ir))))


def observe(developer, out):
    clang = str(Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/clang")
    sdk = str(Path(developer) / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk")
    source = write_sources(out)
    report = {f"{name} {' '.join(flags)}": accepts(clang, sdk, source / name, flags) for name, flags in CASES}
    with tempfile.TemporaryDirectory() as cache:
        for name, flags in SOURCE_CASES:
            report[f"source {name} {' '.join(flags)}"] = compiles(clang, sdk, source / name, flags, cache)
    for level in ["-O0", "-O1", "-O2", "-Os", "-Oz"]:
        report[f"matrix lowering {level}"] = matrix_lowering(clang, sdk, source / "vla.c", level)
    for level in ["-Os", "-O2"]:
        report[f"vectors scan.c {level}"] = vector_types(clang, sdk, source / "scan.c", [level])
    return report


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "xcode":
        out = Path(sys.argv[2]).resolve()
        developer = os.environ.get("DEVELOPER_DIR") or subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
        report = observe(developer, out)
        (out / "xcode.json").write_text(json.dumps(report, indent=2) + "\n")
        for case, result in report.items():
            print(f"{case}: {result if isinstance(result, str) else 'accepted' if result else 'reported'}")
    elif len(sys.argv) == 4 and sys.argv[1] == "run":
        out = Path(sys.argv[2]).resolve()
        report = observe(sys.argv[3], out)
        (out / "run.json").write_text(json.dumps(report, indent=2) + "\n")
        expected = json.loads((out / "xcode.json").read_text())
        differences = [case for case in expected if report.get(case) != expected[case]]
        for case in differences:
            if isinstance(expected[case], str):
                print(f"{case}: Xcode's {expected[case]}, this clang's {report[case]}")
            else:
                print(f"{case}: Xcode's {'accepts' if expected[case] else 'reports'} it, this clang "
                      f"{'accepts' if report[case] else 'reports'} it")
        print(f"{len(expected) - len(differences)} of {len(expected)} cases as Xcode's")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
