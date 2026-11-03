# Macro expansions of Apple's frameworks

Observed with Xcode 27.0 (27A266a) and its iOS 27.0 SDK: `.github/scripts/macro_experiments.py
record` compiles self-written inputs (the `CASES` of the script, named below) with Xcode's
compiler and `-dump-macro-expansions`, and logs the plugin protocol between the compiler and
Apple's plugins. nomac's plugins (docs/adr/0150-macro-plugins.md) give the same text for every
case; `NomacMacrosTests` checks each use of a macro in them against the digest of Xcode's answer.

## How an expansion becomes text

- swift-syntax formats every expansion in the plugin process (`BasicFormat`): it adds the
  newlines and spaces a token needs, and indents each line by its nesting level, except lines
  whose leading trivia already has indentation, which keep it relative to the closest line
  above them that has none. Tokens a macro copies from the source keep their trivia, so the
  user's own indentation shows through.
- Apple's templates are indented as their output is, and a syntax node interpolated alone on a
  template line is indented by that line's indentation (SwiftSyntaxBuilder). Together these
  explain the expansions below that do not look formatted, such as a body closure indented twice
  when the `#Preview` is nested, or `{ content }` split oddly in a `body:` argument.
- Names come from the compiler: `makeUniqueName("PreviewRegistry")` is
  `$s<discriminator>15PreviewRegistryfMu_`, the discriminator mangling the module, file,
  0-based line and column of the expansion.

## Previews (`PreviewsMacros`)

| Macro | Declared by | Type |
|---|---|---|
| `#Preview(_:traits:body:)` with a view | SwiftUI | `SwiftUIView` |
| `#Preview(_:traits:arguments:body:)` | SwiftUI | `SwiftUIViewGroup_1` |
| `#Preview(_:traits:body:)` with a view or view controller | UIKit, AppKit | `KitViewMacro` |
| `#Preview(_:traits:arguments:body:)` | UIKit, AppKit | `PreviewCommonGroup` |
| widget, timeline, relevance and Live Activity `#Preview`s | WidgetKit | `Common` |
| `@Previewable` | SwiftUI | `Previewable` |

Every `#Preview` expands to one struct, the same in Debug and Release (`preview`), never under
`#if DEBUG`:

```swift
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, watchOS 10.0, *)
nonisolated struct $s<discriminator>15PreviewRegistryfMu_: DeveloperToolsSupport.PreviewRegistry {
    static var fileID: String {
        "<module>/<file name>"
    }
    static var line: Int {
        <line of the #>
    }
    static var column: Int {
        <column of the #>
    }

    @MainActor static func makePreview() throws -> DeveloperToolsSupport.Preview {
        <call>
    }
}
```

- **Location.** `line` and `column` are the `#`'s, after the preview's attributes
  (`preview-available`, `preview-indentation`).
- **The call** is `DeveloperToolsSupport.Preview` with the macro's own parentheses and arguments,
  their trivia kept (`preview-spacing`: `( "x" , traits: .portrait )`); trivia after the closing
  parenthesis and after the macro name is dropped, and so are comments there. Trailing closures
  follow (`preview-widget`: `} timeline: {`).
- **The content closure** (the trailing closure, else the `body:` argument) is rewritten:
  - SwiftUI (`SwiftUIView`), when it starts with no `@Previewable` declaration:
    ```swift
    {
        func __b_buildView(@SwiftUI.ViewBuilder body: () -> any SwiftUI.View) -> any SwiftUI.View {
            body()
        }
        return __b_buildView <the closure, trimmed>
    }
    ```
  - SwiftUI with leading `@Previewable` declarations (`preview-previewable`): the declarations
    become properties of a view, without `@Previewable`, their comments and trailing trivia,
    separated by blank lines; a multi-line declaration loses its line's indentation on its other
    lines. The other statements become its body, with their own indentation and without the
    newlines before the first one (`Odd indentation`, `Tabs`); with none, the body is a blank line
    (`Only`):
    ```swift
    {
        struct __P_Previewable_Transform_Wrapper: SwiftUI.View {
            <properties>

            var body: some SwiftUI.View {
            <statements>
            }
        }
        return __P_Previewable_Transform_Wrapper()
    }
    ```
    A `@Previewable` after another statement is an error, "'@Previewable' items must be at the
    beginning of the preview block", with the fix-it "Move the '@Previewable' item" that puts the
    `@Previewable` statements first (`preview-errors`).
  - UIKit and AppKit (`KitViewMacro`), `@Previewable` not applied (`preview-uikit`):
    ```swift
    {
        @resultBuilder struct __B_Builder<Content> {
            static func buildBlock(_ content: Content) -> Content { content }
        }
        func __b_buildContent<Content>(@__B_Builder<Content> build: () -> Content) -> Content {
            build()
        }
        return __b_buildContent <the closure, trimmed>
    }
    ```
  - `arguments:` previews and WidgetKit's: the closures as written (`preview-groups`,
    `preview-uikit-groups`, `preview-widget`).
