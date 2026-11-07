# Core Data models in Xcode's builds

Observed with Xcode 27.0 (27A266a) on macOS 27.0.1: `.github/scripts/coredata_experiments.py`
(self-written models compiled with the command lines below; `build` records them from a build;
`version-hashes` reads Core Data's public `versionHash` and `versionChecksum`), the 34 models of
the corpus checkouts, and the 365 models of the coverage survey's repositories
(`.github/scripts/coredata_survey.py`: momc's outputs against nomac's, outside the repository).
`nomac momc` (`NomacCoreData`, ADR 0270) writes what this file describes;
`.github/scripts/coredata_compare.py` compares it with momc's outputs.

## Tasks

An iOS build compiles each `.xcdatamodel` or `.xcdatamodeld` into the product, and generates the
classes of entities whose `codeGenerationType` is `class` or `category`:

```
DataModelCompile <app>/ <src>/Model.xcdatamodeld
    momc --sdkroot <iPhoneOS SDK> --iphoneos-deployment-target 27.0 --module T <src>/Model.xcdatamodeld <app>/
DataModelCodegen <src>/Model.xcdatamodeld
    momc --action generate --swift-version 5.0 --sdkroot <SDK> --iphoneos-deployment-target 27.0 --module T \
        <src>/Model.xcdatamodeld <DerivedSources>/CoreDataGenerated/Model
```

Planning runs `momc --dry-run --action generate ...` for the generated file names. The deployment
target does not change the outputs (UnCloudNotes compiled for iOS 9.0, 12.0, 15.0, 17.0, 18.0, 26.0
and 27.0). Targets of other platforms pass `--$(PLATFORM_NAME)-deployment-target` with their SDK,
to momc and mapc alike (`CoreData.xcspec`; rocketchat's watch app: `--watchos-deployment-target
9.0`). Neither changes the outputs either: for watchOS 9.0 and 27.0, the watchOS Simulator, tvOS,
macOS, visionOS and the iOS Simulator, every observed model's compiled files, generated classes,
dry run and messages, and every corpus mapping model's `.cdm`, are iOS's (coredata-experiments
`platforms`: 685 outputs per platform, 0 different; `version-strings`' generated classes, which
overwrite each other, vary from run to run). The tvOS and visionOS Simulators, DriverKit and the
warning switches are not observed (B-236).

## Outputs

- `.xcdatamodel` → `<name>.mom`.
- `.xcdatamodeld` → `<name>.momd/` with one `<version>.mom` per `*.xcdatamodel` inside,
  `VersionInfo.plist`, and `<current version>.omo` when `.xccurrentversion`'s
  `_XCCurrentVersionName` names one of the versions (all 22 corpus models with an `.omo`; the 12
  without have no `.xccurrentversion`, or one with an empty dictionary). nomac writes the `.omo`
  with its SQL column-name lists sorted (ADR 0230) and refuses the records not decoded yet
  (BACKLOG B-256); it is also the one output that changes from run to run (two bytes of
  UnCloudNotes' v4.omo swapped between two runs).
- Codegen: the files "Code generation" lists.

## Code generation

`momc --dry-run --action generate ... <model> <dir>` prints the paths code generation would write,
one per line, and writes nothing (135 observed models, `dry-runs`): for each entity with a
`codeGenerationType`, in file order, `<Class>+CoreDataClass` and `<Class>+CoreDataProperties` for
`class`, `<Class>+CoreDataProperties` for `category`, `<Class>` being `representedClassName` without
its module (`.Mid` → `Mid`, `Other.Beta` → `Beta`, `codegen-order`); then `<input name>+CoreDataModel`
(moonlight's `Limelight.xcdatamodeld` gives `Limelight+CoreDataModel`, not its version's name).
Each is `.swift` when the model's `sourceLanguage` is Swift or missing (`no-language`), `.h` then
`.m` when Objective-C. A model without such entities prints nothing. A versioned model uses its
current version; without one declared, by no `.xccurrentversion` or an empty one, the last file name
in byte order, so `Model.xcdatamodel` before a space sorts after `Model 2.xcdatamodel`
(`no-current-*`, `versioned-no-current`, `versioned-empty-current`, 20 of 20 self-written sets and
the survey's models).

The files (`momc --action generate`, 133 observed models of both languages, `coredata_compare.py`)
start with the same comment: `//`, `//  <file name>`, `//  ` (two spaces), `//`, `//  Created by
<the user's full name> on <M/d/yy>.`, `//`, `//  This file was automatically generated and should
not be edited.`, `//`. Properties come attributes first, then relationships, each in file order
(`relationships-order`); scalars only for attributes with `usesScalarValueType="YES"`. A class of
another module (`Other.Mod`) or of the current one (`.Mod`, `class-in-module`) is named without it.

Swift (`type-*`, `to-many`, `ordered`, `inheritance`, `codegen-order`, `relationships-order`):

- Every file continues `public import Foundation`, `public import CoreData`; the properties file
  then has `import <Module>` for a relationship to a class of another module or a transformable's
  `UIKit.UIColor` (`transformable-module`), or an empty line.
- `+CoreDataClass.swift`: `public typealias <C>CoreDataClassSet = NSSet`, `@objc(<C>)` (an empty
  line for a class with a module, the current one's `.C` too), `public class <C>: <parent class or
  NSManagedObject> {}`.
- `+CoreDataProperties.swift`: `public typealias <C>CoreDataPropertiesSet = NSSet`, an extension
  with `fetchRequest()` and one `@NSManaged nonisolated public var` per property (`Int16`, `Int32`,
  `Int64`, `Double`, `Float`, `Bool` scalars, otherwise optional `NSNumber`, `NSDecimalNumber`,
  `String`, `Date`, `Data`, `UUID`, `URL`, the transformable's `customClassName` or `NSObject`, the
  destination class, `NSSet` or `NSOrderedSet`); then a `// MARK: Generated accessors for <r>`
  extension per to-many relationship (insert, remove and replace methods first when ordered); then
  `extension <C> : Identifiable {}` for entities without a parent.
- `<input>+CoreDataModel.swift`: `<letters>FoundationFrameworkSet` and
  `<letters>CoreDataFrameworkManagedObject` typealiases, `<letters>` being the input's name without
  anything but its ASCII letters (`lil_wallet` is `lilwallet`, `Technex18` is `Technex`, `12` is
  empty: `model-names`, 3 survey models). Class names keep their digits and underscores. Input
  names of other characters are refused (`Äb` gave `Ab`, one observation).

Objective-C (moonlight, `objc-*`):

- `+CoreDataClass.h`: `#import <Foundation/Foundation.h>`, then `#import <CoreData/CoreData.h>` or
  the parent's `"<Parent>+CoreDataClass.h"`; `@class` with the classes of the relationships'
  destinations and the transformable attributes (`NSObject` without `customClassName`), but the
  entity's own and its parent's, in byte order; the `@interface`; `#import "<C>+CoreDataProperties.h"`.
- `+CoreDataProperties.h`: imports `"<representedClassName>+CoreDataClass.h"`, or
  `"<representedClassName>.h"` for a category (`.Mid.h`). `fetchRequest` has
  `NS_SWIFT_NAME(fetchRequest())` unless the entity has subentities. Properties are `(nonatomic)`
  scalars (`int16_t`, `int32_t`, `int64_t`, `double`, `float`, `BOOL`), `(nullable, nonatomic,
  copy)` objects, but `retain` for `NSData`, transformables and relationships (`NSSet<D *>`,
  `NSOrderedSet<D *>`). The to-many relationships' accessors follow in one
  `(CoreDataGeneratedAccessors)` interface, an empty line between relationships.
- `+CoreDataProperties.m`: `fetchRequest` (tab-indented) and one `@dynamic` per property.
- `<input>+CoreDataModel.h` imports each entity's class header (`+CoreDataProperties.h` for a
  category) under its full `representedClassName` (`Other.Beta+CoreDataClass.h`), in byte order.

nomac refuses what was not observed (B-258): another `--swift-version` than 5.0 (Swift Build passes
5.0 for both languages), numeric attributes without `usesScalarValueType`, scalar dates, parents of
another module, relationships to classes of several modules, and classes whose names differ only
by case (on a Mac's case-insensitive volume their files overwrite each other,
`version-strings`).

## Standard error

momc compiles the versions in the order of a copy of a Foundation table of their paths
(`<input>/<version>.xcdatamodel`, docs/formats/foundation-collections.md), filled in the order the
directory lists them (`versions-*`; the copy shows at 7, 12 and 20 versions, which it moves to a
larger table, 8 survey models): on a Mac's default APFS volume, by the 22-bit CRC-32C of the case-folded,
decomposed name in UTF-32, then by the name's length (Apple File System Reference; all 15 observed
listings). For each version it prints, in that order:

```
<version>.xcdatamodel: note: Model <version> version checksum: <base64 of versionChecksum>
```

Then the warnings, each prefixed `<model path>:<Entity>[.<property>]: warning: `, entities in file
order (`sort-order`), properties in momc's order ("`.mom`: order"):

| Warning | When |
|---|---|
| `abstract entity E has no children [1]` | an abstract entity no entity names as parent |
| `E.a is using a nil or insecure value transformer. Please switch to NSSecureUnarchiveFromDataTransformerName or a custom NSValueTransformer subclass of NSSecureUnarchiveFromDataTransformer [2]` | a transformable attribute without `valueTransformerName`, transient or not |
| `Setting the No Action Delete Rule on E.r may result in relationships to deleted objects [7]` | `deletionRule="No Action"`, before the inverse warning |
| `E.r should have an inverse [2]` | a to-one relationship whose `inverseName` is missing or does not name a relationship of the destination (`inverse-missing`, `inverse-attribute`) |
| `E.r does not have an inverse; this is an advanced setting (no object can be in multiple destinations for a specific relationship) [7]` | a to-many relationship likewise |
| `The inverse relationship for E.r does not reciprocate an inverse relationship [2]` | the inverse names another relationship, or none (`inverse-without`; artsy's `Image.artist`) |
| `Ordered relationships are unsupported in SwiftData. [10]` | an ordered relationship with `usedWithSwiftData="YES"` on the model, after its inverse warning (`swiftdata-warnings`) |
| `Abstract entities are not supported in SwiftData. [10]` | an abstract entity likewise, after `abstract entity` (`swiftdata-warnings`) |
| `E.a is set to be stored using a Spotlight external record file, which is deprecated. Use Core Spotlight integration instead. [5]` | `storedInTruthFile="YES"`, transient or not, before its other warnings (`property-flags-*`) |
| `<input>:: warning: Missing current version declaration [0]` | an `.xcdatamodeld` of several versions without a current one, last |

Across versions each message is printed once, with the path of the last version that has it, in the
order of those last versions (mastodon: `translatedContent` is in four versions, only the last
compiled is printed).
The insecure value transformer warning comes only from the current version when there is one
(`warn-transformer-old-version` prints none, `warn-transformer-current` one; wikipedia's
Wikipedia has seven in versions that are not current and none printed), from every version
otherwise (`warn-transformer-no-current`).

## Version hashes (`VersionInfo.plist`)

Observed through Core Data's public API (`version-hashes`: 69 probes, every input varied alone),
then checked on every entity of the 174 corpus and experiment `.mom` files loaded with
`NSManagedObjectModel(contentsOf:)` (548 entities, 5,018 properties) and every observed
`VersionInfo.plist`. Strings enter as their UTF-8 bytes up to the first NUL, with no terminator or
length; integers are 32-bit little-endian.

- **Property**: `own = SHA256(name, flags, 00, versionHashModifier)`, flags 1 for optional and 2 for
  transient (`modifier-attribute`, `modifier-relationship`).
  - Attribute: `SHA256(own, attributeType, 01 if allowsExternalBinaryDataStorage, 01 if
    preservesValueInHistoryOnDeletion)`.
  - Relationship: `SHA256(own, destination entity's name, inverse relationship's name, maxCount,
    minCount, 01 00 if ordered)`. A relationship that is its own inverse hashes as one without an
    inverse (`own-inverse`; two entities' relationships of one name are not: `same-name-inverse`),
    and so does one whose `inverseName` names no relationship of the destination or its parents,
    which the `.mom` archives as no inverse either (`inverse-missing`, `inverse-attribute`).
  - Not inputs: `isIndexed`, `isIndexedBySpotlight`, `renamingIdentifier`, `userInfo`,
    `valueTransformerName`, `defaultValue`, `allowsCloudEncryption`, validation predicates, the
    value class name, the delete rule.
  - Fetched property: `own` alone with flags 6 and 1 for optional: 2 for transient and 4 for
    read-only, which they all are (`fetched-*`; found by search, then checked on the `.omo`s).
- **Entity**: `SHA256(name, isAbstract as one byte, the superentity's hash, the hashes of its
  non-transient properties, inherited ones included, in name order, versionHashModifier, each
  uniqueness constraint's names joined by "." in sorted order)`. An empty entity is `SHA256(00)`.
  Fetch indexes, the class name, the renaming identifier and user info are not inputs.
- **Model** (`versionChecksum`, `NSManagedObjectModel_VersionChecksums`): `SHA256` of the entities'
  hashes in name order, in base64; an empty model's is `SHA256("")`.

Name order is the order of UTF-8 bytes, as observed on ASCII names (every corpus name).

`VersionInfo.plist` is a binary property list Core Foundation writes from momc's objects
("Keyed archives" below for the writer):

```
NSManagedObjectModel_VersionChecksums = {<version>: base64 checksum}
NSManagedObjectModel_VersionHashes = {<version>: {<entity>: 32 bytes}}
NSManagedObjectModel_CurrentVersionName = <current version>      (only with a current version)
```

- Top keys in the order above with a current version; `VersionHashes`, then `VersionChecksums`
  without.
- The two version dictionaries are mutable dictionaries filled in compilation order (37 of 37).
  Each version's entity dictionary is in the order of the model's entities (a dictionary copied
  twice from momc's order), put in a dictionary created with those keys, then again (64 of 64 with
  more than one entity).
- Sharing: a version name is one object in both dictionaries only when it is a tagged pointer of at
  least six characters (`version-strings`: names of 1 to 5 characters are two objects); entity names
  are one object across versions only when tagged (all 128 of `version-strings`); the current
  version name, the checksums and the hashes are always objects of their own.

## Keyed archives

A `.mom` is `NSKeyedArchiver`'s archive of the `NSManagedObjectModel` momc builds: archiving the
model `NSKeyedUnarchiver` reads back from a `.mom` gives the same bytes but for the two keys momc
adds (`CDMCompilerToolVersion` = 25249.0, a double, and `CDMCompilerXcodeVersion` = 270000). The
archiver's rules, observed with self-written `NSCoding` classes and `NSKeyedArchiver` on macOS
27.0.1:

- `{$version: 100000, $archiver: "NSKeyedArchiver", $top: {root: UID 1}, $objects}`, in that order.
- **Numbering**: an object gets the next UID when first encoded, before what it encodes; a
  conditionally encoded object gets one at its first reference and its contents when it is encoded
  unconditionally (a relationship's destination entity); each class's description
  `{$classname, $classes}` gets one right after the first object of that class has been encoded.
  `nil` is UID 0, `$null`.
- **Per-object keys**: a mutable dictionary filled in encoding order with `$class` last, then copied
  (196 of 196 archives of 1 to 49 keys; docs/formats/foundation-collections.md). Collections encode
  `NS.keys` then `NS.objects` as arrays of UIDs.
- **Sharing in the archive** follows object identity: `NSKeyedArchiver` itself never merges equal
  objects (two equal strings, numbers or data archive as two). momc's strings are interned, so a
  string is one archive object per value; numbers are one object per value and width (64-bit
  defaults and validation bounds; an Integer 32's default 0 is not `encodeInt32`'s 0).

The property list is written by Core Foundation's binary writer, depth first (a dictionary, its
keys, then its values), where sharing follows identity too: a string or number already written is
referenced again; booleans and UIDs are written at every use, every reference naming the first one
of that value; containers and data are never shared. Which strings are one object:

- keys and the archiver's constants, one per text;
- strings that fit a tagged pointer (ASCII of up to 7 characters, 8 or 9 from a 64-character
  alphabet, 10 or 11 from its first 32), one per text wherever they come from: the class name
  `NSDate` is also the value class name `NSDate`;
- the archive's other strings and Foundation's class names longer than a tagged pointer
  (`NSDictionary`, `NSMutableDictionary`, `NSMutableArray`, `NSComparisonPredicate`, the
  expression classes), one per text: wikipedia's value class name `NSDictionary` is also the class
  name;
- Core Data's class names and `NSComparisonPredicateOperator`, a new string at each use,
  `$classname` and `$classes` included.

## `.mom`: what each class encodes

Recorded with an `NSCoder` subclass given to each object's `encode(with:)` on every observed `.mom`
(optional keys in brackets):

| Class | Encoded, in order |
|---|---|
| `NSManagedObjectModel` | `NSEntities`, [`NSConfigurations`], `NSFetchRequestTemplates`, `NSVersionIdentifiers` (`{userDefinedModelVersionIdentifier}`, `{""}` without one: `version-identifier`), then momc's two keys |
| `NSEntityDescription` | `NSEntityName`, `NSClassNameForEntity`, [`NSIsAbstract`], `NSManagedObjectModel` (conditional), `NSSuperentity` (conditional), `NSSubentities`, `NSProperties`, `NSUserInfo`, `NSVersionHashModifier`, `NSRenamingIdentifier` (`elementID` or the name), [`NSUniqueTuples`], [`NSFetchIndexDescriptions`, `NSCompoundIndexes`] |
| `NSAttributeDescription` | [`NSIsOptional`], [`NSIsTransient`], [`NSIndexedBySpotlight`], [`NSIsStoredInTruth`], [`NSAllowsCloudEncryption`], `NSRenamingIdentifier` (`elementID` or the name), `NSPropertyName`, `NSEntity` (conditional), [`NSValidationPredicates`, `NSValidationWarnings`], [`NSUserInfo`], [`NSVersionHashModifier`], `_P`, `NSAttributeType`, `NSAttributeValueClassName`, `NSDefaultValue`, `NSValueTransformerName`, `NSFlagsKey` |
| `NSRelationshipDescription` | [`NSIsOptional`], [`NSIsTransient`], [`NSIndexedBySpotlight`], [`NSIsStoredInTruth`], [`NSIsOrdered`], `NSRenamingIdentifier` (`elementID` or the name), `NSPropertyName`, `NSEntity` (conditional), [`NSUserInfo`], [`NSVersionHashModifier`], `_P`, `NSMaxCount`, `NSMinCount`, `NSDeleteRule`, `NSDestinationEntity` (conditional), `_NSDestinationEntityName`, `NSInverseRelationship` (conditional), `_NSInverseRelationshipName` |
| `NSFetchIndexDescription` | `NSIndexName`, `NSIndexElements` (an `NSArray`), `NSEntity`, `NSPartialIndexPredicate` (nil) |
| `NSFetchIndexElementDescription` | `NSPropertyName`, `NSFetchIndexElementType` (0, 64-bit), `NSFetchIndexDescription`, `NSAscending` |
| `NSFetchedPropertyDescription` | [`NSIsOptional`], `NSIsReadOnly`, `NSIsTransient`, `NSRenamingIdentifier` (`elementID` or the name), `NSPropertyName`, `NSEntity` (conditional), [`NSVersionHashModifier`], `_P` (as others', and 4 for read-only), `NSFetchRequest`, `_NSFetchRequestEntityName` (`fetched-*`) |
| `NSFetchRequest` (a model's or fetched property's `<fetchRequest name entity/>`) | `NSValuesToGroupBy`, `NSHavingPredicate`, `NSFetchOffset`, `NSValuesToFetch`, `NSEntity` (conditional), `NSPredicate`, `NSSortDescriptors`, `NSFetchLimit` (`fetchLimit`), `NSBatchSize`, `NSRelationshipKeyPathsForPrefetching`, `NSResultType`, `NSAllocationType`, `NSHasFetchRequestFlags` (true), `NSFetchRequestFlags` (30) |
| `NSComparisonPredicate` (`predicateString`) | `NSLeftExpression`, `NSRightExpression`, `NSPredicateOperator` |
| `NSCompoundPredicate` (`AND`) | `NSSubpredicates` (an `NSArray`), `NSCompoundPredicateType` (1) |
| `NSEqualityPredicateOperator` | `NSOperatorType` (4, `!=` 5), `NSModifier`, `NSNegate`, `NSOptions` |
| `NSVariableExpression` | `NSExpressionType` (2), `NSVariable` |
| `NSFunctionExpression` (`max:(a)`) | `NSExpressionType` (4), `NSSelectorName`, `NSOperand` (an `NSConstantValueExpression` of `NSConstantValueClassName` `_NSPredicateUtilities`), `NSArguments` (an `NSMutableArray`) |

Order: momc archives the entities by name, and each entity's attributes by name, then its
relationships by name, whatever the file's order (`relationships-order`, whose relationships are out
of order and between attributes). Names compare as `localizedStandardCompare(_:)` does
(`sort-order`): underscores, then numbers by value (`a9` before `a10`), then letters ignoring case;
names that differ only by case put lowercase first (`ab`, `aB`, `Ab`, whatever their order in the
file). Xcode writes model files in that order: all 84 corpus versions are, while 15 are not in byte
order (`Camper` before `CampSite`). nomac refuses names of other characters and numbers that differ
only by leading zeros (B-257).

Values:

- `NSEntities`, `NSSubentities`, `NSProperties` and `NSFetchRequestTemplates` are
  `NSMutableDictionary`s; entities in the order of a dictionary copied twice from momc's order,
  properties (own ones only: attributes, relationships, then fetched properties, each by name)
  once. `NSConfigurations`, when the file has `<configuration>`s, is an `NSMutableDictionary` filled
  by name, of `NSSet`s of entities in the order of a table created with the entities' names, in the
  file's order, an entity's hash being its name's (`configuration-*`). `usedWithCloudKit`, and the
  model's `name` and `usedWithSwiftData`, change no file. An entity's `NSSubentities` is a copy of a dictionary filled in
  the iteration order of a copy of a dictionary of every entity that has a parent (302 of 302
  dictionaries of several keys in the survey's models, whose order shows only where names collide:
  `subentities-8` and `subentities-9` order Egg, Food and Quest differently). `NSUserInfo` is one
  empty `NSDictionary` shared by every entity, or an `NSDictionary` of the file's entries.
- `NSClassNameForEntity`: `representedClassName`, `--module` prepended when it starts with `.`
  (`.ImageAttachment` → `T.ImageAttachment`, a new string for each entity: two entities of one
  class archive it twice), nil for `NSManagedObject` or without `representedClassName` (`no-class`,
  `omo-default-class`); `customClassName` is kept as written (`.`).
- `NSAttributeValueClassName`: `customClassName`, or by type `NSNumber` (integers, Double, Float,
  Boolean), `NSString`, `NSDate`, `NSData`, `NSUUID`, `NSURL`, nil for Transformable, and
  `NSDecimalNumber`, a new string for each attribute (`decimal-several`).
- `NSDefaultValue`: `defaultValueString` read as `NSString.integerValue` for integers (`0.0` and
  `YES` are 0), as `NSString.boolValue` for Boolean (`boolean-defaults`: blanks, a sign and zeros,
  then one of `YyTt1-9`: `0.5` and `` false, `01` and `T` true), a float or double, a string, an `NSDecimalNumber` for
  Decimal ("`NSDecimalNumber`" below); `defaultDateTimeInterval` floored to a whole minute as an
  `NSDate` (`NS.time`; 1030 and 1000.7 give 960, -59 gives -60: `omo-date-defaults`), one object per
  value. momc drops the `defaultValueString` of URI, UUID, Binary and Transformable attributes
  (`default-ignored`).
- `_P`: `1` always, `2` optional, `8` transient, `0x30` without validation, `0x40` without user info,
  `0x80` without a version hash modifier, `0x100` indexed by Spotlight, `0x200` stored in truth,
  `0x400` ordered, `0x800` cloud encryption (attributes only; `0xF1` for a plain required property).
  A transient property keeps neither Spotlight nor truth, in its keys or its flags
  (`property-flags-*`). `NSFlagsKey`: 4 with `allowsExternalBinaryDataStorage`, else 0.
- `elementID` on an entity, attribute or relationship is its `NSRenamingIdentifier` as written,
  an empty one included; it is no version hash input (`renaming-entity`, `renaming-relationship`,
  `renaming-empty`, `renaming-all`).
- Validation from `minValueString`/`maxValueString`: `NSArray`s of `NSComparisonPredicate`s, the
  minimum first (`>=`, operator and variant 3; `<=`, 1), and of warning codes (numbers: 1620 too
  small, 1610 too large; strings: 1670, 1660). Numbers compare `SELF` (one `NSSelfExpression` per
  model) with a 64-bit constant; strings compare a new `NSKeyPathExpression` (`valueForKey:`,
  `SELF`, `[length]`) per predicate. A String's `regularExpressionString` follows them: `SELF`
  against a constant string with an `NSMatchingPredicateOperator` (`NSOperatorType` 6, `NSModifier`
  0, `NSFlags` 0), warning code 1680 (`regular-expression`).
- Fetch indexes: the file's `<fetchIndex>` elements, then indexed attributes and relationships in
  momc's order (`by<Name>Index`, `relationship-indexed`), then the older `<compoundIndexes>`
  (`compoundIndex`, `compoundIndex1`, ...: `compound-*`). With `minimumToolsVersion` Xcode 8.0 or
  older (`indexed-tools-*`; 9.0 and later as above), an indexed attribute's index is named after
  the attribute, a compound index of one property counts as that property's index, once, and one
  of several is named `a_b` with an `NSMutableString`, whose `NS.string` is in the object itself;
  indexes have no entity unless the entity has one of several properties (`compound-legacy-*`).
  `<fetchIndex>` under old tools is refused: momc renames it (`a`, not `f`), not explained yet.
  `NSCompoundIndexes` lists the property names of every index of several elements that are all
  attributes (wikipedia: an index with a to-one or to-many relationship is left out).
- With `minimumToolsVersion` Xcode 10.0 or older, an entity, attribute or relationship without a
  `syncable` attribute has the user info `com.apple.syncservices.Syncable = NO` after the file's
  entries; `syncable="NO"` adds nothing, nor does 11.0 and later (`syncable-*`).
- `minimumToolsVersion="Automatic"` in a file whose `lastSavedToolsVersion`, read as an integer,
  is from 2 to 11116 acts as an old Xcode for the last two items; 0, 1, 11117 and later, a missing
  or unreadable value do not (`tools-automatic-*`, found by bisection; 9525.2 reads as 9525).

### `NSDecimalNumber`

A Decimal's default archives as `NSDecimalNumberPlaceholder` (`$classes` `NSDecimalNumberPlaceholder`,
`NSDecimalNumber`, `NSNumber`, `NSValue`, `NSObject`), encoding `NS.exponent`, `NS.length`,
`NS.negative`, `NS.compact` (true unless zero or NaN), `NS.mantissa.bo` (1) and `NS.mantissa` (16
bytes of little-endian 16-bit units, `NS.length` used), each attribute's its own object.
`NSDecimalNumber(string:)` reads the text: blanks, a sign, digits, a point, digits and an exponent,
what follows ignored (`12abc` is 12, `1,5` is 1, `1.2.3` is 1.2); no digits is the one shared NaN
(`abc`, ``, `NaN`: negative, exponent 0, length 0). Trailing zeros go to the exponent (`1.50` is 15
with exponent -1, `100` is 1 with exponent 2); zero keeps the fraction's length as its exponent
(`0.00` is -2) unless negative (`-0.0` is 0). `decimal-defaults` covers these; nomac refuses what
would need rounding, more than 38 digits or exponents outside ±38, and zero with an exponent.

### Predicates

A fetch request's `predicateString` is parsed for the forms observed (`predicate-*`): comparisons
(`==`, `!=`, `<`, `<=`, `>`, `>=`; types 4, 5, 0, 1, 2, 3, `NSVariant` repeating the last four as in
validation) of a key path with an integer, a double-quoted string, a `$VARIABLE` or `max:(keyPath)`,
joined by `AND`. The left side is an `NSKeyPathExpression` as in validation, `valueForKeyPath:` when
it has a dot. Strings the parser makes are new objects, and integers are not the 64-bit numbers of
defaults. Other forms are refused (`OR`, `NOT`, `IN`, `CONTAINS`, `nil`, `TRUEPREDICATE`, floats and
Booleans are observed in the scratch experiments, not implemented: no surveyed model uses them).

Not observed yet, refused by nomac (BACKLOG B-257): other predicate forms, derived attributes,
binary `elements` models, validation of types other than numbers and strings, regular expressions
on other types, a Date's `defaultValueString`, `<fetchIndex>` under old tools.

## Mapping models

A build compiles each `.xcmappingmodel` into the product:

```
MappingModelCompile <app>/<name>.cdm <src>/<name>.xcmappingmodel
    mapc --sdkroot <SDK> --iphoneos-deployment-target 15.0 --module <M> <src>/<name>.xcmappingmodel <app>/<name>.cdm
```

Observed on the corpus's 8 mapping models (`mapping-corpus`) and 318 self-written ones (the
mapc experiments, outside the repository, from the public `NSMappingModel(contentsOf:)`, an `NSCoder`
subclass on what it loads, and mapc's outputs); `--module`, the deployment target and the SDK change
nothing, and mapc prints nothing on success.

- **Input**: `xcmapping.xml`, a Core Data XML store: one `XDDEVMAPPINGMODEL` whose
  `sourcemodeldata` and `destinationmodeldata` (base64) are `NSKeyedArchiver` archives of Xcode's
  model document (`XDPMModel`), and `XDDEVENTITYMAPPING`s with their `XDDEVATTRIBUTEMAPPING`s and
  `XDDEVRELATIONSHIPMAPPING`s. Membership comes from the owner's `idrefs`. The model paths and
  `mappingtypename` are ignored.
- **Models**: entities, properties and their version-hash inputs are read from the archives:
  `XDPMEntity._name`, the stereotypes' `XDUMLPropertyImp._default` values (`XD_PSK_isAbstract`,
  `XD_PPSK_isOptional`, `XD_PPSK_isTransient`, `XD_PAttK_attributeType`,
  `XD_PAttK_allowsExternalBinaryDataStorage`, `XD_PRK_destination`, `XD_PRK_inverseRelationship`,
  `XD_PRK_maxCount`, `XD_PRK_minCount`, `XD_PRK_ordered`), and the parent from
  `XDUMLGeneralizationImp._general`; the hashes are then "Version hashes" above.
- **`.cdm`**: the keyed archive of `NSMappingModel {NSEntityMappings, NSEntityMappingsByName}`.
  Entity mappings are in `mappingnumber` (int16) order. `NSEntityMappingsByName` is a copy of a
  dictionary filled in that order. Each `NSEntityMapping` encodes `NSMappingName`, `NSMappingType`
  (32-bit), `NSSourceEntityName`, `NSSourceEntityVersionHash`, `NSDestinationEntityName`,
  `NSDestinationEntityVersionHash`, `NSSourceExpression`, `NSUserInfo`,
  `NSEntityMigrationPolicyClassName`, `NSAttributeMappings`, `NSRelationshipMappings`. Each
  `NSPropertyMapping` encodes `NSDestinationPropertyName`, `NSValueExpression`, `NSUserInfo` and
  `NSPropertyTransforms`. Property mappings are sorted with `compare(_:options: [.caseInsensitive,
  .numeric])`.
- **Values**:
  - The mapping name is `name`, or `<source>To<destination>`, or the one entity name set.
  - The type: 1 with a migration policy; 2 without a source entity; 3 without a destination
    entity; 5 for different names; otherwise 4 when the source entity's persistent properties all
    match the destination's in kind and hash inputs, else 5.
  - The source expression is
    `FETCH(FUNCTION($manager, "fetchRequestForSourceEntityNamed:predicateString:", <source name>,
    <filter or TRUEPREDICATE>), $manager.sourceContext, NO)` when `autogenerateexpression` is set
    and a source name is given.
  - Attribute values are `$source.<name>` when the source entity has that attribute.
  - Relationship values are `FUNCTION($manager,
    "destinationInstancesForEntityMappingNamed:sourceInstances:", <mapping>, <key path>)`. The
    mapping is `sourcemappingname`, or the one whose destination is the source relationship's.
    When the key path's relationship or the destination relationship leads to an entity with
    subentities, `destinationInstancesForSourceRelationshipNamed:sourceInstances:` is used with the
    relationship's name instead.
- **Identity**: mapc does not intern strings.
  - Each entity name, mapping name, property name and expression string is an object of its own,
    except where one is built from another: the fetch's first constant is the source name object,
    the dictionary keys are the mapping name objects, and a mapping named after one entity uses
    that name object.
  - Tagged strings, selector names and `TRUEPREDICATE` are one object per text.
  - Each entity's hash is one `NSData`, whichever mappings name it.
  - Empty mapping lists are one `NSArray`.
- **Not reproduced** (refused, B-270):
  - stored expressions (`valueexpressiondata`, `sourceexpressiondata`), user info, empty filters;
  - mappings or property names whose order mapc leaves to chance (equal `mappingnumber`s, names
    equal but for case);
  - every case where mapc fails, warns or crashes.
  - Five self-written cases differ: several mappings sharing a non-tagged entity name
    (`rel-R10`, `R13`, `R14`, `R15`) and a model whose inverse names an attribute (`type2-C15`).

## `.omo`

What momc writes for a current version, mapped from the `omo-*` experiments (one input varied at a
time, `omo-n1-*` and `omo-ord-*` for the SQL names) and the corpus's 22 models with one. nomac writes
it (`OptimizedModel`) with each SQL column-name list sorted by UTF-8 name, the one order not
explained, which ADR 0230 shows equivalent; it refuses transient relationships (B-256).

- **Conventions**: integers are big-endian (u16, u32, u64); u64 fields are 8-aligned from the start
  of the file. Sections end with a separator, `0xDEADBEEF` written little-endian twice, unaligned.
  Strings and data are interned per table: entry 0 is the empty value, the others come in first-use
  order, and fields hold entry indexes.
- **Layout**: `momv2$` and a fixed 58-character ASCII string (64 bytes); a header of 23 u32; then
  the sections U (UTF-16 strings, at 172), C (C strings), B (data), K (lookup tables), P (properties),
  E (entities), F (fetch request templates) and S (the SQL model, to the end). The header
  holds each section's offset and entry count, and the numbers of entities, properties,
  attributes and relationships.
- **U**: `""`, entities' renaming identifiers (`elementID` or the name) and version hash
  modifiers, then per property its version hash modifier, renaming identifier, transformer name
  and string default (`modifier-strings`; UTF-16LE, length-prefixed). **C**: `""`, fetch request
  names, `PF_DEFAULT_CONFIGURATION_NAME`, entity, class, property and value-class names, a Decimal
  default's description, and SQL column names, these in the iteration order of an immutable copy
  of a Foundation dictionary of the entity's columns (docs/formats/foundation-collections.md
  "Immutable copies"; seven columns are copied from 13 buckets into 13). That dictionary is filled
  with `_ent`, `_pk`, `_opt`, then from the root entity down each entity's attributes, to-one
  relationships (`_Z<KEY>`, `_Z<number>_<KEY>` for a destination with subentities, the name) and
  to-many relationships, each by UTF-8 name, plain before ordered, then the hidden to-ones and the
  order keys (766 of 766 entities of the survey's models). Configuration names follow the fetch
  request names, with `PF_DEFAULT_CONFIGURATION_NAME`, in the order of a table filled by name with
  the default last (`omo-configuration-*`). **B**: a keyed archive of the model's
  version identifier (`version-identifier`; the string is `""` without one), then the entity and
  property version hashes ("Version hashes" above) and, per property, its user-info archive and a
  regular expression's archives; last, each fetch request's predicate archive
  (`omo-predicate-*`).
- **K**: per lookup table (entities by name, fetch requests, then per entity its properties,
  subentities, attributes, relationships), the keys' C indexes in slot order and a dispatch tree on
  the key's length and then, among keys of one length, the first byte position with the most
  distinct values, children created breadth first. That rule gives 152 of the 159 distinct
  splits of the observed tables; momc splits seven mastodon, WMFData and `version-shared-names`
  groups at a position of
  fewer distinct values (`timestamp`, `projectID`, `savedInfo`, `pageViews` at 0, not 2), which no
  rule on distinct values, character spans or group sizes explains yet (B-256). Core Data reads a
  table that dispatches on other positions alike as long as every key reaches its slot (ADR 0231).
- **P and E**: one record per property and per entity, in entity order, carrying flags, indexes into
  U, C, B and K, types, defaults, counts and delete rules. Within an entity, properties come in this
  order: persistent attributes, transient attributes, to-one, to-many, then ordered to-many
  relationships, inherited ones first, each group by UTF-8 name. Each entity record also holds 17
  ranges over those groups. Entities come in UTF-8 order (`CampSite` before `Camper`), and an
  entity of class `NSManagedObject` has class index 0 though the name is interned
  (`omo-default-class`).
  A property whose renaming identifier differs from its name, or an attribute with validation,
  has after its name's C index and a word 0 the words 1, whether it has a renaming identifier and
  its U index, then two aligned u64s: the minimum and the maximum (integers and string lengths as
  64-bit integers, Double and Float bounds read as a Double: a Float's `0.1` is Double 0.1), where
  others have one word 0; a minimum adds flag `0x400` and 2 to the attribute's last word, a
  maximum `0x200` and 1 (`omo-val-cases`, `omo-val-float`, `omo-min-max`). The next word is the B
  index of the attribute's user info, a keyed archive of its `NSDictionary` interned after the
  version hash; an entity's is in the word after its constraints (`omo-user-info`)
  (`omo-renaming`, `omo-renaming-cases`: empty, shared and alignment-shifted identifiers).
  A relationship record holds its `maxCount` as written (5 for a to-many of at most 5, 0 when
  unbounded), its `minCount` and its delete rule (`omo-rel-rules`); flag `0x100` marks an ordered
  one (`omo-rel-ordered`), and the word after the optionals block is the B index of its user info
  (`omo-relationship-user-info`).
  A property's flag word gains `0x20` for Spotlight and `0x40` for truth, and so does its entity's
  flag word unless the property is transient (`omo-property-flags-*`); cloud encryption adds `0x8000` there and
  `0x40` to the attribute's last word. The word after the flags is the U index of its version hash
  modifier (`omo-modifier-*`). A Decimal default is 1 and the C index of its description
  (`NSDecimalNumber`'s: `NaN`, `0`, or positional, `1e3` is `1000`, `1E-2` is `0.01`:
  `omo-decimal-defaults`). `syncable` marks enter the user-info archives as in the `.mom`. A
  regular expression's block is two zero u64s, the words 0 and 1, the B index of its predicate's
  archive as a u64, the words 0, 0, 0, 0, 0 and 1, and the u64s 1 and the B index of an archive of
  the number 1680; bounds stay in the optionals block (`omo-regular-expression`).
  An entity's fetch indexes (indexed properties as `by<Name>Index`, or named after the property
  under an old `minimumToolsVersion`, then the compound index, then `<fetchIndex>` elements, as in
  the `.mom`) follow its U name and three zero words: their count,
  then per index the u64s name (C), 0, element count and, per element, property name (C), 0,
  ascending (1) or descending (0), 0. Index names and their properties' names enter C after the
  entity's class name (`omo-fi-class`), and header words 21 and 22 count the model's indexes and
  elements (`omo-fi-several`, `omo-fi-indexed-compound`, `omo-indexed`, `omo-fetch-index`).
  Uniqueness constraints follow the indexes: a zero word and their count, then per constraint the
  u64s 0, 0, its count of properties and each property's name (C), a to-one included; the entity's
  flag word gains `0x1800`, and the S section's first word 8 when any entity has constraints
  (`omo-uq-several`, `omo-uniqueness`).
- **F**: the count of fetch requests, then per request, between `0xBEEFCAFE` markers, a 76-byte
  record: 1 at offset 32, its entity's index at 36, its predicate's B index at 40, its limit at
  64, flags at 72 (326, `0x146`, for a template, `0x46` for a fetched property's). Templates come in
  the order of a copy of a dictionary of their names, as in the `.mom`, then fetched properties' in
  their records' order; template names enter C right after `""`, and their lookup table follows the
  entities' (`omo-fr-several`, `omo-fetch-request`, `omo-predicate-limit`, `omo-fetched-*`).
  Fetched property records: kind 3, flag 4 for optional, then as a relationship's up to the optionals
  block, then 0, their index and their request's index in F; an entity's fifth range after the ten is
  theirs, and its count in the tail includes them twice (`count + fetched`). Header word 9 and
  P's fifth word count them.
- **S** starts with 7 (8 added with constraints), the count of entities and the count of
  templates, then one aligned u64 per template (its index) when there are any, then the count of
  configurations and, per configuration in C's order, its C index, two aligned zero u64s, the
  words 0 and its count of members, and their entity indexes as aligned u64s, in the file's order;
  `PF_DEFAULT_CONFIGURATION_NAME` lists every entity (`omo-configuration-*`).
- **S**: per entity, the C indexes of its SQL column names, in the iteration order of a hash table.
  Besides `_ent`, `_pk`, `_opt`, attributes, to-many names and to-one `_Z<KEY>` and name, a
  destination gets, for each to-many without an inverse, a hidden to-one named the source's
  entity number and the relationship's name (`1bs`, `_Z1BS`: `omo-rel-no-inverse`), and the
  to-one side of an ordered to-many its order key `_Z_FOK_<KEY>` (`_Z_FOK_A`, `_Z_FOK_1BS`:
  `omo-rel-ordered`, `omo-ordered`). Many-to-many relationships with inverses add nothing
  (`omo-rel-many-to-many`, `omo-rel-ordered-many-to-many`).
  That table is not Foundation's (see B-256 for what it is and is not).
  `<KEY>` is the upper-case name, followed by 1, 2, ... for later to-ones of one upper-case name in
  one family, in entity number order (`sibling-keys-*`: `_ZUSER1`, `_Z4_USER1`, `_Z_FOK_USER1`).
  An entity's number counts roots by UTF-8 name, each followed by its subentities by name, depth
  first (68 of 68 `_Z<number>_` columns of the survey's models).

Every observed `.omo` of a model nomac compiles is identical, or equivalent once column-name lists
and families are sorted and lookup tables compared by their keys (`coredata_compare.py`,
`coredata_survey.py`, ADR 0230 to 0232); nomac refuses none of the corpus's current versions.

**Inheritance**: a superentity gets a subentities lookup table (its direct subentities, by UTF-8
name, unlike the `.mom`: 27 of 27 lists of several) after its properties table; an entity's members are, per group, the inherited properties first (the
root's first), then its own, each entity's by UTF-8 name, and a property record's index is its
position there. An entity record's fields after its name are the superentity (one word 0, or
`0x01000000` and its index), the root entity's index (its own without a superentity), the
subentities (one word 0, or `0x01000000`, the K index of their table, their count and each one's
index as a u64), then the K index of its first table. A subentity's lists before the ranges are
n aligned zero u64s, then packed on 4-byte boundaries, per member, either 0 and its record
(own) or 1, padding to 8 bytes when needed, its record, its index here and 7 zero words
(inherited, attribute or relationship), then padding to 8 bytes. The tail's count of the entity's
family (itself and all its subentities) is written twice, before the list of their indexes, whose
order changes from run to run; nomac writes it sorted (ADR 0232). A to-one whose destination has
subentities adds a column `_Z<destination's entity number>_<NAME>` (`omo-inh-fk`: `_Z2_B`).
Experiments: `omo-inh-*`.

**Run to run**: only models with a subentity vary. Two u64 slots of the superentity's record hold
the indexes of the entity and its subentity, in an order that changes between compilations
(`omo-inheritance` bytes 2423 and 2431, uncloudnotes final v4 bytes 4943 and 4951, `0 1` or `1 0`
over three compilations each); the other 70 observed files are identical in all three (`omo-runs`).
That list is the family list above; nomac writes it sorted (ADR 0232).
