#!/usr/bin/env python3
"""Apple's closed macros: which corpus apps use them, and what Xcode 27.0 expands them to (B-121).

Xcode loads the macros of Apple frameworks from the iPhoneOS platform's
`usr/lib/swift/host/plugins` (SwiftData, Previews, SwiftUI, AppIntents, TipKit,
FoundationModels, ...) through the platform's `swift-plugin-server`: macOS binaries a Linux
compiler cannot load. nomac reimplements them (docs/formats/macros.md, docs/adr/0150-macro-plugins.md).

Usage:
  macro_experiments.py survey <corpus-checkouts-dir>
      per app, the Swift files that use each kind of closed macro; package checkouts and Pods
      are skipped
  macro_experiments.py preview <output-dir>      (on a Mac; DEVELOPER_DIR selects the Xcode)
      compiles a self-written #Preview file for iOS as Release (-O) and as Debug (-Onone
      -DDEBUG) with -dump-macro-expansions, and counts the PreviewRegistry symbols of each object
  macro_experiments.py record <output-dir> [case...]      (on a Mac)
      compiles each case with Xcode's compiler and -dump-macro-expansions (<case>/xcode.txt), with
      the platform's plugins behind a proxy that logs the plugin protocol (<case>/protocol/*.jsonl)
  macro_experiments.py compare <output-dir> [case...]     (on a Mac, after record)
      builds nomac's plugins (Sources/NomacMacros/Plugins) against the selected Xcode's host
      swift-syntax, compiles each case with Xcode's compiler and those plugins first
      (<case>/nomac.txt) and prints whether the expansions are identical to Xcode's
  macro_experiments.py linux <output-dir> <developer-dir> [case...]      (on Linux, after record)
      compiles each case with the swift.org compiler 'nomac toolchain install' put in
      <developer-dir> (at the Mac's paths), against its iPhoneOS SDK, with nomac's plugins
      (<case>/linux.txt), and prints whether the expansions are identical to Xcode's
  macro_experiments.py corpus <corpus-checkouts-dir> <output-dir> <kind>...     (on a Mac)
      type-checks, one at a time, every corpus Swift file that uses the given kinds of macros
      (see KINDS) with Xcode's compiler, once with Apple's plugins and once with nomac's first,
      and compares the expansion buffers; imports of modules the SDK lacks are removed from both
  macro_experiments.py facts <output-dir> <module>... [--case <case>]...
      prints, as Swift for NomacMacrosTests, each recorded case's self-written source, where the
      compiler addressed each use of the given plugin modules' macros, and the SHA-256 digest of
      Xcode's answer; no capture is written into the repository
  macro_experiments.py tee <server> <log-dir>
      the logging proxy record puts in front of the platform's swift-plugin-server
"""

import collections
import concurrent.futures
import glob
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import threading
from pathlib import Path

KINDS = {
    "previews": r"#Preview\b|@Previewable\b",
    "state": r"@State\b",
    "swiftdata": r"@Model\b|#Unique\b|#Index\b|@Relationship\b|@Transient\b|@Attribute\(|@ModelActor\b|@Query\b",
    "swiftui": r"@Entry\b|@Animatable\b",
    "appintents": r"@Assistant(Intent|Entity|Enum)\b|@AppIntent\(|@AppEntity\(|@AppEnum\(|@UnionValue\b|@ComputedProperty\b|@DeferredProperty\b",
    "tipkit": r"#Rule\b",
    "foundationmodels": r"(?m)^\s*@Generable\b|^\s*@Guide\b",
}
SKIPPED = ("/Pods/", "/checkouts/", "/SourcePackages/", "/.build/", "/DerivedData/")
TARGETS = {"ios17": "arm64-apple-ios17.0", "ios18": "arm64-apple-ios18.0", "ios26": "arm64-apple-ios26.0", "ios27": "arm64-apple-ios27.0"}
PLUGINS = Path(__file__).resolve().parents[2] / "Sources" / "NomacMacros" / "Plugins"

PREVIEW_SOURCE = """import SwiftUI

struct V: View {
    var body: some View { Text("x") }
}

#Preview {
    V()
}

#Preview("Named") {
    V()
}
"""

PREVIEW_VIEW = """import SwiftUI

struct V: View {
    var title = ""
    var body: some View { Text(title) }
}
"""

