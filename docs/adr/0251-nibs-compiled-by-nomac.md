# ADR 0251: nomac compiles nibs itself, and refuses what it has not observed

- Status: accepted
- Date: 2026-10-21

## Context

iOS builds compile `.xib` and `.storyboard` files with `ibtool`, a closed tool that runs in a
daemon and needs Interface Builder's plugins; nothing of it runs on Linux. A compiled nib is a
`NIBArchive` file (docs/formats/nib.md) whose objects are UIKit's archived classes, with a key
table in Foundation's hash-table order (docs/formats/foundation-collections.md).

A wrong nib fails at run time, on a device, far from its cause; a missing one fails the build.

## Decision

1. **`NomacNib`** reads Interface Builder documents with Foundation's `XMLParser` and writes
   `NIBArchive` files with its own writer and encoder; each archived class is written as observed
   with `nib_experiments.py`. `nomac ibtool` takes the build's command line.
2. **Only what is observed is compiled.** Every element, attribute, attribute value and ibtool
   option outside what the experiments observed stops it with `nomac does not compile <what> yet
   (BACKLOG B-26x)`, in ibtool's error format, so a build fails instead of shipping a nib that is
   not Xcode's (docs/formats/nib.md "Inputs nomac compiles").
3. **The key-table order** uses `NomacPlist.FoundationHashTable`, shared with the Core Data work.

## Consequences

- Plain views (frames, masks, flags, content modes, tags, subviews, custom classes) and their
  background colors (gray and sRGB components, system and named colors) compile byte for byte
  in all 348 xib experiments nomac accepts; `nib_compare.py` reports any difference.
- Storyboards compile for the scenes observed (38 of 42 experiments, retro-rampage's two,
  docs/formats/nib.md "Storyboards"); other scenes, converted colors and every other UIKit class
  are BACKLOG B-260 and B-261, added one observed class at a time; key tables of more than 156
  keys are B-259.