- **Attributes** (`preview-available`, `preview-availability`, `preview-availability-kinds`,
  `preview-availability-ios18`):
  - `@available` attributes are merged: for each platform, the highest introduced version, from
    the short form (`iOS 18.0`) or `introduced:`; a version with one component gets `.0`
    (`18` → `18.0`), others are written as given (`17.0.1`, `18.0.0`). Platforms the registry
    lists keep only versions above its own (iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0,
    watchOS 10.0); any other platform is always kept (`iOSApplicationExtension 17.0`,
    `macCatalyst 13.0`). If any remains, the call is guarded, platforms sorted by name; the
    deployment target does not matter:
    ```swift
    if #available(iOS 18.0, macCatalyst 18.0, *) {
        <call>
    } else {
        throw DeveloperToolsSupport.PreviewUnavailable()
    }
    ```
  - Platforms made `unavailable` drop their introduced versions and guard the whole, sorted:
    `#if os(tvOS) || os(watchOS)`, `throw DeveloperToolsSupport.PreviewUnavailable()`, `#else`,
    the call, `#endif`, all at the call's indentation.
  - Deprecations are copied to the struct after the registry's own attribute, without their
    messages: `@available(*, deprecated)`, `@available(iOS, deprecated: 26.0)`.
  - Any other attribute is an error, "'@MainActor' attribute cannot be applied to a preview",
    fix-it "Remove the attribute"; a modifier is "'private' cannot be applied to a preview",
    fix-it "Remove 'private'". These and the `@Previewable` order error have no highlights.
- **`@Previewable` elsewhere** is an error, "'@Previewable' can only be used in a SwiftUI
  #Preview body closure", highlighting the attribute.

## SwiftUI state (`SwiftUIMacros`, `@State`)

In the iOS 27.0 SDK, `@State` is a macro besides the property wrapper (`StateMacro`, accessor and
peer); its expansions use four more: `_PropertyWrapperProjectedValue` (`ProjectedValueMacro`),
`_StateProjectedValue`, `_StatePropertyWrapperStorage` and `_StateInitialStoredValue`. Cases
`state-*`; the property's access modifier, type, initial value (written, or `initialValue:` /
`wrappedValue:` in the attribute), container and observers decide the form. The access is the
first access modifier without a setter detail, in any order: `private(set)` and `fileprivate(set)`
do not count (`private(set) var` is internal state, `private(set) public var` public), and `package`
and `open` are written on `$name` as the others are (`state-modifiers`). A name written with
backticks, a keyword or not, keeps them around every name made from it: `` `_default` ``,
`` `__default` ``, `` `$default` `` (`state-keywords`):

- **Directly stored** (internal or public state, and private state without a value):
  ```swift
  private var _name = SwiftUICore.State<T>(initialValue: <value>)

  @SwiftUICore._PropertyWrapperProjectedValue
  <access >var $name = SwiftUICore.State<T>(initialValue: <value>).projectedValue
  ```
  `<T>` only when the property has a type; an optional without a value gets `nil`. Without a
  value and not optional: `private var _name: SwiftUICore.State<T>` and
  `<access >var $name: SwiftUICore.Binding<T> { _name.projectedValue }`.