CASES = {
    # #Preview with a SwiftUI view (PreviewsMacros.SwiftUIView)
    "preview-plain": ("ios17", PREVIEW_VIEW + """
#Preview {
    V()
}
"""),
    "preview-names": ("ios17", PREVIEW_VIEW + """
#Preview("Named") {
    V()
}

#Preview("Ünïcödé \\u{1F600} \\"q\\" \\(1 + 1)") {
    V()
}

#Preview(#"raw "name""#) {
    V()
}

#Preview(
    "Multi-line arguments",
    traits: .sizeThatFitsLayout
) {
    V()
}
"""),
    "preview-traits": ("ios17", PREVIEW_VIEW + """
#Preview("Second", traits: .landscapeLeft) {
    V()
}

#Preview(traits: .sizeThatFitsLayout, .fixedLayout(width: 100, height: 200)) {
    V()
        .padding()
}

#Preview(traits: .portrait) { V() }
"""),
    "preview-spacing": ("ios17", PREVIEW_VIEW + """
#Preview( "x" ,traits:.portrait ){V()}

#Preview{V()}

#Preview  {
    V()
}

#Preview("a")   {   V()   }

#Preview /* comment */ {
    V() // comment
}

#Preview("b"  ) /* c */ {
    V()
}

#Preview(  ) {
    V()
}

#Preview("c")
{
    V()
}

#Preview(
    "d"
)   {
    V()
}

#Preview("e") {
    V()
} // trailing comment

#Preview("f") { V() } /* block */ // line
"""),
    "preview-body-label": ("ios17", PREVIEW_VIEW + """
#Preview(body: {
    V()
})

#Preview("Labeled", body: { V(title: "x") })
"""),
    "preview-bodies": ("ios17", PREVIEW_VIEW + """
#Preview {
    let title = "a"
    return V(title: title)
}

#Preview {
    // a comment
    VStack {
        V()  // trailing
        V(title: "b")
    }
    /* block */
}

#Preview { if Bool.random() { V() } else { Text("y") } }

#Preview {}

#Preview {

    V()

}

#Preview {
#if DEBUG
    V(title: "debug")
#else
    V()
#endif
}
"""),
    "preview-indentation": ("ios17", """import SwiftUI

struct V: View {
\tvar body: some View { Text("x") }
}

#Preview("Tabs") {
\tVStack {
\t\tV()
\t}
}

#Preview("Two") {
  V()
    .padding()
}

enum Holder {
    #Preview("Nested") {
        V()
    }
}

#if DEBUG
#endif
#if os(iOS)
  #Preview("In if") {
      V()
  }
#endif
"""),
    "preview-available": ("ios17", PREVIEW_VIEW + """
@available(iOS 18.0, *)
#Preview("Available") {
    V()
}

@available(iOS 17, *)
#Preview {
    V()
}

@available(iOS 16.0, watchOS 10.0, *)
#Preview("Two platforms") {
    V()
}

@available(macOS 13.0, *)
#Preview {
    V()
}

@available(iOS 17.0, *)
@available(macOS 14.0, *)
#Preview("Two attributes") {
    V()
}

@available(iOS 18.0, *) #Preview("Same line") { V() }

@available(iOS, introduced: 17.0)
#Preview("Introduced") {
    V()
}
"""),
    "preview-availability": ("ios17", PREVIEW_VIEW + """
@available(iOS 17.2, *)
#Preview("17.2") {
    V()
}

@available(iOS 18, *)
#Preview("18") {
    V()
}

@available(iOS 18.0, macOS 15.0, *)
#Preview("Both higher") {
    V()
}

@available(iOS 16.0, macOS 15.0, *)
#Preview("macOS higher") {
    V()
}

@available(watchOS 11.0, *)
#Preview("watchOS higher") {
    V()
}

@available(visionOS 2.0, tvOS 18.0, *)
#Preview("visionOS and tvOS higher") {
    V()
}

@available(iOS 18.0, *)
@available(macOS 15, *)
#Preview("Two attributes higher") {
    V()
}

@available(iOS, introduced: 18.0)
#Preview("Introduced higher") {
    V()
}

@available(iOSApplicationExtension 18.0, *)
#Preview("Extension") {
    V()
}

@available(iOS 18.0,*)
#Preview("Spacing") {
    V()
}

@available(iOS 17.0.1, *)
#Preview("Patch") {
    V()
}

@available(iOS 26, *)
#Preview("26") {
    @Previewable @State var count = 0
    V(title: "\\(count)")
}
"""),
    "preview-availability-kinds": ("ios17", PREVIEW_VIEW + """
@available(*, deprecated, message: "Old")
#Preview("Deprecated message") {
    V()
}

@available(iOS, deprecated: 18.0)
#Preview("iOS deprecated") {
    V()
}

@available(iOS, introduced: 18.0, deprecated: 26.0, message: "x")
#Preview("Introduced and deprecated") {
    V()
}

@available(iOSApplicationExtension 17.0, *)
#Preview("Extension 17") {
    V()
}

@available(macCatalyst 13.0, *)
#Preview("Catalyst 13") {
    V()
}

@available(macCatalyst 18.0, iOS 18.0, *)
#Preview("Catalyst 18") {
    V()
}

@available(iOS 18.0, *)
@available(iOS 18.1, *)
#Preview("Twice") {
    V()
}

@available(iOS 18.0.0, *)
#Preview("Three components") {
    V()
}

@available(watchOS, unavailable)
@available(tvOS, unavailable)
#Preview("Two unavailable") {
    V()
}

@available(iOS, unavailable)
@available(iOS 18.0, *)
#Preview("Unavailable and higher") {
    V()
}

@available(*, deprecated)
@available(iOS 18.0, *)
#Preview("Deprecated and higher") {
    V()
}
"""),
    "preview-availability-ios18": ("ios18", PREVIEW_VIEW + """
@available(iOS 18.0, *)
#Preview("Deployment target 18") {
    V()
}
"""),
    "preview-errors": ("ios17", PREVIEW_VIEW + """
/// Doc comment
@MainActor
#Preview {
    V()
}

private #Preview("Private") {
    V()
}

@available(*, deprecated)
#Preview("Deprecated") {
    V()
}

@available(iOS, unavailable)
#Preview("Unavailable") {
    V()
}

#Preview("Middle", traits: .portrait) {
    let title = "a"
    @Previewable @State var count = 0
    V(title: title + "\\(count)")
}

struct Peer {
    @Previewable var outside = 0
}
"""),
    "preview-previewable": ("ios17", PREVIEW_VIEW + """
#Preview {
    @Previewable @State var count = 0
    V(title: "\\(count)")
}

#Preview("Two") {
    @Previewable @State var selection: String? = "secure"
    @Previewable @State var flag = false

    let options = ["a", "b"]
    return VStack {
        ForEach(options, id: \\.self) { V(title: $0) }
        Toggle("x", isOn: $flag)
    }
}

@available(iOS 17.0, *)
#Preview("Available") {
    @Previewable @State var count = 0
    V(title: "\\(count)")
}

@available(iOS 18.0, *)
#Preview("Available higher") {
    @Previewable @State var count = 0
    V(title: "\\(count)")
}

#Preview {
    @Previewable @FocusState var focused: Bool
    V().focused($focused)
}

#Preview("Comments") {
    // The state
    @Previewable @State var count = 0 // trailing
    /// Doc
    @Previewable @AppStorage("key") var stored = 1
    V(title: "\\(count) \\(stored)")
}

#Preview("Only") {
    @Previewable @State var count = 0
}

#Preview("Let") {
    @Previewable @State var a = 0; @Previewable @State var b = 1
    let sum = a + b
    V(title: "\\(sum)")
}

#Preview(body: {
    @Previewable @State var count = 0
    V(title: "\\(count)")
})

#Preview("Odd indentation") {
    @Previewable @State var count = [
      1,
        2
    ]
    VStack {
          V()
      V(title: "x")
    }
}

#Preview("Tabs") {
	@Previewable @State var count = 0
	VStack {
		V()
	}
}

#Preview("Arguments", traits: .portrait) {
    @Previewable @State var text = ""
    VStack {
        TextField("t", text: $text)
    }
    .padding()
}
"""),
    "preview-previewable-groups": ("ios26", PREVIEW_VIEW + """
#Preview("Group", arguments: [1, 2]) { n in
    @Previewable @State var count = 0
    V(title: "\\(n) \\(count)")
}
"""),
    "preview-uikit": ("ios17", """import UIKit

#Preview {
    UIViewController()
}

#Preview("Label", traits: .portrait) {
    let label = UILabel()
    label.text = "x"
    return label
}

@available(iOS 18.0, *)
#Preview("Available") {
    UIView()
}

#Preview("Single line") { UIView() }

#Preview("Newline")
{
    UIView()
} // trailing comment

#Preview("Previewable") {
    @Previewable @State var count = 0
    UIView()
}

#Preview(body: {
    UIView()
})
"""),
    "preview-groups": ("ios26", PREVIEW_VIEW + """
#Preview("Numbers", arguments: [1, 2, 3]) { n in
    V(title: "\\(n)")
}

#Preview(traits: .landscapeLeft, arguments: ["a"]) { s in
    Text(s)
}

@available(iOS 26.0, *)
#Preview("Available", arguments: [true]) { b in
    V(title: b ? "y" : "n")
}
"""),
    "preview-uikit-groups": ("ios26", """import UIKit

#Preview("Group", arguments: [1, 2]) { n in
    let label = UILabel()
    label.text = "\\(n)"
    return label
}

#Preview(arguments: [UIColor.red]) { color in
    let controller = UIViewController()
    controller.view.backgroundColor = color
    return controller
}
"""),
    # @State (SwiftUIMacros.StateMacro and the macros its expansions use)
    "state-access": ("ios17", """import SwiftUI

struct V: View {
    @State var plain = 0
    @State private var hidden = 0
    @State fileprivate var file = 0
    @State internal var explicit = 0
    var body: some View { Text("\\(plain) \\(hidden) \\(file) \\(explicit)") }
}

public struct P: View {
    @State public var shown = 0
    @State private var hidden = 0
    public var body: some View { Text("\\(shown) \\(hidden)") }
}
"""),
    "state-keywords": ("ios17", """import SwiftUI

struct V: View {
    @State private var `default` = 0
    @State var `class`: String = "a"
    @State private var `for`: Bool
    @State var `is` = [1]
    @State private var `plain` = 0.5
    init() { _for = State(initialValue: true) }
    var body: some View {
        Toggle("\\(`default`) \\(`class`) \\(`is`) \\(`plain`)", isOn: $for)
            .disabled(`for`)
    }
}
"""),
    "state-types": ("ios17", """import SwiftUI

struct V: View {
    @State var untyped = 0
    @State var typed: Int = 0
    @State private var typedPrivate: String = "a"
    @State private var untypedPrivate = "b"
    @State var optional: String?
    @State private var optionalPrivate: Int?
    @State var noValue: Int
    @State private var noValuePrivate: Double
    @State var optionalNil: String? = nil
    @State var array: [String] = []
    @State var dictionary = [String: Int]()
    var body: some View { Text("x") }
}
"""),
    "state-values": ("ios17", """import SwiftUI

final class Model: ObservableObject {}

struct V: View {
    @State var call = Model()
    @State private var member: Color = .red
    @State var closure: () -> Void = {}
    @State var multiline = [
        1,
        2,
    ]
    @State private var computed = Int.random(in: 0...10) * 2
    @State var string = "a \\(1 + 1)"
    @State var tuple = (1, "a")
    @State var date = Date.now
    var body: some View { Text("x") }
}
"""),
    "state-arguments": ("ios17", """import SwiftUI

struct V: View {
    @State(initialValue: 1) var initial: Int
    @State(wrappedValue: 2) var wrapped: Int
    @State() var empty = 3
    var body: some View { Text("x") }
}
"""),
    "state-containers": ("ios17", """import SwiftUI

struct Generic<T: Hashable>: View {
    @State var value: T?
    @State private var items: [T] = []
    var body: some View { Text("x") }
}

enum Namespace {
    struct Nested: View {
        @State var flag = false
        var body: some View { Text("x") }
    }
}

struct Outer {
    struct Inner: View {
        @State private var count = 0
        var body: some View { Text("x") }
    }
}

final class Holder {
    @State var count = 0
}
"""),
    "state-spacing": ("ios17", """import SwiftUI

struct V: View {
    @State   private   var   spaced   =   0
    /// Documentation
    @State var documented = 1 // trailing
    @State
    var split = 2
    @MainActor @State var first = 3
    @State @MainActor var second = 4
    @State private var multiline: [Int] = [
        1,
        2
    ]
\t@State var tabbed: Int = 5
    var body: some View { Text("x") }
}
"""),
    "state-observers": ("ios17", """import SwiftUI

struct V: View {
    @State var observed = 0 {
        didSet { print(observed) }
    }
    @State private var willSet = 0 {
        willSet { print(newValue) }
    }
    var body: some View { Text("x") }
}
"""),
    "state-observers-forms": ("ios17", """import SwiftUI

struct V: View {
    var text = ""
    @State var reveal = true {
        willSet(val) {
            if val {
                print(text)
            }
        }
    }
    @State var both = 0 {
        willSet { print("will", newValue) }
        didSet { print("did", oldValue) }
    }
    @State private var named = 0 {
        didSet(old) {
            print(old)
            print(named)
        }
    }
    @State var optional: Int? {
        didSet { print(1) }
    }
    @State var typed: String = "a" {
        didSet {}
    }
    var body: some View { Text("x") }
}
"""),
    "state-two-spaces": ("ios17", """import SwiftUI

struct V: View {
  @State private var currentIcon =
    Bool.random() ? "a" : "b"
  @State private var items: [String] = [
    "a",
    "b",
  ]
  @State var flag = false {
    didSet {
      print(flag)
    }
  }
  @State private var closure: () -> Void = {
    print(1)
  }
  @State private var value: Int = {
    let x = 1
    return x + 1
  }()
  var body: some View { Text("x") }
}
"""),
    "state-classes": ("ios17", """import SwiftUI

final class Holder {
    @State private var hidden = 0
    @State var typed: Int = 1
    @State private var optional: String?
    @State var noValue: Int
    init() { noValue = 0 }
}

actor Worker {
    @State var count = 0
}

extension Holder {
    struct Nested: View {
        @State var count = 0
        var body: some View { Text("x") }
    }
}
"""),
    "state-local": ("ios17", """import SwiftUI

func make() -> some View {
    struct Local: View {
        @State var count = 0
        @State private var hidden = "a"
        @State var typed: Int = 1
        @State var optional: String?
        @State var noValue: Double
        var body: some View { Text("\\(count) \\(hidden) \\(typed) \\(noValue)") }
    }
    return Local(noValue: 1)
}

func inClosure() {
    let make = { () -> Void in
        struct InClosure: View {
            @State private var flag = false {
                didSet { print(flag) }
            }
            var body: some View { Text("x") }
        }
        _ = InClosure()
    }
    make()
}

struct Outer: View {
    var body: some View {
        struct InBody: View {
            @State var value = 0.5
            var body: some View { Text("\\(value)") }
        }
        return InBody()
    }
}
"""),
    "state-modifiers": ("ios17", """import SwiftUI

public struct V: View {
    @State private(set) var setterPrivate = 0
    @State public private(set) var publicSetter = 1
    @State private(set) public var setterFirst = 2
    @State fileprivate(set) var fileSetter = 3
    @State package var packaged = 4
    @State private(set) var typedSetter: String = "a"
    @State private(set) var optionalSetter: Int?
    public var body: some View { Text("x") }
}

open class Base {
    @State open var opened = 0
    @State public private(set) var shown: Int = 1
}
"""),
    # @Entry (SwiftUIMacros.EntryMacro and the macros its expansions use)
    "entry-environment": ("ios17", """import SwiftUI

final class Router {
    init(coordinator: Int?, isRoot: Bool) {}
}

struct Proxy {}

extension EnvironmentValues {
    @Entry var typed: Bool = false
    @Entry var untyped = 0
    @Entry var optional: String? = nil
    @Entry var optionalNoValue: Int?
    @Entry public var shown: Double = 1.5
    @Entry var router: Router = .init(
        coordinator: nil,
        isRoot: false
    )
    @Entry var binding: Binding<Double> = .constant(1)
    @Entry var action: (() -> Void)? = nil
    @Entry var proxy: Proxy = Proxy()
    @Entry var dictionary: [CoordinateSpace: CGFloat] = [:]
    /// Documented
    @Entry var documented: Int = 1 // trailing
}

private extension EnvironmentValues {
    @Entry var hidden: Bool = true
}
"""),
    "entry-containers": ("ios18", """import SwiftUI

extension FocusedValues {
    @Entry var focusedName: String?
    @Entry var focusedCount: Int = 0
}

extension Transaction {
    @Entry var animated: Bool = false
}

extension ContainerValues {
    @Entry var badge: Int = 0
}
"""),
    "entry-types": ("ios17", """import SwiftUI

extension EnvironmentValues {
    @Entry var t0: Int8 = 0
    @Entry var t1: UInt = 0
    @Entry var t2: Int64 = 0
    @Entry var t3: Float = 0
    @Entry var t4: CGFloat = 0
    @Entry var t5: Double? = nil
    @Entry var t6: String = ""
    @Entry var t7: Character = "a"
    @Entry var t8: Substring = ""
    @Entry var t9: Date = .now
    @Entry var t10: Data = Data()
    @Entry var t11: UUID = UUID()
    @Entry var t12: URL? = nil
    @Entry var t13: Decimal = 0
    @Entry var t14: CGPoint = .zero
    @Entry var t15: CGSize = .zero
    @Entry var t16: CGRect = .zero
    @Entry var t17: [Int] = []
    @Entry var t18: [String] = []
    @Entry var t19: Set<Int> = []
    @Entry var t20: [String: Int] = [:]
    @Entry var t21: (Int, Int) = (0, 0)
    @Entry var t22: Optional<Int> = nil
    @Entry var t23: Swift.Int = 0
    @Entry var t24: Foundation.URL? = nil
    @Entry var t25: Color = .red
    @Entry var t26: Font = .body
    @Entry var t27: Angle = .zero
    @Entry var t28: Edge.Set = .all
    @Entry var t29: LocalizedStringKey = "a"
    @Entry var t30: AnyView = AnyView(EmptyView())
    @Entry var t31: Text = Text("")
    @Entry var t32: Image? = nil
    @Entry var t33: UIColor = .red
    @Entry var t34: TimeInterval = 0
    @Entry var t35: Range<Int> = 0..<1
    @Entry var t36: ClosedRange<Int> = 0...1
    @Entry var t37: Never? = nil
    @Entry var t38: Void = ()
    @Entry var t39: Int = 0
    @Entry var t40: [Int]? = nil
    @Entry var t41: any Error = CancellationError()
    @Entry var t42: (any Error)? = nil
    @Entry var t43: Bool? = nil
    @Entry var t44: [Bool] = []
    @Entry var t45: Int.Type = Int.self
    @Entry var u0 = 0
    @Entry var u1 = ""
    @Entry var u2 = 1.5
    @Entry var u3 = false
    @Entry var u4 = [1]
    @Entry var u5 = CGFloat(0)
    @Entry var u6 = Color.red
    @Entry var u7 = { }
}
"""),
    "entry-values": ("ios18", """import SwiftUI

struct Proxy {
    var child: Proxy? { nil }
    func make() -> Proxy { self }
    static func make() throws -> Proxy { Proxy() }
}

extension EnvironmentValues {
    /// Documented
    @Entry
    var documentedCall: Proxy = Proxy()
    @Entry var unwrapped: Proxy = Proxy().child!
    @Entry var method: Proxy = Proxy().make()
    @Entry var tried: Proxy? = try? Proxy.make()
    @Entry var cast: Proxy = Proxy() as Proxy
    @Entry var array: [Proxy] = [Proxy()]
    @Entry var member: Proxy = .init()
    @Entry var ternary: Int = Bool.random() ? 1 : 2
    @Entry var closureValue: () -> Int = { 1 }
    @Entry var untypedCall = Proxy()
}

extension SwiftUI.EnvironmentValues {
    @Entry var qualified: Int = 0
}

extension FocusedValues {
    @Entry var focusedNil: String? = nil
    @Entry var focusedValue: Int? = 1
}
"""),
    "entry-errors": ("ios18", """import SwiftUI

struct Other {
    @Entry var outside: Int = 0
}

extension EnvironmentValues {
    @Entry var noType = nil
    @Entry var noValue: Int
    @Entry let constant: Int = 0
    @Entry static var shared: Int = 0
}
"""),
    "entry-closures-focused": ("ios18", """import SwiftUI

extension EnvironmentValues {
    @Entry var sendable: @Sendable () -> Void = {}
    @Entry var mainActor: @MainActor () -> Void = {}
    @Entry var optionalSendable: (@Sendable () -> Void)? = nil
    @Entry var function: ((Int) -> Int)? = nil
    @Entry var escapingTuple: (() -> Void, Int)? = nil
}

extension FocusedValues {
    @Entry var untyped = nil
    @Entry var untypedValue = 1
    @Entry var typedNoValue: String
}
"""),
    "entry-two-spaces": ("ios17", """import SwiftUI

extension EnvironmentValues {
  @Entry public var isCompact: Bool = false
  @Entry var referrer: URL = URL(string: "https://www.example.com/")!
  @Entry var insets: EdgeInsets = EdgeInsets(
    top: 1,
    leading: 2,
    bottom: 3,
    trailing: 4
  )
}
"""),
    # Open-source macros Xcode loads from the platform (its own builds) and Linux from swift.org's toolchain
    "observation": ("ios17", """import Observation
import SwiftUI

@Observable
final class Model {
    var name = ""
    var count: Int = 0
    private(set) var items: [String] = []
    @ObservationIgnored var cache: [Int] = []
    let constant = 1
    var computed: Int { count * 2 }
}

@Observable
class Generic<T> {
    var value: T?
    init(value: T?) { self.value = value }
}
"""),
    "foundation-predicate": ("ios18", """import Foundation

struct Item {
    var name: String
    var count: Int
}

let predicate = #Predicate<Item> { item in
    item.count > 1 && item.name.contains("a")
}

let expression = #Expression<Item, Int> { item in
    item.count * 2
}
"""),
    "foundation-predicate-forms": ("ios18", """import Foundation

struct Item {
    var name: String
    var count: Int
    var date: Date
    var tags: [String]
    var parent: String?
}

func make(cutoff: Date, server: String) {
    _ = #Predicate<Item> {
        $0.name == server
          && $0.count >= 2
          && $0.date < cutoff
    }
    _ = #Predicate<Item> { $0.parent?.isEmpty ?? true }
    _ = #Predicate<Item> { item in item.tags.contains { $0.localizedStandardContains("a") } }
    _ = #Predicate<Item> { $0.name.localizedCompare(server) == .orderedAscending }
    _ = #Predicate<Item> { $0.name.caseInsensitiveCompare("x") == .orderedSame }
    _ = #Predicate<Item> { !$0.tags.isEmpty && ($0.count > 1 ? true : false) }
    _ = #Predicate<Item> { $0.name.hasPrefix("a") }
    _ = #Predicate<Item> { $0.name.localizedCaseInsensitiveContains("a") }
    _ = #Expression<Item, Bool> { $0.tags.count > 1 }
    _ = #bundle
}
"""),
    # SwiftData (SwiftDataMacros)
    "swiftdata-model": ("ios17", """import Foundation
import SwiftData

@Model public class Draft {
    public var content: String = ""
    public var creationDate: Date = Date()

    public init(content: String) {
        self.content = content
        creationDate = Date()
    }
}

@Model public class TagGroup: Equatable {
    public var title: String = ""
    public var tags: [String] = []

    public init(title: String, tags: [String]) {
        self.title = title
        self.tags = tags
    }
}

@Model
final class Item {
    var name: String
    var count: Int
    var optional: String?
    private var hidden: Int = 0
    let constant: UUID
    var computed: Int { count * 2 }
    static var shared = 1

    init(name: String, count: Int) {
        self.name = name
        self.count = count
        self.constant = UUID()
    }
}
"""),
    "swiftdata-attributes": ("ios17", """import Foundation
import SwiftData

enum Kind: String, Codable {
    case one, two
}

struct Point: Codable {
    var x: Double
}

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    @Attribute(originalName: "title") var name: String
    @Attribute(.externalStorage) var data: Data?
    @Relationship(deleteRule: .cascade, inverse: \\Note.folder) var notes: [Note] = []
    @Relationship var parent: Folder?
    @Transient var cache: [String: Int] = [:]
    var kind: Kind = Kind.one
    var point: Point = Point(x: 0)

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class Note {
    var text: String = ""
    var folder: Folder?

    init(text: String) {
        self.text = text
    }
}
"""),
    "swiftdata-access": ("ios18", """import Foundation
import SwiftData

@Model public final class PublicFinal {
    public var name: String = ""
    public init() {}
}

@Model public class PublicOpen {
    public var name: String = ""
    public init() {}
}

@Model class Internal {
    var name: String = ""
    init() {}
}

@Model open class Opened {
    public var name: String = ""
    public init() {}
}

@Model fileprivate final class FilePrivate {
    var name: String = ""
    init() {}
}

@Model private final class Private {
    var name: String = ""
    init() {}
}

enum Outer {
    @Model final class Nested {
        var name: String = ""
        init() {}
    }
}
"""),
    "swiftdata-properties": ("ios18", """import Foundation
import SwiftData

struct Tag: Codable, Hashable {
    var value: String
}

final class Transformer: ValueTransformer {}

@Model
final class Item {
    var optionalNil: String? = nil
    var optionalValue: Int? = 3
    var untyped = 0
    var date = Date()
    var observed: Int = 0 {
        didSet { print(observed) }
    }
    private(set) var setter: Int = 1
    public var shown: Double = 1.5
    var tags: Set<Tag> = []
    var dictionary: [String: Tag] = [:]
    var implicitlyUnwrapped: String! = nil
    var closure: (() -> Void)? = nil
    @Attribute(.ephemeral) var ephemeral: Int = 0
    @Attribute(.unique, originalName: "old", hashModifier: "v2") var combined: String = ""
    @Attribute(.transformable(by: Transformer.self)) var transformed: Data? = nil
    @Attribute(.spotlight, .allowsCloudEncryption, .preserveValueOnDeletion) var many: String = ""
    @Attribute() var emptyAttribute: Int = 0
    @Relationship(.unique, deleteRule: .deny, minimumModelCount: 1, maximumModelCount: 3, originalName: "kids", inverse: \\Item.parent, hashModifier: "h") var children: [Item] = []
    @Relationship var parent: Item?
    @Transient private var transient = 1
    /// Documented
    var documented: Int = 0 // trailing

    init() {}
}
"""),
    "swiftdata-constraints": ("ios18", """import Foundation
import SwiftData

@Model
final class Person {
    #Unique<Person>([\\.name], [\\.email, \\.phone])
    #Index<Person>([\\.name], [\\.email, \\.phone])
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    init() {}
}

@ModelActor
actor Worker {
    func count() -> Int { 0 }
}

@ModelActor
public actor PublicWorker {}
"""),
    "swiftdata-inheritance": ("ios26", """import Foundation
import SwiftData

@Model
class Base {
    var name: String = ""
    init(name: String) { self.name = name }
}

@available(iOS 26, *)
@Model
final class Derived: Base {
    var extra: Int = 0
    init(name: String, extra: Int) {
        self.extra = extra
        super.init(name: name)
    }
}
"""),
    "swiftdata-inheritance-clauses": ("ios26", """import Foundation
import SwiftData

protocol Named {}

@Model
class Root {
    var name: String = ""
    init() {}
}

@Model final class UserProtocol: Named {
    var a: Int = 0
    init() {}
}

@Model final class Identified: Identifiable {
    var b: Int = 0
    init() {}
}

@Model final class Several: Hashable, Codable {
    var c: Int = 0
    init() {}
    func encode(to encoder: Encoder) throws {}
    required init(from decoder: Decoder) throws {}
}

@Model final class Plain: Root {
    var d: Int = 0
    override init() { super.init() }
}

@Model final class WithProtocol: Root, Named {
    var e: Int = 0
    override init() { super.init() }
}

@Model final class ObjectSub: NSObject {
    var f: Int = 0
    override init() {}
}
"""),
    "swiftdata-two-spaces": ("ios17", """import Foundation
import SwiftData

@Model public class MetricsNotificationGroup {
  public var groupKey: String = ""
  public var notificationsCount: Int = 0
  public var latestPageNotificationAt: Date = Date()
  /// Documented
  public var documented: Int = 0
  /// First line
  /// Second line
  public var twoLines: Int = 0

  public init(
    groupKey: String,
    notificationsCount: Int
  ) {
    self.groupKey = groupKey
    self.notificationsCount = notificationsCount
    latestPageNotificationAt = Date()
  }
}

extension MetricsNotificationGroup {
  public var isEmpty: Bool { notificationsCount == 0 }
}
"""),
    "swiftdata-errors": ("ios17", """import SwiftData

@Model
struct NotAClass {
    var name: String = ""
}

@Model
enum NotAClassEither {
    case one
}

@Model
final class Bindings {
    var first = 1, second = 2
    init() {}
}
"""),
    "swiftdata-query": ("ios17", """import SwiftData
import SwiftUI

@Model
final class Tag {
    var title: String = ""
    var lastUse: Date = Date()
    init() {}
}

struct V: View {
    @Query var all: [Tag]
    @Query(sort: \\Tag.lastUse, order: .reverse) var recent: [Tag]
    @Query(filter: #Predicate<Tag> { $0.title != "" }, sort: \\Tag.title) private var filtered: [Tag]
    @Query(FetchDescriptor<Tag>()) var described: [Tag]
    var body: some View { Text("\\(all.count) \\(recent.count) \\(filtered.count) \\(described.count)") }
}
"""),
    "swiftdata-forms": ("ios18", """import Foundation
import SwiftData

final class Transformer: ValueTransformer {}

@Model
final class Item {
    @Attribute var bare: Int = 0
    @Relationship() var emptyRelationship: Item?
    @Attribute(.unique , originalName:"x") var spaced: String = ""
    @Attribute(
        .unique,
        originalName: "lines"
    )
    var lines: String = ""
    /// Documented attribute
    @Attribute(.spotlight) var documentedAttribute: String = ""
    // A line comment
    var commented: Int = 0
    /** Block */ var block: Int = 0
    var `default`: Int = 0
    var multiline: [String] = [
        "a",
        "b"
    ]
    var spacedValue = [ 1,2 ]
    var closureValue: Int = { 1 }()
    var both: Int = 0 {
        willSet { print(newValue) }
        didSet { print(oldValue) }
    }
    @Attribute(.transformable(by: "Name")) var named: Data? = nil
    @Attribute(.unique, .transformable(by: Transformer.self)) var second: Data? = nil
    var noValueOptional: Int?
    /// First line
    /// Second line
    var twoLines: Int = 0
        /// Deeper
        var deeper: Int = 0

    init() {}
}

@Model
final class Empty {
    init() {}
}

enum Outer {}

extension Outer {
    @Model final class InExtension {
        var a: Int = 0
        init() {}
    }
}

@Model
final class Constraints {
    #Index<Constraints>([\\.b], [\\.a, \\.b])
    #Unique<Constraints>([\\.a])
    var a: Int = 0
    var b: Int = 0
    init() {}
}

@Model
final class UniqueOnly {
    #Unique<UniqueOnly>([\\.a])
    var a: Int = 0
    init() {}
}

@Model
final class IndexOnly {
    #Index<IndexOnly>([\\.a])
    var a: Int = 0
    init() {}
}
"""),
    "swiftdata-property-errors": ("ios18", """import Foundation
import SwiftData

@Model
final class Item {
    lazy var lazyValue: Int = 0
    weak var weakParent: Item?
    @Transient var transientNoDefault: Int
    var (x, y) = (1, 2)
    @ObservationIgnored var ignored: Int = 0
    var a = 1, b: Int = 2
    init() {}
}

@Model
final class Twice {
    #Unique<Twice>([\\.a])
    #Unique<Twice>([\\.b])
    #Index<Twice>([\\.a])
    #Index<Twice>([\\.b])
    var a: Int = 0
    var b: Int = 0
    init() {}
}

@Model
final class NoInit {
    var name: String = ""
}

@Model
final class TransientOptionals {
    @Transient var unwrapped: Int!
    @Transient var spelled: Optional<Int>
    @Transient var optional: Int?
    init() {}
}

@Model
enum WithInit {
    case a
    var computed: Int { 0 }
    init() { self = .a }
}

@Model
actor AnActor {
    var a: Int = 0
    init() {}
}

@ModelActor
final class NotAnActor {}

@ModelActor
struct NotAnActorEither {}
"""),
    "swiftdata-subclasses": ("ios26", """import Foundation
import SwiftData

@Model public class Root {
    public var name: String = ""
    public init() {}
}

@available(*, deprecated)
@Model final class Deprecated: Root {
    var a: Int = 0
    override init() { super.init() }
}

@available(iOS 26, macOS 26, *)
@Model final class Several: Root {
    var b: Int = 0
    override init() { super.init() }
}

@available(iOS, introduced: 26)
@Model final class Long: Root {
    var c: Int = 0
    override init() { super.init() }
}

@available(iOS 26, *)
@Model public final class PublicSub: Root {
    public var d: Int = 0
    public override init() { super.init() }
}

@available(iOS 26, *)
@Model class Middle: Root {
    var e: Int = 0
    override init() { super.init() }
}

@available(iOS 26, *)
@Model final class Leaf: Middle {
    var f: Int = 0
    override init() { super.init() }
}

@available(iOS 26, *)
@Model final class NoProperties: Root {
    override init() { super.init() }
}

@Model final class ExplicitObservable: Observable {
    var g: Int = 0
    init() {}
}

@Model final class ExplicitModel: PersistentModel {
    var h: Int = 0
    init() {}
}
"""),
    "swiftdata-query-forms": ("ios27", """import SwiftData
import SwiftUI

@Model
final class Tag {
    var title: String = ""
    var section: String = ""
    init() {}
}

struct V: View {
    @Query(sort:\\Tag.title) var spaced: [Tag]
    @Query(
        sort: \\Tag.title,
        order: .reverse
    ) var lines: [Tag]
    @Query(sort: \\Tag.title, sectionBy: \\Tag.section) var sections: SectionedResults<Tag, String>
    @Query(filter: #Predicate<Tag> { tag in
        tag.title.isEmpty
    }) var multilinePredicate: [Tag]
    @Query(animation: .default) var animated: [Tag]
    @Query public var publicQuery: [Tag]
    @Query private(set) var privateSet: [Tag]
    @Query var array: Array<Tag>
    /// Documented
    @Query var documented: [Tag]
    var body: some View { Text("") }
}

struct Errors: View {
    @Query let constant: [Tag]
    @Query var untyped = [Tag]()
    @Query static var shared: [Tag]
    var body: some View { Text("") }
}
"""),
    "foundationmodels-generable": ("ios26", """import FoundationModels

@Generable
struct Tags {
    @Guide(description: "The value of the hashtags, must be camelCased and prefixed with a # symbol.", .count(5))
    let values: [String]
}

@Generable(description: "A person")
struct Person {
    var name: String
    @Guide(description: "Age in years", .range(0...120))
    var age: Int
    var nickname: String?
    var scores: [Double]
    var friend: Tags
}

@Generable
enum Mood {
    case happy
    case sad
}

@Generable
public struct Shared {
    public var title: String
}
"""),
    "foundationmodels-forms": ("ios27", """import FoundationModels

@Generable(name: "Recipe", description: "A recipe")
struct Dish {
    /// The dish's name.
    var title: String
    let servings: Int
    @Guide(description: "Steps")
    var steps: [String]
    @Guide(.minimum(1), .maximum(5))
    var rating: Int
    @Guide(.anyOf(["a", "b"]))
    var letter: String
    @Guide(description: "Code", #/[A-Z]{3}/#)
    var code: String
    var  spaced  :  Bool
    var flag: Bool = false
    static var shared: Int = 0
    var computed: Int { 1 }
    var nested: [[Int]]
    var optionalList: [String]?
}

@Generable(representNilExplicitlyInGeneratedContent: true)
struct Explicit {
    var maybe: Int?
}

@Generable
fileprivate struct Hidden {
    var a: Int
}

@Generable
internal struct Internal {
    internal var a: Int
    private var b: Int
}

@available(iOS 26.0, *)
@Generable
struct Available {
    var a: Int
}

enum Outer {
    @Generable
    struct Inner {
        var a: Int
    }
}
"""),
    "foundationmodels-enums": ("ios26", """import FoundationModels

@Generable
enum Plain {
    case a, b
    case c
}

@Generable(description: "Raw")
enum Raw: String {
    case first = "one"
    case second
}

@Generable
enum Payload {
    case number(Int)
    case pair(a: Int, b: String)
    case none
}

@Generable
public enum Open {
    case x
}
"""),
    "foundationmodels-errors": ("ios26", """import FoundationModels

@Generable
class Box {
    var a: Int = 0
}

@Generable
actor Worker {
    var a: Int = 0
}

@Generable
struct Untyped {
    var a = 1
}

@Generable
protocol Shape {}

struct Lone {
    @Guide(description: "alone")
    var a: Int
}
"""),
    "tipkit-parameter": ("ios17", """import SwiftUI
import TipKit

struct PlainTip: Tip {
    @Parameter
    static var isCompactWidth: Bool = false

    @Parameter
    static var willDisplayModal: Bool? = nil

    @Parameter(.transient)
    static var enableTip: Bool = false

    @Parameter
    static var count: Int = 0

    @Parameter
    public static var name: String = "a"

    @Parameter(.transient)
    private static var hidden: Double = 1.5

    @Parameter
    static var  spaced  :  [String]  =  []

    var title: Text { Text("Plain") }
}

public struct PublicTip: Tip {
    @Parameter
    public static var shown: Bool = true

    public var title: Text { Text("Public") }
}

enum Tips2 {
    struct NestedTip: Tip {
        @Parameter static var level: Int = 1
        var title: Text { Text("Nested") }
    }
}
"""),
    "tipkit-rule": ("ios17", """import SwiftUI
import TipKit

struct RuleTip: Tip {
    @Parameter
    static var isCompactWidth: Bool = false

    @Parameter
    static var willDisplayModal: Bool? = nil

    @Parameter
    static var count: Int = 0

    static let opened = Tips.Event(id: "opened")

    var title: Text { Text("Rule") }

    var rules: [Rule] {
        [
            #Rule(Self.$isCompactWidth) { $0 == true },
            #Rule(Self.$willDisplayModal) { $0 == false },
            #Rule(Self.$count) { $0 >= 2 },
            #Rule(Self.$count) { value in value > 1 && value < 10 },
            #Rule(Self.opened) { $0.donations.count >= 3 },
            #Rule(Self.$isCompactWidth, Self.$count) { compact, count in
                compact || count > 3
            },
            #Rule(RuleTip.$count) {
                $0 != 5
            },
        ]
    }
}
"""),
    "tipkit-rule-inputs": ("ios26", """import SwiftUI
import TipKit

struct InputsTip: Tip {
    @Parameter static var a: Bool = false
    @Parameter static var b: Int = 0
    @Parameter static var c: String = ""
    static let opened = Tips.Event(id: "opened")

    var title: Text { Text("Inputs") }

    var rules: [Rule] {
        [
            #Rule(Self.$a, Self.$b) { a, b in a && b > 1 },
            #Rule(Self.$a, Self.$b, Self.$c) { a, b, c in
                a || b == 2 || c.isEmpty
            },
            #Rule(Self.$a, Self.$b) { a, b in (a && b > 1) || !a },
            #Rule(Self.$b, Self.opened) { b, opened in b > 1 && opened.donations.count > 2 },
            #Rule(Self.$b, Self.$b) { x, y in x > y },
            #Rule(Self.$a, Self.$b) { $0 && $1 > 3 },
            #Rule(Self.$a) { !$0 },
            #Rule(Self.$c) { $0 == "x" },
        ]
    }
}
"""),
    "tipkit-rule-errors": ("ios26", """import SwiftUI
import TipKit

struct RuleErrorTip: Tip {
    @Parameter static var a: Bool = false
    @Parameter static var b: Int = 0
    @Parameter static var c: String = ""

    var title: Text { Text("Rule errors") }

    var function: Rule { #Rule(Self.$c) { $0.uppercased() == "X" } }
    var statements: Rule {
        #Rule(Self.$a) { value in
            let x = value
            return x
        }
    }
    var global: Rule { #Rule(Self.$b) { abs($0) > 1 } }
    var shared: Rule { #Rule(Self.$b, Self.$b) { x, y in x > y } }
    var mixed: Rule { #Rule(Self.$a, Self.$b) { a, b in (a && b > 1) || !a } }
    var notClosure: Rule { #Rule(Self.$a, { $0 }) }
    var ternary: Rule { #Rule(Self.$b) { $0 > 1 ? true : false } }
    var optional: Rule { #Rule(Self.$c) { $0.first == "x" } }
    var bare: Rule { #Rule(Self.$a) { $0 } }
    var spaced: Rule { #Rule(Self.$a, Self.$b) { a, b in   a || b > 1 || !a } }
    var multiline: Rule {
        #Rule(Self.$a, Self.$b) { a, b in
            a && b > 1 && !a
        }
    }
}
"""),
    "tipkit-rule-forms": ("ios26", """import SwiftUI
import TipKit

struct FormsTip: Tip {
    @Parameter static var a: Bool = false
    @Parameter static var b: Int = 0
    @Parameter static var c: String = ""
    struct Viewed: Codable, Sendable { var count: Int }
    static let opened = Tips.Event(id: "opened")
    static let viewed = Tips.Event<Viewed>(id: "viewed")

    var title: Text { Text("Forms") }

    var localized: Rule { #Rule(Self.$c) { $0.localizedStandardContains("x") } }
    var contains: Rule { #Rule(Self.$c) { $0.contains("x") } }
    var nested: Rule { #Rule(Self.$a, Self.$b, Self.$c) { a, b, c in (a && b > 1) || c.isEmpty } }
    var mixed: Rule { #Rule(Self.$a, Self.$b, Self.$c) { a, b, c in a && b > 1 || c.isEmpty } }
    var single: Rule { #Rule(Self.$a, Self.$b) { a, b in a } }
    var shorthand: Rule { #Rule(Self.$b, Self.$c) { $0 > 1 || $1 == "y" } }
    var week: Rule { #Rule(Self.opened) { $0.donations.donatedWithin(.week).count >= 3 } }
    var filtered: Rule { #Rule(Self.viewed) { $0.donations.filter { $0.count > 5 }.count >= 3 } }
    var days: Rule { #Rule(Self.opened) { $0.donations.donatedWithin(.days(3)).count > 0 } }
    var arithmetic: Rule { #Rule(Self.$b) { $0 + 1 > 2 } }
    var optionalParameter: Rule { #Rule(Self.$c) { $0 != "" } }
    static let limit = #Predicate<Int> { $0 > 1 }
    var evaluated: Rule { #Rule(Self.$b) { FormsTip.limit.evaluate($0) } }
}
"""),
    "tipkit-errors": ("ios17", """import SwiftUI
import TipKit

struct ErrorTip: Tip {
    @Parameter
    var instance: Bool = false

    @Parameter
    static var untyped = false

    @Parameter
    static var noValue: Bool

    @Parameter
    static let constant: Bool = false

    @Parameter
    static var computed: Bool { true }

    var title: Text { Text("Errors") }
}
"""),
    "appintents-calendar": ("ios27", """import AppIntents
import Foundation

@AppEntity(schema: .calendar.attendee)
struct Attendee {
    static let defaultQuery = AttendeeQuery()
    var id: String
    var person: IntentPerson
    var status: AttendeeStatus?
    var type: AttendeeType?
    var isAttendanceOptional: Bool
    var displayRepresentation: DisplayRepresentation { "x" }
}

struct AttendeeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Attendee] { [] }
}

@AppEntity(schema: .calendar.event)
struct Event {
    static let defaultQuery = EventQuery()
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendar: CalendarItem
    var location: Place?
    var virtualLocation: URL?
    var attendees: [Attendee]
    var organizers: [IntentPerson]
    var recurrence: Calendar.RecurrenceRule?
    var alarms: [Alarm]
    var status: EventStatus?
    var travelTime: Duration?
    var note: String?
    var uid: String?
    var recurrenceId: String?
    var displayRepresentation: DisplayRepresentation { "x" }
}

struct EventQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Event] { [] }
}

@AppEntity(schema: .calendar.calendar)
struct CalendarItem {
    static let defaultQuery = CalendarItemQuery()
    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { "x" }
}

struct CalendarItemQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CalendarItem] { [] }
}

@AppEnum(schema: .calendar.attendeeStatus)
enum AttendeeStatus: String {
    case accepted
    case declined
    static let caseDisplayRepresentations: [AttendeeStatus: DisplayRepresentation] = [.accepted: "accepted", .declined: "declined"]
}

@AppEnum(schema: .calendar.attendeeType)
enum AttendeeType: String {
    case person
    case room
    static let caseDisplayRepresentations: [AttendeeType: DisplayRepresentation] = [.person: "person", .room: "room"]
}

@AppEnum(schema: .calendar.eventStatus)
enum EventStatus: String {
    case confirmed
    case canceled
    static let caseDisplayRepresentations: [EventStatus: DisplayRepresentation] = [.confirmed: "confirmed", .canceled: "canceled"]
}

@AppEnum(schema: .calendar.eventSpan)
enum EventSpan: String {
    case this
    case future
    static let caseDisplayRepresentations: [EventSpan: DisplayRepresentation] = [.this: "this", .future: "future"]
}

@AppIntent(schema: .calendar.createEvent)
struct CreateEvent {
    var title: String
    var startDate: Date
    var endDate: Date?
    var location: Place?
    var calendar: CalendarItem
    var isAllDay: Bool
    var recurrence: Calendar.RecurrenceRule?
    var attendees: [Attendee]
    var note: AttributedString?
    func perform() async throws -> some IntentResult { .result() }
}

@AppIntent(schema: .calendar.deleteEvent)
struct DeleteEvent {
    var entity: Event
    var span: EventSpan?
    func perform() async throws -> some IntentResult { .result() }
}

@AppIntent(schema: .calendar.updateEvent)
struct UpdateEvent {
    var event: Event
    var title: String?
    var attendees: [Attendee]?
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool?
    var calendar: CalendarItem?
    var recurrence: Calendar.RecurrenceRule?
    var note: String?
    var location: Place?
    var span: EventSpan?
    func perform() async throws -> some IntentResult { .result() }
}

@UnionValue
enum Place {
    case address(String)
    case url(URL)
}

@UnionValue
enum Alarm {
    case duration(Duration)
    case date(Date)
}
"""),
    "appintents-reminders": ("ios27", """import AppIntents
import Foundation
import GeoToolbox

@AppEntity(schema: .reminders.list)
struct ReminderList {
    static let defaultQuery = ReminderListQuery()
    var id: String
    var name: String
    var type: ListType
    var entityId: String
    var displayRepresentation: DisplayRepresentation { "x" }
}

struct ReminderListQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ReminderList] { [] }
}

@AppEntity(schema: .reminders.locationTrigger)
struct Trigger {
    static let defaultQuery = TriggerQuery()
    var id: String
    var place: PlaceDescriptor
    var event: TriggerEvent
    var displayRepresentation: DisplayRepresentation { "x" }
}

struct TriggerQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Trigger] { [] }
}

@AppEntity(schema: .reminders.reminder)
struct Reminder {
    static let defaultQuery = ReminderQuery()
    var id: String
    var title: String
    var list: ReminderList
    var dueDate: DateComponents?
    var completionDate: Date?
    var creationDate: Date?
    var isCompleted: Bool
    var isFlagged: Bool?
    var recurrence: Calendar.RecurrenceRule?
    var locationTrigger: Trigger?
    var note: String?
    var tags: Set<String>
    var urls: [URL]
    var uid: String
    var displayRepresentation: DisplayRepresentation { "x" }
}

struct ReminderQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Reminder] { [] }
}

@AppEntity(schema: .reminders.section)
struct Section {
    static let defaultQuery = SectionQuery()
    var id: String
    var name: String
    var list: ReminderList
    var displayRepresentation: DisplayRepresentation { "x" }
}

struct SectionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Section] { [] }
}

@AppEnum(schema: .reminders.listType)
enum ListType: String {
    case standard
    case grocery
    static let caseDisplayRepresentations: [ListType: DisplayRepresentation] = [.standard: "standard", .grocery: "grocery"]
}

@AppEnum(schema: .reminders.locationTriggerEvent)
enum TriggerEvent: String {
    case arriving
    case leaving
    static let caseDisplayRepresentations: [TriggerEvent: DisplayRepresentation] = [.arriving: "arriving", .leaving: "leaving"]
}

@AppIntent(schema: .reminders.createReminder)
struct CreateReminder {
    var title: String
    var list: ReminderList?
    var note: AttributedString?
    var isFlagged: Bool?
    var images: [IntentFile]
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var locationTrigger: Trigger?
    var section: Section?
    func perform() async throws -> some IntentResult { .result() }
}

@AppIntent(schema: .reminders.deleteReminders)
struct DeleteReminders {
    var entities: [Reminder]
    func perform() async throws -> some IntentResult { .result() }
}

@AppIntent(schema: .reminders.updateReminder)
struct UpdateReminder {
    var target: Reminder
    var title: String?
    var note: AttributedString?
    var tags: Set<String>?
    var urls: [URL]?
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var isCompleted: Bool?
    var isFlagged: Bool?
    var list: ReminderList?
    var locationTrigger: Trigger?
    func perform() async throws -> some IntentResult { .result() }
}
"""),
    "appintents-forms": ("ios27", """import AppIntents
import Foundation

/// A calendar.
///
/// With a second paragraph.
@available(iOS 27.0, *)
@AppEntity(schema: .calendar.calendar)
public struct PublicCalendar: IndexedEntity {
    public static let defaultQuery = PublicCalendarQuery()
    public var id: String
    @Property(title: "Name")
    public var title: String
    let bogus: Int
    static var shared: Int = 0
    public var displayRepresentation: DisplayRepresentation { "x" }
}

public struct PublicCalendarQuery: EntityQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [PublicCalendar] { [] }
}

@AppIntent(schema: .reminders.createReminder)
struct Forms: AppIntent {
    let title: String
    @Parameter(title: "List")
    var list: String?
    var images: [URL]
    var photos: [IntentFile]
    var  tags  :  Set<String>
    static var title2: LocalizedStringResource = "x"
    var computed: Int { 1 }
    func perform() async throws -> some IntentResult { .result() }
}

@available(iOS 27.0, *)
@AppEnum(schema: .calendar.eventSpan)
public enum Span: String, AppEnum {
    case this
    public static let caseDisplayRepresentations: [Span: DisplayRepresentation] = [.this: "this"]
}

/// A union.
@available(iOS 27.0, *)
@UnionValue
public enum Choice {
    case text(String)
    case number(Int)
    case pair(Int, String)
    case flag
}

/// A public union.
@UnionValue
public enum PublicChoice {
    case text(String)
    case when(Date)
}

/// A public intent.
@AppIntent(schema: .calendar.deleteEvent)
public struct PublicDelete {
    public var entity: String
    public init() { entity = "" }
    public func perform() async throws -> some IntentResult { .result() }
}

/// A documented entity.
@AppEntity(schema: .reminders.section)
struct DocumentedSection {
    static let defaultQuery = DocumentedSectionQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { "x" }
}

struct DocumentedSectionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DocumentedSection] { [] }
}
"""),
    "preview-widget": ("ios17", """import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    var date: Date
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {}
}

struct W: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "w", provider: Provider()) { entry in
            Text(entry.date, style: .time)
        }
    }
}

#Preview(as: .systemSmall) {
    W()
} timeline: {
    Entry(date: .now)
    Entry(date: .distantFuture)
}

#Preview("Medium", as: .systemMedium) {
    W()
} timeline: {
    Entry(date: .now)
}

@available(iOS 17, *)
#Preview(as: .systemSmall, widget: {
    W()
}, timeline: {
    Entry(date: .now)
})

#Preview("Provider", as: .systemLarge, widget: { W() }, timelineProvider: { Provider() })
"""),
}


