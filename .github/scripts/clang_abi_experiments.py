#!/usr/bin/env python3
"""Which C++ ABI Xcode 27.0's clang and Swift's Clang importer follow, against swift.org's.

Observed rules: docs/formats/build.md "Clang's C++ ABI".

Xcode 27.0's clang mangles `Node<Name>` (a `const char *` template argument given an array) as
`XadL_Z4NameE`, swift.org 6.4.0's as `XadsoKcL_Z4NameEE`. Each `-fclang-abi-compat=<N>` level of
upstream Clang brings back older rules (mangling, record layout, argument passing); this compiles
self-written C++ with Xcode's clang at its default and at every level, finds the levels that give
the default's IR, and compares swift.org's compilers, as nomac installs them, with Xcode's
objects: symbols, and code and data at -O1.

Usage:
  clang_abi_experiments.py xcode <out>               Mac: Xcode's clang and swiftc (DEVELOPER_DIR);
                                                     writes <out>/xcode.json and Xcode's objects
  clang_abi_experiments.py run <out> <developer-dir> a developer directory nomac installed (Linux):
                                                     its clang and swiftc as installed and with the
                                                     Clang 4 ABI asked for; writes <out>/run.json
"""

import json
import os
import subprocess
import sys
from pathlib import Path

TARGETS = ["arm64-apple-ios15.1", "x86_64-apple-ios15.1-simulator"]
LEVELS = ["3.8", "4", "5", "6", "7", "9", "11", "12", "14", "15", "17", "18", "19", "20", "latest"]
VENDOR_FEATURES = ["disableNonDependentMemberExprInCurrentInstantiation", "enableAggressiveVLAFolding", "revert09abecef7bbf",
                   "thisNoAlignAttr", "thisNoNullAttr", "disableAtImportPrivateFrameworkInImplementationError"]
# -fno-sized-deallocation: Xcode's driver passes it for iOS, nomac's settings add it (LinuxCompiler).
FLAGS = ["-fblocks", "-O1"]
# C++ sources only.
CXX_FLAGS = ["-std=c++20", "-fno-sized-deallocation"]