- **Lazily stored** (`private` or `fileprivate` with a value, or an optional): storage `__name`
  made on first use from a static copy of the value, named `makeUniqueName("_initialStoredValue_")`:
  ```swift
  private var __name = SwiftUICore.State._makeStorage(<storage>)

  @SwiftUICore._StatePropertyWrapperStorage(initialValue: "<base64 of the static's name>")
  private var _name: SwiftUICore.State<_>! = SwiftUICore._stateNil(of: { SwiftUICore.State<T>(initialValue: <value>) })

  @SwiftUICore._StateProjectedValue
  <access> var $name = SwiftUICore.State<T>(initialValue: <value>).projectedValue

  @SwiftUICore._StateInitialStoredValue("<base64 of an expression>")
  private static var <static> = (<initial>)
  ```
  Untyped, `<storage>` is `{ <value> }` and `<initial>` `SwiftUICore.State._makeStorage(initialValue: <value>)`;
  typed, `({ let value: <T> = <value>\nreturn value })` and
  `SwiftUICore.State._makeStorage(initialValue: { let x: <T> = <value>\nreturn x }())`. The base64
  expression is the storage's (`SwiftUICore.State._makeStorage(<storage>)`), or, for an optional
  without a written value, `<initial>`; both are the text before formatting.
- **Accessors**: `@storageRestrictions(initializes: <storage>) init(initialValue)` unless the state
  is lazily stored with a written value (`_makeStorage(initialValue: initialValue)` for a lazy
  optional), `get` and `nonmutating set` over `<storage>.wrappedValue`.
- **Classes and actors** keep the storage internal (no `private`); a class's setter is `set`, an
  actor's stays `nonmutating set`, which the compiler rejects (`state-classes`).
- **Observers** (`state-observers`, `state-observers-forms`): the accessors are separated by blank
  lines, and the setter's statements are, joined by newlines (only the first is indented by the
  template): `let <old> = <storage>.wrappedValue` when `didSet` has a parameter or uses `oldValue`
  (`<old>` is `makeUniqueName("_oldValue_")`), the `willSet` body as
  `({ <parameter or newValue> in\n    <statements>\n})(newValue)`, the store, then the `didSet`
  body as `({ <parameter or oldValue> in\n    <statements>\n})(<old>)`, or `({\n    <statements>\n})()`
  when it needs no old value.
- The helper macros: `_PropertyWrapperProjectedValue` on `$name` gives `get { _name.projectedValue }`,
  `_StateProjectedValue` `get { __name.projectedValue }`; `_StatePropertyWrapperStorage` gives
  `__name` an `init(initialValue)` from the static or `_makeStorage(initialValue: initialValue.wrappedValue)`,
  a `get` making a `State` from it and a `set` storing a new one; `_StateInitialStoredValue` a
  `get` returning the decoded expression.
- **Local types** (`state-local`). Xcode 27.0's compiler does not apply the macro to state in a
  type declared in a function, closure or property (`@Previewable`'s wrapper view is one): it
  uses the `State` property wrapper and never asks the plugin, so Xcode's dump has no expansion
  and its objects call `State.init(wrappedValue:)`. swift.org's 6.4.0 compiler applies the macro
  there, with a lexical context that has a function, closure or variable after the type. For
  those, nomac's `StateMacro` gives the property wrapper's code (SE-0258) instead: no lazy
  storage, `private var _name = SwiftUICore.State<T>(wrappedValue: <value>)` (or a typed
  `SwiftUICore.State<T>` without a value), `$name` through `_PropertyWrapperProjectedValue`
  (or a `Binding<T>` getter), and the usual accessors with `init(initialValue)` making the state
  with `init(wrappedValue:)`, which the memberwise initializer needs (`init(count:...)`, as with
  the wrapper). The objects then import the `State` entry points Xcode's do (`init(wrappedValue:)`,
  `wrappedValue`, `projectedValue`). In a type local to a closure, the init accessor makes both
  compilers check the access to the storage dynamically (`swift_beginAccess`, `swift_endAccess`
  in the memberwise initializer), which the property wrapper Xcode's compiler applies does not.
  The view `@Previewable` declares its state in (`__P_Previewable_Transform_Wrapper`, which the
  preview makes without arguments) therefore gets no init accessor: `preview-previewable`'s
  object built on Linux then differs from Xcode's only as any Swift object does (stack checks,
  register-specific retains, ADR 0101; metadata accessors). Another closure-local type with a
  `some View` member crashes both compilers, state or not. `macro_experiments.py linux` counts a
  case whose dump differs only by these buffers (`_$l` in their names) as identical, and says
  so. A closure-local type that is not a view keeps the init accessor and its access check.

## SwiftUI entries (`SwiftUIMacros`, `@Entry`)

