#!/usr/bin/env python3
"""Observes how Xcode 27.0 builds, archives and exports an app with each kind of nested product:
a widget, an App Intents widget, a Live Activity, notification service and content extensions,
share and action extensions, an App Clip, a watch app with its widget, and all of them in one app
(docs/formats/extensions.md).

Each case is a self-written project made into a corpus-style reference by
corpus/scripts/capture_reference.py (loader outputs, an unsigned build, an ad-hoc archive with every
codesign step recorded, a `debugging` export), so that `nomac verify --build` compares nomac's
outputs with Xcode's file by file on any host, with the `extension` checks of each nested product
(docs/VERIFICATION.md "Extension checks").

    extension_experiments.py capture <out> [case...]   # Mac, Xcode 27.0
    extension_experiments.py thinning <out> [case...]  # Mac: Xcode's thin-for-all-variants exports
    extension_experiments.py verify <out> <nomac> <developer dir> [case...]   # Mac or Linux
    extension_experiments.py compare-thinning <out> <nomac> [case...]         # Mac or Linux, with DEVELOPER_DIR
    extension_experiments.py summary <out>

`<out>` stays outside the repository and at the same absolute path on every host; the checkouts go
to /private/tmp/nomac-ext/<case>, as nomac's paths have to be Xcode's.
"""

import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from signing_experiments import BASE_SETTINGS, CLIP_SIGN_SCRIPT, EXPORT_OPTIONS, OFFLINE, Project

REPOSITORY = Path(__file__).resolve().parents[2]
WORK = Path("/private/tmp/nomac-ext")
IDENTIFIER = "org.nomac.ext"

APP_SOURCE = """import SwiftUI

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup { Text("App") }
    }
}
"""

WIDGET_SOURCE = """import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date())], policy: .atEnd))
    }
}

struct ExampleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ExampleWidget", provider: Provider()) { entry in
            Text(entry.date, style: .time).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Example")
        .description("An example widget.")
    }
}

@main
struct ExampleBundle: WidgetBundle {
    var body: some Widget { ExampleWidget() }
}
"""

INTENT_WIDGET_SOURCE = """import AppIntents
import SwiftUI
import WidgetKit

struct ConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "An example." }

    @Parameter(title: "Favorite", default: "Value")
    var favorite: String
}

struct Entry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationIntent
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), configuration: ConfigurationIntent()) }
    func snapshot(for configuration: ConfigurationIntent, in context: Context) async -> Entry { Entry(date: Date(), configuration: configuration) }
    func timeline(for configuration: ConfigurationIntent, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [Entry(date: Date(), configuration: configuration)], policy: .atEnd)
    }
}

struct IntentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "IntentWidget", intent: ConfigurationIntent.self, provider: Provider()) { entry in
            Text(entry.configuration.favorite).containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

@main
struct IntentBundle: WidgetBundle {
    var body: some Widget { IntentWidget() }
}
"""

LIVE_ACTIVITY_SOURCE = """import ActivityKit
import SwiftUI
import WidgetKit

struct ExampleAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var emoji: String
    }
    var name: String
}

struct ExampleActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExampleAttributes.self) { context in
            Text(context.state.emoji).activityBackgroundTint(Color.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Text(context.state.emoji) }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T")
            } minimal: {
                Text(context.state.emoji)
            }
        }
    }
}

@main
struct ExampleBundle: WidgetBundle {
    var body: some Widget { ExampleActivity() }
}
"""

NOTIFICATION_SERVICE_SOURCE = """import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        contentHandler(request.content)
    }
}
"""

NOTIFICATION_CONTENT_SOURCE = """import UIKit
import UserNotifications
import UserNotificationsUI

class NotificationViewController: UIViewController, UNNotificationContentExtension {
    func didReceive(_ notification: UNNotification) {
        view.backgroundColor = .clear
    }
}
"""

SHARE_SOURCE = """import Social
import UIKit

class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool { true }
    override func didSelectPost() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
"""

ACTION_SOURCE = """import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

class ActionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        _ = UTType.image
    }
}
"""

