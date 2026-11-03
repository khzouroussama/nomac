# Core ML models: what Xcode 27.0's coremlc writes

Observed with `.github/scripts/coreml_experiments.py` on self-written models (coremltools 9.0's
public protobuf classes and builders), Xcode 27.0 (27A266a). The model format itself is public:
coremltools' `mlmodel/format/*.proto` (BSD-3-Clause). Nothing here comes from coremlc's code.

## Tasks

Swift Build plans two tasks per model of a Sources phase (`CoreMLCompiler.swift`, `CoreML.xcspec`):

```
coremlc compile <model> <products>/<App>.app/ --deployment-target 18.0 --sdkroot <iPhoneOS27.0.sdk> \
  --platform ios --output-partial-info-plist <TARGET_TEMP_DIR>/<Name>-CoreMLPartialInfo.plist --container bundle-resources
coremlc generate <model> <DERIVED_FILE_DIR>/CoreMLGenerated/<Name> <the same options> --language Swift --swift-version 6.0
```

The rule names are `CoreMLModelCompile <products>/<App>.app/ <model>` and
`CoreMLModelCodegen <model>`. To plan code generation, Swift Build first runs the generate command
with `--dry-run yes` after the output directory; coremlc then prints the paths it would write, one
per line (`<dir>/GLM.swift`), and writes nothing. Before either, it reads coremlc's version with
`/usr/bin/what -q <coremlc>`: `PROGRAM:coremlcompiler  PROJECT:CoreML-3600.25.1`. Off macOS, nomac's
Swift Build looks `what` up through the tool search paths (patch 10, docs/upstream/swift-build.md),
where `nomac toolchain install` puts nomac's `what`, and nomac's `coremlc` launcher carries that string.

`--language` is `Swift` or `Objective-C` (from `COREML_CODEGEN_LANGUAGE`, else the target's
predominant language); Swift adds `--swift-version` and, with public visibility,
`--public-access`. Objective-C writes `<Name>.h` and `<Name>.m`, Swift `<Name>.swift`.

## What compile writes

Into the output directory: `<Name>.mlmodelc/` and the partial Info.plist, an XML property list
with one key whatever the model:

```
<key>LSBundleContainsCoreMLmlmodelc</key>
<true/>
```

The model directory holds, for every type, `coremldata.bin`, `metadata.json` and
`analytics/coremldata.bin`; then per type:

| Model type | Other files |
|---|---|
| GLM regressor and classifier, scaler, identity | none |
| tree ensembles | `_B0000.DAT` (the trees, a binary table) |
| pipelines | `model0/`, `model1/`, ... each a compiled model directory's `coremldata.bin` |
| neural networks | `model.espresso.net` (JSON), `model.espresso.shape` (JSON), `model.espresso.weights`, `model/coremldata.bin`, `neural_network_optionals/coremldata.bin` |
| ML programs (`.mlpackage`) | `model.mil` (the program as MIL text), `weights/weight.bin` (the package's, byte for byte) when it has weights |

`--deployment-target` (13.0, 16.0, 18.0) changes nothing in these outputs; for an ML program
below its minimum it adds a warning (`This model is not supported on specified deployment target
of ios 13.0. It requires 16.0 or greater`) and still writes them.

### Run-to-run variations

A model whose `userDefined` metadata has several entries (every coremltools conversion has three:
`com.github.apple.coremltools.version`, `.source`, `.conversion_date`) compiles differently from
one run to the next: the map's entries are re-serialized in `coremldata.bin`, and listed in
`metadata.json`, in an order that changes (six runs of one ML program: five different
`coremldata.bin`, two different `metadata.json`). A comparison takes those entries without their
order. Models with at most one entry compile identically every time.

### `coremldata.bin`

An archive whose first 32-bit word is the number of the `Model.proto` field the model's type sets
(`glmRegressor` 300, `glmClassifier` 400, `scaler` 604, `identity` 900, `pipelineRegressor` 201,
`treeEnsembleRegressor` 302, `neuralNetwork` 500, `mlProgram` 502), then a kind string with its
64-bit length at offset 0x1c: `spec` or `generic`.

A `spec` archive (GLM regressor and classifier, support vector regressor, one-hot encoder,
imputer, feature vectorizer, scaler, categorical mapping, normalizer, array feature extractor,
identity: coreml-experiments `types`) is 72 bytes of header (words:
type, 1, then zeros; the kind; at 0x28 the specification version as a 32-bit word; zeros up to
0x48) followed by the whole `Model` message re-serialized: the fields in their order with
`ModelDescription.metadata` (field 100) present, empty when the model has none. The message ends
the file; no length is written.

A `generic` archive keeps only the `ModelDescription` (64-bit length at 0x4b, the message at
0x53), then data of the type (an ML program: the type again as 64 bits and 8 zero bytes; a tree
ensemble: the name `_B0000.DAT` of its table). A pipeline's kind string is the kinds and names of
its models (`generic.model0v1.0.0spec.model1v1.0.0spec`).

### `analytics/coremldata.bin`

Groups of key-value strings, each string preceded by its 64-bit length: a group name, the
group's entry count as 64 bits, then the entries. Groups and keys are in alphabetical order. `SpecificationDetails` has `modelHash`, the
base64 SHA-256 of the input file (a package's root `model.mlmodel`), and `modelName`, the
model's file name without extension. Neural networks and ML programs add
`NeuralNetworkModelDetails` first (`containsCustomLayer`, `modelDimension`, ...).

### `metadata.json`

An array of one object, pretty-printed by `NSJSONSerialization` (two-space indent,
`"key" : value`, empty arrays and objects on two lines), each dictionary's keys in the order of a
Foundation hash table (docs/formats/foundation-collections.md). The keys of the top object:
`metadataOutputVersion` ("3.0"), `outputSchema`, `modelParameters`, `specificationVersion`,
`isUpdatable` ("0"), `stateSchema`, `availability`, `modelType` (`{"name" :
"MLModelType_<type>"}`), `userDefinedMetadata`, `inputSchema`, `generatedClassName`, `method`
("predict"), and when the model has them `shortDescription`, `version`, `author`, `license`,
`classLabels`, `mlProgramOperationTypeHistogram` (`"Ios16.linear" : 1`), `computePrecision`,
`storagePrecision`, `neuralNetworkLayerTypeHistogram`. Every value but `specificationVersion` and
counts is a string.

`availability` follows the specification version (tvOS and Mac Catalyst as iOS):

| Version | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| iOS | 11.0 | 11.2 | 12.0 | 13.0 | 14.0 | 15.0 | 16.0 | 17.0 | 18.0 |
| macOS | 10.13 | 10.13.2 | 10.14 | 10.15 | 11.0 | 12.0 | 13.0 | 14.0 | 15.0 |
| watchOS | 4.0 | 4.2 | 5.0 | 6.0 | 7.0 | 8.0 | 9.0 | 10.0 | 11.0 |
| visionOS | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 2.0 |

A feature's dictionary has `name`, `shortDescription`, `type`, `formattedType`, `isOptional` and
per type: multi-arrays `dataType`, `shape` (`"[1, 3]"`), `hasShapeFlexibility`, and when flexible
`shapeFlexibility`, `shapeRange`; dictionaries `keyType`; images `width`, `height`,
`colorspace`, `isColor`, `hasSizeFlexibility`. `formattedType` reads `Double`, `Int64`,
`MultiArray (Double 3)`, `MultiArray (Float32 1 × 2)`, `Dictionary (Int64 → Double)`.

Each dictionary's keys are in the iteration order of a mutable Foundation table filled in a fixed
order, then copied (`FoundationHashTable.inserting(_:).copied()`); the orders were fitted on the
`tools`, `metadata` and `types` observations and hold on 60 random models nomac was not fitted on
(`validation`, `coreml_compare.py`):

- the top object (ML programs add their histogram and precisions): `author`, `outputSchema`, `license`, `availability`, `modelType`,
  `classLabels`, `modelParameters`, `version`, `shortDescription`, `metadataOutputVersion`,
  `method`, `specificationVersion`, `inputSchema`, `stateSchema`, `isUpdatable`,
  `generatedClassName`, `userDefinedMetadata`, then the histograms and precisions;
- a feature: `sizeRange`, `enumeratedShapes`, `shapeRange`, `hasSizeFlexibility`,
  `sizeFlexibility`, `shape`, `type`, `enumeratedSizes`, `valueType`, `width`,
  `shapeFlexibility`, `keyType`, `name`, `hasShapeFlexibility`, `dataType`, `isColor`,
  `colorspace`, `isOptional`, `shortDescription`, `formattedType`, `height`; except a multi-array
  of fixed shape, whose dictionary fills in another order (`shape`, `name`, `type`,
  `hasShapeFlexibility`, `isOptional`, `dataType`, `shortDescription`, `formattedType`): no one
  order fits both;
- `availability`: alphabetical; `userDefinedMetadata`: the specification's order.

Values: a range reads `1...` without an upper bound (`-1`), `32...128` with one, `3` when both
ends are equal; dimensions join with ` × `, enumerated shapes and sizes with ` | `
(`"1 × 3 | 2 × 3"`), and `shapeRange`, `sizeRange`, `enumeratedShapes`, `enumeratedSizes` are
lists (`"[[1, -1], [3, 3]]"`). An optional feature's `formattedType` ends with `?`. Images:
`colorspace` `RGB` (`isColor` `1`, `Image (Color 64 × 32)`) or `Grayscale`. Sequences:
`valueType`, `sizeRange` (`"[1, 0]"`), `Sequence (Int64 1...0)`. Classifiers list their labels
in `classLabels` (numbers or strings).

nomac's `coremlc compile` writes every file identically for the 277 observed models of these
types (`tools`, `metadata`, `types`, the 60 random `validation` models and 156 `names`); it refuses the types it does not compile yet, FLOAT16 and INT8
arrays, BGR images, updatable models, state features, functions, specification versions above 9
and file names that are not identifiers, none of which is observed.

## ML programs

A `.mlpackage`'s root `model.mlmodel` holds a `Model` whose type is `mlProgram`: the program in
coremltools' public `MIL.proto`. coremlc writes (coreml-experiments `programs`, `opsets`,
`program-validation`):

- `coremldata.bin`, a `generic` archive: words type (502) and archive version (5 for
  specification versions 6 and 7, else the specification version: 8, 9), the kind `generic`
  with its length at 0x1c, the specification version at 0x2b, the description's length at 0x4b
  as 64 bits, the description (with an empty `metadata` when it has none), then 502 and 0 as
  64-bit words.
- `analytics/coremldata.bin`: `NeuralNetworkModelDetails` (`containsCustomLayer` `0`,
  `modelDimension` `0`) then `SpecificationDetails`, whose `modelName` is the specification
  file's, `model`, and whose `modelHash` is that file's SHA-256.
- `metadata.json` with `mlProgramOperationTypeHistogram`, `computePrecision` and, when the
  program reads weights from a file, `storagePrecision`.
- `model.mil`, the program as text, and every weight file it reads (`weights/weight.bin`),
  copied byte for byte.

`model.mil`:

```
program(1.0)
[buildInfo = dict<tensor<string, []>, tensor<string, []>>({{"coremlc-component-MIL", "3600.16.1"}, {"coremlc-version", "3600.25.1"}, ...})]
{
    func main<ios16>(tensor<fp32, [1, 3]> x) {
            tensor<fp32, [2]> b = const()[name = tensor<string, []>("b"), val = tensor<fp32, [2]>([0x1p+0, 0x1p+0])];
            tensor<fp32, [1, 2]> y = linear(bias = b, weight = w, x = x)[name = tensor<string, []>("y")];
        } -> (y);
}
```

- The program version is `1.0` for the iOS 15, 16 and 17 opsets (`CoreML5` to `CoreML7`,
  printed `ios15` to `ios17`) and `1.3` for iOS 18 (`CoreML8`); from `1.3` a scalar is printed as
  its type alone (`string("x")`, `int32(4)`, `dict<string, string>`).
- `buildInfo` gets coremlc's two entries; its entries are sorted by key.
- The function's inputs are sorted by name; operations keep their order; an operation's
  arguments and attributes are sorted by name; an argument of several values is `(a, b)`; an
  operation with several outputs lists them before `=`; the file ends with `}` and no newline.
- Values print with their type, `tensor<int32, [2]>([0, 1])`, nested by dimension; numbers as
  C's `%a` prints a double (`0x1.8p+1`, `0x0p+0`), half-precision ones too; booleans `true` and
  `false`; weights in a file as `BLOBFILE(path = ..., offset = tensor<uint64, []>(64))`.
- An input with ranges of shapes in the description gets a function attribute
  `[FlexibleShapeInformation = tuple<...>((("DefaultShapes", {{"x", [1, 3]}}), ("RangeDims",
  {{"x", [[1, 32], [3, 3]]}})))]`, which the package's program does not have.

`mlProgramOperationTypeHistogram` counts the operations but constants, each under a name: its
type in upper camel case in an iOS 15 program (`SliceByIndex`), and in later opsets
`Ios<version>.<lower camel case>`, the version of the operation's last revision up to the
program's opset. The revisions are Core ML's, not coremltools' (`Ios16.relu` in an iOS 17
program); they were read for 127 operations in every opset (`MILOperations`). The keys are
inserted in the order the operations first appear, then copied; tables of 124 to 127 keys keep
the mutable table's order.