def kinds_used(text):
    found = {kind for kind, pattern in KINDS.items() if re.search(pattern, text)}
    # TipKit's @Parameter is a macro; AppIntents' is a property wrapper.
    if re.search(r"^import TipKit", text, re.M) and re.search(r"@Parameter\b", text):
        found.add("tipkit")
    return found


def survey(root):
    for app in sorted(os.listdir(root)):
        files = collections.Counter()
        kinds = collections.Counter()
        for directory, _, names in os.walk(os.path.join(root, app)):
            if any(skipped in directory + "/" for skipped in SKIPPED):
                continue
            for name in names:
                if not name.endswith(".swift"):
                    continue
                found = kinds_used(open(os.path.join(directory, name), errors="replace").read())
                if not found:
                    continue
                files["previews and state only" if found <= {"previews", "state"} else "other"] += 1
                kinds.update(found)
        if files:
            print(f"{app:26} previews and state only {files['previews and state only']:4}  other {files['other']:3}  "
                  + " ".join(f"{kind}={count}" for kind, count in sorted(kinds.items())))


def sdk_path():
    return subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()


def developer_dir():
    return subprocess.run(["xcode-select", "-p"], capture_output=True, text=True, check=True).stdout.strip() \
        if "DEVELOPER_DIR" not in os.environ else os.environ["DEVELOPER_DIR"]


