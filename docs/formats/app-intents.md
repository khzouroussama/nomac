# App Intents metadata

What Xcode 27.0's `appintentsmetadataprocessor` and `appintentsnltrainingprocessor` write, as
nomac's `AppIntentsTools` and `AppIntentsMetadata` reproduce it. Observed with
`.github/scripts/app_intents_experiments.py` (`record` builds self-written apps with Xcode and
keeps each task's command and outputs outside the repository; `compare` runs nomac's tool on the
same inputs). Every form outside what is written here is refused with its name (B-107, B-159).

## The inputs

Swift Build runs `ExtractAppIntentsMetadata` for every Swift target, with
`--compile-time-extraction`: the processor reads the Swift compiler's constant values
(`--swift-const-vals-list`, `.swiftconstvalues` files), which Swift Build asks for with
`-emit-const-values` and a protocol list (`<target>_const_extract_protocols.json`) from its own
Apple platform plugin, off macOS too. swift.org 6.4.0's compiler writes the same constant values as
Xcode's, byte for byte (`basic`). They list each type conforming to a gathered protocol, its
conformances, associated types (`PerformResult`) and every property's value as a typed tree
(`RawLiteral`, `InitCall` with all arguments, defaults included, `Array`, `Dictionary`, `Enum`,
`MemberReference`, `InterpolatedStringLiteral` with `KeyPath` segments, `Builder`, `NilLiteral`,
`Runtime` for a value left to run time).
`--swift-const-vals-list` names one file per line with blanks and punctuation escaped by
backslashes (Swift Build's `quotedStringListRepresentation`); the tool removes every backslash
(gomap's `Go\ Map\!\!-primary.swiftconstvalues`). The dependency metadata lists hold raw paths.
For a target built for several architectures (watchOS's arm64 and arm64_32, `watch`) Swift Build
repeats `--target-triple`, `--dependency-file`, `--stringsdata-file`, `--source-file-list` and
`--swift-const-vals-list` per architecture: Xcode's tool reads every constant values list (the
same types in each), writes the strings data to the last `--stringsdata-file` only, and reads the
universal binary (a fat executable, or a fat archive for a static library, which also gets
`--force`); nomac decides whether it links App Intents by its 64-bit slices.

## Outputs

- A target that does not link App Intents, or links it without declaring any of its types
  (`linked`: "Extracted no relevant App Intents symbols, skipping writing output"): only the strings
  data, an empty table set.
- Otherwise `<bundle>/Metadata.appintents/`:
  - `extract.actionsdata`: one line, keys sorted, no trailing newline. `actions`, `entities` and
    `queries` by type name without its module; `enums`, `autoShortcuts` and four empty lists;
    `generator` (`xcode-tools`, the Xcode build), `shortcutTileColor` 14, `version` 1;
    `autoShortcutProviderMangledName` only with an App Shortcuts provider.
  - `version.json`: `toolsVersion` (the Xcode build) and `version` "3.0".
  - `root.ssu.yaml` and `nlu/` are the training's (below).
  - `extract.packagedata`, for a target that declares an `AppIntentsPackage`: `includes`, the
    mangled names of the packages its `includedPackages` lists, and `version` 1, compact; Xcode
    writes the two keys in dictionary order, which changes from build to build (`package`: a
    framework's package and an app including it), judged equivalent.
- The strings data (`--stringsdata-file`): `source` is the App Shortcuts provider's file, else
  `ExtractedAppShortcutsMetadata`; `tables` has `AppShortcuts` (one entry per shortcut: its index,
  intent identifier and title, its enum and entity parameters' types and display strings, its
  first phrase as the key and all its phrases as the values, the provider's `appShortcuts` line;
  `training`) and `Localizable` (the parameter summaries' format strings).
- JSON is written as Darwin's Foundation writes it: `\/` for `/`, and pretty files with two
  spaces, ` : ` and an empty container as `{\n\n  }` (`FoundationJSON`).

## Run-to-run order

Three builds of `basic` give three orders of each parameter's `resolvableInputTypes` and of
`root.ssu.yaml`'s parameter variables, and three builds of `types` three orders of the key and value
pairs of `typeSpecificMetadata` (Xcode keeps them in sets and dictionaries, whose order is seeded per
process), and so different training outputs. Everything else is identical. nomac writes those in
one order; `compare` counts outputs that differ only there as "identical but for set order", and
`nomac verify` judges them equivalent (`appintents.set-order`).

## Dependencies

Swift Build lists the `extract.actionsdata` of every bundle the target depends on
(`--metadata-file-list`; `embedded`: an app and the WidgetKit extension it embeds). Each bundle
keeps its own metadata. A parameter or result of a type the target's own constant values lack is
one of those bundles' entities or enums (`dependency`: an app intent on a framework's): typed by
its name there, an entity with `dynamicOptionsSupport` 0 whatever its query, an enum's default
written as its case's title (`Sweet`), where the target's own enum's is its case's name. Other
types are refused.

## Actions (intents)

- `title` and `description` (string literals) give `title` and `descriptionMetadata`;
  `openAppWhenRun` gives `openAppWhenRun` and `supportedModes` 2 (else 1).
- A parameter (`_name: IntentParameter<T>`) gives `name`, `title`, `isOptional` (`T?`),
  `capabilities` 1 with a default, 8 with an `optionsProvider` (which also makes
  `dynamicOptionsSupport` 1), `typeSpecificMetadata` with
  `LNValueTypeSpecificMetadataKeyDefaultValue` and the default (`int`, `double` written as `0.5` or
  `1`, a Boolean as `int` 1 or 0, `string`, an empty `array`), a `Double`'s `inclusiveRange` as
  `LNValueTypeMetadataKeyNumberRangeType` 0 and its lower and upper bounds, String `inputOptions` as
  `LNValueTypeMetadataKeyStringCapitalizationType` (`.none` 0), `…Multiline`, `…Autocorrect`,
  `…SmartQuotes` and `…SmartDashes` (1 or 0),
  `parameterDescription` from `description:`, and `inputConnectionBehavior` 2 with `isInput` true
  for `.connectToPreviousIntentResult`. `supportedContentTypes` gives
  `LNValueTypeMetadataKeyFileSupportedTypes` with the types' identifiers (`.image` `public.image`,
  `.jpeg` `public.jpeg`, `.png` `public.png`, `.gif` `com.compuserve.gif`, `.heic` `public.heic`).
  `requestValueDialog` leaves no trace. Arguments left at their defaults are `NilLiteral` or
  `Runtime` (`controlStyle`, `inputConnectionBehavior`, `supportedValues`, `kind`, `displayStyle`,
  an input option's `keyboardType`).
- Value types: `String` primitive 0, `Bool` 1, `Int` 2, `Double` 7, `Date` 8, `CLPlacemark` 10
  (with the types each resolves from: `Double` and `Int` from 0, 2 and 7, `Date` and `CLPlacemark`
  from themselves);
  `IntentFile` `intents` 12; `[T]` an `array` of T with capabilities 3, resolving from none; an
  `AppEnum` `linkEnumeration`; an `AppEntity` `entity`, with `dynamicOptionsSupport` 1 when its
  default query is an `EntityQuery`, 2 for an `EntityStringQuery`.
- `Summary("Add \(\.$text)")` gives `actionConfiguration.actionSummary` with the format string
  `Add ${text}` and the parameters it names; the parameters a `Summary { \.$a \.$b }` lists (after
  its format string or alone) are its `otherParameterIdentifiers` (`summaries`).
- `When(\.$p, .equalTo, true) { … } otherwise: { … }` gives `whenClause` with the condition
  (`comparisonOperator` 2, the parameter, `{"bool": {"value": true}}`) and the two summaries;
  `Switch(\.$p) { Case(.c) { … } … DefaultCase { … } }` gives `switchStatement` with the parameter
  and its cases, each with its configuration, `isDefaultCase` and, but for the default, its enum
  case as a one-element array (`summaries`). The strings data's `Localizable` lists the format
  strings of every `Summary`, nested ones too. Other operators, values and `Case`s of several
  values are refused.
- An enum parameter's default is written as its case's name (`string`, `summaries`).
- A `URL` is the primitive 11, resolved from 11 and 0 (a parameter, a result, an entity property);
  an `Int`'s `inclusiveRange` is written as a `Double`'s; a `Measurement<UnitLength>` is
  `{"measurement": {"wrapper": {"unitType": 1}}}` with `LNValueTypeMetadataKeyMeasurementUnitAdjustsForLocale`
  0 and `LNValueTypeMetadataKeyMeasurementUnitType` 1 (other units are refused); a `DeleteIntent` has
  the system protocol `com.apple.link.systemProtocol.DeleteEntity` and its `entities`' entity
  metadata, as an open intent its `target`'s; `@available` on an enum gives its
  `availabilityAnnotations` (`more`).
- Titles and descriptions may be `LocalizedStringResource(_:defaultValue:table:)` (also inside
  `IntentDescription(…)`): `defaultValue` and `table` are written beside `key` (`controls`,
  `sweep`: bluewallet's `table: "InfoPlist"`); a `comment:` is left out (`comments`: netnewswire's).
- `@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)` gives `availabilityAnnotations` with
  `LNPlatformNameIOS`, `LNPlatformNameMACOS` and `LNPlatformNameWATCHOS` (`LNPlatformNameVISIONOS`
  for visionOS, `sweep`), each version as written
  (`18`, `17.0`), beside the wildcard (`controls`); nomac refuses other platforms, unavailable or
  deprecated ones, and `@available` on types other than intents.
- A `ControlConfigurationIntent` is written as a widget configuration intent with the system
  protocol `com.apple.link.systemProtocol.ControlConfiguration`; a `SetValueIntent` gets
  `com.apple.link.systemProtocol.SetValue` and stays discoverable; a `CustomIntentMigratedAppIntent`
  is keyed and identified by its `intentClassName` and has `customIntentClassName` (`controls`).
- A `SetFocusFilterIntent` has the system protocol `com.apple.link.systemProtocol.FocusConfiguration`,
  a `LiveActivityIntent` `com.apple.link.systemProtocol.SessionStarting`; an intent with several
  lists them in that order, each in `systemProtocolMetadata` with an empty value (`sessions`:
  gomap's live activity intents, home-assistant's focus filter, a live activity intent by an
  extension). An explicit `isDiscoverable = false` also sets `visibilityMetadata.isDiscoverable`.
- A `Date` parameter's `kind:` gives `LNValueTypeMetadataKeyDateFormat`, `.date` 0 and
  `.dateTime` 2; an array parameter's `size:` per widget family gives
  `LNValueTypeMetadataKeyCollectionSizes` with each family's `max` and `min` (`sessions`).
- The result's protocols (the compiler lists them without `IntentResult`) set `outputFlags`:
  `OpensIntent` 1, `ShowsSnippetView` 2, `ProvidesDialog` 4, added up (`results`: a dialog and a
  snippet view 6); `ReturnsValue<String>` gives `outputType` and no flag.
- A `WidgetConfigurationIntent` is not discoverable (`isDiscoverable` false, its
  `visibilityMetadata` unchanged), has `outputFlags` 8 and the system protocol
  `com.apple.link.systemProtocol.WidgetConfiguration`, and no output type (`Never`).
- A static property that is no App Intents requirement is the app's own and is not read.

## Entities, queries, enums

- An entity: `displayTypeName` from `typeDisplayRepresentation`, `defaultQueryIdentifier` its
  query's full name, `properties` from `@Property(title:)`; its other stored properties are not
  listed.
- A `TransientAppEntity` has `transient` true and no `defaultQueryIdentifier`; an entity that
  conforms to `IndexedEntity` (an extension may add it) has the system protocol metadata
  `com.apple.appintents.entity.Indexed`; `TypeDisplayRepresentation(name:)` gives the display name,
  with its `defaultValue`; `@available` on an entity or query gives its `availabilityAnnotations`;
  property titles may be string resources, a property may be optional (`isOptional`), and a `URL`
  property is the primitive 11 (`entities`).
- An `OpenIntent` has the system protocol `com.apple.link.systemProtocol.OpenEntity`, opens the
  app unless it says otherwise, and its `typeSpecificMetadata` holds its `target`'s entity
  metadata (as `entities` lists it) and type name; an intent returning an entity has it as
  `outputType` (`entities`). A transient entity as a parameter is refused.
- A query: `capabilities` 66 for an `EntityQuery`, 70 for an `EntityStringQuery`, whatever methods
  it implements (`queries`); dependencies on an intent's parameters
  (`@IntentParameterDependency`) add nothing.
- An enum: its cases' display representations (a string, or `DisplayRepresentation(title:subtitle:)`,
  `.init(title:)` too), whether `caseDisplayRepresentations` is stored or computed, `nonisolated`
  or not; its own `typeDisplayName` is not read (`results`). `enums` are in name order, whatever
  their source order (`results`, three builds).

## App Shortcuts

`autoShortcuts` lists each `AppShortcut(intent:phrases:shortTitle:systemImageName:)` with its
phrases (`\(.applicationName)` as `${applicationName}`, a parameter `\(\.$mood)` as `${mood}`, a
literal as written) and the provider's `availabilityAnnotations`. A computed `appShortcuts` that
returns arrays comes as a builder: Xcode keeps its expressions and leaves out what is behind
`if #available` (`buildLimitedAvailability`; `sweep`, after bluewallet). `shortcutTileColor` is 14,
or the provider's own (`.blue` 7, `sweep`).

## Training

`appintentsnltrainingprocessor` (`AppShortcutsTraining`) reads `extract.actionsdata` and the
Info.plist; without App Shortcuts it writes nothing ("No AppShortcuts found - Skipping."). It
refuses an Info.plist whose `CFBundleIdentifier` is not `--bundle-id` ("Mismatch bundle identifier
values between Info.plist and --bundle-id."). Run on its own (`basic`), the metadata processor
writes no `root.ssu.yaml`: the training generates it into `--temp-dir-path` and copies it into
`Metadata.appintents`, then writes the trainings: one, English, into `Metadata.appintents/nlu/`
for an app without `.lproj` folders; one per `.lproj` folder of the product, Base included, into
`<locale>.lproj/nlu.appintents/` for an app with them (`localized`: 31 folders; icecubes: 19).

`root.ssu.yaml` writes each shortcut as an SSU intent named `<Intent>_<index>` with its title and
its phrases as English utterances behind `{${+prefix} }` (`${applicationName}` as
`${+applicationName}`, a parameter as `${<its type>}`), a `+negative` intent, and the variables:
`+applicationName` (the Info.plist's `CFBundleDisplayName`, else `CFBundleName`, else the bundle's
name), each enum and entity parameter type of the shortcuts' intents, used in a phrase or not (an
enum's case titles in declaration order, an entity's displayed type name), and `+prefix` and
`+standardAppShortcutNegatives`, which refer to YAML lists of Xcode's
`SiriSSUKitModel.framework/Resources` (`prefix/en.yaml`: "hey Siri", "Siri";
`standardAppShortcutNegatives/en.yaml`: 37 requests such as "close ${+applicationName}"), which
`nomac sdk` keeps. Scalars follow a YAML emitter's rules (`quoting`, icecubes): plain
(`Mike's Notes`, `What's new?`, `100%`, `Say "hi"`, `Café`, `Send image(s) to Mastodon`), unless
they start with an indicator (`- `, `? `, `: `, or one of ``#,[]{}&*!|>'"%@` ``), contain `: ` or
` #`, end with `:`, start or end with a blank (`'Anasayfa '`) or would read as another YAML type
(`'123'`, `'true'`, `'null'`); then single-quoted, a `'` doubled (`'Log: today''s #1 entry'`, the
utterances' `'{${+prefix} }What''s new'`).

The training reads synonyms as templates too (`quoting`): `{…}` is an optional part (`{set}` gives
an utterance without it and one with `set`); a backslash may escape `$`, `|`, `(`, `)`, `{` and
`}`, and a synonym where it escapes another character is left out with a warning ("\ should be
followed by one of the supported escaped chars"). Unbalanced or empty braces (`a\{b}`, `{}`) make
Xcode's training fail: it warns, writes no `nlu/` and the build goes on. nomac refuses those,
alternatives (`|`, `( )`) and escaped characters, no experiment having shown their utterances.

Localized (`localized`), each corpus and each variable has one entry per locale, in set order (it
changes from build to build like the parameter variables'):
- A locale's phrases are those its `AppShortcuts.strings` translates, when it translates any of
  the shortcut's (`de` translates one of `Search`'s two and trains only that one), else the
  English ones; `Localizable.strings` translates no phrase (`fr`).
- `+applicationName` is the locale's `InfoPlist.strings` `CFBundleDisplayName`, else the bundle's
  (`de`: `Notizen`); an enum's case titles and an entity's displayed name are translated by the
  locale's `Localizable.strings` (`de`: `Froh`; icecubes' `zh-Hans`: `App 账户` for `AppAccount`).
- The phrase lists are those of the locale's name (da, de, en, es, fi, fr, it, ja, ko, ms, nb,
  nl, pt, ru, sv, th, tr) or `pt` for `pt-BR`; `en-GB`, `en-AU`, `de-CH`, `es-MX`, `fr-CA`, `pt-PT`,
  `zh-Hans`, `zh-Hant`, `zh-HK`, `ca`, `pl`, `uk` and Base have none, and the lists `zh_CN`,
  `zh_HK`, `zh_TW` and `yue_CN` serve none of them. A locale without lists has its utterances
  plain, without `{${+prefix} }`, its negative intent `utterances: []`, and no `+prefix` or
  `+standardAppShortcutNegatives` definition. nomac refuses a locale it has not observed whose
  language has lists, and an app whose only folder is Base.
- The lists' entries are YAML scalars: plain ones lose their surrounding blanks (`es`, `it`, `pt`,
  … have entries with a leading or trailing space), quoted ones use `\uXXXX` and `\xXX` escapes
  (`ko`, `ru`, `pt`).

`nlu/nlu.lzfse` is LZFSE-compressed as Apple's reference encoder compresses (NomacLZFSE gives the
same bytes), a FlatBuffers buffer laid out by the format's reference builder (back to front,
fields in the order added, identical vtables shared). The root has a 16-bit 1, a header, the locale
`en` and one group whose second field holds one bundle: its identifier, its intents and the negative
utterances. The header holds the digest (32 hexadecimal digits), the training's time (seconds since
1970, 64 bits), an empty vector and "1.0". An intent holds its SSU name, the parameters its phrases
use (each type with its first synonym, in set order: `phrases`, three builds; nomac in the order the
phrases first use them) and its utterances; an utterance a byte 1 and a table with the text. Objects are created in the order: digest, empty vector, "1.0", header, locale,
bundle identifier, then per intent its name, parameter, utterances (each text, its table and the
utterance), their vector and the intent, then the intents' vector, the negatives, the bundle, the
group and the root. A template expands to the cartesian product of its parts, the leftmost varying
slowest: the optional prefix first left out, then "hey Siri" and "Siri", each variable its
synonyms in order (`training`: prefix, then phrase, then parameter value; the negatives prefix by
prefix).

