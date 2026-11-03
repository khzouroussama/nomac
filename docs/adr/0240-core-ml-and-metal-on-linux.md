# ADR 0240: Core ML models compiled by nomac; Metal shaders refused until the owner chooses a compiler

- Status: proposed (Core ML accepted for implementation; Metal awaits the owner's decision)
- Date: 2026-11-03

## Context

Xcode compiles `.mlmodel` and `.mlpackage` files with `coremlc` and `.metal` files with `metal`
and `metallib` (in Xcode 27.0 a separate component, `xcodebuild -downloadComponent MetalToolchain`). All three
are macOS binaries. How often apps need them: in the 3,249-repository survey
(`feature_survey.py`), 27 projects have Metal shaders (82 files) and 15 have Core ML models (26
`.mlmodel`, one `.mlpackage`); in the corpus, signal has one shader
(`SpoilerParticleShader.metal`); in the holdout, mlx-swift-examples compiles nine shaders of the
mlx-swift package; no corpus, holdout or sweep app has a Core ML model.

**Core ML.** The model format is public (coremltools' protobuf specifications, BSD). What
`coremlc` writes was observed on self-written models (docs/formats/coreml.md): an archive around
the re-serialized specification, a JSON summary, a hash of the input, template classes; ML
programs as MIL text, printed from the program's protobuf, with the weights copied. These are
reproducible from observation and the public specification. Neural networks are the exception:
each layer becomes an Espresso layer with its own fields and weight layout, a translation per
layer type.

**Metal.** A shader is compiled to AIR (LLVM bitcode for Apple's GPU target, with Apple's
metadata) and linked into `default.metallib`. The options:

- (a) Apple's Metal Developer Tools for Windows, run under Wine on Linux. Apple publishes them for
  building Metal shaders on Windows for iOS, tvOS and macOS, with the same command-line options as
  the macOS tools; they are downloaded with an Apple developer account, under Apple's license.
  Releases follow Xcode's (forum reports name 5.3 "for Xcode 16.3"). Unknown until measured:
  whether a release matches Xcode 27.0's compiler, whether it runs under Wine, and whether its
  output is byte-identical to Xcode's.
- (b) An open-source path to AIR: none exists. LLVM has no AIR target; projects that translate
  shaders (SPIRV-Cross) write Metal source, not AIR. Writing one would mean reproducing Apple's
  compiler from its outputs.
- (c) Refuse with a `nomac check` finding, and build such apps on a Mac.

## Decision

1. **Core ML: `NomacCoreML` reimplements `coremlc compile` and `generate`**, each model type
   from experiments on self-written models and the public specification, in the order of B-240:
   archived specifications, classes, ML programs, then pipelines and tree ensembles; neural
   networks layer by layer (B-242). Swift Build's version probe off macOS is B-243. Until a type
   is compiled, `nomac check` reports `coreml:model=<type>` unverified.
2. **Metal: (c) now.** `nomac check` reports `metal:shader` unverified (B-241), so a Linux build
   is known to need a Mac before it stops at `CompileMetalFile`.
3. **Metal: (a) is the route to measure**, if the owner agrees: the owner downloads the Windows
   tools of the release matching Xcode 27.0 with their Apple account, as they download Xcode,
   and accepts Apple's license for them; nomac installs them into the user's developer directory
   from that download and runs them under Wine; nothing of them is committed or published. The
   measurement decides: byte-identical `.air` and `default.metallib` for self-written shaders and
   signal's, or (c) stays.

## Consequences

- Core ML outputs are compared as Xcode writes them, except the order of `userDefined` metadata
  entries, which Xcode itself changes from run to run (docs/formats/coreml.md).
- Option (a) adds Wine to the Linux build machine's requirements for apps with shaders only, and
  a download the user makes with an Apple account; `nomac check` will say both.
- The README's "Metal and CoreML" line gets a check kind when the first model type compiles.