STORYBOARD = """<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="A1">
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="Safe area layout guides" minToolsVersion="9.0"/>
        <capability name="System colors in document resources" minToolsVersion="11.0"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="S1">
            <objects>
                <viewController id="A1" customClass="{controller}" customModuleProvider="target" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="V1">
                        <rect key="frame" x="0.0" y="0.0" width="320" height="568"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <viewLayoutGuide key="safeArea" id="G1"/>
                        <color key="backgroundColor" systemColor="systemBackgroundColor"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="F1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
        </scene>
    </scenes>
</document>
"""

CATALOG_ROOT = '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
UNIVERSAL_COLOR = ('{\n  "colors" : [\n    {\n      "idiom" : "universal"\n    }\n  ],\n'
                   '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
WIDGET_CATALOG = {"Contents.json": CATALOG_ROOT,
                  "AccentColor.colorset/Contents.json": UNIVERSAL_COLOR,
                  "WidgetBackground.colorset/Contents.json": UNIVERSAL_COLOR}
WIDGET_CATALOG_SETTINGS = {"ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                           "ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME": "WidgetBackground"}

CLIP_SOURCE = """import SwiftUI

@main
struct ClipApp: App {
    var body: some Scene {
        WindowGroup { Text("Clip") }
    }
}
"""

WATCH_SOURCE = """import SwiftUI

@main
struct WatchExampleApp: App {
    var body: some Scene {
        WindowGroup { Text("Watch") }
    }
}
"""

PLIST_HEADER = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n')


def extension_info(body):
    return f"{PLIST_HEADER}<dict>\n\t<key>NSExtension</key>\n\t<dict>\n{body}\t</dict>\n</dict>\n</plist>\n"


def point(identifier, *entries):
    return extension_info("".join(entries) + f"\t\t<key>NSExtensionPointIdentifier</key>\n\t\t<string>{identifier}</string>\n")


PRINCIPAL = "\t\t<key>NSExtensionPrincipalClass</key>\n\t\t<string>$(PRODUCT_MODULE_NAME).{}</string>\n"
STORYBOARD_KEY = "\t\t<key>NSExtensionMainStoryboard</key>\n\t\t<string>MainInterface</string>\n"
ACTIVATION = ("\t\t<key>NSExtensionAttributes</key>\n\t\t<dict>\n\t\t\t<key>NSExtensionActivationRule</key>\n"
              "\t\t\t<string>TRUEPREDICATE</string>\n\t\t</dict>\n")
ACTION_ATTRIBUTES = ("\t\t<key>NSExtensionAttributes</key>\n\t\t<dict>\n\t\t\t<key>NSExtensionActivationRule</key>\n"
                     "\t\t\t<string>TRUEPREDICATE</string>\n\t\t\t<key>NSExtensionServiceRoleType</key>\n"
                     "\t\t\t<string>NSExtensionServiceRoleTypeViewer</string>\n\t\t</dict>\n")
CONTENT_ATTRIBUTES = ("\t\t<key>NSExtensionAttributes</key>\n\t\t<dict>\n\t\t\t<key>UNNotificationExtensionCategory</key>\n"
                      "\t\t\t<string>myNotificationCategory</string>\n\t\t\t<key>UNNotificationExtensionInitialContentSizeRatio</key>\n"
                      "\t\t\t<real>1</real>\n\t\t</dict>\n")

# Each kind of extension as Xcode 27.0's templates make it: its code, its Info.plist with the
# NSExtension dictionary, a storyboard's view controller, and the extra build settings.
EXTENSIONS = {
    "Widget": {"source": WIDGET_SOURCE, "info": point("com.apple.widgetkit-extension"), "catalog": True},
    "IntentWidget": {"source": INTENT_WIDGET_SOURCE, "info": point("com.apple.widgetkit-extension"), "catalog": True},
    "Activity": {"source": LIVE_ACTIVITY_SOURCE, "info": point("com.apple.widgetkit-extension"), "catalog": True},
    "Service": {"source": NOTIFICATION_SERVICE_SOURCE, "source_name": "NotificationService.swift",
                "info": point("com.apple.usernotifications.service", PRINCIPAL.format("NotificationService"))},
    "Content": {"source": NOTIFICATION_CONTENT_SOURCE, "source_name": "NotificationViewController.swift", "storyboard": "NotificationViewController",
                "info": point("com.apple.usernotifications.content-extension", CONTENT_ATTRIBUTES, STORYBOARD_KEY)},
    "Share": {"source": SHARE_SOURCE, "source_name": "ShareViewController.swift", "storyboard": "ShareViewController",
              "info": point("com.apple.share-services", ACTIVATION, STORYBOARD_KEY)},
    "Action": {"source": ACTION_SOURCE, "source_name": "ActionViewController.swift", "storyboard": "ActionViewController",
               "info": point("com.apple.ui-services", ACTION_ATTRIBUTES, STORYBOARD_KEY)},
}


def add_catalog(project, files, name, entries):
    for path, text in entries.items():
        files[f"{name}/Assets.xcassets/{path}"] = text
    return project.build_file(project.file(f"{name}/Assets.xcassets", "folder.assetcatalog"))


def extension_target(project, files, name, kit, deployment="18.0", sdk=None, embed_kit=False):
    """The target of the kind `EXTENSIONS[name]`; `kit` (target, product) links a framework, which
    with `embed_kit` the extension embeds in its own `Frameworks`."""
    kind = EXTENSIONS[name]
    source_name = kind.get("source_name", f"{name}.swift")
    files[f"{name}/{source_name}"] = kind["source"]
    files[f"{name}/Info.plist"] = kind["info"]
    source = project.file(f"{name}/{source_name}", "sourcecode.swift")
    project.file(f"{name}/Info.plist", "text.plist.xml")
    resources = []
    settings = {}
    if kind.get("catalog"):
        resources.append(add_catalog(project, files, name, WIDGET_CATALOG))
        settings.update(WIDGET_CATALOG_SETTINGS)
    if kind.get("storyboard"):
        files[f"{name}/Base.lproj/MainInterface.storyboard"] = STORYBOARD.format(controller=kind["storyboard"])
        group = project.variant_group(name, "MainInterface.storyboard", ["Base"], "file.storyboard")
        resources.append(project.build_file(group))
    platform = {"SDKROOT": "watchos", "WATCHOS_DEPLOYMENT_TARGET": deployment, "TARGETED_DEVICE_FAMILY": "4",
                "SWIFT_VERSION": "5.0", "CODE_SIGN_STYLE": "Manual", "ALWAYS_SEARCH_USER_PATHS": "NO"} if sdk == "watchos" else {
        **BASE_SETTINGS, "IPHONEOS_DEPLOYMENT_TARGET": deployment}
    return project.target(
        name, "com.apple.product-type.app-extension", f"{name}.appex", "wrapper.app-extension",
        [project.phase("PBXSourcesBuildPhase", [project.build_file(source)]),
         project.phase("PBXFrameworksBuildPhase", [project.build_file(kit[1])] if kit else []),
         project.phase("PBXResourcesBuildPhase", resources),
         *([project.copy_phase("Embed Frameworks", 10, [project.build_file(kit[1], ["CodeSignOnCopy", "RemoveHeadersOnCopy"])])] if embed_kit else [])],
        {**platform, "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": f"{IDENTIFIER}.{'watchkitapp.' if sdk == 'watchos' else ''}{name}",
         "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": f"{name}/Info.plist", "SKIP_INSTALL": "YES",
         "INFOPLIST_KEY_CFBundleDisplayName": name, "SWIFT_EMIT_LOC_STRINGS": "YES",
         "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks")',
         "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0", **settings},
        [(kit[0], "Kit")] if kit else [])


def framework_target(project, files, name, sdk="iphoneos", embeds=()):
    """A framework; `embeds` are the (name, target, product) it holds in its own `Frameworks`."""
    files[f"{name}/{name}.swift"] = f'public enum {name} {{ public static let text = "{name}" }}\n'
    platform = BASE_SETTINGS if sdk == "iphoneos" else {"SDKROOT": "watchos", "WATCHOS_DEPLOYMENT_TARGET": "11.0", "TARGETED_DEVICE_FAMILY": "4",
                                                        "SWIFT_VERSION": "5.0", "CODE_SIGN_STYLE": "Manual", "ALWAYS_SEARCH_USER_PATHS": "NO"}
    return project.target(
        name, "com.apple.product-type.framework", f"{name}.framework", "wrapper.framework",
        [project.phase("PBXSourcesBuildPhase", [project.build_file(project.file(f"{name}/{name}.swift", "sourcecode.swift"))]),
         project.phase("PBXFrameworksBuildPhase", []), project.phase("PBXResourcesBuildPhase", []),
         *([project.copy_phase("Embed Frameworks", 10, [project.build_file(product, ["CodeSignOnCopy", "RemoveHeadersOnCopy"]) for _, _, product in embeds])] if embeds else [])],
        {**platform, "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": f"{IDENTIFIER}.{name}",
         "GENERATE_INFOPLIST_FILE": "YES", "DEFINES_MODULE": "YES", "SKIP_INSTALL": "YES",
         "APPLICATION_EXTENSION_API_ONLY": "YES", "DYLIB_INSTALL_NAME_BASE": '"@rpath"',
         "INSTALL_PATH": '"$(LOCAL_LIBRARY_DIR)/Frameworks"',
         "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks")',
         "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0", "VERSIONING_SYSTEM": '"apple-generic"'},
        [(target, held) for held, target, _ in embeds])


