# Resources: Metal and Core ML

Branch `res/metal-coreml`. BACKLOG B-240–B-249, ADRs 0240–0249. Decision record: ADR 0240.
Formats: docs/formats/coreml.md. Experiments: `.github/scripts/coreml_experiments.py` (needs a
Python with coremltools 9.0: `python3 -m venv <dir> && <dir>/bin/pip install coremltools==9.0`).

## Current step

Core ML (2026-11-03): `nomac coremlc compile` and `generate --language Swift` reproduce Xcode
27.0's coremlc for the types stored as `spec` archives and for ML programs, identically on every
observed model (`coreml_compare.py` over `coreml_experiments.py`'s observations: compile 303
identical, generate 902; refused: neural networks, pipelines, tree ensembles, a non-ASCII name).
`nomac verify` reruns Core ML tasks of a reference build (`coreml` checks); on a capture of a
self-written app (`corpus/scripts/capture_reference.py` with a local manifest): 14 identical, 1
equivalent (Xcode's run-to-run metadata order), 3 refused. On Linux (Swift Build at the fork's
`79a7d991`, patch 10), `nomac build` of that app with its six supported models succeeds and its 32
Core ML outputs match Xcode's (30 identical, 2 equivalent).

## Just finished

- `metadata.json` key orders fitted (Foundation tables filled in a fixed order, then copied; a
  fixed-shape multi-array's own order); validated on 60 random models.
- Swift classes: the template per feature kind, availability, Swift 5/6, public access, escaped
  names (156-name experiment).
- ML programs: MIL text, `generic` archives, Core ML's operation revisions for the histogram
  (127 operations, every opset), precisions, `FlexibleShapeInformation`; 9 random programs.
- `nomac what`, `coremlc` and `what` launchers, the `coreml` tool checks, the `coreml:` domain's
  verified types.

## Feasibility (2026-11-03)

- Where they occur: survey of 3,249 repositories, 27 with shaders (82 `.metal`), 15 with models
  (26 `.mlmodel`, one `.mlpackage`); corpus: signal, one shader; holdout: mlx-swift-examples,
  nine shaders in the mlx-swift package (B-244); no Core ML in corpus, holdout or sweep.
- Core ML (`coremlc`), reimplementable: outputs deterministic for models with at most one
  `userDefined` metadata entry, otherwise Xcode's own map order changes run to run; the
  deployment target changes nothing; archives, analytics hash (SHA-256 of the input), JSON
  summary and partial Info.plist decoded for simple types; ML programs are MIL text printed from
  the protobuf (generic over operations) plus the package's weights byte for byte; template
  classes. Neural networks need a per-layer Espresso translation (B-242).
- Metal: Xcode 27.0's Metal Toolchain is a MobileAsset (838 MB); it was installed, and macOS
  purged it on 2026-11-02 21:14 (the catalog's `.purged` copy in
  /System/Library/AssetsV2/com_apple_MobileAsset_MetalToolchain). Downloading it again stalled:
  `xcodebuild -downloadComponent MetalToolchain` received nothing, once in 30 minutes and once in
  an hour. Xcode's own metallib determinism is not measured yet. No open-source AIR compiler exists; the
  Windows tools need the owner's Apple account and license acceptance (ADR 0240).

## Next actions

1. Objective-C classes (B-240): the observations are recorded (`coreml_experiments.py` generates
   Objective-C for every model); the template is next.
2. Pipelines and tree ensembles; neural networks layer by layer (B-242); operations missing from
   the histogram table (B-245).
3. Metal: waiting for the owner (ADR 0240): the Windows tools under Wine, and the Metal Toolchain
   download on the Mac to measure Xcode's metallib.

## Reproducing

```sh
python3 -m venv /tmp/cml && /tmp/cml/bin/pip install coremltools==9.0
DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer /tmp/cml/bin/python .github/scripts/coreml_experiments.py <out>
python3 .github/scripts/coreml_compare.py <out>/coreml/observations.json .build/debug/nomac
```