`computePrecision` names the data types of every operation's outputs, constants included,
booleans and strings left out: `Float32`, or `Mixed (Float16, Float32, Int32)` with the names
sorted (`Float16`, `Float32`, `Int32`, `UInt32`). `storagePrecision` names those of the constants
read from a weight file the same way.

nomac compiles every observed program identically (15 written for the cases above, four of
every operation in each opset, nine random ones); it refuses operations whose counted name is not
observed (B-245), nested blocks, several functions, enumerated input shapes, and data types other
than `bool`, `string`, `fp16`, `fp32`, `int32`, `uint32`, `uint64`.

## What generate writes

One Swift file per model, `<Name>.swift` (317 lines for a GLM regressor), a template filled from
the model's description (coreml-experiments `metadata`, `types`, `validation`, `names`: 830
generations, Swift 5.0, 5.0 with `--public-access` and 6.0):

- A header naming the file, `@preconcurrency import CoreML` for Swift 6, `import CoreML` for 5.
- `<Name>Input : MLFeatureProvider`: a property per input in the description's order, commented
  `/// <description, else name> as <phrase>`; `featureNames`; `featureValue(for:)`; an initializer
  taking the required inputs, then the optional ones (`= nil`); convenience initializers for each
  way to pass images and arrays but the designated one, in the order shaped arrays; `CGImage`
  (`<name>With`, optional `<name>From`), with arrays then shaped arrays; URLs (`<name>At`), the
  same; then per image input `set<Name>(with:)` for a `CGImage`, then for a URL.