def held_frameworks(project, files, tree):
    """The frameworks of `tree` (name to the tree of what it holds), inner ones first."""
    return [(name, *framework_target(project, files, name, embeds=held_frameworks(project, files, held))) for name, held in tree.items()]


def app_project(extensions=(), framework=False, embed_in_extension=False, framework_holds=None, live_activities=False, clip=None,
                watch=False, watch_widget=False, watch_framework=False):
    """An app embedding `extensions` in `PlugIns`, with `framework` a framework all of them link,
    embedded in the app, or with `embed_in_extension` in each extension instead; `clip` is `signed`
    (Xcode signs the App Clip) or `script` (the build's script phase does, the stand-in of
    signing_experiments' `appclip-script`); `watch` adds a watch app, `watch_widget` its widget
    extension, `watch_framework` a framework it embeds; `framework_holds` is the tree of frameworks
    the app's framework holds."""
    files, project = {}, Project()
    files["App/App.swift"] = APP_SOURCE
    source = project.file("App/App.swift", "sourcecode.swift")
    catalog = add_catalog(project, files, "App", {"Contents.json": CATALOG_ROOT, "AccentColor.colorset/Contents.json": UNIVERSAL_COLOR})
    kit = framework_target(project, files, "Kit", embeds=held_frameworks(project, files, framework_holds or {})) if framework else None
    targets = [extension_target(project, files, name, kit, embed_kit=embed_in_extension) for name in extensions]
    dependencies = [(target, name) for (target, _), name in zip(targets, extensions)]
    embeds = []
    links = []
    if kit and embed_in_extension:
        dependencies.insert(0, (kit[0], "Kit"))
    elif kit:
        dependencies.insert(0, (kit[0], "Kit"))
        links.append(project.build_file(kit[1]))
        embeds.append(project.copy_phase("Embed Frameworks", 10, [project.build_file(kit[1], ["CodeSignOnCopy", "RemoveHeadersOnCopy"])]))
    if targets:
        embeds.append(project.copy_phase("Embed Foundation Extensions", 13, [project.build_file(product, ["RemoveHeadersOnCopy"]) for _, product in targets]))
    if watch:
        files["Watch/WatchApp.swift"] = WATCH_SOURCE
        watch_dependencies = []
        watch_embeds = []
        watch_links = []
        if watch_framework:
            watch_kit = framework_target(project, files, "WatchKitLibrary", sdk="watchos")
            watch_dependencies.append((watch_kit[0], "WatchKitLibrary"))
            watch_links.append(project.build_file(watch_kit[1]))
            watch_embeds.append(project.copy_phase("Embed Frameworks", 10, [project.build_file(watch_kit[1], ["CodeSignOnCopy", "RemoveHeadersOnCopy"])]))
        if watch_widget:
            widget_target = extension_target(project, files, "Widget", None, deployment="11.0", sdk="watchos")
            watch_dependencies.append((widget_target[0], "Widget"))
            watch_embeds.append(project.copy_phase("Embed Foundation Extensions", 13, [project.build_file(widget_target[1], ["RemoveHeadersOnCopy"])]))
        watch_target, watch_product = project.target(
            "Watch", "com.apple.product-type.application", "Watch.app", "wrapper.application",
            [project.phase("PBXSourcesBuildPhase", [project.build_file(project.file("Watch/WatchApp.swift", "sourcecode.swift"))]),
             project.phase("PBXFrameworksBuildPhase", watch_links), project.phase("PBXResourcesBuildPhase", []), *watch_embeds],
            {"SDKROOT": "watchos", "WATCHOS_DEPLOYMENT_TARGET": "11.0", "TARGETED_DEVICE_FAMILY": "4", "SWIFT_VERSION": "5.0",
             "CODE_SIGN_STYLE": "Manual", "ALWAYS_SEARCH_USER_PATHS": "NO", "PRODUCT_NAME": '"$(TARGET_NAME)"',
             "PRODUCT_BUNDLE_IDENTIFIER": f"{IDENTIFIER}.watchkitapp", "GENERATE_INFOPLIST_FILE": "YES", "SKIP_INSTALL": "YES",
             "INFOPLIST_KEY_CFBundleDisplayName": "Watch", "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": IDENTIFIER,
             "INFOPLIST_KEY_UISupportedInterfaceOrientations": '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown"',
             "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
             "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0"},
            watch_dependencies)
        dependencies.append((watch_target, "Watch"))
        embeds.append(project.copy_phase("Embed Watch Content", 16, [project.build_file(watch_product, ["RemoveHeadersOnCopy"])], "$(CONTENTS_FOLDER_PATH)/Watch"))
    if clip:
        files["Clip/ClipApp.swift"] = CLIP_SOURCE
        phases = [project.phase("PBXSourcesBuildPhase", [project.build_file(project.file("Clip/ClipApp.swift", "sourcecode.swift"))]),
                  project.phase("PBXFrameworksBuildPhase", []), project.phase("PBXResourcesBuildPhase", [])]
        settings = {}
        if clip == "script":
            # The capture's unsigned build clears the identity, and has nothing to sign with.
            phases.append(project.script_phase("Sign Ad Hoc", f'if [ -n "${{CODE_SIGN_IDENTITY}}" ]; then {CLIP_SIGN_SCRIPT}; fi'))
            settings = {"CODE_SIGNING_ALLOWED": "NO", "ENABLE_USER_SCRIPT_SANDBOXING": "NO", "STRIP_INSTALLED_PRODUCT": "NO"}
        clip_target, clip_product = project.target(
            "Clip", "com.apple.product-type.application.on-demand-install-capable", "Clip.app", "wrapper.application", phases,
            {**BASE_SETTINGS, "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": f"{IDENTIFIER}.Clip",
             "GENERATE_INFOPLIST_FILE": "YES", "SKIP_INSTALL": "YES",
             "INFOPLIST_KEY_UILaunchStoryboardName": '""', "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
             "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
             "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0", **settings})
        dependencies.append((clip_target, "Clip"))
        embeds.append(project.copy_phase("Embed App Clips", 16, [project.build_file(clip_product, ["RemoveHeadersOnCopy"])], "$(CONTENTS_FOLDER_PATH)/AppClips"))
    project.target(
        "App", "com.apple.product-type.application", "App.app", "wrapper.application",
        [project.phase("PBXSourcesBuildPhase", [project.build_file(source)]),
         project.phase("PBXFrameworksBuildPhase", links),
         project.phase("PBXResourcesBuildPhase", [catalog]), *embeds],
        {**BASE_SETTINGS, "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": IDENTIFIER,
         "GENERATE_INFOPLIST_FILE": "YES", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
         "INFOPLIST_KEY_UILaunchStoryboardName": '""', "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
         **({"INFOPLIST_KEY_NSSupportsLiveActivities": "YES"} if live_activities else {}),
         "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
         "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0"},
        dependencies)
    files["Ext.xcodeproj/project.pbxproj"] = project.text()
    return files