`EntryMacro` (accessor and peer), `EntryDefaultValueMacro` (`__EntryDefaultValue`), and
`EntryTypeCheckMacro` and `EntryTypeCheckClassMacro` (`_SwiftUIEntryTypeCheck`, chosen by the
compiler for a class or optional class). Cases `entry-*`. `EntryMacro`'s expansions are not
formatted: the value keeps its spelling (`0..<1`, `{ 1 }`) and the accessors carry their own
indentation:

```swift
{
    get {
        self[__Key_name.self]
    }
    set {
        self[__Key_name.self] = newValue
    }
    _modify {
        yield &self[__Key_name.self]
    }
}
```

```swift
private struct __Key_name: <key> {
    @SwiftUICore.__EntryDefaultValue
    static var defaultValue<: T> = <value>
}
```

- `<key>` comes from the extended type, by its last name component: `EnvironmentValues`
  `SwiftUICore.EnvironmentKey`, `Transaction` `SwiftUICore.TransactionKey`, `ContainerValues`
  `SwiftUICore.ContainerValueKey`, `FocusedValues` `SwiftUI.FocusedValueKey`. For `FocusedValues`
  the key is `typealias Value = <wrapped type>`; an entry without a type is "Property missing a
  type annotation", fix-it "Add type annotation" (`<name> : <#Type#> = <value>`), the type must be
  optional ("custom 'FocusedValues' entry must be Optional", fix-it `<type>?`) and a value other
  than `nil` is an error with two fix-its (`entry-containers`, `entry-closures-focused`).
- An optional without a value gets `nil`; no value otherwise is "Property missing a default
  value", fix-it `= <#T##default value##<T>#>`.
- When the value is a function call (`Proxy()`, `.init(...)`, `.constant(1)`; not `Proxy()!`,
  `try?`, `as`, arrays or ternaries), the key also checks the type, at the `var`'s line:
  ```swift
      #sourceLocation(file: "<module>/<file>", line: <line of var>)
      private static let _typeCheck: Void = #_SwiftUIEntryTypeCheck(Value.self, macroName: "Entry", propertyName: "<name>")
      #sourceLocation()
  ```
  which expands to `()`, with a warning for a class ("Storing a class type in '@Entry var <name>'
  may invalidate dependents on every update ..."). A function type, with attributes
  (`@Sendable () -> Void`, `@MainActor () -> Void`), optional or in parentheses, or a closure value,
  is warned about by `EntryMacro` ("Storing a closure in '@Entry var <name>' ...") on the type,
  else the value; a tuple with a function among its elements is not (`entry-closures-focused`).
- `__EntryDefaultValue` gives `defaultValue` a `get` returning the value.
- Errors are diagnosed with an empty expansion: outside the four containers, on a `let` (fix-it
  "Replace 'let' with 'var'"), on a static member (accessor role, fix-it "Remove 'static'").

## SwiftData (`SwiftDataMacros`)

| Macro | Type | Roles |
|---|---|---|
| `@Model` | `PersistentModelMacro` | member, member attribute, extension |
| `@_PersistedProperty`, `@_TransformablePersistedProperty` | `PersistedPropertyMacro`, `TransformablePersistedPropertyMacro` | peer, accessor |
| `@Transient`, `@Attribute`, `@Relationship` | `TransientPropertyMacro`, `AttributePropertyMacro`, `RelationshipPropertyMacro` | peer (empty) |
| `#Unique`, `#Index` | `UniqueConstraintsMacro`, `IndexMacro` | declaration (empty) |
| `@ModelActor` | `PersistentModelActorMacro` | member, extension |
| `@Query` (declared by `_SwiftData_SwiftUI`) | `QueryMacro` | peer, accessor |

Cases `swiftdata-*`. All are formatted (`BasicFormat`). `@Model`'s `schemaMetadata` and
`init(backingData:)` templates are indented by two spaces, its `access` function's parameter by
four. Values and arguments copied from the source keep their own line breaks, and `BasicFormat`
adds what their tokens need: `[ 1,2 ]` gives `[ 1, 2 ]`, `originalName:"x"` gives
`originalName: "x"`, and `{ 1 }()` gives a closure on three lines.

**Persisted properties.** A property is persisted when its first binding is a `var` or `let` that
stores its value (no accessors, or only `willSet`/`didSet`), and it is not `static` or `class` and
has no `@Transient`. `lazy`, `weak`, `private(set)` and `@ObservationIgnored` properties are
persisted too; a tuple pattern is not (`swiftdata-properties`, `swiftdata-property-errors`).

The member attribute is `@_TransformablePersistedProperty` when an `@Attribute` option is
`.transformable(...)`, else `@_PersistedProperty`. It carries the property's leading trivia (its
comments), so a doc comment shows before it. `BasicFormat` indents a first token by its line, so
`/** Block */ var` gives `/** Block */     @_PersistedProperty`. Names are unescaped:
`` `default` `` gives `_default` and `\Item.default`.

