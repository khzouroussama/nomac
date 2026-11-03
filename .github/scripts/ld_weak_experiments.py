#!/usr/bin/env python3
"""Which imports a linker makes weak when `$ld$previous$` moves a symbol to another library (B-171).

flappy-fly-bird's binary imports CGFloat's nominal type descriptor, which the iOS SDK's
`libswiftCoreFoundation.tbd` moves to `libswiftCoreGraphics` below iOS 16.0, weakly in Xcode's build
and strongly in nomac's. Its Swift objects reference the descriptor strongly; their only other imports
from `libswiftCoreFoundation` are the weak `__swift_FORCE_LOAD_$_swiftCoreFoundation`, so Xcode's `ld`
links that library weakly (`LC_LOAD_WEAK_DYLIB`). These variants isolate the rule with a stub `libC`
that moves `_d` and `_f` to `libP` and keeps `_e` and `_e2`, the objects referencing each strongly or
weakly (`weak_import`).

Usage, the same as ld_experiments.py, whose stubs, links and records these variants use:
  ld_weak_experiments.py <output-dir>               on a Mac, with Xcode's ld: xcode.json, summary-xcode.txt
  ld_weak_experiments.py <output-dir> --lld <lld>   anywhere, with lld: lld.json, summary-lld.txt
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ld_experiments as ld  # noqa: E402

MOVED = ["$ld$previous$/usr/lib/libP.dylib$$2$12.2$18.0$_d$", "$ld$previous$/usr/lib/libP.dylib$$2$12.2$18.0$_f$"]
CHILD = ld.stub("/usr/lib/libC.dylib", "3", "1", MOVED + ["_d", "_e", "_e2", "_f"])


def uses(strong=(), weak=()):
    """An object calling `strong` and `weak`, the latter declared `weak_import`."""
    lines = [f"extern int {name}(void);" for name in strong]
    lines += [f"extern int {name}(void) __attribute__((weak_import));" for name in weak]
    terms = [f"{name}()" for name in strong] + [f"({name} ? {name}() : 0)" for name in weak]
    return "\n".join(lines) + "\nint g(void) { return " + " + ".join(terms) + "; }\n"


def moved(strong=(), weak=(), libs=("-lC",), minos="15.0"):
    return ld.variant(ld.LONE_PARENT, CHILD, list(libs), uses(strong, weak), minos)


VARIANTS = {
    "moved": moved(["d"]),
    "moved-with-strong": moved(["d", "e"]),
    "moved-with-weak": moved(["d"], ["e"]),
    "moved-with-weak-and-strong": moved(["d", "e2"], ["e"]),
    "moved-weak": moved([], ["d"]),
    "two-moved-with-weak": moved(["d", "f"], ["e"]),
    "moved-weak-linked": moved(["d"], libs=["-weak-lC"]),
    "moved-with-strong-weak-linked": moved(["d", "e"], libs=["-weak-lC"]),
    "outside-range-with-weak": moved(["d"], ["e"], minos="18.0"),
}

if __name__ == "__main__":
    ld.VARIANTS = VARIANTS
    ld.main()
