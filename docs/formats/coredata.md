# Core Data models in Xcode's builds

Observed with Xcode 27.0 (27A266a) on macOS 27.0.1: `.github/scripts/coredata_experiments.py`
(self-written models compiled with the command lines below; `build` records them from a build;
`version-hashes` reads Core Data's public `versionHash` and `versionChecksum`) and the 34 models of
the corpus checkouts. `nomac momc` (`NomacCoreData`, ADR 0270) writes what this file describes;
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
Each is `.swift` when the model's `sourceLanguage` is Swift, `.h` then `.m` when Objective-C. A
model without such entities prints nothing. A versioned model uses its current version; which one
it uses without one is not settled (`versioned-no-current` uses its first listed version,
`versioned-empty-current` another), so nomac refuses that case (B-258).

The files (`momc --action generate`, 133 observed models of both languages, `coredata_compare.py`)
start with the same comment: `//`, `//  <file name>`, `//  ` (two spaces), `//`, `//  Created by
<the user's full name> on <M/d/yy>.`, `//`, `//  This file was automatically generated and should
not be edited.`, `//`. Properties come attributes first, then relationships, each in file order
(`relationships-order`); scalars only for attributes with `usesScalarValueType="YES"`. A class of
another module (`Other.Mod`) is named without it.

Swift (`type-*`, `to-many`, `ordered`, `inheritance`, `codegen-order`, `relationships-order`):

- Every file continues `public import Foundation`, `public import CoreData`; the properties file
  then has `import <Module>` for a relationship to a class of another module, or an empty line.
- `+CoreDataClass.swift`: `public typealias <C>CoreDataClassSet = NSSet`, `@objc(<C>)` (an empty
  line for a class of another module), `public class <C>: <parent class or NSManagedObject> {}`.
- `+CoreDataProperties.swift`: `public typealias <C>CoreDataPropertiesSet = NSSet`, an extension
  with `fetchRequest()` and one `@NSManaged nonisolated public var` per property (`Int16`, `Int32`,
  `Int64`, `Double`, `Float`, `Bool` scalars, otherwise optional `NSNumber`, `NSDecimalNumber`,
  `String`, `Date`, `Data`, `UUID`, `URL`, the transformable's `customClassName` or `NSObject`, the
  destination class, `NSSet` or `NSOrderedSet`); then a `// MARK: Generated accessors for <r>`
  extension per to-many relationship (insert, remove and replace methods first when ordered); then
  `extension <C> : Identifiable {}` for entities without a parent.
- `<input>+CoreDataModel.swift`: `<input>FoundationFrameworkSet` and
  `<input>CoreDataFrameworkManagedObject` typealiases.

Objective-C (moonlight, `objc-*`):

- `+CoreDataClass.h`: `#import <Foundation/Foundation.h>`, then `#import <CoreData/CoreData.h>` or
  the parent's `"<Parent>+CoreDataClass.h"`; `@class` with the classes of the relationships'
  destinations and the transformable attributes (`NSObject` without `customClassName`), but the
  entity's own, in byte order; the `@interface`; `#import "<C>+CoreDataProperties.h"`.
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
5.0 for both languages), numeric attributes without `usesScalarValueType`, scalar dates, a class of
the current module (`.Name`) with `class` generation, parents of another module, Objective-C
categories that need `@class`, relationships to classes of several modules, and classes whose
names differ only by case (on a Mac's case-insensitive volume their files overwrite each other,
`version-strings`).

## Standard error