**Members.** `T` is the class's name. A member role without a conformance list means a subclass
of a model: the compiler sends no list when the superclass already conforms.

```swift
@Transient
private var _$backingData: any SwiftData.BackingData<T> = T.createBackingData()

public var persistentBackingData: any SwiftData.BackingData<T> {
    get {
        return _$backingData
    }
    set {
        _$backingData = newValue
    }
}

[override ][public ]class var schemaMetadata: [SwiftData.Schema.PropertyMetadata] {
  return [
    SwiftData.Schema.PropertyMetadata(name: "<name>", keypath: \T.<name>, defaultValue: <value or nil>, metadata: <nil or the attribute>),
    ...
  ]
}

[required ][public ]init(backingData: any SwiftData.BackingData<T>) {
  _<name> = _SwiftDataNoType()
  ...
  self.persistentBackingData = backingData
}

@Transient private let _$observationRegistrar = Observation.ObservationRegistrar()

internal nonisolated func access<_M>(
    keyPath: KeyPath<T, _M>
) {
  _$observationRegistrar.access(self, keyPath: keyPath)
}

internal nonisolated func withMutation<_M, _MR>(
  keyPath: KeyPath<T, _M>,
  _ mutation: () throws -> _MR
) rethrows -> _MR {
  try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
}

struct _SwiftDataNoType {
}
```

- `public` is added only for a `public` class (not `open`, `fileprivate`, `private` or nested).
  `required` is added unless the declaration is a `final` class. `persistentBackingData` is always
  `public` (`swiftdata-access`).
- An empty list of properties leaves an empty line between `return [` and `]`, and between the
  init's `{` and its last statement.
- The metadata repeats the property's `@Attribute` or `@Relationship`: its name as written, then
  its arguments trimmed. So `@Attribute var` gives `SwiftData.Schema.Attribute ()` (the name keeps
  the space before `var`), and a multi-line argument list loses its first line break
  (`swiftdata-forms`).
- `#Index` and `#Unique` among the members change `return [...]` (`swiftdata-constraints`):
  ```swift
    let storedProperties = [
      ...
    ]
    var otherProperties = [SwiftData.Schema.PropertyMetadata]()
    <#Index line>
    <#Unique line>
    return storedProperties + otherProperties
  ```
  Each line is empty when its macro is absent. Otherwise it is, for the first `#Index` (or
  `#Unique`):
  ```swift
  if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) {
      otherProperties.append(
        SwiftData.Schema.PropertyMetadata(name: "SwiftData.Schema.Index", keypath: \SwiftData.Schema.encodingVersion, defaultValue: nil, metadata: SwiftData.Schema.Index<T>(<arguments>)))
    }
  ```
- A subclass (`swiftdata-inheritance`, `swiftdata-subclasses`):
  - has no `persistentBackingData`, and `override` on `schemaMetadata`;
  - has `required [public ]init(backingData: any SwiftData.BackingData<Root>)`, with `Root` as
    written whatever the superclass. Its init ends with
    `_$backingData = backingData._generateCurrentClassBackingData()` and
    `super.init(backingData: backingData._superClassBackingData(of: T.self))`;
  - gets nothing from the extension role.
- These errors still come with the expansion (`swiftdata-errors`, `swiftdata-property-errors`):
  - "'@Model' cannot be applied to struct type 'T'" (or `enumeration`, `actor`), on the attribute;
  - "@Model requires an initializer be provided for 'T'", on the declaration;
  - "A PersistentModel Subclass is required to have platform availability specified", when no
    `@available` names a platform with a version. `@available(iOS 26, *)` names one;
    `@available(iOS, introduced: 26)` and `@available(*, deprecated)` do not;
  - "@Transient requires non-optional property 'x' to have a default value". `T?` and `T!` count
    as optional, `Optional<T>` does not;
  - "#Unique can only be used once per PersistentModel" (and `#Index`), on each later one.