CASES = {
    "widget": lambda: app_project(["Widget"]),
    "widget-intent": lambda: app_project(["IntentWidget"]),
    "live-activity": lambda: app_project(["Activity"], live_activities=True),
    "notification-service": lambda: app_project(["Service"]),
    "notification-content": lambda: app_project(["Content"]),
    "share": lambda: app_project(["Share"]),
    "action": lambda: app_project(["Action"]),
    "appclip": lambda: app_project(clip="signed"),
    "appclip-script": lambda: app_project(clip="script"),
    "watch": lambda: app_project(watch=True),
    "watch-widget": lambda: app_project(watch=True, watch_widget=True),
    "framework-share": lambda: app_project(["Share"], framework=True),
    "extension-framework": lambda: app_project(["Share"], framework=True, embed_in_extension=True),
    "framework-framework": lambda: app_project(framework=True, framework_holds={"Inner": {}}),
    "framework-framework-deep": lambda: app_project(framework=True, framework_holds={"Inner": {"Deep": {}}, "Other": {}}),
    "watch-framework": lambda: app_project(watch=True, watch_framework=True),
    "all": lambda: app_project(["Widget", "Service", "Content", "Share", "Action"], framework=True, clip="script", watch=True, watch_widget=True),
}


def git(*arguments, cwd):
    return subprocess.run(["git", "-c", "user.name=nomac", "-c", "user.email=nomac@example.com", *arguments], cwd=cwd, check=True,
                          capture_output=True, text=True).stdout.strip()


