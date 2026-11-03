# Property lists as Xcode's tools write them

Observed with Xcode 27.0 (27A266a) on self-written inputs: `plutil -convert xml1`,
`xcstringstool compile` and the files `builtin-copyStrings` writes in builds
(`.github/scripts/strings_experiments.py`). nomac writes them with `NomacPlist`, never with
Foundation's `PropertyListSerialization`, whose output differs between Darwin and Linux (ADR 0250).

## XML

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>arr</key>
	<array/>
	<key>d</key>
	<data>
	AAE=
	</data>
	<key>date</key>
	<date>2001-01-01T00:00:00Z</date>
	<key>empty</key>
	<dict/>
	<key>f</key>
	<false/>
	<key>i</key>
	<integer>-3</integer>
	<key>r</key>
	<real>0.10000000000000001</real>
	<key>s</key>
	<string>&lt;&amp;&gt;'"</string>
</dict>
</plist>
```

- One tab per level. Empty dictionaries and arrays are `<dict/>` and `<array/>`; an empty string
  is `<string></string>`.
- Only `&`, `<` and `>` are escaped. Quotes, tabs, newlines and other control characters are
  written as they are.
- Reals have 17 significant digits (`%.17g`).
- Data is base64 on lines of `76 - 8 × depth` characters, each indented like the element
  (observed at depths 1 to 8), between `<data>` and `</data>` lines.
- Keys are sorted. `plutil` and `xcstringstool`'s `.strings` tables sort by UTF-16 code units
  (U+1F600 before U+FF01); `xcstringstool`'s `.stringsdict` tables sort as Swift compares
  strings (U+FF01 before U+1F600).

## Binary

The `bplist00` files Swift Build's builtin tasks write on a Mac (`builtin-copyStrings`; the same
code path writes the other binary property lists of Swift Build's builtins: `swiftBuildData`
writes Xcode's bytes for the Info.plists of retro-rampage's `Engine`, `Renderer` and
`Rampage.app`, Debug and Release, B-105). Swift Build sorts
dictionary keys and interns strings before handing the property list to Core Foundation, so the
layout is:

- **Objects, depth first.** A dictionary is written, then its keys, then its values; an array,
  then its elements. Keys are in Swift's string order: canonical composition first, so
  `e` + U+0301 + `x` sorts after `é` and before `z` (`key-order-unicode`).
- **Sharing.** Equal strings (by UTF-16 code units) are one object, and so are equal integers.
  Reals, dates, data, arrays and dictionaries are never shared, even when equal or empty. Every
  boolean is written, but every reference to `true` names the first `true` object (and likewise
  for `false`), so a second `true` is an object nothing refers to (`xml-duplicates`).
- **Encodings.** Booleans `08`/`09`; integers `10`–`13` with 1, 2, 4 or 8 big-endian bytes,
  negative ones always 8; reals `23` + 8 bytes; dates `33` + 8 bytes (seconds since 2001);
  data `4n`; strings `5n` when every character is ASCII, else `6n` with UTF-16 big-endian code
  units; arrays `An`; dictionaries `Dn` with all key references, then all value references. A
  count of 15 or more is `xF` followed by an integer object. Keyed archives also hold 4-byte reals
  `22` and UIDs `8n` of 1, 2 or 4 bytes (docs/formats/coredata.md "Keyed archives").
- **Trailer.** Offsets take 1, 2, 4 or 8 bytes, as many as the offset table's own position
  needs (a table at 256 takes 2, `table-at-256`); object references as many as the number of
  objects needs (256 objects take 2, `objects-256`). The top object is 0.

## Dictionary key order by tool

| Writer | Key order |
|---|---|
| Swift Build's builtins (`builtin-copyStrings`, Info.plist processing), binary | Swift's string order (`BinaryPropertyList.swiftBuildData`) |
| `plutil -convert xml1`, `xcstringstool`'s `.strings` tables, XML | UTF-16 code units (`XMLPropertyList`) |
| `xcstringstool`'s `.stringsdict` tables, XML | Swift's string order |
| An app-store-connect export, writing again the binary Info.plist of the app and of each extension (not of frameworks) | each dictionary's keys in the order of a Foundation dictionary created with them in Swift's order, the top dictionary's in the order of a copy created with them in that order (a shallow mutable copy; it differs when a key wrapped around the first table) (`BinaryPropertyList.foundationData(rereading:)`) |
| ibtool's NIB key tables | a mutable Foundation table (docs/formats/nib.md "Encoding") |
| ibtool's `.storyboardc` `Info.plist`, binary | a Foundation table's; objects shared when ibtool held one object twice, not when values are equal (docs/formats/nib.md "Storyboards"; `BinaryPropertyList.data(objects:)`) |
| momc's keyed archives (`.mom`) | copies of mutable Foundation tables (docs/formats/coredata.md) |

A Foundation dictionary created with its keys has the bucket count whose capacity fits them
(3, 6, 11, 19, 32, 52 and 85 keys for 3, 7, 13, 23, 41, 71 and 127 buckets) and its keys
inserted in the order given (docs/formats/foundation-collections.md; `FoundationHashTable.created`).
The export's file is otherwise the archive's: the same objects, sharing and sizes. Observed on
the 20 app and extension Info.plists of the packaging workstream's app-store-connect exports
(`.github/scripts/signing_experiments.py`: `adhoc`, `nested`, `span*`, `symbols`), all
reproduced byte for byte; nested dictionaries (`NSExtension`) follow the same rule.

## Reading

`.strings` files are old-style (OpenStep) property lists, mostly in the strings-file form of
top-level `key = value;` pairs; `.stringsdict` files are XML. nomac reads both itself
(`TextPropertyListParser`): comments `//` and `/* */`; quoted strings with `"` or `'`;
unquoted strings of ASCII letters, digits and `_$/:.-`; `{ k = v; }`, `( a, b, )`, `<hex>`;
`key;` at the top level for `key = key;`; the last of duplicate keys wins. Escapes: `\a \b \f
\n \r \t \v`, `\U` with up to four hex digits, up to three octal digits, and any other
character for itself. Each `\U` escape is one UTF-16 code unit: a high surrogate followed by a
low one is one character, and every other surrogate becomes U+FFFD (`\UD83D\UD83D\UDE00` is
U+FFFD U+1F600; the `copy-escapes` experiment of `.github/scripts/strings_experiments.py`).
In XML, every `<key>` and `<string>` loses one U+FEFF at its start, written as such or as
`&#xFEFF;` (`\u{FEFF}\u{FEFF}x` is `\u{FEFF}x`); old-style text keeps it, and so do the outputs
copied as text (UTF-8, UTF-16). `plutil -convert` reads XML the same way (strings-experiments
`copy`: `xml-bom-values`, `xml-bom-keys`, `text-bom-values`, `bom-forms`; nextcloud's
NextcloudKitUI `kn.lproj`).
No corpus `.strings` file is a binary property list, and the strings workstream does not take
them yet (BACKLOG B-252). `BinaryPropertyList.value(from:path:)` reads `bplist00` files, as an
app-store-connect export reads the archive's Info.plists; it refuses UIDs, sets, nulls and
integers over 64 bits, which Info.plists do not hold.