def preview(out):
    out.mkdir(parents=True, exist_ok=True)
    (out / "V.swift").write_text(PREVIEW_SOURCE)
    sdk = sdk_path()
    for label, flags in [("release", ["-O"]), ("debug", ["-Onone", "-DDEBUG"])]:
        proc = subprocess.run(["xcrun", "swiftc", "-target", "arm64-apple-ios17.0", "-sdk", sdk, *flags, "-c", "V.swift",
                               "-module-name", "Previewed", "-o", f"{label}.o", "-Xfrontend", "-dump-macro-expansions"],
                              cwd=out, capture_output=True, text=True)
        (out / f"{label}-expansions.txt").write_text(proc.stdout + proc.stderr)
        symbols = subprocess.run(["xcrun", "nm", "-m", f"{label}.o"], cwd=out, capture_output=True, text=True).stdout
        print(f"{label}: exit {proc.returncode}, {symbols.count('PreviewRegistry')} PreviewRegistry symbols, "
              f"'#if DEBUG' in expansions: {'#if DEBUG' in proc.stdout + proc.stderr}")
    same = (out / "release-expansions.txt").read_text() == (out / "debug-expansions.txt").read_text()
    print(f"expansions identical in Release and Debug: {same}")


def platform_usr(root):
    return root / "iPhoneOS.platform" / "Developer" / "usr"