**Extensions.** `E` is the extended type as the compiler renders it (`Outer.Nested`). The
extensions are the same whatever conformances the compiler lists:

```swift
extension E: nonisolated SwiftData.PersistentModel {
}

extension E: nonisolated Observation.Observable {
}

@available(swift, deprecated: 5.9, message: "PersistentModels are not Sendable, consider utilizing a ModelActor or use E's persistentModelID instead")
@available(*, unavailable, message: "PersistentModels are not Sendable, consider utilizing a ModelActor or use E's persistentModelID instead")
extension E: Sendable {
}
```

**`@_PersistedProperty`.**
- The peer is `@Transient\nprivate var _<name>: _SwiftDataNoType[?|!][ = _SwiftDataNoType()]`:
  `?` for `T?`, `!` for `T!`, and the value when the property has one.
- The accessors:
  - `init(initialValue)`, under `@storageRestrictions(accesses: _$backingData, initializes: _<name>)`,
    sets `_$backingData.setValue(forKey: \.<name>, to: initialValue)`;
  - `get` goes through `_$observationRegistrar.access` and `self.getValue(forKey:)`;
  - for a `var`, `set` goes through `withMutation` and `self.setValue(forKey:to:)`.
- The transformable form uses `setTransformableValue` and `getTransformableValue`.
- Each accessor's first token has the attribute's leading trivia followed by two spaces. A
  documented property's comment is therefore repeated before each accessor, its last line indented
  by two more: `/// a\n    @_PersistedProperty` gives `/// a\n      get {`, which the braces then
  indent by four.

**`@ModelActor`.** It adds `[public ]nonisolated let modelExecutor: any SwiftData.ModelExecutor`,
`[public ]nonisolated let modelContainer: SwiftData.ModelContainer` and
`[public ]init(modelContainer:)`, which makes a `ModelContext` and a `DefaultSerialModelExecutor`.
Its extension is `extension E: SwiftData.ModelActor {\n}`. On a class or struct it expands the
same, and the compiler reports the errors.

**`@Query`** (`swiftdata-query`, `swiftdata-query-forms`).
- The peer is `private(set) var _<name>: SwiftData.Query<<element>, <type>> = .init(<arguments>)`,
  whatever the property's access, `static` or `let`.
- `<element>` is `<type>.Element` (`[Tag].Element`, `Array<Tag>.Element`), or the first generic
  argument of `SectionedResults<E, S>`.
- The arguments are the attribute's as written, their line breaks kept.
- The accessor is `get {\n    _<name>.wrappedValue\n}`.
- Without a type annotation the peer is "Property missing a type annotation", on the binding; the
  accessor is still made.

## AppIntents (`AppIntentsMacros`)

`AppEntityMacro`, `AppIntentMacro`, `AppEnumMacro` and `_UnionValueMacro`; the `appintents-*`
cases and home-assistant's 21 schema files. Not formatted.

- `@AppEntity(schema: .calendar.event)` marks each instance variable the schema has with
  `@Property`, and `@AppIntent(schema:)` with `@Parameter()`, unless the variable already has
  that attribute; `let` variables too (the compiler then rejects the wrapper). Which names a
  schema has is the plugin's own knowledge: neither the SDK nor any diagnostic shows it
  (`id`, app-specific names such as `uid` or `entityId`, and `bogus` are not marked).
  `reminders.createReminder`'s `images` is `@Parameter(supportedContentTypes: [.image])`, whatever
  its type. nomac knows the 13 schemas home-assistant uses (`AppIntentsMacros/Members.swift`);
  an entity or intent on another schema gets nomac's error (B-158). `@AppEnum` marks nothing.
- The extension role writes, for the conformances the compiler still lacks, in this order:
  `extension T: AssistantSchemaEntity { static let __appSchemaEntity = "calendar.event" }`
  (`AssistantSchemaIntent`/`__appSchemaIntent`, `AssistantSchemaEnum`/`__appSchemaEnum`), the
  name as written without its leading dot; `extension T: AppEntity {\n}` (`AppIntent`,
  `AppEnum`); and the schema's own (`reminders.deleteReminders`: `DeleteIntent`, not
  `calendar.deleteEvent`). Each repeats the type's `@available` attributes with their leading
  trivia, so a documentation comment comes only with them; without any, the first and the
  schema's own get `@available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)`
  and the kind's none. A public type's static member is `public`.