SOURCES = {
    # What Xcode's driver adds for Apple targets: -fcommon (tentative definitions as common symbols)
    # and -fno-strict-return (a function that falls off its end, no noundef on returns).
    "defaults-c.c": """int counter;
int table[16];
static int hidden;
int twice(int x) { if (x > 0) return x * 2; }
int sum(void) { return counter + table[1] + hidden; }
""",
    "defaults-cxx.cpp": """int pick(int x) { if (x) return 1; }
struct S { int v; int get() const; };
int S::get() const { if (v > 0) return v; }
""",
    # Pointers and references into objects as template arguments (ItaniumMangle's array decay).
    "subobjects.cpp": """struct Pair { int a; int b; };
struct Base { int x; };
struct Derived : Base { int y; };
extern const char Name[] = "ab";
extern const int Arr[3] = {1, 2, 3};
extern const Pair P = {1, 2};
extern const Derived D = {};
extern const int Two[2][2] = {};
template <const char *> struct PC { static int get(); };
template <const int *> struct PI { static int get(); };
template <const int &> struct RI { static int get(); };
template <const void *> struct PV { static int get(); };
template <auto> struct AU { static int get(); };
template <const int (*)[3]> struct PA { static int get(); };
template <const Base *> struct PB { static int get(); };
template <const int *> int fn();
struct Holder { const char *p; };
template <Holder> struct CL { static int get(); };
template <const char *Q> auto nested() -> decltype(PC<Q>::get());
int use() {
  return PC<Name>::get() + PC<&Name[0]>::get() + PC<&Name[1]>::get() + PC<Name + 2>::get()
    + PI<Arr>::get() + PI<&Arr[2]>::get() + PI<&P.b>::get() + PI<&P.a>::get() + PI<&Two[1][0]>::get()
    + RI<Arr[0]>::get() + RI<Arr[1]>::get() + RI<P.b>::get()
    + PV<static_cast<const void *>(Name)>::get() + PV<static_cast<const void *>(&Arr[1])>::get() + PV<static_cast<const void *>(&P)>::get()
    + AU<Name>::get() + AU<&Arr[1]>::get() + AU<&P.b>::get()
    + PA<&Arr>::get() + PB<static_cast<const Base *>(&D)>::get() + fn<Arr>() + fn<&P.b>()
    + CL<Holder{Name}>::get() + CL<Holder{&Name[1]}>::get() + nested<Name>();
}
""",
    # One case for each mangling rule a -fclang-abi-compat level restores.
    "manglings.cpp": """template <int> struct SI {};
template <class T> concept C = sizeof(T) > 0;
int ei(int x) __attribute__((enable_if(x > 0, "pos"))) { return x; }
int ei(int x) { return -x; }
int g1 = ei(1);
struct Q { template <class> struct X {}; struct Inner { struct A {}; struct B {}; }; template <int> static int g(); };
template <class T> void dt(typename T::template X<int>, typename T::template X<char>) {}
template void dt<Q>(Q::X<int>, Q::X<char>);
struct LS { static inline auto f = [](int) { return 1; }; };
int g3 = LS::f(2);
inline auto glam = [](auto x) { return x; };
int g3b = glam(1);
struct BS { static inline int (^b)(void) = ^{ return 1; }; };
int g4 = BS::b();
template <class T> auto al(T) -> SI<__alignof__(T)> { return {}; }
template SI<4> al<int>(int);
template <class T> auto te(T) -> decltype(T::template g<1>()) { return 0; }
template int te<Q>(Q);
template <class T> void ns(typename T::Inner::A, typename T::Inner::B) {}
template void ns<Q>(Q::Inner::A, Q::Inner::B);
template <C T> void ct(T) {}
template void ct<int>(int);
void ca(C auto) {}
template void ca<long>(long);
template <class T> struct FR { template <class U> friend void fr(FR, U) requires C<T> {} };
void usefr() { fr(FR<int>{}, 1); }
template <template <class> class> struct TTH { static int h(); };
template <class T, class U = int> struct DD {};
int g11 = TTH<DD>::h();
template <class T> auto cex(T) -> SI<C<T>> { return {}; }
template SI<1> cex<int>(int);
int lc() { struct L { int m() { return [] { return 1; }(); } }; return L().m(); }
namespace n { struct V { virtual ~V(); }; struct A : virtual V { virtual void a(); }; struct B : A { void a() override; }; }
void n::B::a() {}
template <class T> auto g6(T) { return T(); }
template auto g6<int>(int);
int zz();
template <class T> auto (*g7(T))() -> auto { return &zz; }
template auto (*g7<int>(int))() -> auto;
""",
    # Record layout and argument passing rules a level restores.
    "layout.cpp": """struct E6 { int : 3; };
int e6 = __is_empty(E6);
struct B6 { int i; };
struct __attribute__((packed)) P6 : B6 { char c; };
int p6 = alignof(P6) * 100 + sizeof(P6);
int a7 = alignof(double) * 100 + alignof(long long);
union UF { float f; int i; };
struct SU { UF u; float g; };
float takeSU(SU s) { return s.g; }
float callSU() { return takeSU(SU{{1}, 2}); }
struct NC { int a; NC() = default; NC(NC &) = default; };
int takeNC(NC n) { return n.a; }
int callNC() { NC n; return takeNC(n); }
struct D15b { D15b() = default; int i; char c; };
struct D15 : D15b { char d; };
int s15 = sizeof(D15);
typedef float V8 __attribute__((vector_size(32)));
struct R256 { V8 v; };
R256 retR(V8 v) { return R256{v}; }
struct Empty {};
int takeEmpty(int a, Empty, int b) { return a + b; }
int callEmpty() { return takeEmpty(1, Empty{}, 2); }
struct DC { DC(int v) : x(v) {} DC(const DC &) = delete; int x; };
int takeDC(DC d) { return d.x; }
int callDC() { return takeDC(DC(1)); }
struct DM { DM(int v) : x(v) {} DM(const DM &) = delete; DM(DM &&) = delete; long x[3]; };
long takeDM(DM d) { return d.x[0]; }
long callDM() { return takeDM(DM(1)); }
""",
    # A null check on `this`, which the vendor features thisNoNullAttr and thisNoAlignAttr keep.
    "this.cpp": """struct S { int a; bool isNull() const { return this == nullptr; } int get() const; };
int S::get() const { return isNull() ? -1 : a; }
""",
}