def compile_case(out, name, platform, label, compiler=("xcrun", "swiftc"), sdk=None):
    """Compiles a case with Xcode's compiler, `platform` searched for plugins before Xcode's own
    (the driver's PLATFORM_DIR); the plugin server runs unsandboxed so that it may log."""
    target, source = CASES[name]
    directory = out / name
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{name}.swift").write_text(source)
    environment = dict(os.environ, PLATFORM_DIR=str(platform / "iPhoneOS.platform")) if platform else None
    sandbox = ["-Xfrontend", "-disable-sandbox"] if platform else []
    proc = subprocess.run([*compiler, "-target", TARGETS[target], "-sdk", sdk or sdk_path(), "-c", f"{name}.swift",
                           "-module-name", "M", "-o", f"{label}.o", "-Xfrontend", "-dump-macro-expansions", *sandbox],
                          cwd=directory, capture_output=True, text=True, env=environment)
    (directory / f"{label}.txt").write_text(proc.stdout + proc.stderr)
    return proc.returncode


def record(out, names):
    xcode_usr = Path(developer_dir()) / "Platforms" / "iPhoneOS.platform" / "Developer" / "usr"
    proxy = out / ".record"
    usr = platform_usr(proxy)
    shutil.rmtree(proxy, ignore_errors=True)
    (usr / "bin").mkdir(parents=True)
    (usr / "lib" / "swift" / "host" / "plugins").mkdir(parents=True)
    for library in (xcode_usr / "lib" / "swift" / "host" / "plugins").glob("*.dylib"):
        (usr / "lib" / "swift" / "host" / "plugins" / library.name).symlink_to(library)
    # The compiler starts the server with an empty environment, so the log directory is read from a file.
    server = usr / "bin" / "swift-plugin-server"
    server.write_text(f"#!/bin/sh\nexec /usr/bin/python3 {Path(__file__).resolve()} tee {xcode_usr}/bin/swift-plugin-server "
                      f"\"$(cat {proxy}/log-dir)\"\n")
    server.chmod(0o755)
    for name in names:
        log = out / name / "protocol"
        shutil.rmtree(log, ignore_errors=True)
        log.mkdir(parents=True)
        (proxy / "log-dir").write_text(str(log))
        print(f"{name}: exit {compile_case(out, name, proxy, 'xcode')}")


