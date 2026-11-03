# Text-based stubs (`tapi stubify`)

Observed with Xcode 27.0 (27A266a): `.github/scripts/tapi_experiments.py` (22 self-written thin
arm64 iOS dylibs, one property varied at a time) and retro-rampage's `Engine`
(`EagerLinkingTBDs/Release-iphoneos/Engine.framework/Engine.tbd`). Swift Build's `GenerateTAPI`
runs, for every framework it links:

    tapi stubify -isysroot <SDK> -F<products> -L<products> [-iframework <dir>]... \
        [--inline-private-frameworks] <dylib> -o <EagerLinkingTBDs>/<product>/<name>.tbd

The search paths and `--inline-private-frameworks` did not change the output of the libraries
observed (`swift-build-options`), which re-export nothing. nomac's `tapi` (`TAPIStub`) writes:

- TBD version 5 JSON on one line, keys sorted, no spaces, then a newline:
  `{"main_library":{...},"tapi_tbd_version":5}`.
- `main_library` keys, in order, each a one-element array:
  - `compatibility_versions` and `current_versions`: `[{"version":"<v>"}]`, each left out on its
    own when it is 1.0.0 (`versions-1.0`, `current-1.0`, `compatibility-1.0`, `Engine`); 0 is
    written `0`; trailing zero components are dropped (`2.3.4`, `1.2`, `2`).
  - `exported_symbols`: `[{"data":{...},"text":{...}}]`, left out when the library exports
    nothing (`no-exports`). Within a category, `global`, `objc_class`, `objc_eh_type`, `objc_ivar`,
    `thread_local` and `weak`, sorted by name; each list is sorted by bytes.
  - `flags`: `[{"attributes":["not_app_extension_safe"]}]` unless the header has
    `MH_APP_EXTENSION_SAFE` (`extension-safe`), else left out.
  - `install_names`: `[{"name":"<LC_ID_DYLIB name>"}]`.
  - `swift_abi`: `[{"abi":<n>}]`, the Swift ABI byte of `__objc_imageinfo`, when there is one.
  - `target_info`: `[{"min_deployment":"<minos>","target":"arm64-ios"}]`, the minimum OS with
    trailing zero components dropped (`15`, `15.4`, `16.0.1`).
- Which category a symbol of the export trie goes to:
  - Swift-mangled names (`_$s`) are `data`, functions included (`swift-function`, `swift-and-c`);
  - other symbols in a section with instructions are `text` (`function`), all others `data`
    (`data`: `__TEXT,__const` and `__DATA,__data`);
  - weak definitions are `weak` (`weak` in text, `weak-data` in data), thread-local ones
    `thread_local` in data;
  - `_OBJC_CLASS_$_<name>` is `objc_class` `<name>` in data; its metaclass is not listed
    (`objc-class`);
  - `_OBJC_IVAR_$_<class>.<ivar>` is `objc_ivar` `<class>.<ivar>` in data: the `@public` and
    `@protected` instance variables, the others being private externs the trie does not export
    (`objc-ivars`, mastodon's MastodonSDKDynamic);
  - `_OBJC_EHTYPE_$_<name>` is `objc_eh_type` `<name>` in data (`objc-exception-type`).

Inputs no variant covers stop with an error (BACKLOG B-106).
