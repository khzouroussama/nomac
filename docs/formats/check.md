# `nomac check`: features and the envelope

`nomac check <App.xcodeproj | App.xcworkspace>` lists the features a project uses and reports
those outside nomac's envelope, the features whose handling a comparison with Xcode 27.0 has
confirmed (docs/adr/0011-feature-envelope.md). It exits with 1 when any feature is outside.

```sh
nomac check App.xcworkspace                       # what is outside, and where
nomac check App.xcworkspace --all                 # every feature with its status and evidence
nomac check App.xcworkspace --json                # for scripts (below)
nomac check App.xcodeproj --source-packages ~/Library/Developer/Xcode/DerivedData/App-<hash>/SourcePackages
nomac check App.xcodeproj --description-only      # a checkout of project-description files only
nomac check --envelope                            # the envelope itself
```

## What is read

From the opened container: the workspace's `contents.xcworkspacedata`, its shared
`WorkspaceSettings.xcsettings` and `IDEWorkspaceChecks.plist`, `xcshareddata/swiftpm`
(`Package.resolved`, `configuration`) and per-user data (`xcuserdata`); every project it lists
and every project those reference, transitively; each project's `project.pbxproj`, shared
schemes and per-user data; the base xcconfig of every configuration and what it includes; the
test plans schemes name; the manifests and shared schemes of root and local packages and of their
path dependencies; with `--source-packages`, every checkout in that folder; without
`--description-only`, the contents of synchronized folders and whether referenced files exist.

## Feature identifiers

`<namespace>:<path>[=<value>]`. The loader's namespaces:

| Namespace | Path | Values | Example |
|---|---|---|---|
| `pbxproj` | `<isa>`, `<isa>.<key>`, nested keys of `attributes`, `TargetAttributes`, `settings`, `requirement`, `projectReferences` | `productType`, `sourceTree`, `fileEncoding`, `dstSubfolderSpec`, `buildActionMask`, `proxyType`, `compilerSpec`, build-rule and proxy `fileType`, platform filters, `ATTRIBUTES`, `ProvisioningStyle`, requirement `kind`, exception-set attributes, platform filters and explicit file types, the effective `fileType` of a file reference (`none` or `none-by-contents` without one), a copy-files phase's `dstSubfolderSpec=none` without one; `archiveVersion`, `objectVersion`, `format` | `pbxproj:PBXCopyFilesBuildPhase.dstSubfolderSpec=10` |
| `settings` | `value=list`, `condition=<kind>`, `conditions=several`, `key=unparsed`, `SYMROOT` (a level assigns it in a project opened alone), `SDKROOT=simulator`, `SDKROOT=condition`, `SDKROOT=condition-other` (a condition other than `sdk`, `config` and `arch`); for the settings nomac reads itself (`INFOPLIST_FILE`, `CODE_SIGN_STYLE`, `PROVISIONING_PROFILE_SPECIFIER`, `PROVISIONING_PROFILE`, `GENERATE_INFOPLIST_FILE`, `CODE_SIGN_IDENTITY`, `PRODUCT_NAME`) how they are written | `macro`, `condition`, `xcconfig`, `condition-and-plain` (one configuration), `condition-and-plain-in-xcconfig` (one base xcconfig with its includes) | `settings:CODE_SIGN_STYLE=condition-and-plain-in-xcconfig` |
| `xcconfig` | `file`, `include`, `include-optional`, `directive=<name>`, `line=unparsed`, `value=semicolon` | `missing`, `not-quoted`, `spelled-otherwise-on-disk` (on disk only in another normalization form) | `xcconfig:include=missing` |
| `scheme` | `<parent>/<element>`, `<element>@<attribute>`, `location=shared\|user`, `management=shared\|user`, `management.<key>` | `YES`/`NO` attributes, `BuildableIdentifier`, `launchStyle`, `testExecutionOrdering`, `runnableDebuggingMode`, `version`; containers as `container:xcodeproj`, `container:folder`, ... | `scheme:LaunchAction/RemoteRunnable` |
| `testplan` | key paths to depth 4, `file`, `version` | booleans; `defaultOptions.codeCoverage=targets`, `configurations.id=not-uuid`, `file=missing`, container kinds | `testplan:defaultOptions.codeCoverage=false` |
| `workspace` | `<parent>/<element>`, `<element>@<attribute>`, `target-name=in-several-projects` | `location` schemes; `FileRef=project\|project-missing\|package\|workspace\|playground\|other\|self` | `workspace:FileRef=project-missing` |
| `workspace-settings`, `workspace-checks` | keys of the shared files, `user` | scalar values | `workspace-settings:IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded=false` |
| `package` | `kind=root\|local-dependency\|remote`, `tools-version`, `condition=<host condition>\|swift\|compiler\|flag`, `api=.<call>` and `api=<label>:` of PackageDescription, `import=<module>`, `manifest`, `resolved`, `configuration`, `unsafe-flags`, `dependency=path-missing` | | `package:condition=canImport(UIKit)` |
| `names` | `container` (the opened project or workspace), `pbxproj` (a project-file object), `sync-item`, `sync-key` (an exception set's, `explicitFileTypes`' or an anchored xcconfig's path), `sync-explicit-folder`, `scheme` (a shared scheme's file name), `scheme-container`, `package` (a local package's folder) | `non-ascii`; for `sync-key`, `precomposed` or `decomposed`; for `container`, `whitespace` (a space, tab, CR or LF, which DerivedData folder names replace) | `names:sync-key=precomposed` |
| `sync` | items of synchronized folders: `fileType`, `group`, `variant-group`, `package-folder`, `explicit-folder`, `member=library` (a static or dynamic library, a stub, an object file, a framework or an XCFramework), `member=libraries-in-several-folders` (one folder's libraries or frameworks in two of its folders or more), `same-stem`, `excepted-path`, `item=skipped`, `folder` | `excepted-path=missing`, `=missing-in-existing-subfolder`, `=missing-in-subfolder` (a path an exception set names, not on disk, at the top level, in a subfolder, in a subfolder that is not on disk) | `sync:variant-group=adds-several-regions` |

Shapes across objects: `pbxproj:PBXNativeTarget.productReference=absent`,
`pbxproj:<isa>.<key>=dangling` (an object ID the project lacks; `PBXBuildFile.fileRef=dangling-beside-synchronized-members` in a target with synchronized folders), `pbxproj:object-id=not-hexadecimal`,
`pbxproj:PBXVariantGroup.children=outside-lproj|region-not-in-knownRegions|mul-not-in-knownRegions|regions-from-several-groups`,
`pbxproj:XCConfigurationList.defaultConfigurationName=differs-from-project`,
`pbxproj:PBXNativeTarget.testBundle=package-products-only|depends-on-other-project`,
`pbxproj:PBXNativeTarget.extension=several-host-apps`, `pbxproj:PBXReferenceProxy.remoteRef=unresolved|unresolved-other-build-folder`,
`pbxproj:PBXTargetDependency.targetProxy=other-project|unresolved|unresolved-in-project`,
`pbxproj:PBXProject.projectReferences=missing-project`, `pbxproj:PBXFileReference.path=missing[-<type>]`,
`pbxproj:XCSwiftPackageProductDependency.linked=second-frameworks-phase`,
`pbxproj:PBXBuildFile.productRef=outside-first-frameworks-phase`,
`pbxproj:PBXNativeTarget.dependencies=product-several-times|target-several-times`.

Other domains add their namespaces (ADR 0011, "Domains"):

| Namespace | Path | Values | Example |
|---|---|---|---|
| `assets` (`AssetsDomain`, the catalogs of targets' resources phases and synchronized folders) | `catalog`, `folder`, `name`, `names`, `identifiers`, `<asset type>` (`colorset`, `dataset`, `imageset`, ...), and for color, data and image sets `<type>.<entry key>`, `<type>.key=<unknown top-level key>`, `<type>.properties.<key>`, `<type>.entry.<unknown entry key>` | `folder=group\|namespace`, `name=non-ascii`, `names=same-name-several-types`, `identifiers=collision\|more-than-126`; color spaces, idioms, display gamuts, appearances (`luminosity:dark`, several joined with `+`), `color=none\|reference\|reference-other`, `component=decimal\|integer\|hexadecimal\|hexadecimal-long`; `dataset.type=explicit\|from-extension\|unknown-extension`, `appiconset.images=none\|files`; `imageset.image=<idiom>-<scale>\|none`, `imageset.file=<extension>\|missing`, `imageset.png=unsupported`, `imageset.pixels=gray`, `imageset.images=several` | `assets:colorset.appearance=contrast:high` |

| `coredata` (`CoreDataDomain`, the `.xcdatamodel` and `.xcdatamodeld` of targets' sources and resources phases and synchronized folders, each compiled, dry-run and generated for Swift 5 by nomac's momc) | `model`, `refused` | `model=versioned`; `refused=<BACKLOG item>` (unverified, the object is nomac's error), `refused=unexplained` (unknown) | `coredata:refused=B-257` |
| `coreml` (`CoreMLDomain`, the `.mlmodel` and `.mlpackage` of targets' sources and resources phases and synchronized folders, each read for its specification's model type, a package's root model by its `Manifest.json`, then compiled and its Swift classes generated in memory by nomac's coremlc) | `model=<type>`: the field of `Model.proto`'s `Type` one-of the model sets (`glmRegressor`, `neuralNetwork`, `mlProgram`, ...), `model=unreadable` when it is not a specification nomac reads; `refused=<B-item>`: nomac's coremlc refuses a model of a type it compiles (the object is its error) | the types nomac compiles verified, the others unverified (B-240, B-242) | `coreml:model=neuralNetwork` |
| `metal` (`MetalDomain`, in the `nomac` target: the `.metal` files of targets' sources and resources phases and synchronized folders) | `shader` | unverified: nomac has no Metal compiler (B-241, ADR 0240) | `metal:shader` |
| `signing` (`SigningDomain`, every native target, read for the configuration archives use: `Release`, else the target's default) | `product=<product type>[@watchos]`, `identity`, `style`, `allowed=NO`, `entitlements`, `profile`, `embed=<destination>`, `pages=4k` (below iOS 16.0), `code-directory=sha1` (below watchOS 12.0), `deployment`, `dsym=none`, `on-demand-resources` | `identity=ad-hoc\|apple-development\|iphone-developer\|distribution\|empty\|other\|default\|expression\|conditional`, `style=manual\|automatic\|default\|expression\|conditional`; `embed=frameworks\|frameworks-without-code-sign-on-copy\|plugins\|watch\|app-clips\|extensionkit\|xpc-services\|products-directory\|other` | `signing:identity=apple-development` |
| `nib` (`NibDomain`, in the `nomac` target: the xibs and storyboards of iOS targets' resources phases, localizations of variant groups among them, and of their synchronized folders) | `refused=<B-item>`: nomac's ibtool refuses the document, run in memory with the options a build passes (the target's `PRODUCT_MODULE_NAME`, `IPHONEOS_DEPLOYMENT_TARGET`, else the iOS 27.0 SDK's default 27.0, and `TARGETED_DEVICE_FAMILY`'s devices), once per distinct set of options; listed with the compiler's own message, which names the BACKLOG item (`refused=unexplained` when it names none); `document=missing`: a resources phase lists a document the checkout does not have, which Xcode's build fails on too. Nothing is written | | `nib:refused=B-260` |
| `build` (`BuildDomain`, every configuration of every native target: its settings, its base xcconfig and what that includes, then the project's; and the `node_modules` folders Node would search from the container's folder) | `setting=mach-o-executable`: a setting whose unconditional value, expanded with those settings and the project's folder as `SRCROOT`, names an executable Mach-O or universal file, or whose `-load-plugin-executable <path>#<module>` names one (a Swift macro plugin; each word may follow a `-Xfrontend`, as the driver passes them on), a tool the build runs that a Linux build cannot (CocoaPods' `HERMES_CLI_PATH`, the `ExpoModulesMacros` plugin of expo-default's pods, docs/state/react-native.md); listed with the value as written, absolute paths relative to the container's folder, and for an executable in an npm package its Linux builds: the ELF executable of the same name at the root of an installed optional dependency, else the Linux (glibc) packages `package-lock.json` lists for it (expo-modules-macros' `ExpoModulesMacros`, ADR 0151); and when an ELF executable of the same name in a sibling of the tool's folder is for another machine, which this one cannot run without user-mode emulation, that build, the note saying to install `qemu-user-static` (on a Mac, which cannot tell, the tool counts as below). `setting=mach-o-executable-linux-build`: such a setting, not a macro plugin, with exactly one ELF executable of the same name in a sibling of the tool's folder that this machine runs, its own machine's first, else through emulation (`hermes-compiler/hermesc/linux64-bin/hermesc` beside `osx-bin/hermesc`); `nomac build` off macOS sets it as an override, so it is no project requirement and does not change the exit status (ADR 0184). `project-fix=expo-autolinking-scan`: `expo-modules-autolinking/build/platforms/apple/apple.js`, in a `node_modules` folder Node would search from the container's folder, holds the text the fix of that name edits in memory (ADR 0184). `macro-plugin=swift-package`: such a plugin with a `Package.swift` at or above its folder, listed with the package; `nomac build` off macOS builds it from that package when its manifest declares a macro target of the executable's name (ADR 0151), so it is no project requirement. `node-module=mach-o-only`: a native Node module (`.node`) that is Mach-O, whose package has no ELF one and, for an npm platform package (`"os": ["darwin"]`), no installed Linux package among the optional dependencies that name it; listed with its package and the alternatives that `package-lock.json` beside the `node_modules` folder lists for Linux with glibc (npm records every platform's optional packages and installs the current machine's). `script=mach-o-executable`: a script phase whose command (a line's first word, or the word after `;`, `&&`, `\|\|`, `\|`, `exec`, `then`, `do` or `else`), expanded with the target's settings and taken from the project's folder when relative, names an executable Mach-O or universal file outside the operating system's and Xcode's folders (`/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`, `/usr/libexec`, `/System`, `/Library/Apple`, an app's `Contents/Developer`), which are Mach-O on a Mac and no project's own (wikipedia's `"$SRCROOT/scripts/localization"`, B-134; the same folders are left out for `setting=mach-o-executable`); listed as `<target>: <phase>: <command as written>`. The notes say what the project does: override the setting on the command line with the tool built for the build machine (`nomac build` does it for a build beside the tool), install the Node packages on the build machine, put a build of a script's tool for the build machine at its path. A tool's own test of the system it runs on is not visible in the project's files: `nomac build` answers the ones in its table in memory (ADR 0184), and any other fails with the tool's own message | `script-command=<command>`: a macOS-only command that a run-script phase, or a shell script it names (to any depth), runs and nomac has no stand-in for (`plutil`, `defaults`, `ipconfig`, `osascript`, `sips`, `security`, …), with what to change; `script-command=nc`: netcat, which macOS has and Linux machines often lack; `script=sed-in-place-bsd` (`sed -i ''`), `script=machine-architecture` (`uname -m`, `arch`), `script=crashlytics-upload-symbols`, `script=sentry-cli-react-native-xcode` (`sentry-cli react-native xcode`, which sentry-cli's Linux build lacks and which runs the JavaScript bundling itself, in a script without `SENTRY_DISABLE_AUTO_UPLOAD`; a script that reads it, as `sentry-xcode.sh` does, is the project fix `sentry-auto-upload`, `project-fix=sentry-auto-upload`); listed with the phase or script and the line, and, when the command is followed by `|| …`, that its failure is hidden and a Linux build goes on without its result (ADR 0183, `script_phase_survey.py` reads the scripts the same way) `script-interpreter=<name>`: a run-script phase whose shell (`shellPath`) is another program than a shell, `/usr/bin/env ruby` among them (Bugsnag's dSYM upload), which the Linux build machine needs installed; listed as `<phase>: shell <shellPath>`, the script not read. `setting=deployment-target-below-minimum`: a target whose `SDKROOT` platform's deployment target, from its levels, is older than Xcode 27.0's SDK supports (iOS and tvOS 15.0, watchOS 9.0, macOS 12.0, visionOS 1.0, the SDKs' `SDKSettings.json`), which Xcode 27.0 and nomac fail with `error: The iOS deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 12.0, but the range of supported deployment target versions is 15.0 to 27.0.x.`; listed with the target, configuration, value and minimum, the note giving the Podfile `post_install` that raises CocoaPods' targets | `build:setting=mach-o-executable`, `build:script=mach-o-executable`, `build:node-module=mach-o-only`, `build:script-command=defaults`, `build:script=sed-in-place-bsd` |

With `--description-only`, asset catalogs, Core Data and Core ML models, and the synchronized
folders that may hold them or Metal shaders are listed as not checked. The `signing` domain reads settings as written in the target's and the
project's configurations and their base xcconfig files (with includes), an `sdk` condition
counting when it matches the target's platform; other conditions give `=conditional` and
macros `=expression`, both outside the envelope. Its envelope (`SigningEnvelope`) cites the
`signing_experiments.py` experiments: ad-hoc signing with manual style of apps, app extensions,
frameworks, loadable bundles, static libraries, watch apps, ExtensionKit extensions and XPC
services, frameworks, plug-ins, watch apps, App Clips, ExtensionKit extensions and XPC services
embedded, 4 KB pages, SHA-1 code directories, archives without dSYMs and on-demand resources.
Apple-issued identities, automatic signing, entitlements files and profiles are unverified
until the build answers Swift Build's provisioning inputs and distribution signing is observed
(B-302); tools are unverified for the reason their entry gives.

## Project fixes

What nomac changes about how a project's tools run in a Linux build (docs/PROJECT-COMPATIBILITY.md,
ADR 0184) is listed apart from the features: a section "Project fixes a Linux build applies to this
project" in the text, before its last line, and `projectFixes` in the JSON (`id`, `tool`, `change`, `why`,
`dropWhen`, `upstream`, `uses`). A fix is listed when the feature that its table entry names is used. Those
features are verified, so the list changes neither the count outside the envelope nor the exit status.

## The envelope

`nomac check --envelope` prints it. On 2026-10-22 the loader's has 1,572 verified features (841
used by the 19 corpus apps identical to Xcode, 635 by the 259 envelope-experiments cases identical
to Xcode, the rest from loader-experiments, pif-experiments, package-experiments and
envelope-experiments) plus every host condition package-experiments observed and the copy-files
destinations 0 to 17, and 27 features known to be unverified:

| Features | Why | BACKLOG |
|---|---|---|
| `package:unsafe-flags=local-dependency`, `=branch-or-revision` | unchecked builder answers | B-010 |
| `PBXNativeTarget.productReference=absent` | synthesized GUID unknown | B-012 |
| `defaultConfigurationName=differs-from-project`, `testBundle=package-products-only`, `testBundle=depends-on-other-project`, `PBXTargetDependency.targetProxy=other-project-extension` | autocreation not observed, or the extension's scheme lacks the app | B-014 |
| `PBXNativeTarget.extension=several-host-apps` | Xcode's order changes per run | B-015 |
| `sync:variant-group=adds-several-regions` | Xcode's order changes per run | B-017 |
| `PBXVariantGroup.children=regions-from-several-groups` | Xcode's order changes per run | B-030 |
| `INFOPLIST_FILE=condition-and-plain[-in-xcconfig]`, profiles `=condition-and-plain-in-xcconfig` | assignment choice | B-026 |
| `sync:member=libraries-in-several-folders` | Xcode's order of a folder's search paths changes per run | B-031 |
| `PBXNativeTarget.productType=com.apple.product-type.kernel-extension` | XcodeProj cannot read the type | B-071 |
| `PBXFileReference.path=case-mismatch` | the file is on disk only in another case: a build on a case-sensitive file system uses the disk's spelling, which debug paths record, unless `nomac build --case-aliases` | B-062 |
| `PBXReferenceProxy.remoteRef=unresolved-other-build-folder` | GUID: the hash of a build folder nomac does not compute from such settings | B-036 |
| `settings:SDKROOT=condition-other` | Xcode's destination check reading of `SDKROOT` under such a condition is not observed | |
| `xcconfig:include=spelled-otherwise-on-disk` | Swift Build opens it by its bytes on Linux | B-075 |
| `names:package=non-ascii` | Xcode's spelling not observed | B-076 |
| `pbxproj:format=xcproj` | no comparison | B-083 |
| `PBXCopyFilesBuildPhase.dstSubfolderSpec` above 17 | xcodebuild stops with SIGTRAP | B-040 |
| `PBXFileReference.fileEncoding=undefined` | Xcode's number changes from dump to dump | |
| `PBXRezBuildPhase`, `PBXShellScriptBuildPhase.dependencyFile` | written by nomac, never observed | |
| `package:condition=canImport(<module>)` for modules package-experiments did not observe | Linux answers | |

Every other feature is unknown until an experiment or a corpus app verifies it.

`nomac verify` checks the envelope against each comparison it makes (docs/VERIFICATION.md,
check kind `envelope`): an app entirely inside the envelope that differs from Xcode fails, and
an app identical to Xcode lists the unknown features it verifies.

## Output

Text: a summary line, then each feature outside the envelope with its status, note, evidence and
up to five uses, each object's first use before repeats of an object already shown (expo-default's
38 Mach-O settings are one macro plugin flag in 18 pods' xcconfigs, two configurations each, and `HERMES_CLI_PATH` in two),
`--all` lists every feature; then the parts not checked, and a closing line.

JSON (`--json`), keys sorted, paths relative to the folder holding the container:

```json
{
  "container" : "App.xcodeproj",
  "descriptionOnly" : false,
  "features" : [
    { "count" : 12, "domain" : "loader", "evidence" : [ "corpus:retro-rampage" ], "id" : "pbxproj:PBXNativeTarget", "status" : "verified" },
    { "count" : 1, "domain" : "loader", "evidence" : [ "B-012" ], "id" : "pbxproj:PBXNativeTarget.productReference=absent",
      "note" : "Xcode synthesizes a product reference whose GUID is not known", "status" : "unverified",
      "uses" : [ { "file" : "App.xcodeproj/project.pbxproj", "object" : "PBXNativeTarget A0000000000000000000000B (Lib)" } ] }
  ],
  "inside" : false,
  "outside" : 1,
  "unchecked" : [ { "domain" : "loader", "file" : "Sources", "what" : "contents of a synchronized folder" } ]
}
```

`status` is `verified`, `unverified` or `unknown`; `uses` is given for features outside the envelope.

## Coverage survey

`.github/scripts/feature_survey.py` (ADR 0011, point 7) fetches the GitHub apps of
dkhamsing/open-source-ios-apps with `git clone --depth 1 --filter=blob:none --sparse` and
`git sparse-checkout set --no-cone` on `*.xcodeproj/`, `*.xcworkspace/`, `*.xcconfig`,
`Package.swift`, `Package@swift-*.swift`, `Package.resolved` and `*.xctestplan`, checks each
repository's entry container (the shallowest workspace, else the shallowest project, outside
`Pods`, `Carthage` and other dependency folders) with `--description-only`, and writes
`summary.json` (commits, containers, usage, blocking features, the greedy order) and
`SUMMARY.md` under `~/nomac-out/survey`. A repository whose clone fails twice is skipped and
counted. The headline coverage is the loader's (ADR 0011, point 7): projects with no loader
feature outside the envelope. A table gives the same share for each domain `nomac check` reports
(`loader`, `assets`, `signing`), and a separate row the projects with no feature of any domain
outside, each with its 95% Wilson interval; the greedy order and the most blocking features are
the loader's, followed by each other domain's ten most blocking features. A check result written
before features carried their domain is checked again.