def tee(server, log_dir):
    """Runs the plugin server, logging each framed message (8-byte little-endian size, then JSON)."""
    log = open(os.path.join(log_dir, f"{os.getpid()}.jsonl"), "a")
    lock = threading.Lock()
    child = subprocess.Popen([server], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    def pump(source, destination, direction):
        while len(header := source.read(8)) == 8:
            payload = source.read(struct.unpack("<Q", header)[0])
            with lock:
                log.write(json.dumps({"direction": direction, "message": json.loads(payload)}) + "\n")
                log.flush()
            destination.write(header + payload)
            destination.flush()
        destination.close()

    answers = threading.Thread(target=pump, args=(child.stdout, sys.stdout.buffer, "plugin"), daemon=True)
    answers.start()
    pump(sys.stdin.buffer, child.stdin, "compiler")
    child.wait()
    answers.join(timeout=5)


def build_plugins(destination):
    """Builds each plugin module of Sources/NomacMacros/Plugins as `nomac toolchain install` does,
    against the selected Xcode's host swift-syntax, served by that toolchain's plugin server."""
    toolchain = Path(developer_dir()) / "Toolchains" / "XcodeDefault.xctoolchain" / "usr"
    host = toolchain / "lib" / "swift" / "host"
    usr = platform_usr(destination)
    (usr / "bin").mkdir(parents=True, exist_ok=True)
    (usr / "lib" / "swift" / "host" / "plugins").mkdir(parents=True, exist_ok=True)
    server = usr / "bin" / "swift-plugin-server"
    server.write_text(f"#!/bin/sh\nexec {toolchain}/bin/swift-plugin-server \"$@\"\n")
    server.chmod(0o755)
    for module in sorted(path.name for path in PLUGINS.iterdir() if path.is_dir()):
        sources = sorted(str(path) for path in (PLUGINS / module).glob("*.swift"))
        libraries = [f"-l{library}" for library in ("SwiftBasicFormat", "SwiftDiagnostics", "SwiftIfConfig", "SwiftOperators", "SwiftParser",
                                                    "SwiftSyntax", "SwiftSyntaxBuilder", "SwiftSyntaxMacros")]
        # As MacroPlugins.compilationConditions: swift-foundation's macros as Apple builds them.
        conditions = ["-DFOUNDATION_FRAMEWORK"] if module == "FoundationMacros" else []
        subprocess.run(["xcrun", "swiftc", "-emit-library", "-module-name", module, "-parse-as-library", *conditions, "-I", str(host),
                        "-L", str(host), *libraries, "-Xlinker", "-rpath", "-Xlinker", str(host), *sources,
                        "-o", str(usr / "lib" / "swift" / "host" / "plugins" / f"lib{module}.dylib")], check=True)


def compare(out, names):
    platform = out / ".nomac"
    shutil.rmtree(platform, ignore_errors=True)
    build_plugins(platform)
    identical = 0
    for name in names:
        compile_case(out, name, platform, "nomac")
        verdict = same_output((out / name / "xcode.txt").read_text(), (out / name / "nomac.txt").read_text())
        identical += verdict != "different"
        print(f"{name}: {verdict}")
    print(f"{identical} of {len(names)} cases identical")


def sdk_modules(sdk):
    modules = {path.name[: -len(".framework")] for path in (Path(sdk) / "System" / "Library" / "Frameworks").glob("*.framework")}
    modules |= {path.name[: -len(".swiftmodule")] for path in (Path(sdk) / "usr" / "lib" / "swift").glob("*.swiftmodule")}
    return modules | {"Swift", "Darwin", "Foundation", "Dispatch", "ObjectiveC", "os"}


def expansions(dump):
    """The expansion buffers of a -dump-macro-expansions output, by name; a file compiled alone has
    errors (its app's other files are missing), which the compiler may report in either order."""
    return sorted(re.findall(r"^(@__swiftmacro_\S+)\n-{30}\n(.*?)\n?-{30}$", dump, re.M | re.S))


def corpus(root, out, kinds):
    sdk = sdk_path()
    available = sdk_modules(sdk)
    platform = out / ".nomac"
    shutil.rmtree(platform, ignore_errors=True)
    build_plugins(platform)
    cases = []
    for app in sorted(os.listdir(root)):
        for directory, _, names in os.walk(os.path.join(root, app)):
            if any(skipped in directory + "/" for skipped in SKIPPED):
                continue
            for name in sorted(names):
                if not name.endswith(".swift"):
                    continue
                text = open(os.path.join(directory, name), errors="replace").read()
                if not kinds_used(text) & set(kinds):
                    continue
                # Modules of the app or its packages are not there; both compiles see the same input.
                text = re.sub(r"^(@\w+ )*import (class |struct |enum |protocol |func |var )?(\w+).*$",
                              lambda m: m.group(0) if m.group(3) in available else "", text, flags=re.M)
                case = out / "corpus" / app / os.path.relpath(directory, os.path.join(root, app)) / name
                case.parent.mkdir(parents=True, exist_ok=True)
                case.write_text(text)
                cases.append(case)

    def compare_file(case):
        outputs = []
        for label, environment in (("xcode", None), ("nomac", dict(os.environ, PLATFORM_DIR=str(platform / "iPhoneOS.platform")))):
            proc = subprocess.run(["xcrun", "swiftc", "-typecheck", "-target", "arm64-apple-ios26.0", "-sdk", sdk, case.name,
                                   "-module-name", "M", "-Xfrontend", "-dump-macro-expansions", "-Xfrontend", "-disable-sandbox"],
                                  cwd=case.parent, capture_output=True, text=True, env=environment)
            (case.parent / f"{case.name}.{label}.txt").write_text(proc.stdout + proc.stderr)
            outputs.append(expansions(proc.stdout + proc.stderr))
        return outputs[0] == outputs[1]

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(compare_file, cases))
    for case, same in zip(cases, results):
        if not same:
            print(f"different: {case.relative_to(out)}")
    print(f"{sum(results)} of {len(cases)} corpus files identical")


