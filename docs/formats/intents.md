# Intent definitions (`.intentdefinition`)

An intent definition is an XML property list: `INIntents`, `INEnums`, `INTypes` and the
definition's versions and namespace. Swift Build runs Xcode's intentbuilderc twice on it
(`SWBApplePlatform`'s intents compiler):

- **IntentDefinitionCodegen**: `intentbuilderc generate -input <file> -output
  <DerivedSources>/IntentDefinitionGenerated/<name> -classPrefix <PROJECT_CLASS_PREFIX>
  -language Swift -swiftVersion <version> -visibility <public|private|project>
  [-moduleName <module>]`. While planning, Swift Build runs the same command with `-dryRun` and
  takes the paths it prints, one per line, as the task's outputs. The empty class prefix is an
  empty argument (the build log shows it as two spaces).
- **IntentDefinitionCompile**: `intentbuilderc compile -input <file> -output
  <product resources>/<lproj>/ -classPrefix <prefix>`, the definition written back into the
  product (BACKLOG B-232: its `INIntentHash`).

`nomac intentbuilderc generate` writes Xcode 27.0's Swift for every definition observed:
`intents_experiments.py` runs about 360 self-written definitions and the 14 of the corpus and the
holdout, in the build's variants (Swift 5 and 6, each visibility, a class prefix, a module name);
`intents_compare.py`: 2,226 of 2,226 Swift outputs identical. Objective-C is B-233.

## Reading

Values are read as intentbuilderc reads them: a number written as a string or a boolean is that
number (`"01"`, `1` and `true` are 1), a boolean is true when it is `true`, a non-zero number or
`YES`, and a missing one is false. Parameters, response parameters and custom-type properties are
taken in display priority order (`INIntentParameterDisplayPriority`), ties in file order.

## Generated files

One file per custom intent (`<prefix><Name>Intent.swift`; a `System` intent has none), per enum
whose `INEnumGeneratesHeader` is true (`<prefix><Name>`) and per custom type (`<prefix><Name>`;
`INTypeClassName` or `INEnumClassName` replaces the whole name), in that order, each in the
definition's order. File names are written and printed decomposed (NFD), as macOS's file system
representation gives them. `-swiftVersion` and `-moduleName` change nothing; `-visibility project`
declares everything `internal` where the others say `public`. Selectors keep the unprefixed
names (`successWithResolvedThing:` in `XYThing`; intents' `handleProbe:completion:`).

Every file starts with the generated-file header, `#if canImport(Intents)` and `import Intents`
(then `import CoreLocation` when a parameter, response parameter or property is a Placemark or a
Location), and ends with `#endif`.

An intent's file declares, in this order: the deprecated `<prefix><Intent><Enum>` enums of the
enums without headers its parameters use; the `INIntent` subclass with an `@NSManaged` property
per parameter; the `…Handling` protocol; the response code enum (`unspecified = 0` to
`failureRequiringAppLaunch`, then the custom codes from 100); the `INIntentResponse` subclass with
its parameters' properties, `code`, `init(code:userActivity:)` and, for each code whose format
strings (`INIntentResponseCodeFormatString`, then the concise one) name response parameters, a
static constructor taking them in order of first appearance; then, for each resolvable
parameter of a number, currency or measurement type, its `…UnsupportedReason` enum and
`…ResolutionResult` class.

The handling protocol: an intent eligible for widgets (`INIntentEligibleForWidgets`) declares
resolution methods (parameters with `INIntentParameterSupportsResolution`), dynamic options
(`INIntentParameterSupportsDynamicEnumeration`, and payment methods that are configurable or
resolvable; those with `INIntentParameterSupportsSearch` first, with a `searchTerm`), the
optional `confirm` and the optional `handle`; any other intent declares a required `handle`
first, then resolution, dynamic options and `confirm`. Both end with the default values and the
deprecated options methods of the dynamic parameters.

## Types

| Type | Property | Multiple | Options element | Resolution |
|---|---|---|---|---|
| String, Duration, unknown names | `String?` | `[String]?` | `NSString` | `INStringResolutionResult` |
| Integer | `NSNumber?` | `[Int]?` | `Int` | generated, `INIntegerResolutionResult` |
| Decimal | `NSNumber?` | `[Double]?` | `Double` | generated, `INDoubleResolutionResult` |
| Boolean ¹ | `NSNumber?` | `[NSNumber]?` | `NSNumber` | `INBooleanResolutionResult` |
| DateComponents ¹ | `DateComponents?` | `[DateComponents]?` | `NSDateComponents` | `INDateComponentsResolutionResult` |
| Date, Location, Data, Image | `Date?`, `CLLocation?`, `Data?`, `INImage?` | arrays | the same | the text `(null)` |
| CurrencyAmount ² | `INCurrencyAmount?` | array | `INCurrencyAmount` | generated, `INCurrencyAmountResolutionResult` |
| Placemark, Person, PaymentMethod, URL | `CLPlacemark?`, `INPerson?`, `INPaymentMethod?`, `URL?` | arrays | the same (`NSURL`) | `IN…ResolutionResult` |
| File ¹ | `INFile?` | `[INFile]?` | `INFile` | `INFileResolutionResult` |
| Distance, Mass ¹, Volume ¹, Temperature, Speed ¹, Energy ¹ | `Measurement<UnitLength…>?` | arrays | `NSMeasurement` | generated, `INLength…ResolutionResult` |
| Object | the custom type, `IN<Name>` in the `System` namespace | array | the type | `<Type>ResolutionResult` |
| Double | `Double` | `[Double]` | `Double` | `INDoubleResolutionResult` |
| SpeakableString | `INSpeakableString?` | array | the same | `INSpeakableStringResolutionResult` |
| Integer with `INIntentParameterEnumType` | the enum | `[Int]` | `Int` | `<Enum>ResolutionResult` |

¹ The property has `@available(iOS 13.0, macOS 10.16, watchOS 6.0, *)`, set apart by a blank
line; ² `@available(iOS 12.0, macOS 12.0, watchOS 5.0, *)`. Custom types' own properties (all but
`identifier`, `displayString`, `pronunciationHint`, `alternativeSpeakableMatches`) carry that line
or `@available(iOS 13.0, macOS 11.0, watchOS 6.0, *)`. Generated resolution results of numbers and
currency amounts have three unsupported reasons (`negativeNumbersNotSupported` = 1,
`greaterThanMaximumValue`, `lessThanMinimumValue`), those of measurements one.
