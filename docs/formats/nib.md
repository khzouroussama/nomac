# Interface Builder documents in Xcode's builds

Observed with Xcode 27.0 (27A266a): `.github/scripts/nib_experiments.py` (1500 self-written iOS
xibs, among them key-table ladders of UIKit controls nomac does not compile yet, some compiled with
other ibtool options; 554 storyboards, `storyboard` and `sb-*`, among them launch screens shaped as
React Native's and Expo's templates write them at every iOS release's deployment target;
`link-lproj`, `missing-file`, `stable` and `build`; and `corpus`, the corpus's 218 storyboards and
376 xibs). `nomac ibtool` reproduces 1391 of the xibs and 503 of the storyboards byte for byte and
refuses the others, naming their BACKLOG items: UIKit controls and `<mask>` variations, colors
ibtool converts or rejects (B-260, among them 14 sweeps of 612 `calibratedRGB` and `deviceRGB` colors), deployment targets below 8.0 or below what a document's
features need (B-263: 37 launch screens below 11.0 or 13.0), unreachable scenes, segues without identifiers and a subview
autoresized to fractions of a point (B-261), and views whose constraints' order is not pinned
(B-265). None differs. Of the corpus's 594 documents it reproduces 116, retro-rampage's two
storyboards among them, and refuses the others; none differs. Of the 207 ibtool compilations of
the corpus's reference builds, 22 compile, each identical to Xcode's, and so do 3 of its 17 links
(measured again with the restored checkouts on 2026-10-30).
The launch screens of the React Native and Expo test apps (docs/state/react-native.md) compile and link
identical to Xcode's, Debug and Release.
`.github/scripts/nib_compare.py` compares (`corpus` for the corpus).

## Tasks

```
CompileXIB <src>/View.xib
    ibtool --errors --warnings --notices --module T --output-partial-info-plist <obj>/View-PartialInfo.plist \
        --auto-activate-custom-fonts --target-device iphone --minimum-deployment-target 27.0 \
        --output-format human-readable-text --compile <app>/View.nib <src>/View.xib
CompileStoryboard <src>/Base.lproj/Main.storyboard
    ibtool ... --output-partial-info-plist <obj>/Base.lproj/Main-SBPartialInfo.plist ... \
        <src>/Base.lproj/Main.storyboard --compilation-directory <obj>/Base.lproj
LinkStoryboards
    ibtool ... --link <app> <obj>/Base.lproj/Main.storyboardc <obj>/Base.lproj/LaunchScreen.storyboardc
```

These are the `build` experiment's tasks. Before planning them Swift Build asks
`ibtool --version --output-format xml1` (SWBApplePlatform `InterfaceBuilderShared.swift`), with no
other option; nomac answers as `IBToolVersion` says (docs/adr/0102-linker.md "Tool probes") and
compiles only with a `--minimum-deployment-target` (B-263). ibtool runs in a daemon and resolves relative paths
against the daemon's directory, not the caller's. Its output is the same for the same input from
run to run (`stable`). A successful compile prints nothing; an error prints
`/* com.apple.ibtool.errors */` and `<path>: error: <message>`, for a missing document
`Interface Builder could not open the document Missing.xib" because it does not exist.`, with that
one quote (`missing-file`). The partial Info.plist of every xib and storyboard observed is an empty
XML dictionary (`<dict/>`). `--link` copies the compiled `.storyboardc` as it is (`storyboard`,
`sb-*`). One LinkStoryboards task links all of a target's storyboards (retro-rampage's
`LaunchScreen` and `Main`), and Xcode's ibtool, given compiled storyboards from `Base.lproj`,
`fr.lproj` and a plain folder in one call (`link-lproj`), copied each into the app's folder of
the same `.lproj` name, and the plain one into the app itself. Storyboards are described in "Storyboards" below.

## Inputs nomac compiles

Only inputs whose every element, attribute, value and option the experiments observed
(ADR 0251); anything else is refused with `nomac does not compile <what> yet (BACKLOG B-26x)`:

- **Options.** `--minimum-deployment-target` of every iOS release from 8.0 to 26.2 (8.0–8.4,
  9.0–9.3, 10.0–10.3, 11.0–11.4, 12.0–12.5, 13.0–13.7, 14.0–14.8, 15.0–15.8, 16.0–16.7,
  17.0–17.7, 18.0–18.7, 26.0–26.2) and 27.0, all giving the same nibs (`deployment-*`); 7.0 writes a
  `View~iphone.nib/` bundle of `runtime.nib` and `objects-8.0+.nib` instead (B-263). A document
  whose features need a later iOS than the target is written the same way, each nib a bundle of
  `objects-<version>+.nib` (the nib the later target gives) and a `runtime.nib` for older
  systems: safe area guides need 11.0 (before 9.0 ibtool fails: "Safe Area Layout Guide before
  iOS 9.0"), named colors 13.0 (before 11.0 ibtool fails: "Named colors do not work prior to iOS
  11.0"; the `runtime.nib` adds the color to `UINibKeyValuePairsKey`). React Native's and Expo's
  launch screens give the same files from 11.0 and from 13.0 to 27.0 (`sb-launch-rn-at-*`,
  `sb-launch-expo-at-*`); nomac refuses targets below a document's features (B-263).
  `--target-device` iphone, ipad, or both, the same nibs (`devices-*`). `--module` as above.
- **Header.** `<document>` attributes `type`, `version` 3.0, `toolsVersion` (any: three values
  give the same nib), `systemVersion` (any: two), `targetRuntime`, `propertyAccessControl` none,
  (below the document, on any element, `propertyAccessControl` changes nothing, nor does IB's empty
  `<animations/>` anywhere: `*-access-*`, `*-animations`),
  `useAutolayout` YES, `useTraitCollections` YES or absent, `useSafeAreas` YES, `launchScreen`
  YES, `colorMatched` YES or absent (it changes colors: "UIColor"), `customObjectInstantitationMethod`
  direct (no change: `header-instantiation-direct`, `sb-instantiation-direct`). `<designables>`,
  IB's intrinsic content sizes of custom views, change nothing (`designable*`, `sb-designable`), nor
  does `<accessibilityOverrides>`, IB's dynamic type preview, text styles included
  (`a11y-overrides-*`, `sb-a11y-overrides`). `<customFonts>`
  change no nib; the partial Info.plist lists their font files as `UIAppFonts` (`custom-fonts*`,
  `sb-custom-fonts`). A
  storyboard's
  `<inferredMetricsTieBreakers>` of segue references changes nothing (`sb-tie-breakers`). `<device>` ids retina3_5,
  retina4_0, retina4_7, retina5_5, retina5_9, retina6_0, retina6_1, retina6_12, retina6_3,
  retina6_5, retina6_7, retina6_72, retina6_9, ipad9_7, ipad11_0rounded and ipad12_9rounded, portrait or
  landscape, light, dark or no appearance, `layout="fullscreen"`, `<adaptation id="fullscreen"/>`,
  or no `<device>`; a storyboard's Xcode 8 `<simulatedMetricsContainer key="defaultSimulatedMetrics">`
  (status bar and orientation without types, screen `retina4_7.fullscreen` or `retina4`) changes
  nothing (`sb-metrics-*`). `<dependencies>`: the Cocoa Touch plug-in (any version: two give the same
  nib), the capabilities named in `capabilities`, `capabilities-more` and `capability-multipliers`,
  Xcode 5's `<development version="5100" identifier="xcode"/>` (`development-xcode-5100`; a
  storyboard's retina6_72 scenes are 393 x 852 in either orientation, as retina3_5's:
  `sb-device-retina6_72*`), and
  `<deployment identifier="iOS"/>`, with or without a `version` in binary-coded decimal (0x1220, 4640, is
  iOS 12.2; survey documents hold 0x0300 to 0x1700) from 0x0800 to 0x1b00, which sizes and warns as
  "Older documents" says (`document-version-*`, `sb-document-version-*`, round 58; gomap's QuestBuilder at 0x1500).
  Before 8.0 ibtool writes nib bundles, as for a deployment target before 8.0 (B-263). None of these changes a xib's nib (`system-version-*`,
  `device-*`, `no-device`); a storyboard sizes its scenes by the device (below).
- **Placeholders.** File's Owner (with or without a class and module) and First Responder (with
  or without `UIResponder`); the classes change nothing (`owner-*`, `no-first-responder-class`).
- **Views** (a xib's `<containerView>` too, a plain view: `container-*`; a storyboard's, with its
  embed segue, is refused), image views, labels (attributed ones as in "Attributed labels"), buttons, stack views and scroll views as in "UIView", "UILabel",
  "UIButton", "UIStackView" and "UIScrollView" below, collection view cells and reusable views as in
  "Collection view cells", activity indicators, segmented controls, progress views, page controls and
  sliders as in "Activity indicators and other controls", text fields and switches as in "Text
  fields, switches and actions", visual effect views as in "Visual effect views", collection views as in
  "Collection views", text views as in "Text views", toolbars as in "Toolbars", web views as in "Web views", navigation bars as in "Navigation bars among subviews", date pickers and picker views as in "Date
  pickers and picker views", their background
  colors as in "UIColor", and their constraints as in "Constraints", with key tables of at most 199
  keys (B-259). `<image>` resources (any size: `image-view-size-*`).
- **Outlets** and an outlet collection as in "Connections" below, and design-time settings that
  change nothing: `<freeformSimulatedSizeMetrics>` and `<nil>` simulated bar metrics on views
  and view controllers (`view-freeform`, `view-simulated-nils`, `sb-simulated-nils`), controllers'
  simulated tab bars, toolbars, and opaque or black navigation bars (round 112, `sb-sim-*`), except
  that for a deployment target under 17.0 a xib's top-level `<view>` without freeform metrics
  takes the document device's size in its orientation (600 x 600 without a device), keeping its
  origin, its subviews autoresized as a storyboard's scene views are; from 17.0 on it keeps its
  frame, and top-level cells keep theirs (round 99, `tl-*`: 15.0 and 16.0 resize, 17.0 and 27.0
  do not; nomac refuses retina3_5 and documents without a device or trait collections there).
- **Storyboards** as in "Storyboards" below.
- **Size-class variations** of labels' fonts and constraints' constants, and a view's
  `<mask key="constraints">` and `<mask key="subviews">` by size class, as in "Variations" below;
  variations of other properties are refused (B-260).

## Archive

Little-endian throughout:

```
"NIBArchive"  u32 1  u32 10
u32 objects count, offset   u32 keys count, offset   u32 values count, offset   u32 classes count, offset
objects:  varint class index, varint first value index (0 for an object of no values), varint value count
keys:     varint length, UTF-8 bytes
values:   varint key index, u8 type, payload
classes:  varint length of the name with its NUL, varint fallback count, u32 fallback class indexes, name, NUL
"LNE" 00
```

Varints have seven bits per byte, least significant first, and the high bit set on the last byte.
Value types: 0–3 integers of 1, 2, 4 and 8 bytes (the smallest that holds the value), 4 `false`,
5 `true`, 6 float, 7 double, 8 data (varint length, bytes), 9 nil, 10 object (u32 index).

## Encoding

- Objects are numbered depth first, when first encoded, and each object's values are written
  together, in object order. An object encoded again is a reference to its number.
- The class table lists classes in the order their first object is numbered, then the fallback
  classes no object has, by name (`UIColor`: `NSColor`; `UIFont`: `NSFont`; `_UILayoutGuide`:
  `UIView`, at the end when the scene's view has a custom class: `sb-view-custom-class`; the 671
  recorded nibs with two or more give `NSColor`, `NSFont`, `UIView` whichever classes name them);
  a class names its fallbacks' indexes.
- The key table is in the order of a mutable Foundation table (docs/formats/foundation-collections.md):
  each key enters it when its value is first written, depth first from the root in value order,
  an object's values where it gets its number. `UINibEncoderEmptyKey`, the key of every collection
  element, enters at its first use too (the third key of every nib) and takes a bucket, but counts
  toward what the table holds only when the archive is finished, which can make the table grow
  once more: 33 keys and the empty key stay in 41 buckets, and the finished 34 move to 71
  (`color-key-outer-rgb-3-0`, `ladder-*`). Before an insertion the table grows when its counted
  keys would exceed what it holds or its keys would exceed its buckets. These rules give all 510
  observed nibs of nib_experiments.py and all 1018 of the corpus, tables of 16 to 199 keys, and the
  2000 more of four investigations into the order (a key held around a color's `UIAlpha`, a
  separate order for view-controller nibs and growth before the empty key is counted, each of
  which an earlier version of these rules had, were each refuted by them). The reason the empty
  key goes uncounted is not known. Two other statements fit the same nibs: the empty key held only
  while each collection element is written and for good from `UINibObjectsKey`; and the empty key
  counted like any key, the table growing right after the insertion that brings it to 13, 21, 34,
  54, 87, 120 or 157 keys, the new key re-inserted with the others (for nibs, whose empty key is
  always the third, this is the same rule).
- The root, an `NSObject`: `UINibTopLevelObjectsKey` (an `NSArray` of the document's top-level
  objects, in document order), `UINibObjectsKey` (every object, breadth first, a view followed
  by its safe area guide, its constraints, a scene's layout guides, then its subviews: `[view,
  sub1, sub3, sub1's child]`, `constraint-to-safe-area`, `sb-image-view`; each object once, and a
  view listed there that a constraint names comes right after that constraint's place, as its
  child: a view deeper than the subviews moves ahead, `deep-other-great`,
  `deep-other-grand-top-grand2-leading`; safe areas and a legacy collection cell's content view
  are not added), `UINibConnectionsKey`, `UINibVisibleWindowsKey`,
  `UINibAccessibilityConfigurationsKey`, `UINibTraitStorageListsKey`, `UINibKeyValuePairsKey`
  (one shared empty `NSArray` for every empty list), `IBUINibLNEVersionKey` 1.
- Equal strings are one `NSString` across the document, whatever holds them: class names, color
  and font names, label texts, outlet names, image names, priorities, a safe area guide's empty
  identifier (`strings-shared`, `same-custom-class`, `same-system-color-twice`, the corpus's
  SettingsHeaderView); placeholders' identifiers are not.
- `NSArray`, `NSMutableArray`: `NSInlinedValue` true, then `UINibEncoderEmptyKey` per element.
  `NSString`: `NS.bytes`, UTF-8. A placeholder is a `UIProxyObject` with
  `UIProxiedObjectIdentifier` (a new string per placeholder); its `customClass` changes nothing.

## UIView

Keys in this order, each written only as noted (`view-*`, `view-flags-*`). Boolean attributes read
`true`, `yes` and `1` as `YES`, and `false`, `no` and `0` as `NO` (`bool-*`: Expo's templates
write `true` and `false`).