def linux(out, developer, names):
    swiftc = developer / "Toolchains" / "XcodeDefault.xctoolchain" / "usr" / "bin" / "swiftc"
    sdk = developer / "Platforms" / "iPhoneOS.platform" / "Developer" / "SDKs" / "iPhoneOS.sdk"
    # Xcode 27.0's compiler loads cross-import overlays (`_SwiftData_SwiftUI`, which declares
    # `@Query`) without being asked; swift.org's on Linux needs the flag (B-154).
    compiler = (str(swiftc), "-Xfrontend", "-enable-cross-import-overlays")
    identical = 0
    for name in names:
        compile_case(out, name, None, "linux", compiler=compiler, sdk=str(sdk))
        verdict = same_output((out / name / "xcode.txt").read_text(), (out / name / "linux.txt").read_text())
        identical += verdict != "different"
        print(f"{name}: {verdict}")
    print(f"{identical} of {len(names)} cases identical")


def same_output(xcode, other):
    """Whether two compiles printed the same: the same text, or the same expansion buffers and
    lines with the compiler's own errors in another order (it reports them as type checking
    reaches each declaration, in no fixed order)."""
    if xcode == other:
        return "identical"
    if expansions(xcode) == expansions(other) and sorted(xcode.splitlines()) == sorted(other.splitlines()):
        return "identical, the compiler's errors in another order"
    if LOCAL_STATE.search(other) and same_output(xcode, LOCAL_STATE.sub("", other)) != "different":
        return "identical but for the @State of local types, which Xcode's compiler does not expand (docs/formats/macros.md, local types)"
    return "different"


# The buffers of @State's macros applied to a property of a local type (`_$l` in the name), which
# swift.org's compiler expands and Xcode 27.0's does not (it applies the State property wrapper).
LOCAL_STATE = re.compile(r"^@__swiftmacro_\S*_\$l\d+(?:State|_PropertyWrapperProjectedValue|_StateProjectedValue|_StatePropertyWrapperStorage|_StateInitialStoredValue)f\S*\n-{30}\n.*?\n?-{30}\n", re.M | re.S)


