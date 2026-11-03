# ADR 0011: The envelope: features nomac has verified, and `nomac check`

- Status: accepted (extends ADR 0004)
- Date: 2026-10-22

## Context

ADR 0004 says when one app's outputs match Xcode's. It does not say what nomac can promise for
an app nobody has compared: "build it and see" finds a difference only after the fact, and only
in the outputs someone compares. The owner wants a number that holds before the fact ("97% of
apps are covered") and no silent failure for the rest.

What decides nomac's outputs is a finite set of things a project can use: object types and keys
of the project file, their values where the value changes the output, how build settings are
written, scheme elements and attributes, workspace items and settings, test plan keys, package
manifest API. nomac's handling of each is either confirmed by a comparison with Xcode or not.

## Decision

1. **Features.** A feature is one thing a project uses, named `<namespace>:<path>[=<value>]`
   (docs/formats/check.md): `pbxproj:PBXNativeTarget.productType=com.apple.product-type.application`,
   `settings:CODE_SIGN_STYLE=condition-and-plain-in-xcconfig`, `scheme:LaunchAction/RemoteRunnable`.
   Files are read as written, not through a model, so keys and elements nomac does not know are
   features too. Shapes that involve several objects (a target without a product reference, a
   proxy whose product is not in the referenced project) are features of their own.
2. **Verified** means nomac's output for the feature equals Xcode 27.0's in a documented
   comparison:
   - `corpus:<app>`: a corpus app whose every `nomac verify` check is identical uses the feature
     (ADR 0004; generated into `LoaderEnvelope+Corpus.swift` by `.github/scripts/envelope_corpus.py`);
   - `<script>:<experiment>`: an experiment in `.github/scripts` whose observation docs/formats
     records and nomac implements, with its tests;
   - `envelope-experiments:<experiment>` also for every feature a case of that experiment uses
     whose `nomac verify` checks (PIF, `-list`, every target and scheme's settings) are all
     identical, as for a corpus app (generated into `LoaderEnvelope+ExperimentCases.swift` by
     `envelope_experiments.py --table`, from the cases' files as compared);
   - for families too large to list, a rule backed by an experiment (the host conditions a Mac
     answers, package-experiments `conditions`; the copy-files destinations 0 to 17,
     loader-experiments `copy-files`).
   A feature that is not verified is **unverified** when nomac knows it differs or has not been
   observed (with its BACKLOG item or reason), and **unknown** when the envelope does not list it.
   Both are outside the envelope. A known difference wins over corpus evidence: an app that
   happened to match does not hide a BACKLOG item.
3. **The envelope** is the set of verified features. It is per Xcode build (27.0, 27A266a): a new
   reference Xcode (BACKLOG B-013) starts from the experiments and corpus again.
4. **`nomac check <project or workspace> [--json]`** lists every feature the container uses and
   reports each one outside the envelope with the file and object that use it; it exits with 1
   when any is outside. Parts it did not read (with `--description-only`, the contents of
   synchronized folders and the presence of referenced files; without `--source-packages`, remote
   manifests) are listed as not checked, never assumed inside.
5. **Keeping it true.** Every rule that lands moves features in with its evidence in the same
   change: an experiment's entry names it, a corpus app that becomes identical is added by
   regenerating the corpus table, a difference found becomes an unverified entry with its BACKLOG
   item. Tests check that every citation exists (corpus app, experiment name, BACKLOG item) and
   that the experiment lists the envelope copies are the scripts' own. `nomac verify`'s `envelope`
   check fails when an app entirely inside the envelope differs from Xcode, since a verified
   feature would then be wrong, and lists what an app that matches would add to it.
6. **Domains.** The loader is the first domain (`LoaderDomain`: PIF, `-list`,
   `-showBuildSettings`). Each workstream adds its own as a `FeatureDomain` in its module, with
   its namespace (`assets:`, `ib:`, `strings:`, `coredata:`, `signing:`, ...), a scan of the files
   it reads and an `Envelope` with its evidence, and registers it in `CheckCommand.domains`. A
   domain without a scan reports nothing, so `nomac check` speaks only for the domains listed in
   its output; the survey's coverage is the loader's until the others land.
7. **Coverage** is the share of surveyed apps with no feature outside the envelope
   (`.github/scripts/feature_survey.py`: the open-source-ios-apps list, sparse checkouts of the
   project-description files, `nomac check --json --description-only`), with its 95% Wilson
   interval. The headline is the loader's: the share of apps with no loader feature outside its
   envelope. The survey also gives each domain's share (loader, assets, signing, ...) and the
   share of apps inside every domain, each with its interval, so readers see where every domain
   stands without the headline falling while the younger domains mature. The features to verify
   next are ranked by how many apps each brings inside the loader's envelope.

## Consequences

- The promise is per feature: every feature an app inside the envelope uses has matched Xcode
  somewhere. Interactions between verified features are covered by the corpus and the fuzzer
  (`fuzz_experiments.py`), not by the envelope itself.
- The closed world makes the first coverage low (5.8% of 1,490 apps, 2026-10-22): most apps use
  something no corpus app or experiment has, often harmless (`objectVersion = 46`, committed
  per-user schemes). Each such feature is one experiment away, and the survey says which first.
- Package manifests are read as text against PackageDescription's vocabulary, not evaluated;
  SwiftPM and the vendored builder (ADR 0010) do what Xcode does with them, so only the API names
  and host conditions that reach nomac's own answers are features.