| Key | Value |
|---|---|
| `UIBounds` | data: 07, then doubles 0, 0, width, height; left out for a 0 x 0 frame (the corpus's wikipedia TextSizeChangeExampleViewController) |
| `UICenter` | data: 07, then doubles x + width/2, y + height/2 |
| `UISubviews` | an `NSMutableArray` of the subviews, when there are any |
| `UIBackgroundColor` | the color, a `UIColor` (below) |
| `UIDeepDrawRect` | true |
| `UIOpaque` | true unless `opaque="NO"` |
| `UIHidden` | true for `hidden="YES"` |
| `UITag` | the tag; 0 writes nothing (`view-tag-0`, `label-tag-0`) |
| `UIUserInteractionDisabled` | true for `userInteractionEnabled="NO"` |
| `UIMultipleTouchEnabled` | true for `multipleTouchEnabled="YES"` |
| `UIAutoresizeSubviews` | true unless `autoresizesSubviews="NO"` |
| `UIAutoresizingMask` | the mask (flexibleMinX 1, widthSizable 2, flexibleMaxX 4, flexibleMinY 8, heightSizable 16, flexibleMaxY 32); 36 without an `autoresizingMask` element or, for a top-level view, with `translatesAutoresizingMaskIntoConstraints="NO"`; left out when 0 |
| `UIClearsContextBeforeDrawing` | false for `clearsContextBeforeDrawing="NO"` (`image-view-clears`, `view-clears-no`) |
| `UIAlpha` | float, when `alpha` is given and not 1 (`alpha-1.000`, `alpha-1.0` write none) |
| `UIContentMode` | `UIViewContentMode`, unless `scaleToFill`; the corners as IB spells them, `TopLeft` 9 capitalized, `topRight` 10, `bottomLeft` 11, `bottomRight` 12, ibtool taking `topLeft`, `TopRight`, `BottomLeft` and `BottomRight` as scale to fill (round 108, `*-mode-*`) |
| `UIContentStretch` | the `<rect key="contentStretch">`'s x, y, width and height as doubles, the document's values exactly; left out at 0, 0, 1, 1 (`view-stretch*`, `image-view-stretch`, `label-stretch`, `button-stretch`, `cell-stretch*`) |
| `UIClipsToBounds` | true for `clipsSubviews="YES"` |
| `UITintColor` | the `<color key="tintColor">` (`view-tint-*`, `button-tint-*`) |
| `UIViewDoesNotTranslateAutoresizingMaskIntoConstraints` | true for `translatesAutoresizingMaskIntoConstraints="NO"` on a top-level view or on a view a constraint names, a placeholder constraint too; another subview is compiled as if the attribute were not there (`color-key-*-3-4`, `-7-0`, `image-view-*`, `constraint-root-height`, `constraint-placeholder`). A constrained subview keeps the `<autoresizingMask>` its document gives (an empty one writes no `UIAutoresizingMask`), else takes 36 (`no-translate-mask-*`, round 64) |
| `UIViewAutolayoutConstraints` | an `NSMutableArray`: a scene's layout guides' constraints, then the view's own as in "Constraints" |
| `UIViewContentHuggingPriority` | a string `{horizontal, vertical}` when either is not 250 (750 for a switch: `sw-*`; for an info button, which image-only buttons' forced `{250, 250}` does not concern: `button-info-hugging-*`), one object per value (`image-view-hugging-*`, `image-view-two-hugging`) |
| `UIViewLayoutGuides` | an `NSMutableArray` of the view's safe area guide, when a constraint names it ("Constraints") |
| `UIViewLayoutMargins` | data: 07, then doubles top, left (leading), bottom, right (trailing) of an `<edgeInsets key="layoutMargins">` or `<directionalEdgeInsets key="directionalLayoutMargins">`, zeros included; a stack view without either writes zeros (`view-margins-*`, `stack`) |
| `UIViewLayoutMarginsFollowReadableWidth` | true for `layoutMarginsFollowReadableWidth="YES"` |
| `UIViewPreservesSuperviewMargins` | true for `preservesSuperviewLayoutMargins="YES"`, then `UIViewPreservesSpecificSuperviewMargins` 15 |
| `UIViewLayoutMarginsAreDirectional` | true for directional margins |
| `UIViewInsetsLayoutMarginsFromSafeArea` | 0 for `insetsLayoutMarginsFromSafeArea="NO"`, after the margins flags (`view-insets-preserves`, `view-margins-flags`) |
| `UIRestorationIdentifier` | the `restorationIdentifier` string, after the margins keys, on views and table cells (`restoration-*`) |
| `UIViewSemanticContentAttribute` | `UISemanticContentAttribute`, always |
| `UIViewLargeContentStoredProperties` | nil |
| `UIImage` | an image view's image, when it has one |

A view with `customClass` is a `UIClassSwapper` with the same keys, then `UIClassName` and
`UIOriginalClassName` (`UIView`; `UILabel`, `UIImageView`, `UIButton`, `UIStackView`, `UITableView`
for those: `label-custom-class*`, `image-view-custom-class-module`). The class name is the Swift mangled name `_TtC<module length>
<module><class length><class>`: with ibtool's `--module` when `customModuleProvider="target"`,
whatever `customModule` says, and with `customModule` when there is no provider; the plain name
with neither (`provider-target-*`, `module-without-provider-*`, each compiled with `--module T`
and `--module Zed`). Class name strings are one object per name.

A view without a `<rect key="frame">` is 1000 x 1000 at 0, 0 (`view-no-rect`,
`image-view-no-rect`). An `<imageView>` is a `UIImageView` with a view's keys (its
`userInteractionEnabled`, `opaque` and `contentMode` defaults are a view's: `image-view-plain`);
its image is a `UIImageNibPlaceholder`: `UIImageWidth` and `UIImageHeight` float 1, whatever
the `<image>` resource's size, `UIResourceName` the name, `UISystemSymbolResourceName`,
`UISymbolImageConfiguration` and `UIResourceCatalogName` nil; image views showing one image
share it (`image-view-*`; the corpus's 275 non-symbol placeholders are all 1 x 1). `adjustsImageSizeForAccessibilityContentSizeCategory="YES"` writes
`UIAdjustsImageSizeForAccessibilityContentSizeCategory` true after `UIImage` (`image-view-adjusts*`). A subview's
`<viewLayoutGuide key="safeArea">` is listed and constrained as a top-level view's, in xibs and
storyboards (`subview-safe-area*`, `sb-subview-safe-area`). A system image
(`catalog="system"`, an SF Symbol) is 0 x 0 with its name as `UISystemSymbolResourceName` too,
one placeholder per name for image views and buttons alike (`image-view-symbol`,
`button-image-symbol-and-view`). An image view's `<imageReference key="image">` of a system symbol
with a `symbolScale` is a placeholder of its own whose `UISymbolImageConfiguration` is a
`UIImageSymbolConfiguration` of that scale (as in "Button configurations"), and its
`<preferredSymbolConfiguration key="preferredSymbolConfiguration">` another, written
`UIPreferredSymbolConfiguration` after `UIImage`, with which the image view writes no `UIOpaque`, when it has an
image (`image-view-symbol-reference*`, `image-view-symbol-preferred-*`, `image-preferred-*-no-image`). A configuration writes
`UISymbolScale`, `UIPointSize`, `UISymbolWeight` (ultraLight 1 to black 9) and `UITextStyle`: `configurationType="font"` of a text style
takes that style and its weight (Headline 6, the others 4) unless the configuration names one, of a system font its size and
weight, and a font without the type changes nothing (`symbol-weight-*`, `symbol-font-*`, `symbol-size-*`, round 157). A `variableValue` is the
placeholder's `UIImageVariableValue` (double) after `UISystemSymbolResourceName`; `renderingMode="template"` and `original` write `UIRenderingMode` 2 and 1 after `UISystemSymbolResourceName` on a system symbol, on an image of the
app nothing, nor does its `symbolScale` (`symbol-rendering-*`); `renderingMode="hierarchical"`
with its `<hierarchicalColors>` puts `UIHierarchicalColors` (an array of the colors) in the symbol
configuration, after any scale, then `UIDerivativeHierarchicalColors` false,
`UISpecifiedPrefersMulticolor` true, `UIPrefersMulticolor` false, `UISpecifiedPrefersMonochrome` true and
`UIPrefersMonochrome` false. A preferred configuration writes `UISymbolScale`, `UISymbolWeight` (light 3,
regular 4, bold 7), `UIPointSize` for `configurationType="pointSize"`, and for `configurationType="font"`
with a text style's `<fontDescription>` that style's weight (Headline 6) and `UITextStyle`; an empty one
is none and leaves `UIOpaque` (`symbol-view-*`). A button state's `<imageReference>` is its image
and its `<preferredSymbolConfiguration>` the content's `UIImageSymbolConfiguration`, after `UIImage`
(`symbol-button-*`). `misplaced`, like `ambiguous`, changes nothing (`misplaced-*`).

## UILabel

A `<label>` is a `UILabel` (`label-*`): a view's keys (with `UIViewContentCompressionResistancePriority`
`{h, v}` after the hugging priority when either is not 750, and `UIViewInsetsLayoutMarginsFromSafeArea`
0 for `insetsLayoutMarginsFromSafeArea="NO"`; `fixedFrame`, `ambiguous`, `userLabel`,
`highlighted` and placeholder sizes change nothing), then, each only as noted: `UIText` (the
`text` attribute or a `<string key="text">`, nil without; in a document of `Base.lproj` an
`NSLocalizableString`: `NS.bytes` the text, `NSKey` the string `<id>.text`, `NSDev` the text:
`label-lproj`, `sb-label`; an empty text, a button's title too, stays a string: `label-empty-lproj`,
`button-empty-title-lproj`), `UIAdjustsFontForContentSizeCategory`
true, `UIFont`, `UITextColor` (a `nil` or absent text color is the system `labelColor`),
`UIHighlightedColor` (when it is a color; an absent one is the system `blackColor`:
`label-highlighted-absent`, `label-no-colors`), `UIShadowColor` for a `<color key="shadowColor">`,
`UIShadowOffset` (07, doubles; 0, -1 without a `<size key="shadowOffset">`, the document's values
with one, left out at 0, 0: round 115, `label-shadow-*`), `UINumberOfLines`
(unless 1), `UIBaselineAdjustment` (alignCenters 1, none 2, and 1 when absent; alignBaselines is
not written), `UIAdjustsFontSizeToFit` true (unless `adjustsFontSizeToFit="NO"`),
`UIMinimumFontSize` float (`minimumFontSize`, or the point size times `minimumScaleFactor` to the
nearest quarter point; for a text style its size at the default content size: Body and Headline
17, Subhead 15, Callout 16, Footnote 13, Caption1 12, Caption2 11, Title0 34, Title1 28, Title2
22, Title3 20: `label-style-scale-*`, `label-system-scale-*`),
`UILineBreakMode` (wordWrap 0, characterWrap 1, clip 2, headTruncation 3, middleTruncation 5;
tailTruncation 4 is not written), `UITextAlignment` always (left 0, center 1, right 2, justified 3,
natural 4; left when absent), `UIEnabled` false, `UIMinimumScaleFactor` float (or minimumFontSize
over the point size), `UIAdjustsLetterSpacingToFit` true, `UIPreferredMaxLayoutWidth` float (none for 0:
`label-max-width-*`),
`UIDisableUpdateTextColorOnTraitCollectionChange` (true when the document gives the text color or
has no text color element: `label-text-absent`, React Native's launch screen). Equal fonts and
colors are one object (`label-two`). With `adjustsFontSizeToFit="NO"` neither `minimumFontSize` nor
`minimumScaleFactor` is written (round 115, `label-min-*-no*`, `label-scale-half-no`); with fitting,
a `minimumFontSize` writes itself and its ratio to the font's size, a text style's default size
counting, and given with a scale factor, the factor makes the minimum (`label-min-and-scale-yes`,
`label-scale-over-one`). A minimum over the font's size makes ibtool warn `<path>:<id>: warning:
Minimum Font Size greater than current font size [9]`, in the order of a Foundation table of the
ids (`label-min-20-*`, `sb-label-min-20*`). A size with a text style ibtool does not know is refused.

`UIFont` (fallback `NSFont`; `label-font-*` for the corpus's 106 font descriptions, `label-size-*`
from 8 to 72 points, `label-weight-*`): `UIFontName`, `UIFontDescriptor` (`UIFontDescriptorAttributes`
a dictionary, `UIFontDescriptorOptions`) or, for a text style, `UIIBTextStyle`, then
`UIFontPointSize`, `UIFontTextStyleForScaling` nil, `UIFontPointSizeForScaling` and
`UIFontMaximumPointSizeAfterScaling` 0 (these three left out by named fonts of options 0),
`UIFontTraits`, `UISystemFont`, `NSName` (the name again), `NSSize`. System fonts are
`.SFUI-<weight>` with `NSCTFontUIUsageAttribute` `CTFont<weight>Usage` and `NSFontSizeAttribute`
(an `NSNumber` double), options 2147517444, whatever the size: traits ultraLight 16, thin 4,
light 8, regular and medium 0, semibold, heavy and black 2; bold (`boldSystem` or `weight="bold"`)
is a mutable dictionary of the emphasized usage, `NSCTFontUIUsageOverrideAttribute`
`CTFontBoldUsage` and the size, traits 2; `italicSystem` is `.SFUI-RegularItalic` with
`NSCTFontTraitsAttribute` {`NSCTFontSymbolicTrait` 1}, one dictionary for all the nib's italic fonts
(`font-share-italic-*`), `CTFontObliqueUsage`, traits 1;
`.AppleSystemUIFont` is the regular system font. A system font of `pointSize="0"` is of 12 points but for
`italicSystem`, which stays 0 (`label-font-zero-*`, `button-font-zero-*`; a label's minimum font size beside it is
refused). Text styles have point size 0 and the
`NSSize` and name of `NibFont.textStyles` (Body 14, Headline semibold 14, Title0 31...). A style
ibtool does not know (`UICTFontTextStyleSubheadline`, or a made-up one: `label-style-subheadline`,
`label-style-made-up`) is a font of `UIFontName` and `NSName` nil, a descriptor of attributes nil
and options 0, point size, traits and `NSSize` 0, `UISystemFont` false.

### Named fonts

Round 115 (`label-named-*`). A named font has `NSFontNameAttribute` (the name string, shared with
`UIFontName` and `NSName`) and `NSFontSizeAttribute` the document's size, fractions too, and
`UISystemFont` false; the family attribute changes nothing (`label-named-helvetica-wrong-family`).
ibtool resolves a name or does not:

- A name it resolves has options 2147483648, the scaling keys and the traits of
  `NibFont.resolvedFonts` (`ResolvedFonts.swift`): italic 1, bold 2, both 3. They mostly follow the
  name, with exceptions (`ArialRoundedMTBold` 0, `BodoniSvtyTwoOSITCTT-Bold` 0, `Impact` 2,
  `HiraginoSans-W5` 2), so they are a table.
- Any other name has options 0, traits 0 and no scaling keys, and nomac writes it without a refusal:
  a made-up name (`label-named-unknown`), a name in another case (`label-named-lowercase`), a display
  name (`label-named-display-name`), `.SFNS-Regular` (`label-named-sfns`, CoreText's note on ibtool's
  stderr), system fonts ibtool does not find (`Courier-Bold`, `Courier-Oblique`, `GurmukhiMN`), and
  custom fonts listed in `<customFonts>` (`label-named-custom-listed`); by hand, with the font's
  file beside the document, the nib was the same.
- One resolved name is written as another font's: `STHeitiSC-Light` is `PingFangSC-Light`
  (`label-named-stheitisc-light`, `NibFont.renamedFonts`); `STHeitiSC-Medium`, `STHeitiTC-Light` and
  `STHeitiTC-Medium` are unresolved.

The table was found by compiling a label of each of about 3,100 names, the fonts CoreText lists on
the Mac and the fonts of the iOS 18, 26 and 27 simulator runtimes; 309 resolve. `IOS_FONTS` in
`nib_experiments.py` holds those and some that do not, so the round reproduces the table. A name
ibtool resolves outside these lists would come out unresolved, and `nomac verify` would report the
difference. Deployment target and devices do not change the result (`label-named-helvetica-15`,
`label-named-unknown-15`).

On a storyboard's device a label's `UIMinimumScaleFactor` and `UIMinimumFontSize` go by the font of that device's
size classes; ibtool's warning about a minimum over the font's size goes by the document's font
(`sb-label-min-variation-*`, `sb-label-scale-variation-*`, `sb-label-min-warning-*`). A label, text field or text
view with `adjustsFontForContentSizeCategory` and a font other than a text style's warns `Automatically Adjusts
Font requires using a Dynamic Type text style [9]` (`warn-adjusts-*`).

## Attributed labels

A label with `usesAttributedText="YES"` and an `<attributedString key="attributedText">` of one
fragment (round 55, `al-*`) writes a plain label's keys from the fragment: `UIText` its content (a
string of the nib's, never localizable: `al-system-15-lproj`), `UIFont` its `NSFont` (`metaFont="system"`
as the system font of that size, a named font as a `<fontDescription>` of that name),
`UITextColor` its `NSColor` or the system `labelColor`, `UITextAlignment` its paragraph style's
alignment (natural without one), `UIDisableUpdateTextColorOnTraitCollectionChange` false; then,
right after `UITextAlignment`, `UIAttributedText`: an `NSMutableAttributedString` of an
`NSMutableString` of the content and an `NSDictionary` of the fragment's attributes in document
order, the color and font the label's objects (without `colorMatched` a `calibratedWhite` or `calibratedRGB` color stays as
written, not converted as a view's: `al-unmatched-*`), `NSOriginalFont` dropped (`al-gomap`), one dictionary for labels of
the same attributes, whatever their texts (`al-share-two-fragments*`). A fragment's font named `.SFNSText`, `.SFUIText`,
`.SFUI-Regular`, `.SFNSDisplay` or `.SFUIDisplay` is the regular system font, one object with the system font of that
size (`al-font-name-*`; the survey's adblockplus MainInterface). The catalog
color `textColor` (`catalog="System"`) is opaque black, unnamed (`al-system-15-text-color`). The
paragraph style is an `NSMutableParagraphStyle` of `NSAlignment` (AppKit's values, none for left),
`NSLineBreakMode` the label's own (tail truncation without one, whatever the paragraph's:
`al-gomap-label`; word wrapping, 0, is not written: `al-break-*-label-word`), `NSLineHeightMultiple` (double) when given, `NSTabStops` nil and
`NSLineBreakStrategy` 65535; `baseWritingDirection="natural"` and `tighteningFactorForTruncation="0.0"`
write nothing. An empty `<attributedString/>` writes the empty string, the system font of 17 points
with descriptor options 0, alignment 4 and an attributed string without attributes (`al-empty`).
Several fragments (`NSAttributeInfo` runs, `al-two-fragments`) are refused.

## UIButton

A `<button>` is a `UIButton` (`button-*`, round 32; `UIClassSwapper` with `UIOriginalClassName`
`UIButton` for a custom class): a view's keys, then a control's, then the button's, each only as
noted. `opaque`, `contentMode`, `fixedFrame`, `ambiguous`, `userLabel` and `menu="NO"` are a
view's as above.

Control (`button-control-flags`, `button-halign-*`, `button-valign-*`): `UIHighlighted`,
`UISelected`, `UIDisabled` (for `enabled="NO"`), `UIContentVerticalAlignment` and
`UIContentVerticalAlignment2` (both, top 1, bottom 2, fill 3), `UIContentHorizontalAlignment`
(left 1, right 2, fill 3, leading 4, trailing 5), `UIPointerInteractionEnabled`; center, or no
alignment attribute, writes none.

Button (`button-button-flags`): `UIButtonStatefulContent`, `UILineBreakMode` (as a label's, but
middleTruncation, IB's default, is not written), `UIReversesTitleShadowWhenHighlighted`,
`UIShowsTouchWhenHighlighted`, `UIAdjustsImageWhenHighlighted` and `UIAdjustsImageWhenDisabled`
(true unless `NO`), `UIButtonType` (system and roundedRect 1, detailDisclosure 2, infoLight 3,
infoDark 4, contactAdd 5; custom, the type without a `buttonType`, is not written),
`UIAdjustsImageSizeForAccessibilityContentSizeCategory`, `UIFont`, `UIButtonRole` (primary 1,
cancel 2, destructive 3), `UIContentEdgeInsets`, `UITitleEdgeInsets`, `UIImageEdgeInsets` (07,
then doubles top, left, bottom, right, that is `minY`, `minX`, `maxY`, `maxX`; an inset of zeros
is not written, IB's `maxX="2.2250738585072014e-308"` is), `UISpringLoaded`,
`UIButtonChangesSelectionAsPrimaryAction`, `UIButtonConfiguration` nil.

`UIButtonStatefulContent` is an `NSMutableDictionary` from the state (an `NSNumber` integer,
one object per value in the nib: normal 0, highlighted 1, disabled 2, selected 4) to a
`UIButtonContent`, in the order of the states whatever the document's order
(`button-states-*`); a state of no content is left out, and a button without content writes no
dictionary (`button-no-state`, `button-no-title`). `UIButtonContent`: `UITitle` (a string, or in
`Base.lproj` an `NSLocalizableString` keyed `<id>.<state>Title`: `button-lproj`),
`UIImage`, `UIBackgroundImage` (image placeholders as an image view's), `UITitleColor`,
`UIShadowColor` (`titleShadowColor`), each when given (`button-state-content`).

The font is the font description's as a label's; without one, the regular system font of 15
points for system buttons and 18 for custom ones (`button`, `button-type-custom`). The
image-only types (detailDisclosure, info, contactAdd) write neither content nor font, whatever
the document gives, and always write `UIViewContentHuggingPriority` (`{250, 250}` included:
`button-type-*-untitled`, `button-type-infoLight-*`); ibtool warns about their titles ("Title
unsupported by this button type"), which nomac refuses. Button configurations
are in "Button configurations".

## Button configurations

A button's `<buttonConfiguration key="configuration">` (round 54, `bc-*`) makes it write
`UIButtonConfiguration`, a `UIButtonConfiguration`, instead of nil, and neither its states' content
nor its font, whatever its `<state>`s and `<fontDescription>` (`bc-no-state`, `bc-font-on-button`).
The configuration writes `UIButtonConfigurationButtonStyle` (plain 0, gray 1, tinted 2, filled 3),
`UIButtonConfigurationBackground` (a `UIBackgroundConfiguration` as a cell's, but `cornerRadius` 17,
`strokeWidth` 1 and `strokeColor` customized, `defaultStyle` and `defaultStyle_v2` 0, its background
color by style: the system `clearColor` for plain, else unnamed sRGB colors of full precision, each
configuration's own object (`bc-filled-two`, `bc-gray-two`; the survey's KeePassium FirstSetupVC), gray
120/255, 120/255, 128/255 at 0.16, tinted 0, 136/255, 1 at 0.18, filled the same opaque; its stroke
the system `clearColor`), `UIButtonConfigurationCornerStyle`, `ButtonSize` and `MacIdiomStyle` 0,
`BaseBackgroundColor` nil, `BaseForegroundColor` (`<color key="baseForegroundColor">`), `Image` (an
image placeholder as a state's, or for an `<imageReference>` of a system symbol a new placeholder
whose `UISymbolImageConfiguration` is a `UIImageSymbolConfiguration` of `UISymbolScale`: default
-1, small 1, medium 2, large 3), `PreferredSymbolConfigurationForImage` (another
`UIImageSymbolConfiguration`, with `UIPointSize` for `configurationType="pointSize"`),
`SymbolContentTransition` nil, `ShowsActivityIndicator` false, `Title` (an `NSAttributedString` of
the title whose `NSAttributes` are `NSFont` the `titleFontDescription`'s font or nothing, one
dictionary per font in the nib: `bc-two`; an empty title writes no attributes), `Subtitle` (the same
for `subtitle`, on the same attributes; a title font beside one is refused), `ImagePlacement` (leading 2,
trailing 8), `ImagePadding` (float), `TitlePadding` 1 (float) and `TitleAlignment` 0. In `Base.lproj` the
strings are `NSLocalizableString`s keyed `<id>.configuration.title` and `.subtitle` (`bc-lproj-*`, `sb-bc-lproj-*`).

## UIStackView

A `<stackView>` is a `UIStackView` (`stack-*`, round 33): a view's keys, with
`UIViewLayoutMargins` always (zeros without margins), then `UIStackViewArrangedSubviews` (an
`NSArray` of its subviews, all of them arranged, when it has any), `UIStackViewAxis`
(horizontal 0, vertical 1), `UIStackViewDistribution` (fill 0, fillEqually 1,
fillProportionally 2, equalSpacing 3, equalCentering 4), `UIStackViewAlignment` (fill 0, leading
and top 1, firstBaseline 2, center 3, trailing and bottom 4, lastBaseline 5; IB's `centerX` and
`centerY` are 0), `UIStackViewSpacing` (double), `UIStackViewBaselineRelative` and
`UIStackViewLayoutMarginsRelative` (true when the stack view has margins), all always.
`spacingType="standard"` writes nothing (`stack-spacing-type-standard`). A stack view with
arranged subviews writes `UIViewDoesNotTranslateAutoresizingMaskIntoConstraints`, and so do its
arranged subviews that do not translate their masks, with mask 36 whatever their
`autoresizingMask` (`stack-arranged-*mask`); an empty one writes neither (`stack-empty`). A
xib's top-level `<stackView>` is compiled as any top-level view and keeps its frame under iOS 17
too, unlike a `<view>` (round 104, `tl-stack`, `tl-stack-15`, `tl-stack-arranged`).

## UIScrollView

A `<scrollView>` is a `UIScrollView` (`scroll-*`, round 34): a view's keys, then
`UIScrollViewIndicatorInsetAdjustmentBehavior` 1, then, each only when it differs from IB's
default, `UIIndicatorStyle` (black 1, white 2), `UIBounceEnabled` false,
`UIShowsHorizontalScrollIndicator` false, `UIShowsVerticalScrollIndicator` false,
`UIScrollDisabled` true, `UIDelaysContentTouches` false, `UICanCancelContentTouches` false,
`UIPagingEnabled` true, `UIBouncesZoom` (true unless `bouncesZoom="NO"`), `UIAlwaysBounceVertical`,
`UIAlwaysBounceHorizontal`, `UIDirectionalLockEnabled`, `UIMinimumZoomScale` and
`UIMaximumZoomScale` (floats), a collection view's nil `UIDelegate`, `UIKeyboardDismissMode` (onDrag 1, interactive 2), and
`UIScrollViewContentInsetAdjustmentBehavior` always (automatic 0, scrollableAxes 1, never 2,
always 3) (`scroll-flags`). Its `contentLayoutGuide` and `frameLayoutGuide` are listed in all
objects as placeholders like a safe area no constraint names (`UILayoutGuide` without an owning
view, the empty string as identifier), after the scroll view and before its constraints
(`scroll-guides-constraints`); constraints to them make `_UIScrollViewLayoutGuide` and
`UILayoutGuide` objects with system constraints (`scroll-content-guides-pinned`): the scroll view
as `UILayoutGuideOwningView`, `UILayoutGuideIdentifier` `UIScrollView-contentLayoutGuide` or
`UIScrollView-frameLayoutGuide`, locked, not archived, no negative dimensions, and
`UILayoutGuideSystemConstraints` of unarchived constraints identified `<identifier>-minX`,
`-minY` (the guide's left and top equal to the scroll view's), the frame guide's also `-width`
and `-height`; the scroll view does not list them in `UIViewLayoutGuides`. Its constraints treat
each guide as a safe area: a group at the origin of its own, guides by id, and the safe area's
attribute order (`scroll-guides-*`, round 51; pocket-casts' and wikipedia's scrolling panels).
Views inside a scroll view are named as deeper views (`deep-through-scroll`; wikipedia's
EditLinkViewController). `scrollsToTop="NO"` writes nothing and is refused until pinned.

## Constraints

A view's `<constraints>` (`order-*`, `constraint-*`). Each `<constraint>` is an
`NSLayoutConstraint`: `NSFirstItem` (the document's `firstItem`, the view itself when there is
none), `NSFirstAttributeV2` and `NSFirstAttribute` (`NSLayoutAttribute`: left 1, right 2, top 3,
bottom 4, leading 5, trailing 6, width 7, height 8, centerX 9, centerY 10), `NSRelation` (-1
`lessThanOrEqual`, 1 `greaterThanOrEqual`), `NSMultiplier` (the value rounded to a float, as a
double; `a:b` and `a/b` are a / b: 1/3, 1:3 and 0.33333333333333331 give 0.3333333432674408,
`constraint-multiplier-*`), then `NSSecondItem` and its two attributes, `NSConstantV2` (double),
`NSSymbolicConstant` (the string `NSSpace`, for `symbolic="YES"`, whose constant, IB's standard
spacing, is not written, with or without a second item: `constraint-symbolic`, `symbolic-*`),
`NSShouldBeArchived` true,
`NSPriority` (integer), `NSLayoutIdentifier` (a string, for `identifier`: the document's one string of that text, which outlets' labels, other identifiers, restoration and accessibility identifiers and texts share, `cid-*`), `NSConstant` (the
constant again), each written only when not the default (no relation, 1, 0, 1000;
`identified-constant-priority`; cwa's home cells).
`placeholder="YES"` constraints are left out. A constraint naming the view's safe area guide
names a `UILayoutGuide` the view lists in `UIViewLayoutGuides`: `UILayoutGuideOwningView` the
view, `UILayoutGuideIdentifier` `UIViewSafeAreaLayoutGuide`, `UILayoutGuideOwningViewIsLocked`,
`UILayoutGuideShouldBeArchived` and `UILayoutGuideAllowsNegativeDimensions` true,
`UILayoutGuideSystemConstraints` an `NSArray` of four constraints, not archived, identified
`UIViewSafeAreaLayoutGuide-top`, `-left`, `-bottom`, `-right`: the guide's top and left equal to
the view's, the view's bottom and right equal to the guide's (`constraint-to-safe-area`).

The order of a view's constraints depends on their content, not on their ids or document order
(`order-*-shuffled`, `order-document-shuffled`), and is not the document's:

- They are grouped by item: the view's own (no second item, or the view twice) first, then one
  group per subview, the constraints between the view and that subview whichever comes first
  (`order-alternating`) and between the subview and the safe area when the subview comes first;
  constraints whose first item is the safe area are a group of their own.
- The groups are in the order of their items' frames' distance from their superview's origin
  (the safe area at 0, 0), then by id (`order-two-*`, `sib-frames-*`, `cell-frames-*`,
  `view-frames-*`: frames apart, touching, overlapping and inside each other, in views and in cells'
  content views). This fits 741 of the corpus's 758 matched views, the others stack views and
  views with constraints to deeper views. Frames partly or wholly outside the view, on its
  edges or of no size sort the same way (`frames-outside-*`, `mask-group-*`, `outside-*`; pocket-casts'
  UserEpisodeDetailViewController); at the same distance the frame of the lesser x comes first, whatever the document's order or ids (`same-distance-*`, round 57); frames as far apart above each other (same x) interleave their constraints and nomac refuses them (B-265).
- Layout margins (`leadingMargin`, `trailingMargin`, `topMargin`, `bottomMargin`, `leftMargin`,
  `rightMargin`, `centerXWithinMargins`, `centerYWithinMargins`): `NSFirstAttributeV2` and
  `NSSecondAttributeV2` are the margin attributes (13 to 20), `NSFirstAttribute` and
  `NSSecondAttribute` their plain ones, `NSConstantV2` the document's constant and `NSConstant`
  that constant moved by the item's margin on that side: plus the left (leading) or top margin
  for a margin attribute of the second item, minus the right (trailing) or bottom one, the
  opposite on the first item, nothing for the centers (`margin-*`). A view's margins are its
  `layoutMargins` or directional margins when it has them, zeros included (`margin-custom-*`; the
  corpus's cwa ExposureSubmissionTestResultHeaderView), and otherwise 8 points in every container
  (a xib's root view and subviews, with or without `preservesSuperviewLayoutMargins`, cells'
  content views, scenes' views on every device). Centers within the margins of a view with
  margins of its own are refused. A margin constraint sorts in one order of all attributes: centerX's margin, centerX,
  centerY's margin, centerY, right and left margins, right, left, trailing and leading margins,
  trailing, leading, width, top and bottom margins, bottom, top, height (`margin-order-*`,
  `norm-all*`, `sub-first-all`; kickstarter's Friends storyboard). A multiplier scales neither margin in the legacy
  `NSConstant`, and a symbolic constant and a size-class variation of the constant write as without margins, the legacy
  `NSConstant` adding the margin (`cs-margin-*`). nomac refuses margins with the safe area or an anchor's symbol type.
- A view's constraints may name views deeper than its subviews, through plain views, cells'
  content views and stack views (`deep-through-stack`); their groups sort by their frames moved by
  their ancestors' origins (`deep-*`), one inside another listed item right after it even when
  nearer the origin (`deep-negative-offset*`; cwa's OnboardingInfoViewController); with an
  unrelated item between their distances ibtool's order is no single key's, and nomac refuses it
  (`deep-negative-offset-sibling`, B-265).
  A deeper view's constraints to the safe area come before those to the view, in the safe area's
  attribute order (`deep-safe-*`; pocket-casts' FilterSettingsOverlayController).
  In a subview's group, its constraints to such deeper views come first, before those to the view,
  the safe area and siblings, the deepest first, then by the view's attribute order
  (`deep-other-*`; the corpus's cwa ExposureDetectionViewController).
  A cell's own `<constraints>` to its content view's subviews are its `UIViewAutolayoutConstraints`,
  after its content view's subviews in all objects (`deep-cell-*`). A constraint whose items' nearest common ancestor is a
  descendant of the view that lists it is installed there and sorts as one of that view's own
  (`moved-*`, round 56; pocket-casts' FilterNameCell, VideoViewController). In all objects it
  comes with that view's constraints, but one between two of that view's subviews listed by a
  cell comes after the cell's own constraints, in its new view's order (`moved-cell-labels`,
  `moved-cell-mixed`); listed by another view that case is refused (B-265).
- `firstBaseline` (12) and `baseline` (11) sort after `top` and before `height` and `width`, the first
  baseline first, in every attribute order, as either attribute, with the view, the safe area or
  a sibling (`baseline-firstBaseline-*`, `cs-baseline-*`, `cs-first-baseline-*`, `cs-pairs-*`).
  `lastBaseline` stays refused: ibtool warns about it on plain views. A constraint's `userLabel`
  changes nothing (`constraint-user-label`).
- `symbolType="layoutAnchor"` writes `NSSymbolicConstant` `NSLayoutAnchorConstraintSpace` and no
  constant, whatever constant the document gives (`cs-symbol-anchor*`). A `customClass` makes the
  constraint a `UIClassSwapper` with its keys, then `UIClassName` and `UIOriginalClassName`
  `NSLayoutConstraint` (`cs-custom-*`). A view's `verifyAmbiguity`, `off` or `ignoreSizes`, changes nothing
  (`cs-verify-*`).
- An older collection view cell's safe area moves to its content view with its constraints; a
  constraint from a subview to it comes before that subview's constraints to the content view
  (`cs-cvsafe-*`).
- A constraint between two subviews is in its first item's group as written (not normalized),
  after that group's constraints with the view and the safe area, in the safe area's attribute
  order (`sib-pair-*`: every pair of attributes, `sib-mix-*`, `sib-with-*`).
- Within a group: the safe area first, none, then second; then the first attribute, then the
  second (none first), in the order centerX, centerY, right, left, trailing, leading, width,
  bottom, top, height between views and centerX, right, left, trailing, leading, centerY, bottom,
  top, width, height with the safe area (`order-sub-root-*`, `order-sub-safe`, every pair:
  `order-pair-*`); then the priority, lowest first; then the relation, `lessThanOrEqual`,
  `greaterThanOrEqual`, equal (`order-twice`, `order-size-relations`). A constraint
  sorts by its attributes as written: one written from the view by the view's attribute first
  (`cross-attribute-normalized`, `norm-*`), one written from the subview by the subview's, but
  one whose second attribute alone is a centerX or centerY by that center, from the view or the
  subview (`order-cross`, `cross-attribute-*`, `norm-cross-*`; cwa's contact diary and home cells,
  uncloudnotes' launch screens). Constraints from one item by the same attributes,
  relation, multiplier and priority to several views tie, and ibtool's order of them is not in the
  document (rounds 48, 49, 59, 60; ADR 0253): nomac writes such a tie in document order when every
  constraint in it is required and satisfied by the frames (a safe area across only), not naming a
  view deeper than the subviews nor beside runtime attributes of several objects, which `nomac
  verify` counts equivalent; others are refused (B-265). Constraints of the same items and
  multiplier that differ only in their constants, or not at all, keep their document order
  (`tie-constant-reversed`; tofu's duplicated constraints), identical ones also when written from
  the view (`tie-identical-normalized`; nextcloud's). Constraints of one item and attribute to
  different subviews follow the subviews' distance from the origin in `tie-second-items-*`, but
  not in eleven corpus documents (cwa, kickstarter, nextcloud, pocket-casts, wikipedia, gomap),
  and are refused (B-265).
- Measured on the corpus's 758 views whose constraints can be matched with their nibs, these
  rules give every view whose constraints join it with one subview or its safe area (652) but
  four table and collection view cells and a document with size-class variations, which nomac
  refuses, and 20 of the 21 views with several subviews that the rules above accept.
  Constraints between two subviews, or with deeper views, follow rules not pinned yet
  (`order-sibling`) and are refused (B-265).

## Variations

A variation's own `<rect key="frame">` and its `misplaced`, `ambiguous` and `fixedFrame` attributes change
nothing, on a device of its size class too (`cm-var-*`, `cm-sb-var-fixed-*`). A label's `<mask>` of its own
constraints compiles as any view's, in the same variation as a font or beside one (`cm-label-mask-*`), and a
size-class mask inside a cell's content view as anywhere else (`cm-cell-sub-mask-*`, `cm-cell-deep-mask-sc`).
`hidden` in a variation is an attribute storage (`cm-var-hidden-*`): refused for now.

A `<variation key>` gives a label's font (`<fontDescription>`), a constraint's constant
(`constant`) or a stack view's `axis`, `distribution` and `spacing` for a size class (rounds 19,
22 and 82: `variation-*`, `vo-*`, `sb-vo-*`, `stack-vary-*`). A stack view's are a storage each,
key paths `axis`, `distribution`, `spacing` in that order, of `NSNumber`s: integers (horizontal 0,
vertical 1; the distributions' values), the spacing a double, its default record the integer 0
when the stack view has no `spacing` (`stack-vary-spacing-default`); equal numbers are one object. The nib's
`UINibTraitStorageListsKey` holds one `_UITraitStorageList` for the top-level view:
`UITopLevelObject`, `UITraitStorages` (an `NSArray` of `_UIAttributeTraitStorage`) and
`UIDescendants` (an `NSSet`, `NS.object.0`, `NS.object.1`..., of the varied objects in storage
order).

- The storages are those of a walk of the views, depth first from the top-level view. A view
  writes its properties' storages, its subviews mask, its constraints mask, then its constraints'
  constants: all its constraints in their order, then the installed ones again (so a constraint
  a default mask excludes once, the others twice). In each of the two, the first constraint
  naming a view deeper than the subviews walks it (`masks-walk-*`), then the view walks its
  subviews. A cell walks its content view and
  that view's subviews, so those are walked twice. A storage walked again is a new object with
  new trait collections (round 44, `masks-*`; `vo-two-constants*`, `mask-cell-group`; wikipedia's
  ShareViewController, PageHistoryCountsViewController, WelcomeContainerViewController, whose
  stack view's mask comes after its properties'). Variations the walk does not reach are refused.

- `_UIAttributeTraitStorage`: `UIObject`, `UIKeyPath` (`font`, or `encodedConstant` for a
  constraint), `UIRecords` (an `NSMutableArray` of `_UIAttributeTraitStorageRecord`:
  `UITraitCollection`, `UIValue`). A constraint's constants are `_NSLayoutConstraintConstant`:
  `UISymbolicConstant` nil, `UINumericConstant` (double).
- Records are in one order of size classes whatever the document's: regular by regular,
  regular-height compact-width, compact-height regular-width, compact by compact, width regular,
  width compact, height regular, height compact, then the default, of no size class
  (`vo-font-all`, `vo-font-all-reversed`). A `UITraitCollection` writes
  `UITraitCollectionBuiltinTrait-_UITraitNameHorizontalSizeClass` and `...VerticalSizeClass` for
  the classes it has (1 compact, 2 regular); the empty one is one object for the whole list, every
  other one a new object, and so is every constant; fonts are shared as everywhere.
- Storages: as the walk above; with no mask, a view's varied constraints in their order, then the
  same list again (with new trait collections and constants), then its subviews' labels
  (`vo-two-constants*`, `vo-two-labels*`, `vo-two-labels-constant`).
- The list's top-level object is the one the varied objects are under, a static cell standing for
  one (the corpus's tofu storyboard: a mask in a static cell's content view names the cell).
- An empty `<mask>` changes nothing, on a default or a size-class variation (`mask-empty-*`,
  `cvmask-old-empty`).
- A view's `<variation key="default"><mask key="constraints">` excludes constraints of its own
  (`mask-*`): they stay in all objects (numbered there, after the installed ones) but leave the
  view's `UIViewAutolayoutConstraints`; the list's `UITraitStorages` holds a
  `_UIRelationshipTraitStorage`: `UIObject` the view, `UIKeyPath` `traitStorageConstraints` (one
  string of the nib), `UIRecords` an `NSMutableArray` of `_UIRelationshipTraitStorageRecord`s,
  `UIRelationshipCandidates` an `NSOrderedSet` of all the view's constraints in their order. A
  record has a `UITraitCollection`, `UIAddedObjects` the `<include>`d objects and
  `UIRemovedObjects` the `<exclude>`d ones, both `NSSet`s. The default's record, of the empty
  trait collection, comes first; then one per `<variation key="<size classes>">`, each its own
  trait collection, in the reverse of the attribute records' order: height only (compact,
  regular), width only, then both, by height then width (`sc-mask-order-all*`, whatever the
  document's order). Only the default's exclusions leave the view's list in a xib (`sc-mask-*`);
  in a storyboard with a `<device>`, the records its size classes match apply after the default's
  (`sb-sc-mask-include-two`). `UIDescendants`: the candidates' items (first, then second) but the
  top-level object, in that order, a safe area as its view's unarchived placeholder guide
  (`mask-safe-area*`, the corpus's pocket-casts ShelfActionsViewController). nomac refuses size-class masks inside a cell's
  content view.
- An `NSSet` of several objects follows ibtool's memory addresses: a rotation of the candidates'
  order that unrelated subviews added to the document move (`sc-mask-set-probe-*`; the
  storyboard of `sb-sc-mask-include-two` against its xib), stable run to run. nomac writes the
  candidates' order, ibtool's in every default-only mask observed and most size-class ones; a nib
  differing only there is equivalent (ADR 0252).
- A `<mask key="subviews">` (`mask-subviews-*`, `sc-mask-subview-include`; nextcloud's
  NCShareUserCell) has records as a constraints mask's; its default leaves its subviews out of the
  view's `UISubviews`, in all objects still (a content view lists them after its
  constraints); its storage has the key path `traitStorageSubviews`, the view's subviews as
  candidates and `UIDescendants` the view but the top-level object. A subview that constraints
  name is refused: ibtool warns and drops them with it.
- A xib's objects, and those of a storyboard without a `<device>`, keep their default values. In a
  storyboard with a device a label's font and a constraint's constant are those of the first
  record the device's size classes match (a record matches when each class it names is the
  device's): iPhones are compact by regular in portrait and compact-height in landscape,
  regular-width for retina5_5, 6_1, 6_3, 6_5, 6_7 and 6_9; iPads regular both ways; retina3_5
  is a phone in portrait in either orientation, its scene 393 x 852 (`sb-vo-all-*`,
  `sb-vo-partial-*`).

## Table views

A `<tableView>` in a xib's view (`table-*`) is a `UITableView` (`UIOriginalClassName`
`UITableView` with a custom class): a view's keys, then its scroll view's in a scroll view's order
(`UIScrollViewIndicatorInsetAdjustmentBehavior` 1, `UIIndicatorStyle` (white 2), `UIBounceEnabled`
false, `UIShowsHorizontalScrollIndicator` false, `UIScrollDisabled` true, `UIDelaysContentTouches` false,
`UICanCancelContentTouches` false, `UIBouncesZoom` true unless `bouncesZoom="NO"`, `UIAlwaysBounceVertical`,
`UIKeyboardDismissMode` (onDrag 1, interactive 2), `UIScrollViewContentInsetAdjustmentBehavior` 0;
`showsVerticalScrollIndicator="NO"` writes nothing: `table-everything`, `table-scroll-flags`,
`table-vertical-indicator-NO`), then `UITableViewStyle` (plain 0, grouped 1, insetGrouped 2), `UIStyle` (0
plain, 1 grouped), the separator style (default: `UISeparatorStyle` and `UISeparatorStyleIOS5AndLater` 1;
none: `UISeparatorStyleIOS9AndLater` 0; singleLineEtched: all three 2: `table-separator-*`),
`UIPrefetchingEnabled`, `UIRowHeight`, `UISectionHeaderHeight`, `UISectionFooterHeight`,
`UIEstimatedRowHeight` (floats; 0 without `estimatedRowHeight`), `UIEstimatedSectionHeaderHeight` and
`UIEstimatedSectionFooterHeight` (0 without them; an estimate over 0 up to 1 is written as 2:
`table-estimated-*`), `UIFillerRowHeight` 0 and `UISectionHeaderTopPadding` -1
(doubles), `cellLayoutMarginsFollowReadableWidth` true with `layoutMarginsFollowReadableWidth` on the table
(`table-readable*`, `sb-table-readable`), `UIAllowsSelection` false for `allowsSelection="NO"`, `UIAllowsSelectionDuringEditing`,
`UIAllowsMultipleSelection`, `UIAllowsMultipleSelectionDuringEditing`, `UIInsetsContentViewsToSafeArea`
(false for `contentViewInsetsToSafeArea="NO"`), `UISeparatorColor`, the prototypes, `UISectionIndexColor`,
`UISectionIndexBackgroundColor`, `UISectionIndexTrackingBackgroundColor` (`sb-table-prototype-*`), `UISeparatorInset`
(07, then top, left, bottom, right: `sb-table-separator-prototype`), and `UISeparatorInsetReference` 0.
`<view key="tableHeaderView">` and `key="tableFooterView"` are the table's first subviews, footer first, written again as
`UITableHeaderView` and `UITableFooterView` after `UIInsetsContentViewsToSafeArea`, and listed in all objects after its constraints
and refresh control. IB lays them out whatever their frames: the header at the origin as wide as the table, its
subviews autoresized; the footer keeps its left and width, below the header, in a grouped table a section footer's height lower with
35 points for no header; both keep their heights (`sb-table-view-*`, `sb-table-header-frame-*`, `sb-table-footer-*`, round 156; the corpus's
netnewswire Inspector). Its own constraints are listed in all objects as a view's (the corpus's pocket-casts
CategorySummaryViewController). A grouped or inset grouped table without a background color gets
`systemGroupedBackgroundColor`; a plain one's background of white 1 named `whiteColor` or
`systemBackgroundColor` becomes the system color `tableBackgroundColor` (`table-background-*`).
`dataSource` and `delegate` are outlets as any.

## Table view controllers

A `<tableViewController>` scene (`sb-tvc-*`) compiles as a view controller's: a controller nib
`UITableViewController-<id>.nib` (class names `UITableViewController`) whose view nib holds the
`<tableView key="view">` as its top-level view, without the layout guides ibtool adds to other
scenes' views; the table's `dataSource` and `delegate` outlets to the controller go through
`UpstreamPlaceholder-1`. In a document using safe areas, a table or collection view controller's view
without a safe area guide compiles as in one without them (round 87, `sb-tvc-safe-areas-*`,
`sb-cvc-safe-areas-no-guide`; kickstarter's and nextcloud's settings storyboards). A table view controller's `<refreshControl>` is its table view's `UIRefreshControl`,
written after `UIAlwaysBounceVertical` and listed after the table view in all objects: a
`UIRefreshControl` of IB's frame, 1000 x 1000 at the origin whatever the document gives, with a
view's keys, `UIDisabled` true for `enabled="NO"` and `UIRefreshControlStyle` 2; its actions are
event connections of the view nib (round 109, `sb-tvc-refresh*`).

- Prototype cells (`dataMode="prototypes"`): each a nib of its own, File's Owner, First Responder
  and the cell compiled as a xib's cell (no safe area guide), in the table's
  `UITableViewCellPrototypeNibs` (an `NSMutableDictionary` from reuse identifier to a `UINib`:
  `captureEnclosingNIBBundleOnDecode` true and `archiveData` an `NSData` of the nested archive)
  and `UITableViewCellPrototypeNibExternalObjects` (the same identifier strings to empty
  `NSMutableDictionary`s), both after `UIInsetsContentViewsToSafeArea`, the identifiers in
  alphabetical order (`sb-tvc-prototype-five`). ibtool warns about a prototype without a reuse
  identifier, which nomac refuses.
- Static cells (`dataMode="static"`): a top-level `UITableViewDataSource` after the table
  (`UITableSections`: `UITableViewSection`s of `UITableSectionHeaderTitle` and
  `UITableSectionRows`, `UITableViewRow`s of `UITableRowCell` and `UITableRowHeight` -1 as a
  float), the cells compiled as cells in the view nib; File's Owner's `staticDataSource` outlet to
  it is the first connection. All objects lists the data source, then its sections, their cells
  (not the rows), then the cells' children as below. A section's `headerTitle`, in a document of
  `Base.lproj`, is an `NSLocalizableString` keyed `<section id>.headerTitle`.

A scene's `<collectionViewController>` (round 70, `sb-cvc*`) is compiled as a table view controller
(`UICollectionViewController` its original class), its `<collectionView key="view">` the view nib's
root without the controller's layout guides. `clearsSelectionOnViewWillAppear="NO"`, on either,
writes `UIClearsSelectionOnViewWillAppear` false after the controller's segue templates
(`sb-cvc-keeps-selection*`, `sb-tvc-keeps-selection`; nomac refuses it beside objects kept alive, a
presentation context or presentation styles). A controller's storyboard identifier is a string of
the document's, one object with an equal title or restoration identifier (`sb-cvc-netnewswire`).

## Table view cells

`IBUITableViewCellStyleValue2` is `UITableViewCellStyle` 2 with the two labels of value1 (`cm-value2`).
`colorLabel` changes nothing (`cm-color-label*`). A static cell's `rowHeight` is its row's `UITableRowHeight`,
-1 without one (`cm-sb-static-row-*`). A prototype's `<frame key="frameInset">` of a top, a width and a height
is that frame at x 0 (`cm-sb-proto-frame-inset`). ibtool warns of a prototype cell without a reuse identifier
or with an empty one, and leaves it out (`cm-sb-proto-no-reuse-*`, `cm-sb-proto-empty-reuse`). Refused for
now, their nibs differ: a guide in a content view
(`cm-content-guide-*`), a static cell's frame inset (`cm-sb-static-frame-inset`).

A xib's top-level `<tableViewCell>` (`cell-*`) is a `UITableViewCell` (a `UIClassSwapper` with
`UIOriginalClassName` `UITableViewCell` for a custom class): a view's keys, among them `tag` (0 writes
nothing), `userInteractionEnabled`, `hidden`, `alpha`, `insetsLayoutMarginsFromSafeArea` and `contentMode`
as on any view (`cell-attr-*`, `cell-mode-*`), and `focusStyle="custom"` as `UIFocusStyle` 1 after the
separator inset (`cell-attr-combination`). An `imageView`, one of the content view's image views, is written
as `UIImageView` after the labels and listed in all objects after the safe area and before the text label,
wherever the document has it, with or without a style (`cm-image-*`, `cm-sb-proto-image*`) (no
`UIOpaque` for `opaque="NO"`: `cell-opaque-*`; no `UIAutoresizingMask` for an empty mask;
`UIClearsContextBeforeDrawing` false for the cell's or its content view's
`clearsContextBeforeDrawing="NO"`: `cell-clears-*`, `cell-content-clears-no`;
`UIViewLayoutMarginsFollowReadableWidth` true for the cell's or its content view's
`layoutMarginsFollowReadableWidth="YES"`, before the preserved margins: `cell-readable*`,
`cell-content-readable`; an accessibility configuration as a view's, the content view's too, and
in a storyboard's prototype cell, whose nested nib keeps it: `cell-a11y*`, round 113
`cell-content-a11y*`, `cell-both-a11y`, `sb-cell-a11y`, `sb-cell-content-a11y`;
`UIViewLayoutMarginsFollowReadableWidth` true for the cell's or its content view's
`layoutMarginsFollowReadableWidth="YES"`, before the preserved margins: `cell-readable*`,
`cell-content-readable`; `UIViewPreservesSuperviewMargins` true and
`UIViewPreservesSpecificSuperviewMargins` 15 for `preservesSuperviewLayoutMargins`, on any view,
before `UIViewInsetsLayoutMarginsFromSafeArea`: the corpus's netnewswire settings cells), then
`UIReuseIdentifier`, `UIShowsReorderControl` true for `showsReorderControl`,
`UITableViewCellStyle` (Value1 1, Subtitle 3; Default writes none), `UIIndentationLevel`,
`UISelectionStyle` (none 0, blue 1, gray 2; the default writes none, and a cell without the attribute is
blue: `cell-selection-absent*`), `UIAccessoryType` and
`UIEditingAccessoryType` (disclosureIndicator 1, checkmark 3), `UIIndentationWidth` (float),
`UITableCellBackgroundColorSet` with a background color, `UISeparatorInset` (data 07, doubles top,
left, bottom, right of `<inset key="separatorInset">`'s minY, minX, maxY, maxX:
`cell-separator-inset-*`; after the flag: `cell-bg-sep`), `UISystemBackgroundView`,
`UIContentConfigurationView` nil, `UIContentView`, `UITextLabel` and `UIDetailTextLabel` (nil
without a style), `UIImageView` nil (`cell-all-keys`, `cell-style-*`); `rowHeight` writes
nothing.

- `UISubviews`: the content view, a `UITableViewCellContentView` (fallback `UIView`) compiled as
  a view, and a `_UITableViewCellSeparatorView` IB adds, at (8 + the separator inset's left,
  height - 1), as wide as the rest of the cell, 1 high (`cell-separator-inset-*`).
- The cell's and the content view's `<edgeInsets key="layoutMargins">` and
  `<directionalEdgeInsets key="directionalLayoutMargins">` are a view's margins; a constraint to the
  content view's margins moves by them (`cell-content-*`, `cell-directional*`). `userLabel` on a
  cell and `ambiguous` on its content view change nothing (`cell-user-label`,
  `cell-content-ambiguous`). A cell's `<color key="tintColor">` is a view's `UITintColor` (cwa's
  exposure detection cells).
- A selection style other than the default gives the cell `UIBackgroundColor` the system color
  `tableCellPlainBackgroundColor` (white 1), `UIDidEncodeCompatibilityBackgroundColor` true, and
  a `_UISystemBackgroundView` of the cell's bounds, its height rounded up
  (`cell-selection-none-height-*`: 44.1 gives 45), whose `configurationAPI` is a
  `UIBackgroundConfiguration` of nothing customized, that color, a `clearColor` stroke and the
  insets `{0, 0, 0, 0}`, one string of the nib (`cell-selection-*`; the corpus's tofu storyboard,
  six such static cells). A cell with a background color of its own keeps it, with
  `UITableCellBackgroundColorSet`, whatever its selection style, and gets no system background view
  (`cell-selection-*-background-*`).
- A cell of a built-in style (`style="IBUITableViewCellStyle..."`, `textLabel` and, but for
  Default, `detailTextLabel`: `cell-style-*`): its labels, subviews of the content view, are
  `UITableViewLabel`s, encoded as labels.
- All objects: the cell, then its children by their keys' order (content view, detail label,
  safe area guide, text label) and its content view's other subviews; the content view's own
  children are its constraints (`cell-style-*`, `mask-cell-group`; tofu's two static cells:
  content view, its subviews, the next cell's, then each content view's constraints).

## Text fields, switches and actions

`background` and `disabledBackground` are image placeholders, `UITextFieldBackground` and
`UITextFieldDisabledBackground` after `UITextColor` and before `UIBorderStyle`; a `background` also writes
`UIRoundedRectBackgroundCornerRadius` 0 (`cm-tf-background`, `cm-tf-disabled`, `cm-tf-both`, `cm-tf-same`,
`cm-tf-disabled-rounded`).

A `<textField>` (`tf-*`) is a `UITextField`: a view's keys, then `UIContentVerticalAlignment` and
`UIContentVerticalAlignment2` unless centered (bottom 2: `tf-valign-bottom`), `UIContentHorizontalAlignment`
(left 1, right 2, trailing 5; center, the default, writes none), `UIAdjustsFontForContentSizeCategory` true
for `adjustsFontForContentSizeCategory` (`tf-adjusts-content-size`), `UIFont` (as a label's), `UIPlaceholder`
(the attribute or a `<string key="placeholder">`: `tf-placeholder-string`), `UITextAlignment` (natural 4,
center 1, right 2, 0 without the attribute: `tf-no-alignment`, `tf-align-*`), `UIText` (in an `.lproj`
folder both `NSLocalizableString`s keyed `<id>.placeholder` and `<id>.text`), `UITextColor` (its
`<color key="textColor">`, else the system `labelColor`; `<nil key="textColor">` is none), `UIBorderStyle`
(line 1, roundedRect 3; none writes none), `UIClearsOnBeginEditing` true (`tf-clears-*`),
`UIAdjustsFontSizeToFit` true unless `adjustsFontSizeToFit="NO"`, `UIMinimumFontSize` (float, required),
`UIClearButtonMode` (whileEditing 1, unlessEditing 2, always 3; never writes none: `tf-clear-*`),
`UIClearButtonOffset` (data 07, doubles 3, 1), its input traits in this order: `UIAutocapitalizationType`
(words 1, sentences 2, allCharacters 3), `UIAutocorrectionType` and `UISpellCheckingType` (no 1, yes 2),
`UIKeyboardAppearance` (alert and dark 1, light 2), `UIKeyboardType` (alphabet 1, numbersAndPunctuation 2,
URL 3, numberPad 4, phonePad 5, namePhonePad 6, emailAddress 7, decimalPad 8, twitter 9, webSearch 10),
`UIReturnKeyType` (go 1, google 2, join 3, next 4, route 5, search 6, send 7, yahoo 8, done 9, emergencyCall
10, continue 11), `UIEnablesReturnKeyAutomatically` true, `UISecureTextEntry` true (which also writes
`UIAutocorrectionType` 1 when not given), `UITextContentType` (the string as written),
`UITextSmartInsertDeleteType`, `UITextSmartQuotesType` and `UITextSmartDashesType` (no 1, yes 2), and for
secure entry `UITextInlinePredictionType` 1; each trait's default writes nothing, as does the keyboard
`asciiCapableNumberPad` (`tf-trait-*`: every value of the coverage survey's documents and UIKit's,
`tf-traits-order*`, `tf-secure`), then `UIDisableTextColorUpdateOnTraitCollectionChange` true, and for a rounded border
`UIRoundedRectBackgroundCornerRadius` 0 (double).

A disabled text field writes `UIDisabled` true first (`tf-enabled-no`); a `tintColor` is a view's (`tf-tint`).
Its `background` and `disabledBackground` images are refused (B-260).

A `<switch>` (`sw-*`) is a `UISwitch`: a view's keys (its default hugging priority 750 writes
none), `UISwitchEnabled` true, `UISwitchOn` true for `on="YES"`, `UISwitchOnTintColor` and
`UISwitchThumbTintColor` for those colors (`sw-*-tint*`). The nib's
`UINibKeyValuePairsKey` holds, for each switch in all objects' order, a `UINibKeyValuePair`:
`UIObject` the switch, `UIValue` an `NSValue` (`NS.special` 3, `NS.rectval` the string
`{{x, y}, {width, height}}` of its document frame), `UIKeyPath` `frame`, the strings the nib's.

A control's `<action>` (`ev-*`, `act-*`) is a `UIRuntimeEventConnection`: `UILabel` the selector,
`UISource`, `UIDestination` (any object of the nib: File's Owner, a view, a cell, a scene's
controller through `UpstreamPlaceholder-1`), `UIEventMask`, `UIControl.Event`'s value
(touchDown 1, touchDownRepeat 2, touchDragInside 4, touchDragOutside 8, touchDragEnter 16,
touchDragExit 32, touchUpInside 64, touchUpOutside 128, touchCancel 256, valueChanged 4096,
primaryActionTriggered 8192, editingDidBegin 65536, editingChanged 131072, editingDidEnd 262144,
editingDidEndOnExit 524288; round 105, `act-control-*`), left out for an action without
`eventType` or of `menuActionTriggered`. Date pickers hold actions as other controls
(`act-date-picker`). The nib lists the actions after the outlets, by event mask (none first), then
selector, then source as "Connections" orders them (`act-with-outlets`, `act-field-mixed-no-event`,
`act-same-*`); of two
actions of one control without an event ibtool keeps one, which nomac refuses. Text fields,
switches, buttons, segmented controls, sliders and page controls take actions (`act-button-*`,
`act-segmented-value`, `act-slider-value`, `act-page-value`). A custom control, a `<view>` with a custom class and
actions, writes a view's keys (`act-control-*`). A text field or switch with a custom class names
`UITextField` or `UISwitch` as its original class (the corpus's pocket-casts FilterDownloadCell,
wikipedia ReadingListDetailHeaderView). An action to a
controller of another scene is left out without a warning (`sb-action-other-scene`; tofu's edit
scene).

## Activity indicators and other controls

Round 36 (`activity-*`, `segmented-*`, `progress-*`, `page-*`, `slider-*`). Each writes
`UIViewContentHuggingPriority` when it differs from its class's: 750 x 750 for activity
indicators, 250 x 750 for progress views; segmented controls, page controls and sliders write
`{250, 250}` always (their own priorities are refused until observed). Control keys are those of
"UIButton".

- `<activityIndicatorView>`, `UIActivityIndicatorView`: `UIActivityIndicatorViewStyle-Modern` and
  `UIActivityIndicatorViewStyle` (medium 100 and 1, large 101 and 0, white 1 and 1, whiteLarge 0
  and 0, gray 2 and 2), `UIHidesWhenStopped` false unless `hidesWhenStopped="YES"`,
  `UIAnimating` true, `UIColor` (the `<color key="color">` or nil), `UITintColor` (that color, or
  for medium and large the system `secondaryLabelColor`), and
  `UIDisableUpdateColorOnTraitCollectionChange` true with a color. A stopped indicator that does
  not hide when stopped writes no `UIHidden`, even with `hidden="YES"` (`activity-hidden-*`).
- `<segmentedControl>`, `UISegmentedControl` (with `UIAlpha` 0.5 when disabled, whatever its own:
  `segmented-control-disabled*`): its tint color as `UISegmentedControlTintColor` in
  `UITintColor`'s place, a control's keys with `UIPointerInteractionEnabled` always,
  `UIMomentary`, `UISegments` (a mutable array of the segments in order),
  `UIUseProportionalWidthSegments` (`apportionsSegmentWidthsByContent`),
  `UISelectedSegmentIndex` always (-1 without one), `UISegmentedControlSelectedSegmentTintColor`.
  Its subviews are its segments in order with the selected one last; all objects lists none of
  them. A `UISegment` is a view of 0 x 32 at 0, 0 whatever the control's height (`segmented-height-*`), not opaque, without a mask,
  `UIUserInteractionDisabled` for `enabled="NO"`, then `UISegmentInfo` (the title; in a document
  of `Base.lproj` an `NSLocalizableString` keyed `<id>.segmentTitles[<index>]`: `segmented-lproj`),
  `UISegmentWidth` (float), `UISegmentStyle` 5 and `UISegmentPosition`: 0 (not written) for the
  first segment, 3 for the second, 1 for the others (`segmented-positions-*`). A segment with an
  image makes ibtool exit 255 without a message.
- `<progressView>`, `UIProgressView`: `UIProgress` (float, unless 0), `UIProgressViewStyle` 1 for
  bar, `UIProgressProgressTintColor`, `UIProgressTrackTintColor`. Its height is at least 4; a
  bar's is the document's less one point, at least 3; the top stays (`progress-*height-*`).
- `<pageControl>`, `UIPageControl`: `UINumberOfPages` and `UICurrentPage` always,
  `UIHideForSinglePage`, `UIDefersCurrentPageDisplay`, `UICurrentPageIndicatorTintColor`,
  `UIPageIndicatorTintColor`.
- `<slider>`, `UISlider`: `UIValue` (float) always, `UIMinValue` unless 0, `UIMaxValue` unless 1,
  `UIContinuous` false, `UIMinimumValueImage`, `UIMaximumValueImage`, `UIMinimumTintColor`,
  `UIMaximumTintColor` (the track tints), `UIThumbTintColor`, `UIBehavioralStyle` 0.

## Visual effect views

A `<visualEffectView>` is a `UIVisualEffectView` (`effect-*`, round 38), listing in all objects its content view,
that view's subviews, then its own constraints (`effect-own-constraint*`): a view's keys with
`UIShouldNotAdaptToMaterials` true after `UIAutoresizingMask` and no `UISubviews`, then
`UIVisualEffectViewEffect`, `UIVisualEffectViewGroupName` nil and `UIVisualEffectViewContentView`.
The effect is a `UIBlurEffect`: `UIBlurEffectMaterialStyle`, `UIBlurEffectAutomaticStyle` and
`UIBlurEffectStyle` by IB's style (extraLight -, -, 0; light -, -, 1; dark -, -, 2; regular -, 4,
1; prominent -, 5, 0; systemUltraThinMaterial 6, 4, 1; systemThinMaterial 7, 4, 1; systemMaterial
8, 4, 1; systemThickMaterial 9, 4, 1; systemChromeMaterial 10, 5, 0; systemMaterialDark 18, -, 2;
`effect-style-*`). The content view, `<view key="contentView">`, is a `_UIVisualEffectContentView`
with its attributes and `UIShouldNotAdaptToMaterials`; all objects lists it after the effect
view's constraints, then its subviews, as the effect view's children, as a cell's content
subviews; the content view's own children are its constraints (`effect-label-constraints`,
`effect-label-sibling-*`, `effect-label-constraints-sibling`; the corpus's cwa
ExposureDetectionViewController).
Vibrancy effects are refused.

A `<vibrancyEffect>` (round 123 and 124, `vibrancy-*`, `vibrancy-grid-*`) holds a `<blurEffect>`: a
`UIVibrancyEffect` writing, over a material, `UIVibrancyEffectVibrancyStyle` (label 0, secondaryLabel 1, its
default, tertiaryLabel 2, quaternaryLabel 3, fill 4, secondaryFill 5, tertiaryFill 6, separator 7), then its
blur's `UIVibrancyEffectBlurMaterialStyle`, `UIVibrancyEffectBlurAutomaticStyle` and `UIVibrancyEffectBlurStyle`.
Its content view writes a `UITintColor` the document does not name: `whiteColor`, or for the label style over a
material 96% black, over a dark material 96% white.

## Collection views

A collection view lists in all objects its layout, then its safe area, constraints and subviews (`collection-safe-area*`;
the survey's woocommerce ProductImagesHeaderTableViewCell). A `<collectionView>` of a xib without prototypes
(`dataMode="none"`; `collection-*`, round 45) is a
`UICollectionView`: a view's and a scroll view's keys (as in "UIScrollView"), then
`UICollectionLayout`, `UIAllowsUserInitiatedMultipleSelection` true and
`UICollectionViewPrefetchingEnabled` (false for `prefetchingEnabled="NO"`). A white gray background
(the color nomac names `whiteColor`) is the system `systemBackgroundColor`; an sRGB white, clear and
black stay (`collection-background-*`). The layout is listed in all objects before the collection
view's constraints (`collection-height`). A `<collectionViewFlowLayout>` is a `UICollectionViewFlowLayout` writing, when
they differ from its defaults, `UIInteritemSpacing` and `UILineSpacing` (floats, 10),
`UIItemSize` (07 then two doubles, 50 x 50), `UIHeaderReferenceSize` and `UIFooterReferenceSize`
(0 x 0), `UISectionInset` (top, left, bottom, right), `UISectionInsetReference` 1 for the safe
area and `UIScrollDirection` 1 for horizontal (`collection-flow-*`);
`automaticEstimatedItemSize="YES"` writes a runtime attribute instead: the layout's
`estimatedItemSize`, an `NSValue` of `{1.7976931348623157e+308, 1.7976931348623157e+308}`
(`collection-flow-estimated`). A `<collectionViewLayout>` with a custom class is a
`UIClassSwapper` of class names only (`UICollectionViewLayout`). With `dataMode="prototypes"` it writes
`UIDelegate` nil (after the scroll view's keyboard dismiss mode) and, for prototype cells (in
storyboards: `sb-collection-*`, round 48), after `UIAllowsUserInitiatedMultipleSelection`:
`UICollectionViewCellPrototypeNibExternalObjects` (a mutable dictionary from each reuse identifier to
an empty mutable dictionary) and `UICollectionViewCellNibDict` (from each reuse identifier to a
`UINib` of the cell's own nib, as table prototypes), by reuse identifier in byte order. A prototype
cell's nib holds File's Owner, First Responder and the cell compiled as in "Collection view cells",
the older template only, without the generated constraints and with a content view that does not
write `UIViewDoesNotTranslateAutoresizingMaskIntoConstraints` (`sb-collection-cell*`).


A collection view in prototypes mode with `<collectionReusableView key="sectionHeaderView">` or
`key="sectionFooterView"` archives each as a nib of its own (`sb-section-*`, `sb-cvc-section-*`):
File's Owner, First Responder and the reusable view with its subviews, constraints, mask and reuse
identifier, as in a xib. `UICollectionViewSupplementaryViewPrototypeNibExternalObjects` follows the
cells' external objects and `UICollectionViewSupplementaryViewNibDict` the cells' nibs, each keyed by
`UICollectionElementKindSectionFooter/<reuse identifier>` and
`UICollectionElementKindSectionHeader/<reuse identifier>`, the footer first; with no cells only these
two are written. An outlet from the view to the controller goes through the nested nib's
`UpstreamPlaceholder-1`, the external objects mapping it to the view nib's placeholder of the
controller, which the view nib then has even without other outlets (`sb-section-footer-outlet-only`).
Without a reuse identifier ibtool warns `Prototype collection view section header or footer views must
have reuse identifiers [9]` at the view and drops it; two views of one reuse identifier are an error
(`sb-section-footer-same-reuse`), which nomac refuses. The flow layout's reference sizes change only
its own keys (`sb-section-footer-no-sizes`).
## Text views

A `<textView>` is a `UITextView` (`text-view-*`, round 51): a view's and a scroll view's keys (as in
"UIScrollView"), then, with a text (`text` attribute or `<string key="text">`), `UIText` (an
`NSLocalizableString` in a document of `Base.lproj`, `text-view-lproj`, a plain string for a custom class:
`text-view-custom-lproj`) and
`UIAttributedText`, an `NSAttributedString` of the plain string (past 512 characters both are
`NSMutableString`s, two objects, whatever the form, the plain one localizable as any in an `.lproj`
folder; labels' texts stay `NSString`s: `text-view-length-*`, `label-length-*`, round 46;
wikipedia's LibrariesUsed; `text-view-length-*-lproj`, round 80) with an `NSDictionary` of `NSColor`
(the text color, when there is one), `NSFont` (the view's font) and `NSParagraphStyle` (an
`NSMutableParagraphStyle` of `NSAlignment` in AppKit's values, center 2, natural 4, none for left,
and `NSTabStops` nil); then `UIFont` (the system font of 17 points without a description,
`text-view-no-font`; before it `UIAdjustsFontForContentSizeCategory` true for a text style's font
with `adjustsFontForContentSizeCategory="YES"`, `text-view-adjusts*`), `UITextColor` when there is one, `UITextAlignment` always (natural 4, center 1,
0 without the attribute), then, each only when it differs from IB's, `UIEditable` false,
`UIDataDetectorTypes` (phone number 1, link 2, address 4, calendar event 8: `text-view-detect-*`),
`UISelectable` false and the input traits:
`UIAutocapitalizationType` (0 without the attribute, nothing for sentences, words 1),
`UIAutocorrectionType` and `UISpellCheckingType` (no 1, yes 2), `UIKeyboardType` (URL 3),
`UIKeyboardAppearance` (alert 1), `UIReturnKeyType` (done 9), `UIEnablesReturnKeyAutomatically`
true, `UITextContentType` (the string, `url`), `UITextSmartInsertDeleteType`,
`UITextSmartQuotesType` and `UITextSmartDashesType` (no 1) (`text-view-all-flags`,
`text-view-traits-*`); a missing `<textInputTraits>` is an empty one. Last come
`UITextHighlightAttributes` (an `NSDictionary` of `NSColor` the view's tint, else its direct superview's, a
storyboard's global tint for a scene's root view, not a grandparent's, else the system `systemBlueColor`:
`text-view-tint-*`, `sb-text-view-tint-*`; and `NSTextHighlightOutlineColor` the system `secondarySystemFillColor`) and
`UITextAllowsNumberPadPopover` true, then a custom class's names. A text view that does not scroll
writes no `UIClipsToBounds` even with `clipsSubviews="YES"` (`text-view-scrollEnabled-NO`, a scroll
view's does), and a white gray background is the system `systemBackgroundColor` as in "Collection
views" (`text-view-white`). `<nil key="text"/>` is no text (`text-view-nil-text`), and
`allowsEditingTextAttributes="YES"` writes `UIAllowsEditingTextAttributes` true after the scroll view's
keys (`text-view-editing-attributes`; with a text it is refused). Other alignments with a text, detector types and trait values are refused
until observed. Text views of one font, text color and alignment share their attributed texts'
attributes dictionary and paragraph style, whatever their texts (round 106, `text-view-two-*`).

## Toolbars

A `<toolbar>` among subviews (round 61, `toolbar-*`, `sb-toolbar`) is a `UIToolbar`: a view's keys,
`UIViewContentHuggingPriority` `{250, 250}` included, then `UIItems` (the nib's one empty array,
which the root's empty lists share, for `<items/>` or no `<items>`), `UIBarPosition` 1 and
`UIBarTranslucence` 1. A navigation controller's `<toolbar key="toolbar">` is in "Navigation
controllers".

Bars (`bars-tb-*`, `bars-nb-*`, `bars-sbn-*`). `barStyle` writes `UIBarStyle` (`black` and
`blackOpaque` 1, `blackTranslucent` 2), `translucent="NO"` makes `UIBarTranslucence` 2, and a
navigation controller's bar then also writes `UIOpaque`. The keys of a bar, in order: `UIBarStyle`,
`UIBarPrefersLargeTitles`, `UIBarLargeTitleTextAttributes`, `UIIsLocked` (a controller's bar),
`UIBarTintColor`, `UIItems`, `UIDelegate` (a controller's bar), `UIShadowImage`, `UITitleTextAttributes`,
`UIBarPosition`, `UIBarTranslucence`, then a custom class's names. `<textAttributes>` is a dictionary
of `NSColor`, `NSFont`, then `NSShadow` (`NSShadowHoriz` and the vertical offset negated as `NSShadowVert`, each when
not 0, and `NSShadowColor`, the `textShadowColor` or nil: `sb-nav-bar-title-*`); empty ones, which share the nib's empty
dictionary, are refused. A controller's bar without a frame is at the origin (`sb-nav-bar-frameless*`), and its
`backgroundColor` is a view's key (`sb-nav-bar-background`).

Bar button items (`bars-tb-*`, `bars-ni-*`). The keys, in order: `UIEnabled` unless disabled,
`UIIsSystemItem` and `UISystemItem`, `UIStyle`, `UITag`, `UIHidesSharedBG` (the two spaces),
`UITitle` (an empty one writes none), `UIWidth` (a float, only when positive, on a titled or image item or a
fixed space, `bars-tb-width-*`; on another system item ibtool prints a note and nomac refuses it), `UIImage`
(an empty one writes none, `bars-tb-image-empty`), `UITintColor`, a custom
class's `UIClassName` and `UIOriginalClassName`. `UIStyle` is 1 without a `style`, 2 for `done`, and
absent for `style="plain"`. `userLabel` changes nothing. System items: `flexibleSpace` 5,
`fixedSpace` 6, `pause` 18, `rewind` 19, `fastForward` 20, `undo` 21, `redo` 22, `pageCurl` 23,
`close` 0, the others in `NibBarButtonItem.systemItems`. Items in `<items>` are listed in all objects
after the toolbar, in order; actions have no event mask and sort as other actions do. ibtool warns
"Plain Style unsupported in a Navigation Item" for `style="plain"` in a navigation controller's or a
view controller's navigation item, and nomac too (`bars-ni-plain-*`, `bars-ni-item-empty`). A navigation
item's title is trimmed, and one of whitespace only is written in curly quotes, “ ” (`bars-ni-title-space-*`).

Navigation items (`bars-ni-*`). The keys, in order: `UITitle`, `UIAttributedTitle`, `UIPrompt`,
`UILeftItemsSupplementBackButton`, `UILeftBarButtonItem`, `UIRightBarButtonItem`,
`UILeftBarButtonItems`, `UICenterItemGroups`, `UIRightBarButtonItems`, `UILargeTitleDisplayMode`
(`always` 1, `never` 2), `UINavigationBar`. With `<leftBarButtonItems>` or `<rightBarButtonItems>`, the
single item is the first of the list. `userLabel` and `<nil key="title">` change nothing. Refused for
now: a back item beside a left or right one, a prompt or `leftItemsSupplementBackButton`
(`bars-ni-back-*`), several items on one side with actions of one selector (`bars-ni-right-two-same`),
and `<barButtonItem>` in `<toolbarItems>` (`bars-vc-*`: `UIToolbarItems` after
`UIParentViewController`).

## Web views

A `<wkWebView>` (round 62, `web-view*`, `sb-web-view`) is a `WKWebView` (a custom class's original):
a view's keys, then `configuration`, a `WKWebViewConfiguration` of IB's defaults (`processPool` a
`WKProcessPool` and `userContentController` a `WKUserContentController`, both without keys,
`preferences` a `WKPreferences` of its `minimumFontSize` (double, 0 without one) and IB's defaults,
`websiteDataStore` a `WKWebsiteDataStore` with `isDefaultDataStore` true, `applicationNameForUserAgent`
the empty string, `dataDetectorTypes` 127 and IB's other booleans), `allowsBackForwardNavigationGestures`
false, `customUserAgent` the same empty string, `allowsLinkPreview` true and `findInteractionEnabled`
false. The document's settings change their values only, the keys and their order staying (round 114,
`web-config-*`, `web-media-*`, `web-detect-*`, `web-prefs-*`, `web-view-*`): the configuration's
`allowsInlineMediaPlayback`, `allowsAirPlayForMediaPlayback`, `allowsPictureInPictureMediaPlayback`,
`suppressesIncrementalRendering`, `ignoresViewportScaleLimits`, `applicationNameForUserAgent` and
`selectionGranularity` (dynamic 0, character 1); `mediaTypesRequiringUserActionForPlayback` a boolean,
false for `none`, true for audio, video, both or no `<audiovisualMediaTypes>`; `dataDetectorTypes`
127 without a `<dataDetectorTypes>`, else its bits (phone number 1, link 2, address 4, calendar event
8, tracking number 16, flight number 32, lookup suggestion 64; 0 for `none` or none named); the
preferences' `javaScriptCanOpenWindowsAutomatically` and `javaScriptEnabled`; the web view's
`allowsBackForwardNavigationGestures`, `allowsLinkPreview` and `customUserAgent`, a string of the
document's pool like the application name, so equal ones are one object. ibtool fails on a web view
without a configuration or preferences, and nomac refuses those.

## Navigation bars among subviews

A `<navigationBar>` among subviews (round 64, `nav-bar-sub-*`, `sb-nav-bar-sub`), not a navigation
controller's, is a `UINavigationBar`: a view's keys, not opaque unless `translucent="NO"`, with
`UIViewContentHuggingPriority` `{250, 250}` and zero `UIViewLayoutMargins`, directional, then `UIItems` (a
mutable array of its `UINavigationItem`s, listed in all objects after its constraints: `UITitle` and
`UIAttributedTitle` for a title, its bar button items as a navigation controller's, the nib's empty array
as `UICenterItemGroups`, `UILargeTitleDisplayMode` 0 and the bar), `UIBarPosition` 2 and
`UIBarTranslucence` (1, 2 for `translucent="NO"`). A bar button item's `style="done"` is `UIStyle` 2.

## Map views

A `<mapView>` (round 123 and 124, `map-*`, `sb-map`) is an `MKMapView`: a view's keys with
`UIViewLayoutMargins` all 0, then `MKDelegate` nil (its outlet is a connection), `MKMapType` (standard 0,
satellite 1, hybrid 2, satelliteFlyover 3, hybridFlyover 4, mutedStandard 5), `MKZoomEnabled`,
`MKScrollEnabled`, `MKShowsUserLocation`, `MKPitchEnabled`, `MKRotateEnabled`, `MKShowsBuildings` (true whatever
the document), `MKShowsTraffic`, `MKShowsCompass`, `MKShowsScaleKey`, `MKShowsPointsOfInterest`,
`MKPointOfInterestFilter` nil, `MKPreferredConfiguration`, `MKPitchButtonVisibility` 1 and
`MKShowsUserTrackingButton` false. The configuration is `MKStandardMapConfiguration` for the standard and muted
types (with `MKStandardMapConfigurationEmphasisStyle` 0, muted 1), `MKImageryMapConfiguration` for satellites and
`MKHybridMapConfiguration` for hybrids: `MKMapConfigurationElevationStyle` (1 for flyovers), `ShowsTraffic` (the
map's, but false for imagery), `ShowsHiking` and `ShowsTopographicFeatures` false, `PointOfInterestFilter` nil. A
`<standardMapConfiguration>` wins over `mapType`, the map then of type 0, its `elevationStyle` and
`showsTraffic` also the map's traffic.

## Date pickers and picker views

A `<datePicker>` (rounds 65 and 158, `date-picker-*`) is a `UIDatePicker`: a view's keys, then `UIContentHorizontalAlignment` when
not centered (left 1, right 2, fill 3, leading 4, trailing 5; a centered `compact` one writes 5), `UIPickerStyle` (wheels 1, compact 2, inline 3,
automatic none; a `wheels` one is 320 x 216 at its frame's origin), `UIDatePickerMode` (time 0, date 1, count-down 3; `dateAndTime` none),
`UICountDownDuration` 60 (float) for a count-down timer, `UIMinuteInterval` when not 1, 0 without the attribute, and, for `useCurrentDate="NO"`,
`UIDatePickerUseCurrentDateDuringDecoding` false. A count-down timer of a style or another interval, whose duration and hugging change, is refused. A `<pickerView>` (`picker-view*`) is a `UIPickerView`: a
view's keys, `UIViewContentHuggingPriority` `{250, 250}` included, then `UIAllowSelectingCells` true. Date
pickers' `<date>`s are refused. IB's `<attributedString key="userComments">` on a view
changes nothing (`user-comments-label`).

## Collection view cells

A top-level `<collectionViewCell>` of a xib is a `UICollectionViewCell` (`cvcell-*`, round 35):
a view's keys, its one subview the content view, `UIViewAutolayoutConstraints` four constraints
IB generates pinning the cell's leading, trailing, top and bottom to the content view's
(`NSLayoutIdentifier` `UIIBSystemGenerated`, not listed in all objects), then
`UIReuseIdentifier`, `UISystemBackgroundView` and `UIContentConfigurationView` nil, and
`UIContentView`. A `<size key="customSize">` changes nothing. The content view writes
`UIViewDoesNotTranslateAutoresizingMaskIntoConstraints` and keeps the document's mask, an empty
one included (`cvcell-*content-mask-*`; the corpus's wikipedia DiffListUneditedCell).

Xcode 12's template, `<collectionViewCellContentView key="contentView">`, is compiled as a view
with its attributes; all objects lists the content view, then the cell's safe area placeholder.
The older template, `<view key="contentView">`, is a plain view whatever its attributes (opaque,
scale to fill, `insetsLayoutMarginsFromSafeArea` ignored: `cvcell-old-content-insets*`); all objects skips it, listing the cell's safe area placeholder, then the content
view's subviews and constraints. The cell's `<constraints>` move to the content view, an item
naming the cell standing for the content view (`cvcell-old-label-cell-constraints`), and the
content view lists its safe area guide (as in "Constraints") when the cell has a safe area and
the content view has subviews, whether or not a constraint names it (`cvcell-old-label`,
`cvcell-old-height`, `cvcell-old-label-no-safe-area`). In Xcode 12's template ibtool drops the
cell's constraints (`cvcell-label-cell-constraints`); nomac refuses them.

In a storyboard with `useSafeAreas="YES"` a section view has a safe area guide in all objects, written or not
(`sb-section-safe-*`; the survey's betcalsa). A top-level `<collectionReusableView>` is a `UICollectionReusableView`: a view's keys, then
`UIReuseIdentifier` (`reusable-*`).


A mask in a `<collectionViewCell>` with its constraints on the cell, an old cell's (`<view
key="contentView">`), compiles against the content view, which installs the constraints, but its
`_UIRelationshipTraitStorage` is the cell's: `UIObject` is the cell, and its descendants leave out
the content view, a subviews mask's being empty. The trait storage list walks the cell, then its
content view once (`sb-cvmask-holder-mask`). Subviews the default mask excludes do not count for the
content view's safe area guide (`cvmask-old-*`). A current cell's content view has its own
constraints and masks as any view (`cvmask-new-content*`); ibtool crashes on a mask on such a cell
(`cvmask-new-on-cell`), which nomac refuses, as it does constraints on one.

A prototype cell has `UIIBSystemGenerated` constraints to its content view, which then does not
translate its mask, only with constraints of its own on the cell; constraints deeper in the cell do
not count (`sb-cvmask-none`, `sb-cvmask-own-constraint`, `sb-cvmask-holder-constraint`).
## User-defined runtime attributes

An object's `<userDefinedRuntimeAttributes>` (views of every kind and File's Owner; `udra-*`, round
39) become the root's `UINibKeyValuePairsKey`: an `NSArray` of `UINibKeyValuePair`s (`UIObject`,
`UIValue`, `UIKeyPath`), by the decimal strings of their objects' places in all objects plus one,
compared byte by byte (`10` before `4`, `100` between `10` and `11`), those of one object in the
document's order. This fits every nib with pairs on several objects: 153 of the corpus and the
experiments, 48 of the holdout not seen when the rule was found, and `udra-order-root-many-*`,
`udra-order-owner-many-*`, `udra-order-owner-root-many-*`, `udra-order-many-97` to `-120` and
`-1100-every-37`, recorded to test it (round 117, B-290). What the default size class's masks exclude from a view,
constraints or subviews, is counted after what the view lists and what the excluded subviews list, so later
objects of the list take lower numbers; other size classes' masks count for nothing (`mask-pairs-*`, round 143;
organicmaps' LocationServicesDisabledAlert, mapsme's MWMMapDownloadDialog, PixPic's PostViewCell).
Accessibility configurations follow the walk of "Connections" (`a11y-order-many-*`, `a11y-walk-*`, `sb-a11y-walk-*`). Values: `number`
an `NSNumber` (`<integer>` `NS.intval`, `<real>` `NS.dblval`, 4 as 4.0), `boolean` the integers 1
and 0, `string` a string (plain in an `.lproj` folder too: `udra-lproj`), `color` a `UIColor`,
`size` an `NSValue` (`NS.special` 2, `NS.sizeval` the string `{0, 2}`; fractional sizes are
refused until observed), `image` an image placeholder (SF Symbols too), `point` and `rect`
`NSValue`s (`NS.special` 1 with `NS.pointval` `{0.5, 0}`, 3 with `NS.rectval` `{{1, 2}, {3, 4}}`:
whole coordinates without a fraction, others as their shortest form, which nomac takes only where
it is also `%.17g`'s), `range` an `NSValue` (`NS.special` 4, `NS.rangeval.length` then
`NS.rangeval.location`, numbers; equal ones are refused until observed), `nil` no `UIValue`, and
`localizedString` a string outside `.lproj` folders (round 100, `udra-point*`, `udra-rect`,
`udra-range`, `udra-nil`, `udra-localized`). Table and collection view cells and their content
views, reusable views, switches, sliders and progress views hold pairs as any view
(`udra-tv-*`, `udra-cv-*`, `udra-reusable`, `udra-switch`, `udra-slider`, `udra-progress`), so do
flow layouts (`udra-flow-layout`; beside an automatic estimated item size they are refused) and
storyboard container views (`sb-udra-container`). In a storyboard the pairs of a scene's views are
in the view's nib; those of a navigation controller's bar and its root's bar button items are in
the navigation controller's nib, the view nib having none (round 101, `sb-udra-bar-item*`,
`sb-udra-nav-bar`; elsewhere they are refused); attributes of view controllers are refused.

Equal numbers are one `NSNumber` across the nib, the first encoded, whatever their types: YES,
the integer 1 and the real 1 are one object written `NS.intval` 1 (`udra-bool-int-one`), a runtime
real 17 is the label font's size number (`udra-label-real-17`), a runtime integer 0 is a button's
normal state key (`udra-button-int-zero`).

## Accessibility

An object's `<accessibility key="accessibilityConfiguration">` (views of every kind; `a11y-*`, round
40) becomes a `UIRuntimeAccessibilityConfiguration` in the root's
`UINibAccessibilityConfigurationsKey`, in the order of the objects in all objects
(`a11y-parent-child`): `UIAccessibileObject` (sic), then, each when given, `UIAccessibilityHint`,
`UIAccessibilityIdentifier`, `UIAccessibilityLabel`, `UIAccessibilityTraits` (an `NSNumber` of
the trait bits: button 1, link 2, image 4, selected 8, staticText 64, summaryElement 128,
notEnabled 256, adjustable 4096, header 65536, none 0) and `UIIsAccessibilityElement` (an
`NSNumber` 1 or 0); numbers are shared as in "User-defined runtime attributes". An empty
configuration writes its object alone (`a11y-empty`). In an `.lproj` folder the label and hint
are `NSLocalizableString`s keyed `<id>.accessibilityLabel` and `<id>.accessibilityHint`, the
identifier a string (`a11y-lproj`). In a storyboard a scene's configurations are in its view's
nib (`sb-a11y`).


Traits by bit: playsSound 16, keyboardKey 32, updatesFrequently 512, searchField 1024,
startsMediaSession 2048, allowsDirectInteraction 8192, causesPageTurn 16384 (`mx-trait-*`).
`<string key="label">` and `<string key="hint">` are the attributes' values (`mx-a11y-string-*`).

## Gesture recognizers

Top-level `<tapGestureRecognizer>`, `<swipeGestureRecognizer>` and `<panGestureRecognizer>` of a xib
(round 50, `gesture-*`) are `UITapGestureRecognizer`, `UISwipeGestureRecognizer` and
`UIPanGestureRecognizer`: `UIGestureRecognizer.disabled` true for `enabled="NO"`,
`UIGestureRecognizer.allowedTouchTypes` 15, `UIGestureRecognizer.requiresExclusiveTouchType` true, then
for a tap `UITapGestureRecognizer._imp`, a `UITapRecognizer` writing
`UITapRecognizer.numberOfTapsRequired` and `numberOfTouchesRequired` when not 1; for a swipe
`UISwipeGestureRecognizer.direction` (left 2, up 4, down 8; right not written); for a pan
`UIPanGestureRecognizer.allowedScrollTypesMask` 0. IB's `<pongPressGestureRecognizer>` is a
`UILongPressGestureRecognizer`: its `_imp` a `UITapRecognizer` of `numberOfTapsRequired` 0, then
`minimumPressDuration` and `allowableMovement` floats unless 0.5 and 10; pinch and rotation
recognizers write nothing more; a screen edge pan recognizer has `allowedTouchTypes` 11, then
`UIPanGestureRecognizer.allowedScrollTypesMask` 0 and `UIScreenEdgePanGestureRecognizer.edges` 0
(round 105, `gesture-long-press*`, `gesture-pinch`, `gesture-rotation`, `gesture-edge-pan`,
`sb-gesture-long-press`, `sb-gesture-pinch`). A view attaches them with an outlet collection
`gestureRecognizers` with `appends="YES"`: `addsContentToExistingCollection` true and, without a
`collectionClass`, `runtimeCollectionClassName` `NSArray`. Their actions are
`UIRuntimeEventConnection`s without an event, those of one selector by class, then in the top-level
objects' order (`gesture-two-*`, `gesture-three-*`). IB's empty `<gestureRecognizers/>` element of a view or a collection
view cell changes nothing (`gesture-empty-element*`, `cvcell-gesture-element`, `sb-gesture-no-empty-element`).

In a storyboard (round 52, `sb-gesture-*`) a recognizer is an object of its scene after First
Responder, compiled as in a xib into the controller's nib: a top-level object after the storyboard
placeholder and before the controller, which keeps it alive (`UITopLevelObjectsToKeepAliveFromStoryboard`)
and loads its view nib with it as `UpstreamPlaceholder-1` (`UIExternalObjectsTableForViewLoading`),
then the controller as `UpstreamPlaceholder-2` when the view nib refers to it
(`sb-gesture-and-controller`): the two are numbered as the view nib's connections, sorted, first
reach them, so the controller is `UpstreamPlaceholder-1` when one of its outlet collections sorts
before the `gestureRecognizers` collection attaching the recognizer (round 107,
`sb-gesture-controller-collection` against `-collection-zzz` and `-outlet`; wikipedia's
EditSaveViewController), the controller's nib mapping them likewise. The view nib lists the two
placeholders after First Responder in that order, and the attaching outlet collection goes to it, from a subview or the
root view (`sb-gesture-root`). The recognizer's actions to the controller are event connections of
the controller's nib after the `sceneViewController` outlet (`sb-gesture`, `sb-gesture-no-action`); a
segue from it is a template the recognizer fires with `perform:` (`sb-gesture-segue`), which nomac
refuses for now. Several recognizers in a scene are refused (B-291): self-written scenes fit one
numbering of their placeholders (`sb-gesture-three*`, `sb-gesture-nested`, `sb-gesture-predict`),
which the corpus's wikipedia DescriptionEditViewController contradicts.

## Connections

`UINibConnectionsKey` lists an object's `<connections>` (`outlet-*`): an
`UIRuntimeOutletCollectionConnection` per outlet collection first (`UILabel`, `UISource`,
`UIDestination` an `NSMutableArray` of its destinations in document order,
`runtimeCollectionClassName` the string `NSMutableArray`, `addsContentToExistingCollection`
false), then a `UIRuntimeOutletConnection` per outlet (`UILabel` the property, `UISource`,
`UIDestination`), by name, byte by byte (`A2`, `Beta`, `_under`, `a1`, `a10`, `a2`, `alpha`),
those of one name placeholders first (File's Owner whatever its class: `oc-class-zowner-image`),
then by their sources' original classes, byte by byte (`UIImageView`, `UIScrollView`, `UIView`; a
custom class counts as its original: `oc-class-*`, the corpus's pocket-casts
SharePublishViewController), then by a walk of the nib's views (below), whatever the document's
order or ids (`outlet-from-both`, `outlet-same-name-*`, `outlet-same-tree-*`). Names are one
string object each. Sources are File's Owner and views; destinations views, placeholders,
constraints, gesture recognizers and a navigation bar's item and bar button items
(`outlet-nav-bar-*`). A prototype cell's outlet to an object of its controller's nib is not
compiled yet (`sb-outlet-bar-tvc-from-cell`), and nomac's refusal of a destination names its
element. The corpus's 483 nibs with plain outlets all follow this. Outlet collections of one
name from several sources, by the first class among the recognizers they attach when they attach some (`gesture-kinds-*`, ADR 0260), follow the same order (`oc-class-collections`, `oc-names-two-sources`,
the corpus's wikipedia WMFImageGalleryDetailOverlayView). Collections of several names from one
source keep the order of their names' first connections in the document, whatever the names or
ids (`oc-names`, `oc-names-seven`, `oc-names-root-seven`, five runs alike; the corpus's wikipedia
ReadingThemesControlsViewController and WMFEditorToolbarHighlightView). Of several sources, File's
Owner's and a view's, ibtool's order changes from run to run: `oc-mix-a`, `oc-mix-h` and
`oc-mix-k` (round 95) came out in three or four orders in four runs each, with File's Owner's own
collections out of document order at times. nomac writes them by name, byte by byte, those of one
name as the outlets' rule orders them, one of ibtool's orders (`oc-mix-a`, `oc-mix-h` are byte for
byte one of their runs); a nib differing from Xcode's only there is equivalent (ADR 0260). Actions
follow the outlets ("Text fields, switches and actions").

Connections of one name, and of one event and selector, from sources of one original class go by a
walk of the nib's views from its top-level objects, in order, whatever the frames or ids (rounds
118 and 119). A xib walks depth first (`act-same-tree-*`, `outlet-same-tree-*`,
`act-same-top-nested`). A storyboard takes all of a view's subviews in order, then goes on from the
last one taken, as a stack: for the tree `[[1, [2, 3], 4], 5, [[6], 7], 8]` the order 5, 8, 7, 6, 1,
4, 2, 3 (`sb-act-same-*`, `sb-outlet-same-tree-*`; the corpus's uncloudnotes DogDoodies, wikipedia
WMFTwoFactorPasswordViewController, the holdout's FancyAlerts). One top-level view follows another,
a static cell being one, in the document's order; under a static or prototype cell each view takes
its subviews last first: `[a, [b, c], d]` in a cell gives d, a, c, b (`sb-static-same-*`,
`sb-proto-cell-outlet-*`; tofu's AccountCreation). A segue's placeholders, as an embed's
`containerView` sources, go in their numbering (`sb-nested-embeds-*`, wikipedia's
DescriptionWelcome). Recognizers and other objects
outside the views follow them, in all objects (`gesture-two-taps`). Of two `<connections>` of one
element ibtool reads the first (`gesture-two`). An `<outlet>`, `<outletCollection>` or `<action>` without an `id` is
dropped, in xibs and storyboards alike (`cid-outlet-no-id*`, `conn-no-id-*`, `sb-conn-no-id`).

## UIColor

A `UIColor`, with the fallback class `NSColor` (`gray-*`, `rgb-*`, `system-*`, `systemColor-*`,
`cocoa-*`, `cocoaTouchSystemColor-*`, `named-color`, `same-*`, `color-key-*`, `two-*`,
`three-colors`, `rgb-then-same-gray`). Keys in this order:

| Key | Value |
|---|---|
| `UISystemColorName` | an `NSString`: the `systemColor` or `cocoaTouchSystemColor` name; `blackColor`, `whiteColor` and `clearColor` for the gray colors white 0 alpha 1, white 1 alpha 1 and white 0 alpha 0 |
| `UIDynamicCatalogName`, `UIDynamicCatalogUseNibBundle` | for a named color: its name, an `NSString`, and true |
| `UIColorComponentCount` | 2 for gray, 4 for RGB |
| `UIWhite`, or `UIRed`, `UIGreen`, `UIBlue` | floats, each followed by `<key>-Double`, the double, when the float is not the value |
| `UIAlpha` | float, followed by `UIAlpha-Double` in the same way |
| `NSWhite` or `NSRGB` | data: the components as text, `%.3g` each and separated by spaces, then the alpha unless it is 1 |
| `NSColorSpace` | 4 for gray, 2 for RGB |

- Components are those written with `colorSpace="custom"` and `customColorSpace`
  `genericGamma22GrayColorSpace` (gray) or `sRGB` (RGB). ibtool converts the other color spaces by
  color management ("Color conversions" below). A `calibratedWhite` gray (either form) becomes a
  generic gray of a float white: 0 and 1 stay (and take the gray names), 0.5 gives 0.572306752204895
  (`calibrated-white`, `cw-*`, `matched-ramp-calibratedWhite`). `calibratedRGB`, `deviceRGB` and custom
  `displayP3` colors become sRGB floats, possibly negative (extended sRGB), so no `-Double` follows them;
  alpha keeps the document's value, rounded in storyboards as above (`converted-*`, `sb-converted-*`,
  `color-grid-*`, `sweep-deviceRGB-*`, `sb-color-matched-white`). A matched `deviceWhite` is refused: its
  `-Double`s follow no rule found (`matched-ramp-deviceWhite`).
- In a document without `colorMatched="YES"` ibtool converts colors otherwise, to Generic RGB values
  it then writes as sRGB (`unmatched-*`): `calibratedRGB` components are written unconverted, as sRGB
  ones with their `-Double`s; `sRGB` and `deviceRGB` convert from sRGB, `displayP3` from Display P3,
  `calibratedWhite` from Generic Gray, `deviceWhite` and `genericGamma22GrayColorSpace` from Generic
  Gray Gamma 2.2. All are rounded in storyboards as above, so the converted ones gain `-Double`s there
  (`sb-color-unmatched-*`). `cocoaTouchSystemColor` and `systemColor` stay what a matched document
  writes, except that a storyboard's `blackColor`, `whiteColor` or `clearColor` makes ibtool exit with
  255, writing nothing (`sb-unmatched-cocoa-white`, `sb-color-unmatched-cocoa-*`); nomac refuses those.
  A `systemColor` that also writes components ignores them (`system-components-*`).
- A storyboard keeps 10 significant digits of an sRGB or gray component (`%.10g`: 0.50980392156862742
  writes `-Double` 0.5098039216), a xib the document's double; named colors and converted
  `calibratedWhite` grays keep theirs (`precise-*`, `sb-precise-*`, `sb-cw-*`; the corpus's 15
  storyboard catalog colors).
- `xcode11CocoaTouchSystemColor` or `systemColor` names the color, the `cocoaTouchSystemColor`
  beside it changing nothing (`x11-system-background`, `color-system-and-cocoa-touch`:
  `systemBackgroundColor` with `whiteColor`, as React Native's launch screen writes it).
- A system color has IB's own components, whatever the document's `<systemColor>` definition
  says (`systemColor-*` define every color as black): `NibColor.systemColors` lists the observed
  values. `cocoaTouchSystemColor` takes eight names (`grayColor` and `redColor` make ibtool fail).
  A named color has the components of its `<namedColor>` definition.
- Equal colors are one object, and so are equal color names (`same-color-twice`,
  `same-system-color-twice`, `rgb-then-same-gray`).


### Color conversions

Found by observing CoreGraphics on macOS (scratch tools, `nib_experiments.py` for ibtool itself); all
in float32, with fused multiply-adds where written `fma`, so the same bits come out on Linux
(`ColorManagement`). Every route below matched every component of 1.2 million random colors, k/255
values, short decimals and out-of-range values through live `CGColor` conversions, and of the recorded
experiments.

| Color, document | Route, as `CGColor.converted(to:)` |
|---|---|
| `displayP3`, matched | Display P3 to extended sRGB |
| `calibratedRGB`, matched | Generic RGB to Display P3 to extended sRGB |
| `deviceRGB`, matched | sRGB to Display P3 to extended sRGB |
| `calibratedWhite`, matched | Generic Gray to Generic Gray Gamma 2.2 |
| `sRGB`, `deviceRGB`, unmatched | sRGB to Generic RGB |
| `displayP3`, unmatched | Display P3 to Generic RGB |
| `deviceWhite`, `genericGamma22GrayColorSpace`, unmatched | Generic Gray Gamma 2.2 to Generic RGB |
| `calibratedWhite`, unmatched | Generic Gray to Generic RGB: not reproduced to the bit, so a table |

Components are taken as floats within 0 to 1 (`converted-range-*`). A conversion is a curve per channel,
a matrix, then a curve per channel, each as `ColorSyncTransformCopyProperty` reports it for the two
profiles; a destination that is not extended clamps to 0 to 1.

- Curve: `(a x + b)^g + e` from `d` up, `c x` below it, mirrored for negative values, `a x + b` by `fma`.
  sRGB and Display P3 use g 2.4; Generic RGB g 1.8 with a linear toe (c 1/16, d 1/32), which a pure gamma
  misses; the inverses come as their own curves.
- Matrix row: `r = m1 y; r = fma(m0, x, r); r = fma(m2, z, r)`.
- Power: `x^g = exp2(g log2(x))`, `g log2(x)` a plain product.
- `log2`: `x = 2^e m`, m in √½ to √2 (the float of √½ decides), u = m - 1. Two polynomials of degree 7 in
  u, one per sign of u, which differ from each other and from Taylor's: `A = fma(fma(fma(c7, z, c5), z,
  c3), z, c1)`, `B = fma(fma(c6, z, c4), z, c2)`, z = u u, `value = fma(u, B, A) * u`, then `e + value`
  unless e is 0. Recovered exactly through custom ICC curves of power-of-two exponents, which make
  `g log2(x)` exact; 0 mismatches of 396,831 and 396,583 points, 360,000 across exponents.
- `exp2`: `y = n + f`, f in 0 to 1; Horner by `fma` of degree 6 in f except the last step, `1 + (r f)`,
  plainly; times 2^n. 0 mismatches of 3,000,000 points.

A gray from Generic Gray to Generic RGB gives `exp2(log2(w))` on 99.7% of inputs and differs by one unit
on the others, with no form found; the survey's 97 values there are observed
(`unmatched-survey-whites`), others refused (B-281).
## Older documents

What Xcode 6 to 8 saved changes no nib, on any view or controller, with a device or without, at 27.0 and
below 17 (rounds 120 to 122; the reader drops them, other values stay and are refused): `<animations/>`
(`animations-*`), `<simulatedStatusBarMetrics>`, `<simulatedOrientationMetrics>`, `<simulatedScreenMetrics>` of the
types observed and the top and bottom bars' metrics (`old-*`, `old-no-device-*`, `sb-old-*`), the capabilities
`header-capability-*`, `defaultVersion` of `<deployment>` (`header-default-version-*`), a `<development>` version
from 5000 (`header-development-*`), `promptedForUpgradeToXcode5`, a `<simulatedMetricsContainer>` in a xib
(`header-metrics-container*`), `<mutableArray>` for a custom font's names (`header-fonts-mutable`), and an empty
`customModule` or `customModuleProvider`, which is none (`header-custom-*`). What does change:

- A `<development>` version under 5000 (4200, 4600, 4800) gives a scene's view no layout guides
  (`sb-header-development-*`); so does a document without `useAutolayout` (`sb-noauto*`).
- Without `useAutolayout` a view without an `<autoresizingMask>` has flexible top and bottom margins, mask 40,
  in place of 36, whatever its kind (`noauto-*` against `auto-*-unmasked`, `sb-noauto-unmasked`).
- `iOS.CocoaTouch.iPad` and `CocoaTouch.iPad.XIB` compile as the iPhone runtime and type, but for what is sized
  without a device: below 17 without trait collections 820 x 1180, not 393 x 852 (`header-traitless-*`,
  `sb-header-traitless-*`), and a storyboard with trait collections 600 x 600 at any target
  (`sb-header-deviceless-*`).
- Devices ibtool knows besides those of "Inputs nomac compiles": `ipad10_9rounded` (820 x 1180), `iPad13_0rounded`
  (1032 x 1376), `ipad7_9` (744 x 1133). `ipad12_9`, `ipad10_5` and `ipad11_0` are as no device
  (`header-device-*`, `sb-header-device-*`).

A document's `<deployment version>` stands for the target in what follows, whatever `--minimum-deployment-target`
(rounds 139 and 141, each version at 27.0, 17.0 and 15.0):

- Before iOS 17, its objects take the sizes of old documents, with or without a device (`docversion-*`,
  `sb-docversion-*`), as without one a target before 17 does.
- Before the smaller of the target and iOS 17, ibtool prints `<path>:global: warning: This file is set to build
  for a version older than the deployment target. Functionality may be limited. [9]`, entered first in the warnings'
  table (`sb-segue-*-docversion-*`).
- From iOS 11.0, a storyboard's constraint to a scene's layout guide warns as with a target from 11.0, beside the
  warning above (`sb-warn-guide-docversion-*`).
- A safe area needs iOS 9.0, under which ibtool fails with `Safe Area Layout Guide before iOS 9.0 [12]`. Up to 11.0,
  a xib drops an unpinned guide from all objects, a storyboard keeps it, and a constraint to it makes a nib bundle
  (`docbundle-safe-*`, `docbundle-safe-cell-*`, `docbundle-safe-subview-*`, `docbundle-safe-pinned-*`, `sb-docbundle-safe-*`).
- A named color needs iOS 11.0, under which ibtool fails with `Named colors do not work prior to iOS 11.0. [12]`, and
  makes a nib bundle up to 13.0 (`docbundle-named-*`, `sb-docbundle-named-*`). Whether the document has the
  capability changes nothing.

nomac refuses what fails or makes a bundle there (B-263).

Only `Base.lproj` makes a document's texts localizable; in `en.lproj`, `fr.lproj`, `zh-Hans.lproj` or
`English.lproj` they are plain strings (`lproj-folder-*`, `sb-lproj-folder-*`). A view without a frame writes
none in a document of `toolsVersion` under 11019 (bisected), and 1000 x 1000 from it (`no-rect-tools-*`,
`sb-no-rect-tools-*`, `view-no-rect-*`, whatever its constraints). A slider of no `value` or of 0 writes no
`UIValue` (`slider-value-*`).


A color `name` with `catalog="System" colorSpace="catalog"` is AppKit's color as this Mac's default
appearance and accent give it: an unnamed RGB color, by name (`mx-catalog-*`, `mx-sb-catalog-*`).
A `name` the document's resources do not define gets ibtool's stand-in, float 0.329, 0.324, 0.478,
0.33, keeping `UIDynamicCatalogName` (`mx-named-undefined`, `mx-named-system-name`,
`mx-sb-named-undefined`, `mx-sb-tint-undefined`). Beside `cocoaTouchSystemColor`, an
`xcode11CocoaTouchSystemColor` or `systemColor` name is the color, whatever the pairing
(`mx-x11-*`, `mx-pair-*`). `cocoaTouchSystemColor` also takes the names in `mx-cocoa-*`; added
system colors: `systemWhiteColor` (RGB 1, 1, 1), `tableCellGroupedBackgroundColor`,
`underPageBackgroundColor` (`mx-system-*`). Without `colorMatched="YES"` named and catalog colors
lose their name and are converted by a route not matched yet (`mx-catalog-unmatched-*`,
`mx-named-*-unmatched`): refused.

## Storyboards

`ibtool <storyboard> --compilation-directory <dir>` writes `<dir>/<name>.storyboardc/`
(`storyboard`, `sb-*`):

- A scene's view controller is compiled when it is the document's `initialViewController`, has
  a `storyboardIdentifier`, or a segue from a compiled controller reaches it (`sb-segue-*`,
  `sb-segue-chain`); otherwise ibtool prints `/* com.apple.ibtool.document.warnings */` and
  `<path>:<id>: warning: “View Controller“ is unreachable because it has no entry points, and no
  identifier for runtime access via -[UIStoryboard instantiateViewControllerWithIdentifier:]. [9]`
  and skips it (`sb-no-initial`, `sb-two-scenes*`, `sb-segue-unreached-source`; nomac refuses
  these, B-261).
- Each compiled scene gives a view-controller nib, `<identifier>.nib` or
  `UIViewController-<id>.nib`, and a view nib, `<id>-view-<view id>.nib`.
- `Info.plist`, binary: `UIViewControllerIdentifiersToNibNames` (each compiled controller's nib
  name to itself), `UIStoryboardDesignatedEntryPointIdentifier` (the initial controller's nib
  name, left out without one: `sb-scenes-no-initial-identified`), `UIStoryboardVersion` 1, in
  that order (a 3-bucket Foundation table). The nib names are in the order of a mutable Foundation
  dictionary they entered in the order of a walk of the segues, then copied (`sb-scenes-*-identified`:
  2 to 9 scenes, in both document orders; `sb-info-order-graph`, `sb-info-walk-*`). The walk starts
  from the entry point and the controllers with a storyboard identifier, in document order, and
  visits a controller before its destinations, once each: a scene's segues are its controller's
  own, then those of what the controller holds in the document's order, then those of the scene's
  other objects. Without segues that is document order. Of 2,591 recorded storyboards, 1,487 have
  Xcode's `Info.plist` byte for byte by this rule, 1,100 nomac refuses for other reasons and 4
  differed, in the references' strings below or the file name; the keys are string objects, then the values, then the entry
  point, a string of its own unless the initial controller has a storyboard identifier, when it
  is the same object as that key (`sb-identifier`, `sb-scenes-two-identified-both`): ibtool's
  writer shares the objects it held twice, not equal values.
- Segues (`<segue>` in a controller's `<connections>`, kind `show` or `presentation`, with an
  `identifier`; ibtool warns about a segue without one, which nomac refuses) are templates in
  their source's controller nib, under `UIStoryboardSegueTemplates` (an `NSArray`, after
  `UIStoryboardIdentifier`): `UIStoryboardShowSegueTemplate` (`UIIdentifier`,
  `UIDestinationViewControllerIdentifier` the destination's nib name, `UIActionName`
  `showViewController:sender:`; a `showDetail` segue's the same with `showDetailViewController:sender:`:
  `sb-segue-showDetail`, `sb-cellseg-prototype-showDetail*`) or
  `UIStoryboardPresentationSegueTemplate` (the first two, then `UIModalPresentationStyle` and
  `UIModalTransitionStyle` for the segue's `modalPresentationStyle` and `modalTransitionStyle`,
  whatever their values, coverVertical 0 too: fullScreen 0, pageSheet 1, formSheet 2,
  currentContext 3, overFullScreen 5, overCurrentContext 6, popover 7, automatic -2;
  coverVertical 0, flipHorizontal 1, crossDissolve 2, partialCurl 3; `sb-segue-style-*`,
  `sb-segue-transition-*`; other kinds of segues with them are refused); equal
  strings of a controller's templates are one object. All objects lists them after the
  controller; each connects to it with a `viewController` outlet, after the others, by template
  class byte by byte (`UIStoryboardPopover...` before `...Presentation...`, `...Show...` and
  `...Unwind...`), the last template of a class first (`sb-segue-two`, `sb-segorder-*`,
  `sb-button-two`, `sb-bar-popover-and-cell`; the corpus's uncloudnotes CreateNoteWithImages).
- A segue a table view cell triggers (`<segue>` in a static or prototype cell's `<connections>`,
  an identifier optional: `sb-cellseg-*`) is a template of the controller too, after the
  controller's own (`sb-segorder-mixed`). Each cell's template gets a placeholder, `UpstreamPlaceholder-2`
  for the last cell's, then up in reverse document order, in the controller's
  `UIExternalObjectsTableForViewLoading` after `UpstreamPlaceholder-1`; the view nib has those
  placeholders as top-level objects after `UpstreamPlaceholder-1`, and a static cell's
  `selectionSegueTemplate` outlet to its own (these outlets in the placeholders' order). A
  prototype cell's nib has its own `UpstreamPlaceholder-1` after First Responder and the outlet
  to it; the table's `UITableViewCellPrototypeNibExternalObjects` maps that prototype's
  `UpstreamPlaceholder-1` (the view nib's string) to the view nib's placeholder.
- A cell's accessory segue (`trigger="accessoryAction"`, round 91: `sb-cellseg-accessory*`) is a
  template as a selection segue, its cell's outlet `accessoryActionSegueTemplate`. Placeholders
  are numbered from `UpstreamPlaceholder-2`: static cells last first in each section, the sections in order
  (`sb-cellseg-sections-*`; the survey's Slide test storyboard), prototype cells first first
  (`sb-cellseg-prototypes-reversed-ids`), a cell's segues in document order whatever triggers them
  (`sb-cellseg-accessory-first`); outlets sort by label, then by placeholder
  (`sb-cellseg-static-two-both`). A prototype's nib numbers its own placeholders from 1 in the same
  order, and the table's `UITableViewCellPrototypeNibExternalObjects` maps each, keyed by the view
  nib's string of that name, to the view nib's placeholder. The detail button accessory is
  `UIAccessoryType` 4 (`sb-cell-detail-button`).
- A segue a button triggers (round 77, `sb-button-*`; an identifier optional) is a template of
  the controller after the controller's own, buttons' in document order, in a scene or a
  navigation controller's root (`sb-nav-root-button-*`). Each template gets an upstream placeholder numbered
  breadth first over the view tree, in document order within a level, while the
  `UIStoryboardSegueTemplates` array stays in document order (`sb-nested-segues-*`), after the
  controller's `UpstreamPlaceholder-1` when the view refers to the controller, from 1 otherwise,
  whatever the segues' and buttons' ids (`sb-button-two*`, `sb-button-outlet`,
  `sb-button-action`); the view nib has them as top-level objects and the
  button a `perform:` `UIRuntimeEventConnection` (`UIEventMask` 64) to its placeholder, ordered
  among actions as any (`sb-button-action-first`). Cells' and buttons' segues in one scene are
  refused.
- An unwind segue (`kind="unwind"` to the scene's `<exit>`, from a button, a bar button item or
  the controller: `sb-unwind-*`) is a `UIStoryboardUnwindSegueTemplate`: `UIIdentifier`,
  `UIDestinationViewControllerIdentifier` nil, `UIAction` the unwind action.
- A popover segue from a button or a bar button item (`sb-popover-*`) is a
  `UIStoryboardPopoverPresentationSegueTemplate`: `UIIdentifier`,
  `UIDestinationViewControllerIdentifier`, `UIPermittedArrowDirections` (up 1, down 2, left 4,
  right 8), `UIPassthroughViews`, `UIAnchorBarButtonItem` and `UIAnchorView` nil; its anchor is an
  outlet from the template, `anchorView` from its placeholder in the view nib, or
  `anchorBarButtonItem` in a navigation controller's nib after the root's outlets.
- A bar button item's segue (`sb-bar-*`, `sb-popover-bar-item`) is a template of the navigation
  controller's root after the view's triggered segues (`sb-bar-popover-and-cell`); the item's
  `perform:` event to it is among the items' actions, all by selector byte by byte
  (`sb-bar-segue-then-action`, `sb-bar-segue-then-zzz`).
- ibtool skips the controllers no entry point, identifier or segue reaches, and what only they
  reach, warning `<path>:<id>: warning: “<name>“ is unreachable because it has no entry points, and
  no identifier for runtime access via -[UIStoryboard instantiateViewControllerWithIdentifier:]. [9]`
  about each no controller refers to; the name is IB's: the controller's `userLabel`, `title`, its
  custom class in words (`LoginViewController`: "Login View Controller") or its kind ("View
  Controller", "Navigation Controller", "Table View Controller") (round 92, `sb-unreached-*`,
  `sb-no-initial`, `sb-segue-unreached-source`). Several such warnings come in an order not known
  yet (`sb-unreached-three`: neither the ids' nor the names' hash order), which nomac refuses.
- Xcode 5's segues (round 86, `sb-segue-push*`, `sb-segue-modal*`, `sb-button-push`,
  `sb-cellseg-prototype-push`, `sb-segue-custom*`; gomap, moonlight): `push` is a
  `UIStoryboardPushSegueTemplate` (`UIIdentifier`, `UIDestinationViewControllerIdentifier`,
  `UIDestinationContainmentContext` 0, `UISplitViewControllerIndex` 0), `modal` a
  `UIStoryboardModalSegueTemplate` (identifier, destination), `custom` a `UIStoryboardSegueTemplate`
  (`UIIdentifier`, `UISegueClassName` its class's runtime name as a view's custom class,
  destination). With `useTraitCollections="YES"`, 67 of 67 storyboards of the survey (`sb-segue-*-no-traits`), ibtool
  warns, after compiling, `/* com.apple.ibtool.document.warnings */` then
  `<path>:<segue id>: warning: Push segues are deprecated since iOS 8.0 [7]` (`Modal` for modal
  segues) per segue, in the order of a Foundation hash table of their ids (`sb-segue-push-three`).
  Where ids collide in that table, ibtool's order changes from run to run: four orders in seven
  runs of one document, its nib the same each time (`warn-adjusts-order-doc`, ADR 0254).
  `splitViewControllerTargetIndex` stays refused.
- With `useSafeAreas="YES"`, a `<viewControllerLayoutGuide>` a constraint of its scene names warns,
  on the controller's view, reached or not, the top guide first: `<path>:<view id>: warning: Top
  layout guide is deprecated since iOS 11.0 [7]` (`Bottom` for the other; `sb-guide-warn-*`, all 59
  such guides of the survey's storyboards). An unused guide, or one without safe areas, does not
  warn (221 and 2,088 of them).
- The views beside a scene's controller keep their user-defined runtime attributes in the
  controller's nib (the corpus's wikipedia Saved storyboard).
- A `<hostingController>` is a view controller without a view, its nib `UIHostingController-<id>`, its class `UIViewController` unless a custom one
  (`sb-hosting-*`; as a navigation controller's root refused). An `<avPlayerViewController>` too, its nib `AVPlayerViewController-<id>`, first among the top-level
  objects, writing `AVShowsPlaybackControls` true and `AVVideoLayerGravity` (`AVLayerVideoGravityResizeAspect` without one) before its class names (`sb-avplayer-*`).
  A navigation or tab bar item of theirs is written as a scene's (round 158).
- A view controller without a view (round 90, `sb-vc-no-view*`; nextcloud's action extension) is one
  nib: File's Owner, First Responder, the storyboard placeholder and the controller, without
  `UIExternalObjectsTableForViewLoading` or `UINibName`; no view nib. `<value
  key="contentSizeForViewInPopover" type="size">` writes `UIPreferredContentSize` (07, width, height)
  after `UIModalPresentationStyle` (`sb-popover-content-size*`). A view's `simulatedAppContext`
  changes nothing (`sb-app-context`).
- `<extendedEdge key="edgesForExtendedLayout">` writes `UIKeyEdgesForExtendedLayout`, its edges' bits
  (top 1, left 2, bottom 4, right 8; none 0), among the presentation settings after
  `UIHidesBottomBarWhenPushed` and before `UIKeyExtendedLayoutIncludesOpaqueBars` (round 88,
  `sb-edges-*`).
- A storyboard's global tint, a `<color key="tintColor">` after its scenes and resources, is the
  `UITintColor` of each scene's view without a tint of its own and of each navigation bar, in tab
  bar controllers too; tab bars, controllers and other views keep none (round 102, `sb-tint-*`
  against `sb-untinted-*`; the holdout's habitica and keepassium). Scene views other than plain
  views are refused with it until observed.
- A controller's `<size key="freeformSize">` without `<freeformSimulatedSizeMetrics>` also sizes its
  scene's view, resizing it from another frame (round 87, `sb-freeform-size-only*`; wikipedia's
  SavedProgressViewController); an embedded freeform controller keeps its own size
  (`sb-embed-freeform`). What an embedded controller's segues reach, one after another and whatever their kinds, takes the
  container's size too (`sb-embed-nav-*`; the survey's eidolon Fulfillment).
- A container view's embed segue (round 84, `sb-embed*`; wikipedia's DescriptionWelcome) is a
  `UIStoryboardEmbedSegueTemplate` (`UIIdentifier`, `UIDestinationViewControllerIdentifier`,
  `UIPerformOnViewLoad` true, `UIContainerView` nil) among the buttons' segues, in document order,
  with an upstream placeholder numbered as theirs; the view nib connects the placeholder to the
  container view, a plain `UIView`, with a `containerView` outlet. The embedded controller's view,
  or its navigation controller's root's, takes the container view's size (`sb-embed`,
  `sb-embed-nav`). A container view without a segue is a plain view (`sb-container-empty`).
- A navigation controller's root with its own identifier is also compiled as a scene of its own;
  in the navigation controller's nib it is a `UIClassSwapper` with `UIStoryboardIdentifier` after
  `UINibName` (`sb-nav-root-identifier`). So is a root that is the storyboard's initial
  controller, a class swapper too, or that segues reach (round 111, `sb-nav-root-initial*`,
  `sb-nav-root-reached*`; the corpus's wikipedia Places, gomap QuestSolver).
- Round 78: a navigation controller with its own identifier writes `UIStoryboardIdentifier` first
  in a nib of that name (`sb-nav-identifier*`); IB's frameless `<toolbar key="toolbar">` is a
  `UIToolbar` after `UINavigationBar` (`UIBounds` 0 x 0 x 1000 x 54, `UICenter` 500, 27,
  `UIDeepDrawRect`, `UIAutoresizeSubviews`, `UIAutoresizingMask` 10,
  `UIClearsContextBeforeDrawing` false, the hugging string, `UIViewSemanticContentAttribute` 0,
  `UIViewLargeContentStoredProperties` nil, `UIItems` the nib's empty array, `UIBarPosition` 1,
  `UIBarTranslucence` 1), listed after the bar (`sb-nav-toolbar`). A controller outside a
  navigation controller keeps its navigation item's bar button items, their events after the
  templates' outlets, by selector (`sb-standalone-bar-*`).
- Round 79: a navigation controller's root writes its `title` first (localizable as
  `<id>.title`), and an undeclared navigation item takes it with its attributed copy
  (`sb-vc-title-nav`); a root keeping its selection writes `UIClearsSelectionOnViewWillAppear`
  false after its templates (`sb-nav-root-tvc-keeps-selection`, Xcode's Master-Detail template
  `sb-split-template*`). Empty `<toolbarItems/>` of a controller and an empty `<sections/>` of a
  prototypes table change nothing (`sb-*toolbar-items`, `sb-tvc-empty-sections`). The external
  objects' `UpstreamPlaceholder-N` keys are the nib's strings, which a container's children share.
- Round 81 (uncloudnotes' UnCloudNotes storyboards): a cell content view's Xcode 8
  `<frame key="frameInset">` of a width and height is the frame at 0, 0 of that size
  (`sb-cell-frame-inset`); a navigation root's and a container child's presentation settings
  (`modalPresentationStyle`, `modalTransitionStyle`, `hidesBottomBarWhenPushed`...) follow its
  templates as a scene's controller's (`sb-nav-root-modal`, `sb-split-detail-modal`,
  `sb-tab-nav-root-modal`); a controller's `userLabel` changes nothing (`sb-*user-label`); a
  container's navigation roots' popover anchors precede `sceneViewController` and their bar
  button items' events come last, as in a navigation controller's nib (`sb-split-bar-*`); a scene
  controller's `title` is localizable as `<id>.title` in an `.lproj` folder.
- The view-controller nib: top-level and all objects File's Owner, First Responder, a
  `UIProxyObject` `UIStoryboardPlaceholder`, and the controller, a `UIClassSwapper` with
  `UIExternalObjectsTableForViewLoading` (an empty `NSDictionary`), `UINibName` (the view
  nib's name), `UIStoryboardIdentifier` when it has one, its segue templates,
  `UITopLevelObjectsToKeepAliveFromStoryboard` and `UIDefinesPresentationContext` true for
  `definesPresentationContext` (`sb-tvc-defines-presentation*`), `UIClassName` (as for views, with
  `UIViewController` as the default) and `UIOriginalClassName` `UIViewController`; a controller
  without a custom class that only segues reach is a `UIViewController` without the two class
  names (`sb-segue-show`, `sb-segue-to-custom-class*`); connections:
  `UIRuntimeOutletConnection`s `storyboard` (controller to placeholder) and
  `sceneViewController` (File's Owner to controller). A scene's two nibs are encoded
  independently: equal encodings give equal key tables whatever the other nib holds, and a view
  nib is the nib of a xib holding the same view.
- The view nib: top-level File's Owner, First Responder and the view; all objects as a xib's,
  the layout guides after the view's constraints and before its subviews (`sb-subview`,
  `sb-image-view`); one outlet `view` (File's Owner to the view); keys as a xib's. ibtool adds to
  the view, in a document without safe areas or when the controller declares them
  (`<layoutGuides>`: `sb-safe-area-layout-guides`), the top and bottom layout guides: `_UILayoutGuide` (fallback `UIView`), the view's last subviews,
  hidden views without geometry or mask that do not translate their masks, with
  `_UILayoutGuideIdentifier` `_UIViewControllerTop` or `_UIViewControllerBottom`, a
  `UIViewAutolayoutConstraints` of one `_UILayoutSupportConstraint` (fallback
  `NSLayoutConstraint`: first item the guide, attribute width, priority 999) and
  `_UILayoutGuideConstraintsToRemove`: for the top guide its leading and top equal to the
  view's and its height; for the bottom one its leading equal to the view's, its height, and the
  view's bottom equal to its bottom. The view's own `UIViewAutolayoutConstraints` lists those six
  before its document constraints. Document constraints may name the guides (by the
  `<viewControllerLayoutGuide>` ids) as they name sibling subviews ("Constraints"): one naming a
  guide first sorts in the guide's group, the top guide at the view's origin and the bottom one at
  its bottom edge, both of no height (`sb-guide-bottom-group`, `sb-guide-bottom-position`); one
  naming it second sorts after its subview's constraints to the view (`sb-guide-top-and-height`;
  round 45, `sb-guide-*`; uncloudnotes' UnCloudNotes). `NSLayoutConstraint`: `NSFirstItem`,
  `NSFirstAttributeV2` and `NSFirstAttribute` (`NSLayoutAttribute`), then `NSSecondItem` and its
  two attributes when there is one, `NSShouldBeArchived` true.
- With `useSafeAreas` and a `viewLayoutGuide key="safeArea"` (on a xib's top-level view too:
  `safe-area`), the view nib has a `UILayoutGuide` only all objects lists, right after the view: `UILayoutGuideOwningView`
  nil, `UILayoutGuideIdentifier` an empty string, `UILayoutGuideOwningViewIsLocked`,
  `UILayoutGuideShouldBeArchived` and `UILayoutGuideAllowsNegativeDimensions` false
  (`sb-safe-area`, `sb-game`).
- A scene's view has the size of the document's `<device>`, whatever its frame says, swapped in
  landscape (`sb-device-*`, `sb-landscape`, `sb-device-frame`): retina4_0 320 x 568, retina4_7
  375 x 667, retina5_5 414 x 736, retina5_9 375 x 812, retina6_0 390 x 844, retina6_1 and
  retina6_5 414 x 896, retina6_12 393 x 852, retina6_3 402 x 874, retina6_7 430 x 932,
  retina6_9 440 x 956, ipad9_7 768 x 1024, ipad11_0rounded 834 x 1210, ipad12_9rounded
  1024 x 1366, and retina3_5, which Xcode 27.0 does not offer, 393 x 852. Without a `<device>` it
  is, when the deployment target is before 17.0 (8.0 to 16.6), 600 x 600 with
  `useTraitCollections="YES"` and 393 x 852 without (`sb-no-traits-*`: the corpus's flutter
  launch screens), and keeps its frame from 17.0 (`sb-deployment-*`, `sb-no-device-frame`,
  `sb-flutter-launch-*`); `--target-device` changes nothing (`sb-targets-*`). Its subviews follow
  their autoresizing masks: each direction's change goes to its one flexible part, whatever its
  length (`sb-flutter-launch-*`: a 1000 x 1000 image view keeps its frame), or is shared between
  two in proportion to their lengths (`sb-device-subview`, `-fixed`, `-both`); results that are not whole points are rounded
  (`sb-device-subview-fraction`: 25.6 to 26, 6.4 to 6), by a rule not pinned yet, and refused.
- A view controller's outlets to its scene's views come from a third top-level placeholder of the
  view nib, `UpstreamPlaceholder-1`, right after First Responder, and the controller nib's
  `UIExternalObjectsTableForViewLoading` holds the entry `UpstreamPlaceholder-1` (a string) to
  the controller (`sb-controller-outlets`); with the `view` outlet they sort as above.
- Views beside a scene's controller in its `<objects>` (`sb-extra-view*`; tofu's empty views)
  are top-level objects of the controller nib in reverse document order, before the controller
  of a `<viewController>` and after a table view controller or a navigation controller; the
  controller keeps them in `UITopLevelObjectsToKeepAliveFromStoryboard` (an `NSArray` in document
  order) and its outlets to them are its connections after `storyboard`, by name. All objects of
  a controller nib is breadth first: a controller's children are its declared navigation item
  and its segue templates, a navigation controller's its bar and root, an item's its bar button
  items (tofu's accounts navigation: the root's templates before its item's add button).
- A controller's freeform size (`<freeformSimulatedSizeMetrics>` with `<size key="freeformSize">`,
  its view's frame) is its scene view's size whatever the device or deployment target
  A scene's view keeps its document origin (such as y 64 below an opaque simulated bar); a device
  resizes it only (`sb-view-at-*`, round 63).
  (`sb-freeform`, `sb-freeform-no-device`).
- `launchScreen="YES"`, declared layout guides, `systemVersion`, `<adaptation>` (other than through
  its device), a First Responder of class `UIResponder` and a dark appearance change nothing
  (`sb-launch-screen`, `sb-layout-guides`, `sb-system-version`, `sb-adaptation`,
  `sb-first-responder-class`, `sb-dark`).

### View controllers' attributes

A storyboard view controller (round 46, `sb-vc-*`) writes `UITitle` first (`title`, one string with
an equal segue identifier of its nib), `UIRestorationIdentifier` after `UIStoryboardIdentifier`
(`restorationIdentifier`, or the storyboard identifier's string for
`useStoryboardIdentifierAsRestorationIdentifier` and for an equal `restorationIdentifier`,
`sb-vc-restoration-equal-storyboard-id`), and after `UIStoryboardSegueTemplates`:
`UIModalTransitionStyle` (flipHorizontal 1, crossDissolve 2; coverVertical not written),
`UIModalPresentationStyle` (whenever given: fullScreen 0, pageSheet 1, formSheet 2, currentContext 3,
overFullScreen 5, overCurrentContext 6), `UIHidesBottomBarWhenPushed` true,
`UIKeyExtendedLayoutIncludesOpaqueBars` the integer 1 and `UIKeyAutomaticallyAdjustsScrollViewInsets`
the integer 0. Segue templates' strings are the document's (shared with equal strings). A navigation
root's title also titles its navigation item (`sb-vc-title-nav`), which nomac refuses.

## Outlets to a controller's navigation item and bar button items

A controller's outlets to its `<navigationItem>` and its bar button items are in the controller's
nib, by name, between `storyboard` and `sceneViewController`, whatever the controller: a table,
collection or plain view controller, of a custom class or not, standing alone, a navigation
controller's root or a tab bar controller's navigation child's root, where the roots' outlets of
all children go by name after the `storyboard` outlets (`sb-outlet-bar-*`, `sb-outlet-item-*`,
`sb-outlet-bar-tab-*`). The item's action is an event connection as usual.

A view of the scene that has an outlet to such an object, or to a view beside the controller, lives
in another nib: the view nib has an `UpstreamPlaceholder-<n>` for it, and the controller's
`UIExternalObjectsTableForViewLoading` maps that name to the object. The placeholders of these
objects and of the controller are numbered as the sorted connections first reach them, so an outlet
`aaa` to the controller makes it `-1` and an outlet `owner` beside `doneButton` makes it `-2`
(`sb-outlet-bar-from-view*`, `sb-outlet-two-bars-from-view*`, `sb-outlet-item-*-from-view`,
`sb-outlet-extra-from-view`), as with a gesture recognizer. nomac refuses them beside a gesture
recognizer's or segues' placeholders, and when a table or collection view's connections would
number one before the controller: neither is observed.

Bar button items' actions go by selector, the strings shared; of one selector, the right item's
comes first, whatever the document's order, ids and system items (`sb-bar-same-selector*`). A tab
bar controller sorts its navigation children's actions together, children in order within a
selector (`sb-outlet-bar-tab-two-navs*`).

## Navigation controllers

A `<navigationController>` scene with a `rootViewController` relationship segue gives one nib,
`UINavigationController-<id>.nib` (or its identifier's), that archives the root controller too;
the root gets its own view nib only, and no entry in the Info.plist (`sb-nav*`, `sb-bar-*`,
`sb-nav-show`, `sb-segue-present-nav`):

- Top-level objects: a `UIStoryboardPlaceholder` proxy, File's Owner, First Responder, a second
  `UIStoryboardPlaceholder` proxy sharing the first one's string, and the navigation controller.
  All objects are breadth first as above.
- The navigation controller: a `UIClassSwapper` when it is an entry point, a
  `UINavigationController` when only segues reach it; `UIChildViewControllers` and
  `UIViewControllers` (two `NSMutableArray`s of the root, after `UITitle` for a `title`:
  `sb-nav-title`; `userLabel` changes nothing), `UIKeyAutomaticallyAdjustsScrollViewInsets`
  integer 0 between them for `automaticallyAdjustsScrollViewInsets="NO"`, `UINavigationBar`, and
  the class names `UINavigationController`. `<toolbarItems/>` and `<nil name="viewControllers"/>`
  change nothing.
- The root: a `UIViewController` or a `UITableViewController` (a `UIClassSwapper` for a custom
  class) with `UINavigationItem`, `UIExternalObjectsTableForViewLoading` (the
  `UpstreamPlaceholder-1` entry when its view nib uses it), `UINibName`, `UIParentViewController`,
  its `UIStoryboardSegueTemplates` (its cells' too, with their placeholders as in a scene:
  `sb-cellseg-nav-root`), `UITopLevelObjectsToKeepAliveFromStoryboard`,
  `UIDefinesPresentationContext`, and its class names (`sb-tvc-in-nav*`, `sb-nav-root-*`).
- `UINavigationItem`: for a declared item `UITitle` (in an `.lproj` folder an
  `NSLocalizableString` keyed `<item id>.title`), `UIAttributedTitle` (an `NSAttributedString` of
  the same string object and an empty `NSDictionary`, one for all the nib's items: `sb-tab-nav-two`), `UILeftBarButtonItem`, `UIRightBarButtonItem`,
  `UILeftBarButtonItems`, `UICenterItemGroups` (the nib's one empty `NSArray`, which the root's
  empty lists share), `UIRightBarButtonItems`; always `UILargeTitleDisplayMode` (automatic 0,
  never 2) and `UINavigationBar`, a conditional reference: the bar is numbered where the
  navigation controller encodes it. A view controller outside a navigation controller with a
  `<navigationItem>` writes it first, without a bar (`sb-nav-item-no-nav`).
- `UINavigationBar`, whatever the document's frame size or the device: `UIBounds` 0 x 54,
  `UICenter` the frame's origin plus 27 points down (`sb-nav-bar-*`), `UIDeepDrawRect`,
  `UIAutoresizeSubviews`, `UIAutoresizingMask` 2, `UIViewContentHuggingPriority` `{250, 250}` (the nib's string),
  `UIViewLayoutMargins` zeros and directional, `UIViewSemanticContentAttribute` 0,
  `UIViewLargeContentStoredProperties` nil, `UIBarPrefersLargeTitles` for `largeTitles="YES"`,
  `UIIsLocked`, `UIItems` (the item), `UIDelegate` (the navigation controller),
  `UIBarPosition` 2, `UIBarTranslucence` 1; `multipleTouchEnabled`, `clipsSubviews` and
  `insetsLayoutMarginsFromSafeArea="NO"` add a view's `UIMultipleTouchEnabled` (after
  `UIDeepDrawRect`), `UIClipsToBounds` (after `UIAutoresizingMask`) and
  `UIViewInsetsLayoutMarginsFromSafeArea` 0 (after the margins); `opaque` changes nothing
  (`sb-nav-bar-*`). An item without a title writes no `UITitle` nor `UIAttributedTitle`
  (`sb-nav-item-no-title*`). `<simulatedNavigationBarMetrics>` on controllers and views changes
  nothing (`sb-sim-nav-*`).
- `UIBarButtonItem` of a system item: `UIEnabled` unless `enabled="NO"`, `UIIsSystemItem`,
  `UISystemItem` (done 0, cancel 1, edit 2, save 3, add 4, compose 7, reply 8, action 9, organize
  10, bookmarks 11, search 12, refresh 13, stop 14, camera 15, trash 16, play 17: `sb-bar-system-*`),
  `UIStyle` 1 (2 for `style="done"`: `sb-bar-done-style*`, `sb-bar-title-done`); a titled item's
  `UIImage` follows its title (`sb-bar-image`); a `backBarButtonItem` is the navigation item's
  `UIBackBarButtonItem` after `UIAttributedTitle` (`sb-bar-back-title`; beside left or right items
  refused); a titled item
  `UIEnabled`, `UIStyle` 1 and `UITitle`, in an `.lproj` folder an `NSLocalizableString` keyed
  `<id>.title` (`sb-unwind-bar-item`, `sb-bar-title-lproj`).
- Connections: `storyboard` from the navigation controller to the second placeholder and from
  the root to the first, the root's outlets to its bar button items, `sceneViewController`, the
  templates' `viewController` outlets, then each bar button item's action, a
  `UIRuntimeEventConnection` (`UILabel` the selector, `UISource` the item, `UIDestination` the
  root).

## Tab bar and split view controllers

A `<tabBarController>` scene with `viewControllers` relationship segues gives one nib,
`UITabBarController-<id>.nib` (or its identifier's), that archives its children too; each view
controller gets its own view nib only, and no entry in the Info.plist (`sb-tab-*`, rounds 72 and
73):

- Top-level objects: one `UIStoryboardPlaceholder` proxy per inlined controller (children and
  navigation children's roots, depth first, listed in reverse), File's Owner, First Responder, the
  tab bar controller's placeholder and the tab bar controller; all placeholders share one string.
  All objects are breadth first as above.
- The tab bar controller: a `UIClassSwapper` when it is an entry point or of a custom class
  (`sb-tab-custom`), with `UIStoryboardIdentifier` for an identifier (`sb-tab-identifier`),
  `UIChildViewControllers` (an `NSMutableArray` of the children in segue order: `sb-tab-order`),
  `UITabBar`, `UICustomizableViewControllers` and `UIViewControllers` (the same list again), and
  its class names. `<toolbarItems/>` changes nothing.
- A view controller child: `UITitle` for a `title` (`sb-tab-child-title`), `UITabBarItem`,
  `UIExternalObjectsTableForViewLoading` (one empty `NSDictionary` all children and roots share),
  `UINibName`, `UIParentViewController`, its class names when custom.
- A navigation controller child: `UITabBarItem`, `UIParentViewController`, then a navigation
  controller's keys as above, its root inlined with the shared external objects
  (`sb-tab-nav-*`); its children in all objects are its bar, its declared tab bar item and its
  root.
- `UITabBarItem`: `UIEnabled`, `UITitle` (the declared item's, or the controller's title for IB's
  default item), `UISpringLoaded` for IB's default item, `UIImage` (`sb-tab-items`,
  `sb-tab-item-*`). A declared item is among all objects, as a child of its controller; the
  default one is not.
- `UITabBar`, whatever the document's frame: `UIBounds` 0 x 54, `UICenter` the frame's origin plus
  27 points down, `UIBackgroundColor` for a `backgroundColor` (`sb-tab-bar-background`),
  `UIDeepDrawRect`, `UIOpaque`, `UIAutoresizeSubviews`, `UIAutoresizingMask` 10,
  `UIViewContentHuggingPriority` `{250, 250}`, `UIViewSemanticContentAttribute` 0,
  `UIViewLargeContentStoredProperties` nil, `UIDelegate` (the tab bar controller),
  `UIItems` (an `NSArray` of the children's items), `UIBarTranslucence` 1.
- A `<splitViewController>` with `masterViewController` and `detailViewController` relationships
  gives `UISplitViewController-<id>.nib` the same way (`sb-split-*`, rounds 71 and 74): the split
  view controller (a `UIClassSwapper` when it is an entry point or of a custom class) writes
  `UITitle` for a `title` (in an `.lproj` folder an `NSLocalizableString` keyed `<id>.title`:
  `sb-split-title-lproj`), `UIStoryboardIdentifier`, `UIChildViewControllers` (master, then
  detail, whatever the segues' order: `sb-split-swapped`), `UISplitViewControllerPrimaryEdge` 0
  and its class names; all objects lists its children detail first. Its children are written as
  a tab bar controller's, without tab bar items; a navigation child starts with
  `UIParentViewController` (`sb-split-nav-*`). Placeholders and outlets follow the
  relationships' document order (`sb-split-segue-order`); `<toolbarItems/>` changes nothing.
- Connections: `storyboard` from each controller to its placeholder, the tab bar controller's and
  the navigation controllers' first, then the view controllers', each depth first
  (`sb-tab-nav-two`, `sb-tab-plain-then-nav`), then `sceneViewController`.

Children's segues (round 76): a view controller child's `UIStoryboardSegueTemplates` follow
`UIParentViewController`, all objects lists them after its declared tab bar item
(`sb-tab-child-show*`); a navigation child's root, a table view controller too
(`sb-split-tvc-master`), is inlined as in a navigation controller's nib, its cells' segues with
their upstream placeholders in its own external objects (`sb-split-showdetail`). The templates'
`viewController` outlets, one label string, follow `sceneViewController` in the view controllers'
order (`sb-tab-two-show`). A child a segue reaches, as a cell's showDetail segue reaches a split
view controller's detail, also has its own nib and Info.plist entry, compiled as any scene
(`sb-split-showdetail*`).

A child whose view refers to it (outlets to its view) has its own external objects with
`UpstreamPlaceholder-1`, the others keeping the shared empty one (`sb-tab-child-outlet`,
`sb-split-detail-outlet`).

nomac refuses children's bar button items or views beside them, split view controllers' other
attributes (display modes, column styles) and supplementary columns (B-292).

Attributes and shapes (rounds 125 to 128, `sb-navattr-*`, `sb-tabattr-*`, `sb-vcattr-*`, `sb-tab-id-*`,
`sb-shape-*`). A navigation controller, alone or as a child, writes `UITitle`, `UITabBarItem`,
`UIStoryboardIdentifier`, `UIRestorationIdentifier`, `UIParentViewController`, `UIChildViewControllers`,
`UIStoryboardSegueTemplates`, `UIDefinesPresentationContext`, the presentation keys of a view controller
(`UIModalTransitionStyle`, `UIModalPresentationStyle`, `UIHidesBottomBarWhenPushed`,
`UIKeyEdgesForExtendedLayout`, `UIKeyExtendedLayoutIncludesOpaqueBars`,
`UIKeyAutomaticallyAdjustsScrollViewInsets`), `UIViewControllers`, `UINavigationBar`, `UIToolbar`,
`UINavigationBarHidden`, `UIToolbarShown`, `UINavigationControllerCondensesBarsWhenKeyboardAppears`, and its
class names; an identifier or a custom class makes it a class swapper, as a child too. Without a root it
has no children and its bar no `UIItems`; its own segues' templates come before its root in all
objects, their `viewController` outlets before its root's. A tab bar controller writes `UITitle`,
`UINavigationItem`, `UIStoryboardIdentifier`, `UIRestorationIdentifier`, `UIChildViewControllers` (none
without children), `UIDefinesPresentationContext`, the presentation keys, `UITabBar`,
`UICustomizableViewControllers`, `UIViewControllers` and its class names. A view controller child with an
identifier is a class swapper writing it after `UINibName`, and has a nib of its own, as a navigation
root does; table and collection view controllers are children as view controllers are.

`UITabBarItem`: `UISystemItem`, `UIEnabled`, `UITag`, `UITitle`, `UISpringLoaded` for IB's default item,
`UIBadgeValue`, `UIBadgeColor`, `UIImage`, `UILandscapeImagePhone`, `UISelectedTemplateImage`, `UIImageInsets`
(top, left, bottom, right), `UITitlePositionAdjustment` (the string `{1, 2}`). Any controller may declare one,
writing it after its title and before its navigation item, and listing it after that item in all objects.
`UITabBar` adds `UIViewInsetsLayoutMarginsFromSafeArea` 0 after its hugging, `UIBarTintColor`,
`UISelectedImageTintColor`, `UITabBarItemPositioning` (fill 1, centered 2) after `UIItems`, `UIBarTranslucence`
2 when not translucent, `UIBarStyle` 1 for black, its class names; its `tintColor` is not written.

nomac refuses a tab bar or split view controller as a navigation controller's root (B-292).

## Search bars

A `<searchBar>` (round 93, `search-bar*`; gomap, nextcloud, wikipedia) is a `UISearchBar`: a view's
keys, never `UIOpaque` whatever `opaque` says, `UIViewContentHuggingPriority` always (`{250, 250}`
included), then `UISearchBarTranslucence` 1, `UIText` (an empty string), `UIPlaceholder`,
`UIAutocorrectionType` (no 1) from its `<textInputTraits>`, `UIEnablesReturnKeyAutomatically` false,
`UISecureTextEntry` false, and `UISearchBarStyle` 2 for `minimal`. A text, other traits, a
placeholder in an `.lproj` folder and table header search bars are not observed yet.

## Page view controllers

A `<pageViewController>` scene (round 83, `sb-page-*`; wikipedia's DescriptionWelcome) gives one
nib, `UIPageViewController-<id>.nib` (or its identifier's), and no view nib: File's Owner, First
Responder, a `UIStoryboardPlaceholder` and the controller, a `UIPageViewController` (a
`UIClassSwapper` when an entry point or of a custom class) with `UIStoryboardIdentifier`,
`UIAutoresizesArchivedViewToFullSize` false, `UITransitionStyle` (pageCurl 0, scroll 1),
`UINavigationOrientation` (horizontal 0, vertical 1), `UISpineLocation` (none 0, min 1),
`UIPageSpacing` (an integer) and its class names; connections `storyboard` and
`sceneViewController`. ibtool refuses a mid spine location for this layout; nomac refuses mid and
max spine locations, fractional spacings and segues of the page view controller.

## Storyboard references

A `<viewControllerPlaceholder>` scene (round 96, `sb-ref-*`; gomap's and nextcloud's storyboards)
stands for a controller of another storyboard, by `storyboardName` and, optionally,
`referencedIdentifier`; IB may give it an empty `<navigationItem>`. Its nib name is
`UIViewController-<id>`. Show, presentation, push and modal segues of buttons, cells and
controllers reach it with the same templates as a controller (`sb-ref-show`, `-present-named`,
`-push`, `-modal`, `-controller-segue`, `-cell-push`, `-cell-show`); it then has a nib of its own:
File's Owner, First Responder, a `UIStoryboardPlaceholder` and a
`UIStoryboardViewControllerPlaceholder` whose `UIStoryboardIdentifier` is its nib name, its
navigation item after them in the objects list only, and one connection, `sceneViewController`;
the reference has no `storyboard` outlet. As a tab bar controller's child (`sb-ref-tab`,
`-tab-two`) or a navigation controller's root (`sb-ref-nav-root`, `-tab-nav-root`) it is inlined
in that controller's nib: the placeholder with `UIStoryboardIdentifier` and
`UIParentViewController`, a storyboard placeholder of its own among the top-level objects, still no
`storyboard` outlet; a tab bar gives it a default spring-loaded item in `UIItems` only, a
navigation bar its navigation item (with `UINavigationBar`) as for a root controller. The
`Info.plist` lists every reference something reaches under
`UIViewControllerIdentifiersToExternalStoryboardReferences`, nib name to a dictionary of
`UIReferencedControllerIdentifier` (when given) and `UIReferencedStoryboardName`, entered in that
order; the references enter in the order of the segues' walk above (`sb-ref-plist-walk-reversed`,
two recorded documents), and both levels are copied Foundation tables. Equal storyboard names and
identifiers are one string object across these dictionaries only when short: any ASCII of up to 7
characters, 8 or 9 characters from ` -./0-9A-PR-Y_a-pr-z` (64 letters: no `Q`, `Z`, `q`), 10 or 11
from ` .0134CIMRSTacdefghijklmnoprstux` (32 letters), and never longer or outside ASCII
(`sb-ref-plist-repeat-*` for the lengths, `sb-ref-plist-letter-*` for each ASCII letter at 8 and at
10 characters); each other use is a string object of its own. The
top-level keys enter as nib names, entry point, references, version (`sb-ref-show`: version,
references, nib names, entry point; `sb-ref-no-entry`: nib names, version, references). Each
reference's dictionary is a key string, then its values; the two inner keys are one string object
each for all references (`sb-ref-tab-two`). Only a referenced identifier names a reference nothing
reaches in ibtool's warning (`sb-ref-unreached`). nomac refuses references as the initial
controller, in split view controllers, as navigation roots without a navigation item, and reached
by other segues or bar button items.

## Version probe

Before it plans Interface Builder tasks, Swift Build runs `ibtool --version --output-format xml1`
and decodes `com.apple.ibtool.version` (SWBApplePlatform `InterfaceBuilderShared.swift`). Xcode
27.0's ibtool printed bundle version `25098` and short bundle version `27.0`. `nomac ibtool`
answers the same, with its own version under `nomac` (`IBToolVersion`, ADR 0102 "Tool probes").