def canonical(answer):
    """The text NomacMacrosTests digests for a plugin's answer: the expansion, then each diagnostic's
    fields (MacroExpansionTests.canonical computes the same)."""
    lines = ["source:" + answer["expandedSource"] if answer.get("expandedSource") is not None else "nil"]
    for diagnostic in answer.get("diagnostics", []):
        span = lambda r: f"{r['fileName']}@{r['startOffset']}-{r['endOffset']}"
        lines.append("|".join([
            diagnostic["severity"], diagnostic["message"],
            f"{diagnostic['position']['fileName']}@{diagnostic['position']['offset']}",
            ",".join(span(h) for h in diagnostic.get("highlights", [])),
            ";".join(f"{n['position']['fileName']}@{n['position']['offset']}:{n['message']}" for n in diagnostic.get("notes", [])),
            ";".join(f["message"] + "=" + ",".join(f"{span(c['range'])}:{c['newText']}" for c in f["changes"]) for f in diagnostic.get("fixIts", [])),
        ]))
    return "\n".join(lines)


# The request fields that address a syntax node in a file or an earlier expansion.
NODE_KEYS = ("syntax", "attributeSyntax", "declSyntax", "parentDeclSyntax")


def swift_string(text):
    escaped = text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    return "\"" + escaped + "\""


def facts(out, modules, names):
    """Prints NomacMacrosTests' observed facts as Swift: each case's self-written source, where the
    compiler addressed each macro use in it (or in an earlier expansion), and the SHA-256 digest of
    Xcode's answer. No request or answer is copied into the tree."""
    import hashlib
    print("// Generated by `.github/scripts/macro_experiments.py facts`: the experiments' self-written sources,")
    print("// where Xcode 27.0's compiler addressed each use of a macro, and SHA-256 digests of the answers of")
    print("// Xcode's plugins (MacroExpansionTests.canonical). Regenerate after `record`; nothing is copied from a capture.")
    print()
    print("extension MacroExpansionTests {")
    emitted = []
    for name in names:
        source = (out / name / f"{name}.swift").read_text()
        exchanges = []
        for log in sorted((out / name / "protocol").glob("*.jsonl")):
            pending = None
            for line in log.read_text().splitlines():
                entry = json.loads(line)
                if entry["direction"] == "compiler":
                    kind, request = next(iter(entry["message"].items()))
                    pending = (kind, request) if kind.startswith("expand") and request["macro"]["moduleName"] in modules else None
                elif pending is not None:
                    exchanges.append((*pending, entry["message"]["expandMacroResult"]))
                    pending = None
        if not exchanges:
            continue
        buffers = {}
        rows = []

        def position(text, offset):
            before = text.encode()[:offset].decode()
            return before.count("\n") + 1, len(before[before.rfind("\n") + 1:].encode()) + 1

        def node(syntax):
            location = syntax["location"]
            if location["fileName"] == f"{name}.swift":
                text, origin = source, ".file"
            else:
                parent = buffers[location["fileName"]]
                text, origin = exchanges[parent][2]["expandedSource"], f".expansion({parent})"
            data = text.encode()
            offset, length = location["offset"], len(syntax["source"].encode())
            assert data[offset:offset + length].decode() == syntax["source"], (name, syntax)
            assert position(text, offset) == (location["line"], location["column"]), (name, location)
            assert location["fileID"] == "M/" + location["fileName"], location
            return f"N({swift_string(syntax['kind'])}, {origin}, {offset}, {length})"

        parents = set()
        for kind, request, answer in exchanges:
            for key in NODE_KEYS:
                if key in request and request[key]["location"]["fileName"] != f"{name}.swift":
                    parents.add(request[key]["location"]["fileName"])
        # A use inside an expansion of a module left out (SwiftData's @Query passing #Predicate on)
        # cannot be rebuilt from nomac's answers: it is left out with it.
        known = {f"{name}.swift"}
        kept = []
        for kind, request, answer in exchanges:
            files = [request[key]["location"]["fileName"] for key in NODE_KEYS if key in request]
            if all(file in known for file in files):
                kept.append((kind, request, answer))
                known.add("@__swiftmacro_" + request["discriminator"][2:] + ".swift")
        exchanges = kept
        if not exchanges:
            continue
        for index, (kind, request, answer) in enumerate(exchanges):
            buffer = "@__swiftmacro_" + request["discriminator"][2:] + ".swift"
            buffers[buffer] = index
            assert set(request) <= {"macro", "macroRole", "discriminator", *NODE_KEYS, "lexicalContext", "staticBuildConfiguration",
                                    "conformanceListSyntax", "extendedTypeSyntax"}, set(request)
            for scope in request.get("lexicalContext", []):
                assert scope["location"] == {"column": 0, "fileID": "", "fileName": "", "line": 0, "offset": 0}, scope
            macro = request["macro"]
            nodes = [node(request["syntax"])] if kind == "expandFreestandingMacro" else [node(request["attributeSyntax"]), node(request["declSyntax"])]
            scopes = []
            for scope in request.get("lexicalContext", []):
                # A declaration an earlier expansion made is rendered as its text up to its first
                # brace, then "}": the tests render nomac's own answer so.
                heads = [k for k, (_, _, earlier) in enumerate(exchanges[:index])
                         if "{" in (earlier.get("expandedSource") or "")
                         and earlier["expandedSource"][:earlier["expandedSource"].index("{") + 1] + "}" == scope["source"]]
                slices = [(k, earlier["expandedSource"].encode().index(scope["source"].encode())) for k, (_, _, earlier) in enumerate(exchanges[:index])
                          if scope["source"].encode() in (earlier.get("expandedSource") or "").encode()]
                # Or one an earlier expansion made after others: from its offset there.
                opening = scope["source"][:-1]
                inner = [(k, earlier["expandedSource"].encode().index(opening.encode())) for k, (_, _, earlier) in enumerate(exchanges[:index])
                         if scope["source"].endswith("{}") and opening.count("{") == 1 and opening.encode() in (earlier.get("expandedSource") or "").encode()]
                if heads:
                    scopes.append(f".head({swift_string(scope['kind'])}, {heads[-1]})")
                elif inner and scope["source"].strip() not in source:
                    k, offset = inner[-1]
                    scopes.append(f".headAt({swift_string(scope['kind'])}, {k}, {offset})")
                elif slices and scope["source"].strip() not in source:
                    k, offset = slices[-1]
                    scopes.append(f".slice({swift_string(scope['kind'])}, {k}, {offset}, {len(scope['source'].encode())})")
                else:
                    # Written in the case: the compiler's rendering of a declaration of the source.
                    assert scope["source"].strip().split("{")[0].strip() in source, (name, scope)
                    scopes.append(f".text({swift_string(scope['kind'])}, {swift_string(scope['source'])})")
            context = ", ".join(scopes)
            # The discriminator only matters when the expansion names something with it, or when a
            # later request reads the expansion (its buffer is named after it).
            needed = request["discriminator"][2:] in (answer.get("expandedSource") or "") or buffer in parents
            discriminator = swift_string(request["discriminator"]) if needed else "nil"
            digest = hashlib.sha256(canonical(answer).encode()).hexdigest()
            # A member or extension macro's request also carries the declaration's parent, the
            # conformances the compiler still lacks (rendered as a placeholder struct) and the type
            # extended (rendered by the compiler, outside any file).
            extra = ""
            if "parentDeclSyntax" in request:
                extra += f", parent: {node(request['parentDeclSyntax'])}"
            if "conformanceListSyntax" in request:
                conformances = request["conformanceListSyntax"]
                match = re.fullmatch(r"struct Placeholder: (.*) \{\}", conformances["source"])
                assert match and conformances["kind"] == "declaration" and conformances["location"]["fileName"] == "", conformances
                extra += f", conformances: [{', '.join(swift_string(name) for name in match.group(1).split(', '))}]"
            if "extendedTypeSyntax" in request:
                extended = request["extendedTypeSyntax"]
                assert extended["kind"] == "type" and extended["location"]["fileName"] == "", extended
                extra += f", extendedType: {swift_string(extended['source'])}"
            rows.append(f"            O({swift_string(macro['moduleName'] + '.' + macro['typeName'] + ':' + macro['name'])}, "
                        f"{swift_string(request.get('macroRole', ''))}, {discriminator}, [{', '.join(nodes)}], [{context}], \"{digest}\"{extra}),")
        # One declaration per case, each typed: the type checker handles them one at a time.
        identifier = "case" + "".join(part.capitalize() for part in re.split(r"[^A-Za-z0-9]+", name))
        emitted.append((name, identifier))
        print(f"    static let {identifier}Source = ##\"\"\"\n{source}\"\"\"##")
        print(f"    static let {identifier}: [Observed] = [")
        print("\n".join(row[4:] for row in rows))
        print("    ]")
        print()
    print("    static let observedCases: [ObservedCase] = [")
    for name, identifier in emitted:
        print(f"        ObservedCase({swift_string(name)}, source: {identifier}Source, expansions: {identifier}),")
    print("    ]")
    print("}")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    command, argument = sys.argv[1], sys.argv[2]
    if command == "survey":
        survey(argument)
    elif command == "preview":
        preview(Path(argument).resolve())
    elif command in ("record", "compare"):
        names = sys.argv[3:] or list(CASES)
        (record if command == "record" else compare)(Path(argument).resolve(), names)
    elif command == "corpus":
        corpus(argument, Path(sys.argv[3]).resolve(), sys.argv[4:])
    elif command == "linux":
        linux(Path(argument).resolve(), Path(sys.argv[3]), sys.argv[4:] or list(CASES))
    elif command == "facts":
        rest = sys.argv[3:]
        names = [rest[i + 1] for i, value in enumerate(rest) if value == "--case"]
        modules = [value for i, value in enumerate(rest) if value != "--case" and (i == 0 or rest[i - 1] != "--case")]
        facts(Path(argument).resolve(), set(modules), names or list(CASES))
    elif command == "tee":
        tee(argument, sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