- `@UnionValue` on an enum whose cases each hold one value writes `nonisolated extension T:
  _IntentValueRepresentable` (after the type's `@available` attributes as above) with
  `allIntentValueTypes`, `asIntentValue` and one `<Type>Resolver` per case, and
  `@available(macOS 27.0, *) @available(iOS 27.0, *) @available(watchOS 27.0, *) @available(tvOS 27.0, *) @available(visionOS 27.0, *) nonisolated extension T: AppUnionValue`
  with `enum <T>Cases`. A public enum makes the members, typealiases and cases enum `public`,
  not the resolvers. Another case is "@UnionValue requires that each enum case have exactly one
  associated value", thrown at the attribute.

## FoundationModels (`FoundationModelsMacros`)

`GenerableMacro` and `GuideMacro`; the `foundationmodels-*` cases. Not formatted: the templates
keep Xcode's spacing (the `addProperty` bodies are indented by two spaces less than their
nesting), and only the guides are formatted (`.range(0...120)` becomes `.range(0 ... 120)`).

- A struct gets `generationSchema`, `generatedContent` and `PartiallyGenerated` (members) and
  `extension <Type>: nonisolated FoundationModels.Generable` with `init(_ content:)`, the type
  as the compiler names it (`Outer.Inner`), after the struct's `@available` attributes. Its
  properties are the stored instance ones with a type annotation, in order, `let` and
  initialized ones included (`static`, computed and untyped ones left out), named trimmed.
- The schema's first arguments are `type: Self.self` (or `name:` for `@Generable(name:)`, which
  the iOS 27.0 SDK does not accept: Xcode's expansion fails to compile, and so does nomac's),
  then `description:`, then `representNilExplicitlyInGeneratedContent:`; then the properties,
  `FoundationModels.GenerationSchema.Property(name:description:type:guides:)` with the `@Guide`'s
  description and its other arguments as guides (a regex literal is a guide). An empty list
  leaves an empty line. `representNilExplicitlyInGeneratedContent: true` makes
  `let explicitNil = true`.
- `public` on the type puts `public` after `nonisolated` on every member and the extension's
  initializer, and before `var id`; other access levels give nothing. `PartiallyGenerated`'s
  properties keep the access modifiers the properties have (`internal`, `private`, `public`).
  Doc comments give no description.
- An enum without associated values: `GenerationSchema(type: Self.self, description:, anyOf: [...])`
  of the cases' names as strings, `generatedContent` switching over them, and an initializer
  switching over the raw content with "Unexpected value"; with `String` among its inherited
  types, `anyOf: [<case>.rawValue, ...]`, `rawValue.generatedContent` and `Self(rawValue:)` with
  "Unexpected rawValue".
- An enum with associated values (any case): a `PartiallyGenerated` enum, `anyOf:` of one
  `private nonisolated struct Discriminated<Case>` per case (a `@Guide(.constant("<case>"))`
  `type` and the values, a single unlabeled one named `value`), each written as a struct's
  members, and `generatedContent` building `GeneratedContent(properties: ["type": ..., ...])`
  (a case without values leaves an empty line). The `@Guide`s inside are expanded too.
- A class, an actor or a protocol: "'@Generable' can only be used on structs and enums.", at the
  attribute and highlighting it, from the member role, which expands to nothing; the extension
  role expands to nothing either. `@Guide` expands to nothing.

## TipKit (`TipKitMacros`)

`ParameterMacro` and `RuleMacro`; the `tipkit-*` cases.

- `@Parameter` on `static var name: T = value` adds the peer
  `<modifiers> static nonisolated(unsafe) var $name: Tips.Parameter<T> = Tips.Parameter(Self.self, "+name", value)`
  and the accessors `get { $name.wrappedValue }` and `set { $name.wrappedValue = newValue }`.
  The modifiers other than `static` are kept in order (`public`, `private`). An instance
  property gets neither `static` nor `nonisolated(unsafe)` and the key `-name`. The options
  (`@Parameter(.transient)`) follow the value as arguments. The name is the pattern with its
  trailing trivia (`static var  spaced  :` gives `$spaced  :`, the key `"+spaced  "` and
  `$spaced  .wrappedValue`); the type and the value are trimmed.