# C++ the Swift compiler's Clang importer compiles for Swift code (C++ interoperability).
INTEROP = {
    "node.h": """template <const char *P> struct Node { static int get(); };
extern const char Name[];
inline int useNode() { return Node<Name>::get(); }
struct DC { DC(int v) : x(v) {} DC(const DC &) = delete; int x; };
int takeDC(DC d);
inline int callDC() { return takeDC(DC(1)); }
template <class T> concept Cn = sizeof(T) > 0;
template <Cn T> int ct(T) { return 1; }
inline int useCt() { return ct(1); }
struct Box { int v; };
inline int useDelete() { Box *b = new Box{2}; int v = b->v; delete b; return v; }
""",
    "module.modulemap": "module NodeC {\n  header \"node.h\"\n  export *\n}\n",
    "main.swift": "import NodeC\npublic func f() -> Int32 { useNode() + callDC() + useCt() + useDelete() }\n",
}
INTEROP_FLAGS = ["-cxx-interoperability-mode=default", "-Xcc", "-std=c++20", "-module-name", "M"]


def write_sources(out):
    source = out / "src"
    (source / "interop").mkdir(parents=True, exist_ok=True)
    for name, text in SOURCES.items():
        (source / name).write_text(text)
    for name, text in INTEROP.items():
        (source / "interop" / name).write_text(text)
    return source


def compile_cxx(clang, source, target, extra, output):
    language = CXX_FLAGS if Path(source).suffix == ".cpp" else []
    command = [clang, "-target", target] + FLAGS + language + extra + ["-c", str(source), "-o", str(output)]
    if output.suffix == ".ll":
        command[-4:-3] = ["-S", "-emit-llvm"]
    return subprocess.run(command, capture_output=True, text=True).returncode == 0


def compile_swift(swiftc, sdk, source, extra, output):
    command = [swiftc, "-target", TARGETS[0], "-sdk", sdk] + INTEROP_FLAGS + extra
    command += ["-I", str(source / "interop"), "-c", str(source / "interop" / "main.swift"), "-o", str(output)]
    return subprocess.run(command, capture_output=True, text=True).returncode == 0


def symbols(nm, obj):
    lines = subprocess.run([nm, str(obj)], capture_output=True, text=True, check=True).stdout.splitlines()
    return sorted(line.split()[-1] for line in lines if line.strip())


def code(objdump, obj):
    text = subprocess.run([objdump, "-d", "-s", "--no-show-raw-insn", str(obj)], capture_output=True, text=True, check=True).stdout
    return [line for line in text.splitlines() if str(obj) not in line]