def write_checkout(case):
    """The case's project at its reference path, committed; returns the commit."""
    source = WORK / case
    shutil.rmtree(source, ignore_errors=True)
    source.mkdir(parents=True)
    for path, text in CASES[case]().items():
        target = source / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    git("init", "-q", cwd=source)
    git("add", ".", cwd=source)
    git("commit", "-q", "-m", case, cwd=source)
    return git("rev-parse", "HEAD", cwd=source)


def manifest_entry(case, commit):
    return {"id": case, "name": case, "repository": str(WORK / case), "commit": commit, "license": "self-written",
            "container": "Ext.xcodeproj", "tier": "A", "submodules": False, "prepare": [], "exercises": ["extensions"],
            "build": {"scheme": "App", "configuration": "Release"}}


def capture(output, cases):
    """`capture_reference.py` on each case, then its archive and `debugging` export, two at a time (at most 2 xcodebuilds at once)."""
    corpus = json.loads((REPOSITORY / "corpus/corpus.json").read_text())
    capture_script = REPOSITORY / "corpus/scripts/capture_reference.py"
    manifest_path = output / "manifest.json"
    known = {app["id"]: app for app in json.loads(manifest_path.read_text())["apps"]} if manifest_path.exists() else {}
    for case in cases:
        known[case] = manifest_entry(case, write_checkout(case))
    manifest_path.write_text(json.dumps({**{k: corpus[k] for k in ("schemaVersion", "xcode", "progress")},
                                         "apps": [known[name] for name in CASES if name in known]}, indent=2) + "\n")
    reference = output / "reference"

    def one(case):
        shutil.rmtree(reference / case, ignore_errors=True)
        common = [sys.executable, str(capture_script), case, str(reference), "--manifest", str(manifest_path), "--work", str(WORK), "--reuse-checkout"]
        with (output / f"capture-{case}.log").open("w") as stream:
            first = subprocess.run(common, stdout=stream, stderr=subprocess.STDOUT).returncode
            second = subprocess.run(common + ["--archive"], stdout=stream, stderr=subprocess.STDOUT).returncode
        recorded = json.loads((reference / case / "summary.json").read_text())
        print(f"{case}: capture {first}, archive {second}, xcodebuild archive {recorded.get('archiveExitStatus')}, export {recorded.get('exportExitStatus')}", flush=True)

    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(one, cases))


