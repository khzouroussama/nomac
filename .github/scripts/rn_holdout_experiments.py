#!/usr/bin/env python3
"""React Native and Expo apps held out from development, generated as test cases for nomac.

expo-default and rn-bare (expo_experiments.py) are the apps nomac is developed against; these are
measured with the same tools and never fixed for directly, so that nomac does not overfit those two.
Each covers what real React Native apps use and the first two do not:

  expo-modules  `create-expo-app` with the blank TypeScript template, then `expo install` (the
                versions Expo SDK 58 bundles) of expo-router, Reanimated, Gesture Handler,
                expo-image, expo-font (a bundled Inter font), expo-splash-screen,
                expo-notifications, expo-camera, expo-location, expo-sqlite, expo-secure-store,
                expo-localization, expo-haptics and expo-apple-authentication; config plugins
                write entitlements (push, associated domains, Sign in with Apple), usage strings,
                a privacy manifest and a French InfoPlist.strings; `expo prebuild`, `pod install`
  rn-native     `@react-native-community/cli init` (React Native's template) with a Swift module
                (`RCT_EXTERN_MODULE`), an Objective-C++ Turbo Module from the app's own codegen
                spec, a WidgetKit extension target with its asset catalog, and
                `use_frameworks! :linkage => :static`; `pod install`
  rn-libs       `@react-native-community/cli init` with community libraries that compile C++
                against React Native's prebuilt core (Fabric components of react-native-svg,
                -screens, -safe-area-context, -pager-view, -webview, @shopify/flash-list; Nitro's
                react-native-mmkv) and react-native-webrtc, whose JitsiWebRTC pod is a prebuilt
                dynamic xcframework downloaded by CocoaPods; `pod install`

React Native 0.88 and Expo SDK 58 use the prebuilt React Native core (React.xcframework,
ReactNativeDependencies, Hermes) by default, so every app links code compiled from source against
those binaries (B-182).

Every xcodebuild and nomac build of these apps runs without sandbox-exec, with expo_experiments.py's
lsof sampling of the sockets the build opens (<reference>/build/network.log): Swift macros'
`swift-plugin-server` applies a sandbox of its own, which cannot be applied inside sandbox-exec's
("sandbox_apply: Operation not permitted", then "external macro implementation type
'SwiftUIMacros.StateMacro' could not be found ... produced malformed response"), as SwiftPM's
manifest sandbox cannot (expo-default's ExpoModulesJSI); react-native-pager-view's Swift uses
`@State`.

A build's derived data is removed once its products are in the reference (`capture`) or its
report and build log are written (`verify`, unless --keep-derived-data): each takes 1.5 to 3 GB.

`archive` adds capture_reference.py's ad-hoc archive and `debugging` export to the Release
reference (`archive/`), whose signing and export `nomac verify` replays.

Generation, capture and verification are expo_experiments.py's (pinned Node, npm resolution as of
PINS["npm-before"], CocoaPods under rbenv, a git repository per app at a fixed date). The extra
steps (edits to the generated projects, the files the apps add, JitsiWebRTC's 252 MB download
fetched resumably into CocoaPods' cache) are in this script; every file it writes is its own.

Usage (DEVELOPER_DIR selects the Xcode; root defaults to ~/nomac-out/wt-scratch/rn-holdout):
  rn_holdout_experiments.py generate [--root R] [app ...]
  rn_holdout_experiments.py capture [--root R] [--configuration C ...] [app ...]
  rn_holdout_experiments.py archive [--root R] [app ...]
  rn_holdout_experiments.py platform-packages [--root R] [app ...]
  rn_holdout_experiments.py verify --nomac <nomac> [--project-fixes] [--keep-derived-data] [--root R] [--configuration C ...] [app ...]
  rn_holdout_experiments.py mangling [--root R] [--configuration C ...] [app ...]
  rn_holdout_experiments.py triage <build.log> ...

`platform-packages` and `--project-fixes` are expo_experiments.py's: the lockfile's Linux optional
packages as a commit on top of the one the references were captured at, and the project's changes
for a Linux build (docs/state/react-native.md).

`mangling` reads a reference's products with the Xcode's `nm`: the symbols whose template
arguments point into objects (Itanium `Xad...`, the forms B-182 changes) that the app's
executables and the static libraries compiled from source leave undefined, and how many of those
the app's embedded frameworks (React Native's prebuilt core, Hermes, xcframeworks) define. Each is
a reference the Linux-compiled code would spell otherwise and fail to link.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import expo_experiments as expo  # noqa: E402

PINS = dict(expo.PINS, **{
    "expo-template-blank-typescript": "58.0.28",
    "@expo-google-fonts/inter": "0.4.2",
    "react-native-svg": "15.16.0",
    "react-native-screens": "4.30.0",
    "react-native-safe-area-context": "5.10.1",
    "react-native-pager-view": "9.0.9",
    "react-native-webview": "14.0.1",
    "@shopify/flash-list": "2.3.3",
    "react-native-mmkv": "4.3.2",
    "react-native-nitro-modules": "0.37.1",
    "react-native-webrtc": "155.0.1",
})

EXPO_MODULES = ["react-dom", "expo-router", "react-native-reanimated", "react-native-worklets", "react-native-gesture-handler",
                "react-native-safe-area-context", "react-native-screens", "expo-linking", "expo-constants",
                "expo-status-bar", "expo-image", "expo-font", "expo-splash-screen", "expo-notifications",
                "expo-camera", "expo-location", "expo-sqlite", "expo-secure-store", "expo-localization",
                "expo-haptics", "expo-apple-authentication"]

RN_LIBS = ["react-native-svg", "react-native-screens", "react-native-safe-area-context", "react-native-pager-view",
           "react-native-webview", "@shopify/flash-list", "react-native-mmkv", "react-native-nitro-modules",
           "react-native-webrtc"]

INTER = "./node_modules/@expo-google-fonts/inter/400Regular/Inter_400Regular.ttf"

EXPO_LAYOUT = """import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect } from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  useEffect(() => {
    SplashScreen.hideAsync();
  }, []);
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <Stack />
    </GestureHandlerRootView>
  );
}
"""

EXPO_INDEX = """import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Haptics from 'expo-haptics';
import { Image } from 'expo-image';
import { getLocales } from 'expo-localization';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import * as SecureStore from 'expo-secure-store';
import * as SQLite from 'expo-sqlite';
import { Pressable, Text, View } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, { useAnimatedStyle, useSharedValue, withSpring } from 'react-native-reanimated';