momc compiles the versions in the order of a Foundation table of their paths
(`<input>/<version>.xcdatamodel`, docs/formats/foundation-collections.md), filled in the order the
directory lists them: on a Mac's default APFS volume, by the 22-bit CRC-32C of the case-folded,
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
| `E.r should have an inverse [2]` | a to-one relationship without `inverseName` |
| `E.r does not have an inverse; this is an advanced setting (no object can be in multiple destinations for a specific relationship) [7]` | a to-many relationship without `inverseName` |
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
  transient.
  - Attribute: `SHA256(own, attributeType, 01 if allowsExternalBinaryDataStorage, 01 if
    preservesValueInHistoryOnDeletion)`.
  - Relationship: `SHA256(own, destination entity's name, inverse relationship's name, maxCount,
    minCount, 01 00 if ordered)`.
  - Not inputs: `isIndexed`, `isIndexedBySpotlight`, `renamingIdentifier`, `userInfo`,
    `valueTransformerName`, `defaultValue`, `allowsCloudEncryption`, validation predicates, the
    value class name, the delete rule.
  - Fetched properties: only `isOptional` changed the hash among the inputs tried, and no small
    preimage fits (no corpus model has one; nomac refuses them).
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
| `NSManagedObjectModel` | `NSEntities`, `NSFetchRequestTemplates`, `NSVersionIdentifiers` (`{""}`), then momc's two keys |
| `NSEntityDescription` | `NSEntityName`, `NSClassNameForEntity`, [`NSIsAbstract`], `NSManagedObjectModel` (conditional), `NSSuperentity` (conditional), `NSSubentities`, `NSProperties`, `NSUserInfo`, `NSVersionHashModifier`, `NSRenamingIdentifier` (`elementID` or the name), [`NSUniqueTuples`], [`NSFetchIndexDescriptions`, `NSCompoundIndexes`] |
| `NSAttributeDescription` | [`NSIsOptional`], [`NSIsTransient`], `NSRenamingIdentifier` (`elementID` or the name), `NSPropertyName`, `NSEntity` (conditional), [`NSValidationPredicates`, `NSValidationWarnings`], [`NSUserInfo`], `_P`, `NSAttributeType`, `NSAttributeValueClassName`, `NSDefaultValue`, `NSValueTransformerName`, `NSFlagsKey` |
| `NSRelationshipDescription` | [`NSIsOptional`], [`NSIsOrdered`], `NSRenamingIdentifier` (`elementID` or the name), `NSPropertyName`, `NSEntity` (conditional), `_P`, `NSMaxCount`, `NSMinCount`, `NSDeleteRule`, `NSDestinationEntity` (conditional), `_NSDestinationEntityName`, `NSInverseRelationship` (conditional), `_NSInverseRelationshipName` |
| `NSFetchIndexDescription` | `NSIndexName`, `NSIndexElements` (an `NSArray`), `NSEntity`, `NSPartialIndexPredicate` (nil) |
| `NSFetchIndexElementDescription` | `NSPropertyName`, `NSFetchIndexElementType` (0, 64-bit), `NSFetchIndexDescription`, `NSAscending` |
| `NSFetchRequest` (a model's `<fetchRequest name entity/>`) | `NSValuesToGroupBy`, `NSHavingPredicate`, `NSFetchOffset`, `NSValuesToFetch`, `NSEntity` (conditional), `NSPredicate`, `NSSortDescriptors`, `NSFetchLimit`, `NSBatchSize`, `NSRelationshipKeyPathsForPrefetching`, `NSResultType`, `NSAllocationType`, `NSHasFetchRequestFlags` (true), `NSFetchRequestFlags` (30) |

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
  properties (own ones only) once. `NSUserInfo` is one empty `NSDictionary` shared by every entity,
  or an `NSDictionary` of the file's entries.
- `NSClassNameForEntity`: `representedClassName`, `--module` prepended when it starts with `.`
  (`.ImageAttachment` → `T.ImageAttachment`), nil for `NSManagedObject` (`omo-default-class`);
  `customClassName` is kept as written (`.`).
- `NSAttributeValueClassName`: `customClassName`, or by type `NSNumber` (integers, Double, Float,
  Boolean), `NSDecimalNumber`, `NSString`, `NSDate`, `NSData`, `NSUUID`, `NSURL`, nil for
  Transformable.
- `NSDefaultValue`: `defaultValueString` read as `NSString.integerValue` for integers (`0.0` and
  `YES` are 0), `YES`/`NO`/`1`/`0` for Boolean, a float or double, a string;
  `defaultDateTimeInterval` floored to a whole minute as an `NSDate` (`NS.time`; 1030 and 1000.7
  give 960, -59 gives -60: `omo-date-defaults`), one object per value.
- `_P`: attributes `0x81`, `+2` optional, `+8` transient, `+0x30` without validation, `+0x40` without
  user info (`0xF1` for a plain required attribute); relationships `0xF1`, `+2` optional, `+0x400`
  ordered. `NSFlagsKey`: 4 with `allowsExternalBinaryDataStorage`, else 0.
- `elementID` on an entity, attribute or relationship is its `NSRenamingIdentifier` as written,
  an empty one included; it is no version hash input (`renaming-entity`, `renaming-relationship`,
  `renaming-empty`, `renaming-all`).
- Validation from `minValueString`/`maxValueString`: `NSArray`s of `NSComparisonPredicate`s, the
  minimum first (`>=`, operator and variant 3; `<=`, 1), and of warning codes (numbers: 1620 too
  small, 1610 too large; strings: 1670, 1660). Numbers compare `SELF` (one `NSSelfExpression` per
  model) with a 64-bit constant; strings compare a new `NSKeyPathExpression` (`valueForKey:`,
  `SELF`, `[length]`) per predicate.
- Fetch indexes: indexed attributes in momc's order (`by<Name>Index`), then the older
  `<compoundIndexes>` (`compoundIndex`), or the file's `<fetchIndex>` elements. With
  `minimumToolsVersion` Xcode 8.0 or older, an indexed attribute's index is named after the
  attribute and has no entity (`indexed-tools-*`; 9.0, 14.0 and Automatic name it `by<Name>Index`).
  `NSCompoundIndexes` lists the property names of every index of several elements that are all
  attributes (wikipedia: an index with a to-one or to-many relationship is left out).
- With `minimumToolsVersion` Xcode 4.1 to 9.0, an attribute without `syncable="YES"` has the user
  info `com.apple.syncservices.Syncable = NO`; 14.0 and Automatic add nothing.

Not observed yet, refused by nomac (BACKLOG B-257): configurations, fetched properties, fetch
requests with predicates or limits, property version
hash modifiers, transient relationships, user info on relationships or with validation, default
values of other types, validation of other types, models of several compound indexes, copied
tables of more than 85 keys (B-259).

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
explained, which ADR 0230 shows equivalent; it refuses fetch indexes and attributes that are not syncable under a `minimumToolsVersion` before Xcode 9.0
and defaults of other types than integers, Boolean, String, Double, Float and Date (B-256).

- **Conventions**: integers are big-endian (u16, u32, u64); u64 fields are 8-aligned from the start
  of the file. Sections end with a separator, `0xDEADBEEF` written little-endian twice, unaligned.
  Strings and data are interned per table: entry 0 is the empty value, the others come in first-use
  order, and fields hold entry indexes.
- **Layout**: `momv2$` and a fixed 58-character ASCII string (64 bytes); a header of 23 u32; then
  the sections U (UTF-16 strings, at 172), C (C strings), B (data), K (lookup tables), P (properties),
  E (entities), F (fetch request templates) and S (the SQL model, to the end). The header
  holds each section's offset and entry count, and the numbers of entities, properties,
  attributes and relationships.
- **U**: `""`, entities' renaming identifiers (`elementID` or the name), version hash modifiers,
  string defaults, transformer names, properties' renaming identifiers (UTF-16LE,
  length-prefixed). **C**: `""`, fetch request names,
  `PF_DEFAULT_CONFIGURATION_NAME`, entity, class, property and value-class names, and SQL column
  names (`_pk`, `_ent`, `_opt`, attributes, `_Z<NAME>` for to-one foreign keys), these in the
  iteration order of an immutable copy of a Foundation dictionary of the entity's columns
  (docs/formats/foundation-collections.md "Immutable copies"; seven columns are copied from 13
  buckets into 13). **B**: a keyed
  archive of `""`, then the entity and property version hashes ("Version hashes" above) and
  user-info archives.
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
  one (`omo-rel-ordered`).
  An entity's fetch indexes (indexed attributes as `by<Name>Index`, then the compound index, then
  `<fetchIndex>` elements, as in the `.mom`) follow its U name and three zero words: their count,
  then per index the u64s name (C), 0, element count and, per element, property name (C), 0,
  ascending (1) or descending (0), 0. Index names and their properties' names enter C after the
  entity's class name (`omo-fi-class`), and header words 21 and 22 count the model's indexes and
  elements (`omo-fi-several`, `omo-fi-indexed-compound`, `omo-indexed`, `omo-fetch-index`).
  Uniqueness constraints follow the indexes: a zero word and their count, then per constraint the
  u64s 0, 0, its count of properties and each property's name (C), a to-one included; the entity's
  flag word gains `0x1800`, and the S section's first word 8 when any entity has constraints
  (`omo-uq-several`, `omo-uniqueness`).