- `<Name>Output : MLFeatureProvider`: a property per output reading the provider, and for an
  array `<name>ShapedArray`; an initializer from the values; `init(features:)`.
- `<Name>`: the loading initializers and `load` functions, the structured predictions, a
  convenience prediction taking the inputs (and one taking shaped arrays when there are arrays),
  batch predictions.

Phrases: `double value`, `integer value`, `string value`, `dictionary of strings to doubles`,
`dictionary of 64-bit integers to doubles`, `3 element vector of doubles`, `1 by 3 matrix of
floats` (`32-bit integers`), `color (kCVPixelFormatType_32BGRA) image buffer, 64 pixels wide by
32 pixels high` (`grayscale (kCVPixelFormatType_OneComponent8)`), `sequence of strings`,
prefixed `optional ` for optional inputs. Images are converted with
`kCVPixelFormatType_32ARGB` (color) or `kCVPixelFormatType_OneComponent8`.

Availability: every class is marked with the model's availability (the specification version's,
as in `metadata.json`); a member is marked too when the API it uses is newer than the model's iOS
version: configurations and batch predictions (iOS 12.0), images from `CGImage` and URLs (13.0),
completion handlers (14.0), shaped arrays and `async` loading (15.0), `async` prediction (17.0).
Below iOS 14.0 the class also has a deprecated `init()`, and `init(configuration:)` has no default
value.

`--public-access` adds `public` to every declaration but `init(model:)`, the bundle URL and the
provider. Swift 6 writes `any` before `MLFeatureProvider` and `Error`.

Names: a feature's property and parameters take its name with every character other than an
ASCII letter, digit or `_` replaced by `_`, `_` before a leading digit, and `_` after a reserved
word (Swift's keywords but those added since Swift 5, Objective-C's and C's, and `input_`; not
C++'s, nor the classes' own members); `featureNames`, `featureValue(for:)` and the comments keep
the name. A name outside ASCII is written empty (`名前`) or refused by coremlc (`café`).

nomac's `coremlc generate --language Swift` writes every one of the 830 observed files
identically; it refuses non-ASCII names, image inputs whose name it would escape, arrays of more
than two dimensions, sequence outputs, optional sequences, Objective-C and `--globalmodule`,
none of which is observed (B-240).