def xcode(out):
    developer = os.environ.get("DEVELOPER_DIR") or subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    bin_dir = Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    clang, nm = str(bin_dir / "clang"), str(bin_dir / "llvm-nm")
    sdk = str(Path(developer) / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk")
    source = write_sources(out)
    objects = out / "xcode"
    objects.mkdir(exist_ok=True)
    scratch = out / "scratch"
    scratch.mkdir(exist_ok=True)
    report = {"levels": {}, "vendorFeatures": {}}
    for name in SOURCES:
        for target in TARGETS:
            stem = f"{Path(name).stem}.{target}"
            assert compile_cxx(clang, source / name, target, [], objects / f"{stem}.o"), stem
            default = scratch / f"{stem}.ll"
            compile_cxx(clang, source / name, target, [], default)
            same = []
            for level in LEVELS:
                variant = scratch / f"{stem}.{level}.ll"
                if compile_cxx(clang, source / name, target, [f"-fclang-abi-compat={level}"], variant) and variant.read_bytes() == default.read_bytes():
                    same.append(level)
            report["levels"][stem] = same
            print(f"{stem}: Xcode's default gives the IR of -fclang-abi-compat={','.join(same) or 'none'}")
    default = scratch / "this.ll"
    compile_cxx(clang, source / "this.cpp", TARGETS[0], [], default)
    for feature in VENDOR_FEATURES:
        variant = scratch / f"this.{feature}.ll"
        compile_cxx(clang, source / "this.cpp", TARGETS[0], ["-Xclang", f"-clang-vendor-feature=-{feature}"], variant)
        report["vendorFeatures"][feature] = variant.read_bytes() != default.read_bytes()
        print(f"this.cpp without {feature}: IR {'differs' if report['vendorFeatures'][feature] else 'identical'}")
    assert compile_swift(str(bin_dir / "swiftc"), sdk, source, [], objects / "interop.o")
    report["interopSymbols"] = [symbol for symbol in symbols(nm, objects / "interop.o") if symbol.startswith("__Z")]
    (out / "xcode.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


def run(out, developer):
    bin_dir = Path(developer) / "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    clang, nm, objdump = str(bin_dir / "clang"), str(bin_dir / "llvm-nm"), str(bin_dir / "llvm-objdump")
    sdk = str(Path(developer) / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk")
    source = write_sources(out)
    objects = out / "xcode"
    scratch = out / "scratch"
    scratch.mkdir(exist_ok=True)
    report = {}
    for variant, extra in {"installed": [], "abi-4": ["-fclang-abi-compat=4.0"]}.items():
        for name in SOURCES:
            if name == "this.cpp":
                continue
            for target in TARGETS:
                stem = f"{Path(name).stem}.{target}"
                ours = scratch / f"{stem}.{variant}.o"
                assert compile_cxx(clang, source / name, target, extra, ours), stem
                reference = objects / f"{stem}.o"
                result = {"symbols": symbols(nm, ours) == symbols(nm, reference), "code": code(objdump, ours) == code(objdump, reference)}
                report[f"{stem}.{variant}"] = result
                print(f"{stem} {variant}: symbols {'identical' if result['symbols'] else 'differ'}, code and data {'identical' if result['code'] else 'differ'}")
    expected = json.loads((out / "xcode.json").read_text())["interopSymbols"]
    # abi-4-unsized: the Clang importer's flags a build off macOS adds (LinuxCompiler).
    for variant, extra in {"installed": [], "abi-4": ["-Xcc", "-fclang-abi-compat=4.0"],
                           "abi-4-unsized": ["-Xcc", "-fclang-abi-compat=4.0", "-Xcc", "-fno-sized-deallocation"]}.items():
        ours = scratch / f"interop.{variant}.o"
        assert compile_swift(str(bin_dir / "swiftc"), sdk, source, extra, ours)
        found = [symbol for symbol in symbols(nm, ours) if symbol.startswith("__Z")]
        report[f"interop.{variant}"] = {"symbols": found == expected, "onlyXcode": sorted(set(expected) - set(found)), "onlyOurs": sorted(set(found) - set(expected))}
        print(f"interop {variant}: C++ symbols {'identical' if found == expected else 'differ'}")
    (out / "run.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "xcode":
        xcode(Path(sys.argv[2]).resolve())
    elif len(sys.argv) == 4 and sys.argv[1] == "run":
        run(Path(sys.argv[2]).resolve(), sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