- **F**: the count of fetch request templates, then per template, between `0xBEEFCAFE` markers, a
  76-byte record: 1 at offset 32, its entity's index at 36, 326 at 72. Templates come in the order
  of a copy of a dictionary of their names, as in the `.mom`; their names enter C right after
  `""`, and their lookup table follows the entities' (`omo-fr-several`, `omo-fetch-request`).
- **S** starts with 7 (8 added with constraints), the count of entities and the count of
  templates, then one aligned u64 per template (its index) when there are any, then 1 and
  `PF_DEFAULT_CONFIGURATION_NAME`.
- **S**: per entity, the C indexes of its SQL column names, in the iteration order of a hash table.
  Besides `_ent`, `_pk`, `_opt`, attributes, to-many names and to-one `_Z<NAME>` and name, a
  destination gets, for each to-many without an inverse, a hidden to-one named the source's
  entity number and the relationship's name (`1bs`, `_Z1BS`: `omo-rel-no-inverse`), and the
  to-one side of an ordered to-many its order key `_Z_FOK_<NAME>` (`_Z_FOK_A`, `_Z_FOK_1BS`:
  `omo-rel-ordered`, `omo-ordered`). Many-to-many relationships with inverses add nothing
  (`omo-rel-many-to-many`, `omo-rel-ordered-many-to-many`).
  That table is not Foundation's (see B-256 for what it is and is not).

Every observed `.omo` of a model nomac compiles is identical, or equivalent once column-name lists
and families are sorted and lookup tables compared by their keys (`coredata_compare.py`, ADR
0230 to 0232); nomac refuses none of the corpus's current versions.

**Inheritance**: a superentity gets a subentities lookup table (its direct subentities) after
its properties table; an entity's members are, per group, the inherited properties first (the
root's first), then its own, each entity's by UTF-8 name, and a property record's index is its
position there. An entity record's fields after its name are the superentity (one word 0, or
`0x01000000` and its index), the root entity's index (its own without a superentity), the
subentities (one word 0, or `0x01000000`, the K index of their table, their count and each one's
index as a u64), then the K index of its first table. A subentity's lists before the ranges are
packed on 4-byte boundaries: 2n zero words and one more, then per member either 0 and its record
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