THINNING_OPTIONS = "\t<key>thinning</key>\n\t<string>&lt;thin-for-all-variants&gt;</string>\n"


def thinning(output, cases):
    """Xcode's `debugging` export of each archive thinned for all variants, in `archive/export-thinned`."""
    for case in cases:
        archive = output / "reference" / case / "archive"
        found = list(archive.glob("*.xcarchive"))
        if not found:
            print(f"{case}: no archive")
            continue
        options = archive / "ExportOptions-thinned.plist"
        options.write_text(EXPORT_OPTIONS.format(method="debugging", team="\t<key>teamID</key>\n\t<string>NOMAC00000</string>\n", extra=THINNING_OPTIONS))
        destination = archive / "export-thinned"
        shutil.rmtree(destination, ignore_errors=True)
        completed = subprocess.run(OFFLINE + ["xcodebuild", "-exportArchive", "-archivePath", str(found[0]), "-exportPath", str(destination),
                                              "-exportOptionsPlist", str(options)], capture_output=True, text=True)
        print(f"{case}: thinned export exit {completed.returncode}", flush=True)


def verify(output, nomac, developer, cases):
    """`nomac verify --build` of each reference; reports under `reports-<system>`."""
    system = os.uname().sysname
    reports = output / f"reports-{system}"
    reports.mkdir(exist_ok=True)
    for case in cases:
        reference = output / "reference" / case
        if not reference.is_dir():
            continue
        if not (WORK / case).is_dir():
            write_checkout(case)
        with (reports / f"{case}.log").open("w") as stream:
            status = subprocess.run([nomac, "verify", str(reference), "--developer-dir", developer, "--build",
                                     "--report", str(reports / f"{case}.json")], cwd=WORK / case, stdout=stream, stderr=subprocess.STDOUT).returncode
        print(f"{case}: verify exit {status}; {tally(reports / f'{case}.json')}", flush=True)