const database = SQLite.openDatabaseSync('notes.db');
database.execSync('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, body TEXT)');

export default function Index() {
  const offset = useSharedValue(0);
  const [permission, requestPermission] = useCameraPermissions();
  const pan = Gesture.Pan().onUpdate((event) => {
    offset.value = event.translationX;
  }).onEnd(() => {
    offset.value = withSpring(0);
  });
  const style = useAnimatedStyle(() => ({ transform: [{ translateX: offset.value }] }));
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ fontFamily: 'Inter_400Regular' }}>{getLocales()[0]?.languageTag}</Text>
      <GestureDetector gesture={pan}>
        <Animated.View style={style}>
          <Image source={require('../assets/icon.png')} style={{ width: 96, height: 96 }} />
        </Animated.View>
      </GestureDetector>
      {permission?.granted ? <CameraView style={{ width: 200, height: 200 }} /> : null}
      <Pressable
        onPress={async () => {
          await Haptics.selectionAsync();
          await requestPermission();
          await Location.requestForegroundPermissionsAsync();
          await Notifications.requestPermissionsAsync();
          await SecureStore.setItemAsync('opened', String(Date.now()));
        }}>
        <Text>Allow</Text>
      </Pressable>
    </View>
  );
}
"""

SWIFT_GREETER = """import Foundation
import React

