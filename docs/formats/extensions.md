# Products nested in an app

What Xcode 27.0 does with each kind of product an iOS app embeds, and what nomac reproduces.
Observed with `.github/scripts/extension_experiments.py`: self-written apps made into corpus-style
references (an unsigned build, an ad-hoc archive with every codesign step, a `debugging` export),
which `nomac verify --build` compares file by file (docs/VERIFICATION.md "Extension checks"). The
export's format is in docs/formats/ipa.md, signatures in docs/formats/code-signature.md.

## Where each is embedded

| Kind | Experiment | Product type | Copy phase | Where in the app |
|---|---|---|---|---|
| Widget | `widget` | `com.apple.product-type.app-extension` | `dstSubfolderSpec` 13 | `PlugIns/<name>.appex` |
| App Intents widget | `widget-intent` | the same | 13 | `PlugIns/<name>.appex`, with `Metadata.appintents` |
| Live Activity | `live-activity` | the same | 13 | `PlugIns/<name>.appex`, and `NSSupportsLiveActivities` in the app's `Info.plist` |
| Notification service | `notification-service` | the same | 13 | `PlugIns/<name>.appex` |
| Notification content | `notification-content` | the same | 13 | `PlugIns/<name>.appex`, with its storyboard |
| Share | `share` | the same | 13 | `PlugIns/<name>.appex`, with its storyboard |
| Action | `action` | the same | 13 | `PlugIns/<name>.appex`, with its storyboard |
| App Clip | `appclip`, `appclip-script` | `com.apple.product-type.application.on-demand-install-capable` | 16, `$(CONTENTS_FOLDER_PATH)/AppClips` | `AppClips/<name>.app` |
| Watch app | `watch`, `watch-framework` | `com.apple.product-type.application` for `watchos` | 16, `$(CONTENTS_FOLDER_PATH)/Watch` | `Watch/<name>.app` |
| Watch widget | `watch-widget` | `com.apple.product-type.app-extension` for `watchos` | 13, in the watch app | `Watch/<watch>.app/PlugIns/<name>.appex` |

`Extensions/` holds ExtensionKit extensions (`com.apple.product-type.extensionkit-extension`,
signing_experiments' `extensionkit`, docs/state/packaging.md).

## Info.plist

An extension's `Info.plist` is its project file with `GENERATE_INFOPLIST_FILE`'s keys merged in, as
for any bundle: `NSExtension` comes from the project's file with its build settings expanded
(`$(PRODUCT_MODULE_NAME).NotificationService` becomes `Service.NotificationService`). A widget's has
only `NSExtensionPointIdentifier` (`com.apple.widgetkit-extension`). `NSSupportsLiveActivities` goes
in the app that holds a Live Activity, from `INFOPLIST_KEY_NSSupportsLiveActivities`, and not in the
extension. A watch app has `WKCompanionAppBundleIdentifier` from its own `INFOPLIST_KEY_`,
`WKApplication` true, and `MinimumOSVersion~ipad` `9.0` beside its `MinimumOSVersion`.

## Signing

Nested code is signed before the bundle that holds it: a framework embedded with `CodeSignOnCopy`,
each extension, then the app; a watch widget, its watch app, then the app (the order of the recorded
codesign steps in `watch-widget`, `framework-share`). A framework linked by both is signed in its
build, and again when copied into the app.

Under ad hoc signing no step of any kind passes `--entitlements` (every recorded step of these
experiments), so what a target's entitlements file does to a nested product is not observed here: it
needs a provisioning profile (B-302). A framework copied into its parent is signed with
`--preserve-metadata=identifier,entitlements,flags`, every other step without.

A bundle's `CodeResources` seals what it nests file by file, `hash2` of each file of every kind
of nested product (the extension's executable, `Info.plist`, `_CodeSignature/CodeResources`, its
resources), in `files2` of the parent, with no `cdhash` and no `nested` rule in `rules2`. So a parent
signed before its nested code holds the hashes of what the nested code was then:
`nomac verify --build` checks that the parent's hashes are the nested product's final files.

### App Clips

An ad hoc archive of an App Clip stops at the product type's entitlement:
`"Clip" requires a provisioning profile. Enable development signing and select a provisioning
profile in the Signing & Capabilities editor.` (exit 65, experiment `appclip`). Its unsigned build
works. `appclip-script` signs it from a script phase (`CODE_SIGNING_ALLOWED` `NO`), the only way to
archive one without a profile, so what a profile adds to a real App Clip is not observed (B-302).

## The export's summary

`DistributionSummary.plist` nests: an entry's `embeddedBinaries` lists what its own bundle holds, in
signing order, for every export method (`debugging`, `release-testing`, `enterprise` and
`app-store-connect` of `watch-widget` and `extension-framework`). So `App.app[Watch.app[Widget.appex]]`,
`App.app[Watch.app[WatchKitLibrary.framework]]` and `App.app[Share.appex[Kit.framework]]`, while
`framework-share`'s is `App.app[Kit.framework, Share.appex]`. docs/formats/ipa.md has each entry's keys.

A framework held by a framework carries its immediate parent's name, not its own:
`Frameworks/Kit.framework/Frameworks/Inner.framework/Frameworks/Deep.framework` and
`Frameworks/Kit.framework/Frameworks/Other.framework` give
`App.app[Kit.framework[Kit.framework[Inner.framework], Kit.framework]]` (`framework-framework`,
`framework-framework-deep`). A framework in an extension or a watch app keeps its own. Other code inside
a framework is not observed, and `nomac export` refuses it (B-314).

## Thinning

Thinned for all variants (`extension_experiments.py compare-thinning`, by
`distribution_experiments.py`'s comparison): `nomac export` matches Xcode's for `widget`, `widget-intent`,
`live-activity`, `notification-service`, `notification-content`, `share`, `action`, `appclip-script`,
`watch` and `framework-share`. It refuses a watch app holding an extension (`watch-widget`, `all`; B-465),
whose rule is not written yet: Xcode's output for both is in the experiments' references.

## Linking

An extension's link adds `-e _NSExtensionMain -fapplication-extension` to the app's. Which library
each SwiftUI symbol binds to follows the output's name, and not its kind. Xcode's `ld` names the
client after the output file of an executable too, unless `-client_name` says otherwise: the leaf up
to its first `.` or `_`, which must begin one of the library's allowable clients. SwiftUICore allows
`AppKit`, so an executable named `App`, `A`, `Ap`, `AppK`, `AppKit`, `App_x` or `App.x` binds SwiftUI's
imports to SwiftUICore and adds its load command, while `AppKitX`, `Apple`, `MyApp` and `Foo` bind them to
SwiftUI; `-client_name AppKit` gives `Foo` the first result and `-client_name Foo` gives `App` the second
(direct links of one Swift object on the Mac). lld does not do this for executables yet (B-313).