def tally(report_path):
    if not report_path.is_file():
        return "no report"
    checks = json.loads(report_path.read_text())["checks"]
    counts = {}
    for check in checks:
        passed = check["status"] in ("identical", "equivalent")
        entry = counts.setdefault(check["kind"], [0, 0])
        entry[0] += passed
        entry[1] += 1
    return " ".join(f"{kind} {good}/{total}" for kind, (good, total) in sorted(counts.items()))


def plist_or_bytes(data):
    try:
        return plistlib.loads(data)
    except Exception:
        return data


def compare_thinning(output, nomac, cases):
    """`nomac export` of Xcode's archive thinned for all variants against Xcode's, each IPA's
    entries by name and contents (`app-thinning.plist` and the summary as property lists)."""
    failures = 0
    for case in cases:
        archive = output / "reference" / case / "archive"
        expected = archive / "export-thinned"
        found = list(archive.glob("*.xcarchive"))
        if not found or not expected.is_dir():
            continue
        with tempfile.TemporaryDirectory(prefix="nomac-ext-thin-") as work:
            actual = Path(work) / "export"
            completed = subprocess.run([nomac, "export", "-archivePath", str(found[0]), "-exportPath", str(actual),
                                        "-exportOptionsPlist", str(archive / "ExportOptions-thinned.plist"),
                                        "--developer-dir", os.environ["DEVELOPER_DIR"]], capture_output=True, text=True)
            differences = [] if completed.returncode == 0 else [f"nomac export exit {completed.returncode}: {completed.stderr.strip()[:300]}"]
            if completed.returncode == 0:
                differences = tree_of_ipas(expected, actual)
        print(f"{'identical' if not differences else 'DIFFERENT'}: {case} thinned export")
        for difference in differences[:12]:
            print(f"    {difference}")
        failures += bool(differences)
    return failures


def tree_of_ipas(expected, actual):
    differences = []
    left = {path.relative_to(expected): path for path in expected.rglob("*") if path.is_file()}
    right = {path.relative_to(actual): path for path in actual.rglob("*") if path.is_file()}
    for name in sorted(set(left) | set(right), key=str):
        if name.name == "Packaging.log":
            continue
        if name not in left or name not in right:
            differences.append(f"{'extra' if name in right else 'missing'} {name}")
        elif name.suffix == ".ipa":
            one, other = zipfile.ZipFile(left[name]), zipfile.ZipFile(right[name])
            first = {info.filename: info for info in one.infolist()}
            second = {info.filename: info for info in other.infolist()}
            differences += [f"{name}: only in Xcode's {entry}" for entry in first if entry not in second]
            differences += [f"{name}: only in nomac's {entry}" for entry in second if entry not in first]
            for entry in first:
                if entry in second and one.read(entry) != other.read(entry):
                    differences.append(f"{name}: {entry}")
        elif plist_or_bytes(left[name].read_bytes()) != plist_or_bytes(right[name].read_bytes()):
            differences.append(f"different {name}")
    return differences


def summary(output):
    for reports in sorted(output.glob("reports-*")):
        print(reports.name)
        for report in sorted(reports.glob("*.json")):
            print(f"  {report.stem}: {tally(report)}")


def main():
    command = sys.argv[1]
    output = Path(sys.argv[2]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if command == "capture":
        capture(output, sys.argv[3:] or list(CASES))
    elif command == "thinning":
        thinning(output, sys.argv[3:] or list(CASES))
    elif command == "verify":
        verify(output, str(Path(sys.argv[3]).resolve()), sys.argv[4], sys.argv[5:] or list(CASES))
    elif command == "compare-thinning":
        sys.exit(1 if compare_thinning(output, str(Path(sys.argv[3]).resolve()), sys.argv[4:] or list(CASES)) else 0)
    elif command == "summary":
        summary(output)


if __name__ == "__main__":
    main()