@objc(SwiftGreeter)
final class SwiftGreeter: NSObject {
  @objc static func requiresMainQueueSetup() -> Bool {
    false
  }

  @objc func greet(_ name: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    resolve("Hello, \\(name), from Swift")
  }
}
"""

SWIFT_GREETER_BRIDGE = """#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(SwiftGreeter, NSObject)
RCT_EXTERN_METHOD(greet:(NSString *)name resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
@end
"""

CALCULATOR_SPEC = """import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  add(a: number, b: number): number;
  reverse(text: string): string;
}

export default TurboModuleRegistry.getEnforcing<Spec>('NativeCalculator');
"""

CALCULATOR_HEADER = """#import <AppSpecs/AppSpecs.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCTNativeCalculator : NSObject <NativeCalculatorSpec>
@end

NS_ASSUME_NONNULL_END
"""

CALCULATOR_IMPLEMENTATION = """#import "RCTNativeCalculator.h"

#include <algorithm>
#include <string>

@implementation RCTNativeCalculator

+ (NSString *)moduleName
{
  return @"NativeCalculator";
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeCalculatorSpecJSI>(params);
}

- (NSNumber *)add:(double)a b:(double)b
{
  return @(a + b);
}

- (NSString *)reverse:(NSString *)text
{
  std::string value = text.UTF8String;
  std::reverse(value.begin(), value.end());
  return [NSString stringWithUTF8String:value.c_str()];
}

@end
"""

RN_NATIVE_APP = """import React, { useEffect, useState } from 'react';
import { NativeModules, Text, View } from 'react-native';
import NativeCalculator from './specs/NativeCalculator';

export default function App() {
  const [greeting, setGreeting] = useState('');
  useEffect(() => {
    NativeModules.SwiftGreeter.greet('nomac').then(setGreeting);
  }, []);
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
      <Text>{greeting}</Text>
      <Text>{NativeCalculator.add(2, 3)}</Text>
      <Text>{NativeCalculator.reverse('nomac')}</Text>
    </View>
  );
}
"""

WIDGET = """import SwiftUI
import WidgetKit

struct GreetingEntry: TimelineEntry {
  let date: Date
}

struct GreetingProvider: TimelineProvider {
  func placeholder(in context: Context) -> GreetingEntry {
    GreetingEntry(date: .now)
  }

  func getSnapshot(in context: Context, completion: @escaping (GreetingEntry) -> Void) {
    completion(GreetingEntry(date: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<GreetingEntry>) -> Void) {
    completion(Timeline(entries: [GreetingEntry(date: .now)], policy: .never))
  }
}

struct RNNativeWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "RNNativeWidget", provider: GreetingProvider()) { entry in
      Text(entry.date, style: .time)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Greeting")
    .supportedFamilies([.systemSmall])
  }
}

@main
struct RNNativeWidgetBundle: WidgetBundle {
  var body: some Widget {
    RNNativeWidget()
  }
}
"""

WIDGET_INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
"""