A locale's buffer is the English one's with the locale's name (`pt-BR`, `Base`), phrases,
synonyms (the parameter's first in that locale) and lists; without lists, no prefixes and no
negatives (`ca`).

`nlu/<digest>.version` holds one byte 0. The digest changes with `root.ssu.yaml` and only with it
(twelve direct runs of the training, three builds of `basic`: two variable orders give two
digests), but no MD5, SHA-1 or SHA-256 of the file, its parts, the phrase lists or JSON forms of it
gives it, and it differs from locale to locale; nomac writes the MD5 of the locale's name, a colon
and `root.ssu.yaml` (B-159). Since Xcode orders the parameter
variables by set order, its digest changes from build to build anyway; `compare` judges `nlu.lzfse`
with the header's digest and time left out ("identical but for its header's hash and time":
`basic`, `training`), and with those two fields equal the compressed files are byte-identical.

`nomac verify` decompresses both `nlu.lzfse` (NomacLZFSE's decoder): two that differ only in the
header's time are equivalent (`appintents.training-time`; Xcode's runs 2 and 3 of `basic`), and
so are two that read the same, an intent's parameters as a set (`appintents.set-order`); a
different digest is reported with Xcode's, and so is the `.version` file of another name (missing
and extra).

A round over the digest's 128 bits (2,721 combinations, `basic`'s two orders and `training`):
MD5, every SHA-1, SHA-2, SHA-3, SHAKE, BLAKE2, RIPEMD-160 and SM3 digest truncated to 16 bytes
from either end, FNV-1 and FNV-1a 128, MurmurHash3 x64_128, and 64-bit halves (XXH64 with seeds
0 and 1, FNV-1 and FNV-1a 64, CRC-64 ECMA and XZ) or 32-bit quarters (CRC-32, Adler-32), in both
byte orders, over `root.ssu.yaml` (as written, without its final newline, in UTF-16), the YAML
joined with the English phrase lists in every order, and the decompressed FlatBuffers without the
header (which cannot hold it: `basic`'s two orders give the same buffer and different digests).
None matched.