- Errors, at the attribute: a `let` is "Unable to expand <the declaration as written, its
  leading trivia and attributes included> using @Parameter."; a variable without a type, without
  a value or with accessors is "Unable to expand due to missing identifier pattern.".
- `#Rule(input) { body }` is `Tips.Rule(input) <closure>`, the closure translated as
  swift-foundation 6.3's `#Predicate` translates it: builder calls without a module selector
  (`PredicateExpressions.build_Equal`), not built with `FOUNDATION_FRAMEWORK` (`evaluate(_:)`
  is "not supported in this predicate"), plus `donatedWithin`, whose argument stays as written
  (`PredicateExpressions.build_donatedWithin(<donations>, .week)`). Its errors are
  `#Predicate`'s ("The uppercased() function is not supported in this predicate", "Predicate
  body may only contain one expression", "Global functions are not supported in this
  predicate") without a source position (the plugin translates a detached copy).
- `.filter` anywhere in the closure is "The filter function is not supported in this rule.", at
  the name `filter`, before any translation.
- With several inputs the body, parsed again as `{<body>}` (Xcode's positions are one column
  further right on its first line only) and folded, is split at `&&` and `||`, through
  parentheses: a chain of one operator is one `Tips.Rule(.conjunction, [...])` or
  `Tips.Rule(.disjunction, [...])`, and `a && b > 1 || c` nests as precedence folds it. Each
  operand, in order, is one input's `Tips.Rule(input) { (name) in <operand> }` (the closure's
  parameter name, or `$0` for the input's own `$n`), translated as above. Each element is
  indented by eight spaces under its compound, whose `])` is indented by four.
- A body with several inputs that is one operand is returned as written (`a`, which the
  compiler then rejects); a top-level operator other than `&&` and `||` is "'<the operator
  with its trailing trivia>' operator is not supported in this rule"; an operand beyond the
  inputs is "failed to expand compound rule: DiagnosticsError(diagnostics: [<line>:<column>:
  unable to expand input for <the operand with its trailing trivia>])", both without a source
  position.

## Open-source macros

Xcode keeps its own builds of `ObservationMacros`, `FoundationMacros` and `SwiftMacros` in the
platform's plugin directory. `@Observable` and `@ObservationIgnored` expand on Linux with swift.org's
plugin as Xcode's do (`observation`), so nomac links it there (ADR 0150). `#Predicate` and
`#Expression` do not with swift.org's: its `FoundationMacros` names `FoundationEssentials` where
Xcode's names `Foundation` (`Foundation.Predicate<Item>`,
`PredicateExpressions.Foundation::build_Conjunction`), which does not compile for iOS. swift-foundation
writes `Foundation`, and accepts `localizedStandardContains`, `localizedCompare`,
`caseInsensitiveCompare` and `evaluate`, only when built with `FOUNDATION_FRAMEWORK`; nomac builds
its `FoundationMacros` so, from swift-foundation at `swift-6.4.0-RELEASE`, and `#Predicate`,
`#Expression` and `#bundle` then expand as Xcode's do, the errors for unsupported functions and
members included (`foundation-predicate`, `foundation-predicate-forms`). `#bundle` reads the
build configuration the compiler sends with each request.

## Plugins of the project's own

Observed with `.github/scripts/macro_plugin_experiments.py` (self-written apps, Xcode 27.0 and
swift.org 6.4.0) and Expo SDK 58's `expo-modules-macros` (ADR 0151):

- A SwiftPM macro target the app depends on is built by Xcode for the build machine, against
  SwiftPM's swift-syntax prebuilts (`SourcePackages/prebuilts/swift-syntax/<version>/
  swiftlang-<compiler>-macosx27.0-MacroSupport`), and loaded with
  `-load-plugin-executable $(BUILT_PRODUCTS_DIR)/<target>#<target>` (macro-package).
- A plugin named in `OTHER_SWIFT_FLAGS` is run as named. Of several `-load-plugin-executable`
  for one module the compiler uses the first (`order`), so a build that loads another build of a
  plugin puts its flag before the project's.
- `swift build` of a package whose macro target no product names needs `--build-system native
  --product <target>` and writes `<bin>/<target>-tool`; the default build system of SwiftPM 6.4
  builds no such target. Macro targets build for the build machine's architecture only.
- The plugin built from the package that ships beside a prebuilt one gives the prebuilt's
  expansions byte for byte (`expansions`; `expo_experiments.py macros` for Expo's).