COLOR_SET = {"colors": [{"color": {"color-space": "srgb", "components": {
    "alpha": "1.000", "blue": "0.937", "green": "0.541", "red": "0.125"}}, "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1}}

# Adds the app's own native files and a widget extension target the way Xcode's templates do:
# an embedded `.appex` built before the app, with its Info.plist only naming the extension point.
RN_NATIVE_PROJECT = """
require 'xcodeproj'
project = Xcodeproj::Project.open(ARGV[0])
app = project.targets.find { |target| target.name == 'RNNative' }
group = project.main_group['RNNative']
folder = File.join(File.dirname(project.path), 'RNNative')
sources = %w[SwiftGreeter.swift SwiftGreeter.m RCTNativeCalculator.mm].map { |name| group.new_reference(File.join(folder, name)) }
group.new_reference(File.join(folder, 'RCTNativeCalculator.h'))
app.add_file_references(sources)
widget = project.new_target(:app_extension, 'RNNativeWidget', :ios, '17.0', nil, :swift)
widget_group = project.main_group.new_group('RNNativeWidget', 'RNNativeWidget')
widget.add_file_references([widget_group.new_reference('RNNativeWidget.swift')])
widget.add_resources([widget_group.new_reference('Assets.xcassets')])
widget_group.new_reference('Info.plist')
widget.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.reactjs.native.example.RNNative.RNNativeWidget'
  settings['INFOPLIST_FILE'] = 'RNNativeWidget/Info.plist'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'RNNativeWidget'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  settings['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = 'WidgetBackground'
  settings['MARKETING_VERSION'] = '1.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['SKIP_INSTALL'] = 'YES'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end
app.add_dependency(widget)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widget.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
"""

# Pods whose source is a large download from GitHub, fetched resumably before `pod install`, which
# restarts a stalled 252 MB download from zero: (pod, version, URL, SHA-256 of the file).
PREFETCH = {"rn-libs": [("JitsiWebRTC", "155.0.0",
                         "https://github.com/jitsi/webrtc/releases/download/v155.0.0/WebRTC.xcframework.zip",
                         "bfc104ed2d3afb4285f4502aa949f1b44a0435d6e29c377094b24ed421578f59")]}

# Fills CocoaPods' download cache through its own Cache#download_pod, with the pod's file taken
# from disk instead of the network, so that `pod install` finds the pod as if it had fetched it.
SEED_CACHE = """
require 'cocoapods'
podspec, file = ARGV
spec = Pod::Specification.from_file(podspec)
Pod::Downloader::Http.send(:define_method, :download_file) { |path| FileUtils.cp(file, path) }
puts Pod::Downloader::Cache.new(Pod::Config.instance.cache_root + 'Pods').download_pod(Pod::Downloader::Request.new(spec: spec, released: true)).location
"""

RN_LIBS_APP = """import { FlashList } from '@shopify/flash-list';
import React from 'react';
import { Text, View } from 'react-native';
import { createMMKV } from 'react-native-mmkv';
import PagerView from 'react-native-pager-view';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { enableScreens } from 'react-native-screens';
import Svg, { Circle } from 'react-native-svg';
import { mediaDevices } from 'react-native-webrtc';
import { WebView } from 'react-native-webview';

enableScreens();
const storage = createMMKV();
storage.set('launches', (storage.getNumber('launches') ?? 0) + 1);

export default function App() {
  return (
    <SafeAreaProvider>
      <SafeAreaView style={{ flex: 1 }}>
        <Svg width={64} height={64}>
          <Circle cx={32} cy={32} r={24} fill="#208AEF" />
        </Svg>
        <PagerView style={{ height: 120 }} initialPage={0}>
          <View key="1"><Text>{String(storage.getNumber('launches'))}</Text></View>
          <View key="2"><Text>{typeof mediaDevices.getUserMedia}</Text></View>
        </PagerView>
        <FlashList data={['svg', 'pager', 'webview']} renderItem={({ item }) => <Text>{item}</Text>} />
        <WebView style={{ height: 120 }} source={{ html: '<p>nomac</p>' }} />
      </SafeAreaView>
    </SafeAreaProvider>
  );
}
"""


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def edit_json(path, change):
    data = json.loads(path.read_text())
    change(data)
    path.write_text(json.dumps(data, indent=2) + "\n")


def expo_modules(apps, env):
    expo.npx(env, apps, f"create-expo-app@{PINS['create-expo-app']}", "ExpoModules",
             "--template", f"expo-template-blank-typescript@{PINS['expo-template-blank-typescript']}", "--no-agents-md")
    src = apps / "ExpoModules"
    # Offline, `expo install` takes the versions of the installed `expo`'s bundledNativeModules.json;
    # online it asks Expo's API for today's, which may postdate PINS["npm-before"].
    expo.npx(dict(env, EXPO_OFFLINE="1"), src, "expo", "install", *EXPO_MODULES,
             f"@expo-google-fonts/inter@{PINS['@expo-google-fonts/inter']}")
    for name in ("App.tsx", "index.ts"):
        (src / name).unlink(missing_ok=True)
    write(src / "app" / "_layout.tsx", EXPO_LAYOUT)
    write(src / "app" / "index.tsx", EXPO_INDEX)
    write(src / "locales" / "fr.json", json.dumps({
        "CFBundleDisplayName": "Modules Expo",
        "NSCameraUsageDescription": "La caméra lit les codes.",
        "NSLocationWhenInUseUsageDescription": "La position trie les notes."}, ensure_ascii=False, indent=2) + "\n")
    edit_json(src / "package.json", lambda package: package.update(main="expo-router/entry"))

    def configure(config):
        app = config["expo"]
        app["scheme"] = "expomodules"
        app["ios"].update({
            "bundleIdentifier": "dev.nomac.ExpoModules",
            "associatedDomains": ["applinks:example.com"],
            "usesAppleSignIn": True,
            "infoPlist": {"UIBackgroundModes": ["remote-notification"], "ITSAppUsesNonExemptEncryption": False},
            "privacyManifests": {"NSPrivacyAccessedAPITypes": [{
                "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}]}})
        app["locales"] = {"fr": "./locales/fr.json"}
        app["plugins"] = [
            "expo-router",
            ["expo-splash-screen", {"backgroundColor": "#101820", "image": "./assets/splash-icon.png", "imageWidth": 120}],
            ["expo-font", {"fonts": [INTER]}],
            "expo-notifications",
            ["expo-camera", {"cameraPermission": "The camera reads codes.", "recordAudioAndroid": False}],
            ["expo-location", {"locationWhenInUsePermission": "Your location sorts notes."}],
            "expo-sqlite",
            "expo-secure-store",
            "expo-localization",
            "expo-apple-authentication",
        ]

    edit_json(src / "app.json", configure)
    expo.npx(env, src, "expo", "prebuild", "--platform", "ios", "--no-install")
    return src, "ios/ExpoModules.xcworkspace", "ExpoModules"


def rn_init(apps, env, name):
    expo.npx(env, apps, f"@react-native-community/cli@{PINS['@react-native-community/cli']}", "init", name,
             "--version", PINS["react-native"], "--skip-git-init", "--install-pods", "false", "--pm", "npm")
    return apps / name


def rn_native(apps, env):
    src = rn_init(apps, env, "RNNative")
    ios = src / "ios"
    write(ios / "RNNative" / "SwiftGreeter.swift", SWIFT_GREETER)
    write(ios / "RNNative" / "SwiftGreeter.m", SWIFT_GREETER_BRIDGE)
    write(ios / "RNNative" / "RCTNativeCalculator.h", CALCULATOR_HEADER)
    write(ios / "RNNative" / "RCTNativeCalculator.mm", CALCULATOR_IMPLEMENTATION)
    write(src / "specs" / "NativeCalculator.ts", CALCULATOR_SPEC)
    write(src / "App.tsx", RN_NATIVE_APP)
    write(ios / "RNNativeWidget" / "RNNativeWidget.swift", WIDGET)
    write(ios / "RNNativeWidget" / "Info.plist", WIDGET_INFO_PLIST)
    catalog = ios / "RNNativeWidget" / "Assets.xcassets"
    write(catalog / "Contents.json", json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for color in ("AccentColor", "WidgetBackground"):
        write(catalog / f"{color}.colorset" / "Contents.json", json.dumps(COLOR_SET, indent=2) + "\n")
    edit_json(src / "package.json", lambda package: package.update(codegenConfig={
        "name": "AppSpecs", "type": "modules", "jsSrcsDir": "specs",
        "android": {"javaPackageName": "com.rnnative.specs"},
        "ios": {"modulesProvider": {"NativeCalculator": "RCTNativeCalculator"}}}))
    podfile = ios / "Podfile"
    text = podfile.read_text()
    dynamic = ("linkage = ENV['USE_FRAMEWORKS']\nif linkage != nil\n"
               "  Pod::UI.puts \"Configuring Pod with #{linkage}ally linked Frameworks\".green\n"
               "  use_frameworks! :linkage => linkage.to_sym\nend\n")
    if dynamic not in text:
        sys.exit(f"error: {podfile} does not have the template's use_frameworks! lines")
    podfile.write_text(text.replace(dynamic, "use_frameworks! :linkage => :static\n"))
    expo.run(["ruby", "-e", RN_NATIVE_PROJECT, ios / "RNNative.xcodeproj"], ios, env)
    return src, "ios/RNNative.xcworkspace", "RNNative"


def prefetch(root, app_id, env):
    for pod, version, url, digest in PREFETCH.get(app_id, []):
        path = root / "downloads" / url.rsplit("/", 1)[1]
        path.parent.mkdir(exist_ok=True)
        if expo.sha256(path) != digest:
            expo.run(["curl", "-fsSL", "--http1.1", "--retry", "20", "--retry-all-errors", "-C", "-", "-o", path, url],
                     root, env)
        if expo.sha256(path) != digest:
            sys.exit(f"error: {path} does not have the SHA-256 of {pod} {version}'s source")
        podspec = expo.output(["pod", "spec", "which", pod, f"--version={version}"], env).splitlines()[-1]
        expo.run(["ruby", "-e", SEED_CACHE, podspec, path], root, env)


def rn_libs(apps, env):
    src = rn_init(apps, env, "RNLibs")
    expo.run(["npm", "install", "--save-exact", *(f"{name}@{PINS[name]}" for name in RN_LIBS)], src, env)
    write(src / "App.tsx", RN_LIBS_APP)
    prefetch(apps.parent, "rn-libs", env)
    return src, "ios/RNLibs.xcworkspace", "RNLibs"


APPS = {"expo-modules": (expo_modules, "ExpoModules"), "rn-native": (rn_native, "RNNative"),
        "rn-libs": (rn_libs, "RNLibs")}


def archive_app(root, app_id):
    record = json.loads((root / "apps" / f"{app_id}.json").read_text())
    src = Path(record["path"])
    developer_dir = os.environ.get("DEVELOPER_DIR") or sys.exit("error: set DEVELOPER_DIR to the reference Xcode")
    env = expo.capture.reference_environment(developer_dir)
    out = root / "refs" / "Release" / app_id
    if not (out / "summary.json").exists():
        sys.exit(f"error: capture {app_id}'s Release reference first")
    expo.reset(src, record.get("referenceCommit", record["commit"]))
    offline = expo.capture.OFFLINE
    expo.capture.OFFLINE = []
    try:
        with expo.NetworkLog(out / "archive" / "network.log"):
            expo.capture.capture_archive(expo.manifest_entry(record, "Release"), src, out, env)
    finally:
        expo.capture.OFFLINE = offline
        expo.reset(src, record["commit"])


def nm(developer_dir, *args):
    tool = Path(developer_dir) / "Toolchains/XcodeDefault.xctoolchain/usr/bin/nm"
    listing = subprocess.run([tool, *args], capture_output=True, text=True).stdout
    return {line.split()[-1] for line in listing.splitlines() if line and not line.endswith(":")}


def mangling(root, app_id, configurations):
    developer_dir = os.environ.get("DEVELOPER_DIR") or sys.exit("error: set DEVELOPER_DIR to the reference Xcode")
    for configuration in configurations:
        products = root / "refs" / configuration / app_id / "build" / "Products"
        apps = sorted(products.glob("*-iphoneos/*.app"))
        if not apps:
            expo.log(f"{app_id} {configuration}: no app in {products}")
            continue
        bundles = [bundle for app in apps for bundle in [app, *app.glob("PlugIns/*.appex")]]
        frameworks = sorted({path for bundle in bundles for path in bundle.glob("Frameworks/*.framework")})
        defined = set()
        for framework in frameworks:
            defined |= nm(developer_dir, "-gU", framework / framework.stem)
        undefined = set()
        for bundle in bundles:
            for binary in (bundle / bundle.stem, bundle / f"{bundle.stem}.debug.dylib"):
                if binary.exists():
                    undefined |= nm(developer_dir, "-u", binary)
        for library in products.glob("*-iphoneos/**/*.a"):
            undefined |= nm(developer_dir, "-u", library)
        pointing = sorted(symbol for symbol in undefined if "Xad" in symbol)
        imported = [symbol for symbol in pointing if symbol in defined]
        result = {"app": app_id, "configuration": configuration, "frameworks": [f.name for f in frameworks],
                  "frameworkSymbolsPointing": sum("Xad" in symbol for symbol in defined),
                  "undefinedPointing": len(pointing), "importedFromFrameworks": imported}
        (root / "refs" / configuration / f"{app_id}.mangling.json").write_text(json.dumps(result, indent=2) + "\n")
        expo.log(f"{app_id} {configuration}: {len(pointing)} undefined symbols with object template arguments, "
            f"{len(imported)} of them defined by {len(frameworks)} embedded frameworks")


def tool_environment(root):
    """expo_experiments.py's, with a curl configuration for CocoaPods' downloads: JitsiWebRTC's
    252 MB xcframework from GitHub timed out over HTTP/2 and downloads over HTTP/1.1 with retries."""
    env = TOOL_ENVIRONMENT(root)
    (root / "curl").mkdir(exist_ok=True)
    (root / "curl" / ".curlrc").write_text("http1.1\nretry = 10\nretry-all-errors\n")
    return dict(env, CURL_HOME=str(root / "curl"))


TOOL_ENVIRONMENT = expo.tool_environment


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["generate", "capture", "archive", "platform-packages", "verify", "mangling", "triage"])
    parser.add_argument("apps", nargs="*")
    parser.add_argument("--root", default=str(Path.home() / "nomac-out" / "wt-scratch" / "rn-holdout"))
    parser.add_argument("--configuration", action="append", dest="configurations")
    parser.add_argument("--nomac")
    parser.add_argument("--project-fixes", action="store_true", help="verify: the project's changes for Linux first")
    parser.add_argument("--keep-derived-data", action="store_true", help="verify: keep nomac's build tree")
    args = parser.parse_intermixed_args()
    if args.command == "triage":
        for log_path in args.apps:
            expo.triage(log_path)
        return
    root = Path(args.root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    expo.APPS = APPS
    expo.PINS = PINS
    expo.NESTED_SWIFTPM = set(APPS)
    expo.tool_environment = tool_environment
    configurations = args.configurations or ["Release", "Debug"]
    for app_id in args.apps or list(APPS):
        if app_id not in APPS and args.command != "mangling":
            sys.exit(f"error: no app {app_id}; the apps are {', '.join(APPS)}")
        if args.command == "generate":
            expo.generate(root, app_id)
        elif args.command == "capture":
            expo.capture_app(root, app_id, configurations)
            shutil.rmtree(root / "apps" / f"{app_id}-DerivedData", ignore_errors=True)
        elif args.command == "mangling":
            mangling(root, app_id, configurations)
        elif args.command == "archive":
            archive_app(root, app_id)
        elif args.command == "platform-packages":
            expo.add_platform_packages(root, app_id)
        else:
            nomac = str(Path(args.nomac or sys.exit("error: --nomac is required")).resolve())
            expo.verify_app(root, app_id, configurations, nomac, fixes=args.project_fixes)
            if not args.keep_derived_data:
                for configuration in configurations:
                    shutil.rmtree(root / "refs" / configuration / f"{app_id}.nomac-DerivedData", ignore_errors=True)


if __name__ == "__main__":
    main()
