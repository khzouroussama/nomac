#!/usr/bin/env python3
"""App Intents metadata: what Xcode 27.0's `appintentsmetadataprocessor` and
`appintentsnltrainingprocessor` write for self-written targets that use App Intents (B-107).

Each case is an iOS app written here (intents, entities, queries, enums, App Shortcuts) built by
xcodebuild for generic iOS without signing. For every `ExtractAppIntentsMetadata` and
`AppIntentsSSUTraining` task, <out>/<case>/ keeps the command line, the files it names that the
build wrote (the Swift compiler's `.swiftconstvalues`, the file lists, the dependency info) and
what the tool wrote (`Metadata.appintents`, the strings data), for nomac's tools to be compared
with. Nothing is kept in the repository.

Usage (DEVELOPER_DIR selects the Xcode):
  app_intents_experiments.py record <out> [case ...]
  app_intents_experiments.py compare <out> --nomac <nomac> [case ...]   nomac's tools on the recorded inputs
                                                  (training needs macOS's compression_tool)
"""

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loader_experiments as loader  # noqa: E402

INTENTS = """import AppIntents
import Foundation

enum Mood: String, AppEnum {
    case happy
    case sad

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let caseDisplayRepresentations: [Mood: DisplayRepresentation] = [
        .happy: "Happy",
        .sad: DisplayRepresentation(title: "Sad", subtitle: "Not happy"),
    ]
}

struct Note: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static let defaultQuery = NoteQuery()

    var id: String
    @Property(title: "Title")
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(title)") }
}

struct NoteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Note] { [] }
    func suggestedEntities() async throws -> [Note] { [] }
}

struct AddNote: AppIntent {
    static let title: LocalizedStringResource = "Add Note"
    static let description = IntentDescription("Adds a note.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Count", default: 1)
    var count: Int

    @Parameter(title: "Pinned")
    var pinned: Bool?

    @Parameter(title: "Mood")
    var mood: Mood

    @Parameter(title: "Parent")
    var parent: Note?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \\(\\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: text)
    }
}

struct OpenNotes: AppIntent {
    static let title: LocalizedStringResource = "Open Notes"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

struct Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddNote(), phrases: ["Add a note in \\(.applicationName)"], shortTitle: "Add Note", systemImageName: "note")
        AppShortcut(intent: OpenNotes(), phrases: ["Open \\(.applicationName)"], shortTitle: "Open", systemImageName: "folder")
    }
}
"""

APP = """import SwiftUI

@main struct NotesApp: App {
    var body: some Scene { WindowGroup { Text("Notes") } }
}
"""

QUERIES = """import AppIntents

struct Plain: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Plain"
    static let defaultQuery = PlainQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct PlainQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Plain] { [] }
}

struct Suggested: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Suggested"
    static let defaultQuery = SuggestedQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct SuggestedQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Suggested] { [] }
    func suggestedEntities() async throws -> [Suggested] { [] }
}

struct Searched: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Searched"
    static let defaultQuery = SearchedQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct SearchedQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [Searched] { [] }
    func entities(matching string: String) async throws -> [Searched] { [] }
}

struct Pick: AppIntent {
    static let title: LocalizedStringResource = "Pick"
    @Parameter(title: "Plain") var plain: Plain
    @Parameter(title: "Suggested") var suggested: Suggested
    @Parameter(title: "Searched") var searched: Searched
    func perform() async throws -> some IntentResult { .result() }
}
"""

WIDGET = """import AppIntents
import WidgetKit

struct Account: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(name)") }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Account] { [] }
    func suggestedEntities() async throws -> [Account] { [] }
}

struct Feed: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Feed"
    static let defaultQuery = FeedQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct FeedQuery: EntityQuery {
    @IntentParameterDependency<FeedConfiguration>(\\.$account)
    var account

    func entities(for identifiers: [String]) async throws -> [Feed] { [] }
    func suggestedEntities() async throws -> [Feed] { [] }
}

struct FeedConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Feed Widget"
    static let description = IntentDescription("Choose a feed")

    @Parameter(title: "Account")
    var account: Account?

    @Parameter(title: "Feed")
    var feed: Feed?

    @Parameter(title: "Tag", default: "swift")
    var tag: String
}

extension FeedConfiguration {
    static var preview: FeedConfiguration { FeedConfiguration() }
}
"""

DIALOGS = """import AppIntents
import Foundation

enum Visibility: String, AppEnum {
    case open
    case closed

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Visibility"
    static let caseDisplayRepresentations: [Visibility: DisplayRepresentation] = [.open: "Open", .closed: "Closed"]
}

struct Post: AppIntent {
    static let title: LocalizedStringResource = "Post"
    static let description = IntentDescription("Posts things")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Visibility", requestValueDialog: IntentDialog("Visibility of your post"))
    var visibility: Visibility

    @Parameter(
        title: "Images",
        description: "Images to post",
        supportedContentTypes: [.image, .jpeg, .png, .gif, .heic],
        inputConnectionBehavior: .connectToPreviousIntentResult)
    var images: [IntentFile]

    @Parameter(title: "Caption", requestValueDialog: IntentDialog("Caption for your post"))
    var caption: String?

    @Parameter(title: "Descriptions", requestValueDialog: IntentDialog("Descriptions in order"))
    var descriptions: [String]?

    @Parameter(title: "Tags", default: [])
    var tags: [String]

    func perform() async throws -> some IntentResult { .result() }
}
"""

LINKED = """import AppIntents

let summary = IntentDescription("Not an intent")
"""

TYPES = """import AppIntents
import CoreLocation
import Foundation

struct Item: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Item"
    static let defaultQuery = ItemQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct ItemQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Item] { [] }
}

struct Names: DynamicOptionsProvider {
    func results() async throws -> [String] { [] }
}

struct Types: AppIntent {
    static let title: LocalizedStringResource = "Types"

    @Parameter(title: "Ratio", default: 0.5, inclusiveRange: (0, 1))
    var ratio: Double

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "When")
    var when: Date

    @Parameter(title: "Until")
    var until: Date?

    @Parameter(title: "Step")
    var step: Int?

    @Parameter(title: "On", default: true)
    var on: Bool

    @Parameter(title: "Off", default: false)
    var off: Bool

    @Parameter(title: "Place")
    var place: CLPlacemark

    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(capitalizationType: .none, multiline: true, autocorrect: false, smartQuotes: false, smartDashes: false))
    var message: String

    @Parameter(title: "Name", optionsProvider: Names())
    var name: String?

    @Parameter(title: "Items")
    var items: [Item]?

    func perform() async throws -> some IntentResult { .result() }
}
"""

TRAINING = """import AppIntents

enum Mood: String, AppEnum {
    case happy
    case sad
    case calm

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let caseDisplayRepresentations: [Mood: DisplayRepresentation] = [
        .happy: "Happy",
        .sad: DisplayRepresentation(title: "Sad", subtitle: "Not happy"),
        .calm: "Calm",
    ]
}

struct Note: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Memo"
    static let defaultQuery = NoteQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct NoteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Note] { [] }
    func suggestedEntities() async throws -> [Note] { [] }
}

struct SetMood: AppIntent {
    static let title: LocalizedStringResource = "Set Mood"

    @Parameter(title: "Mood")
    var mood: Mood

    func perform() async throws -> some IntentResult { .result() }
}

struct OpenNote: AppIntent {
    static let title: LocalizedStringResource = "Open Note"

    @Parameter(title: "Note")
    var note: Note

    func perform() async throws -> some IntentResult { .result() }
}

struct Search: AppIntent {
    static let title: LocalizedStringResource = "Search"
    func perform() async throws -> some IntentResult { .result() }
}

struct Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetMood(), phrases: ["Set my mood to \\(\\.$mood) in \\(.applicationName)", "I feel \\(\\.$mood) with \\(.applicationName)",
                                                 "\\(.applicationName) mood"], shortTitle: "Mood", systemImageName: "face.smiling")
        AppShortcut(intent: OpenNote(), phrases: ["Open \\(\\.$note) in \\(.applicationName)"], shortTitle: "Open", systemImageName: "note")
        AppShortcut(intent: Search(), phrases: ["Search \\(.applicationName)", "Find in \\(.applicationName)"], shortTitle: "Search", systemImageName: "magnifyingglass")
    }
}
"""

RESULTS = """import AppIntents
import SwiftUI

enum Visibility: String, AppEnum {
    case direct, pub

    public static var caseDisplayRepresentations: [Visibility: DisplayRepresentation] {
        [
            .direct: "Private",
            .pub: "Public",
        ]
    }

    static var typeDisplayName: LocalizedStringResource { "Visibility" }

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Visibility"
}

enum Tab: String, AppEnum, Sendable {
    case home, settings

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tab"

    nonisolated static var caseDisplayRepresentations: [Tab: DisplayRepresentation] {
        [
            .home: .init(title: "Home"),
            .settings: .init(title: "Settings"),
        ]
    }
}

struct DialogAndSnippet: AppIntent {
    static let title: LocalizedStringResource = "Dialog and snippet"

    @Parameter(title: "Visibility")
    var visibility: Visibility

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        .result(dialog: "Done")
    }
}

struct DialogOnly: AppIntent {
    static let title: LocalizedStringResource = "Dialog only"

    @Parameter(title: "Tab")
    var tab: Tab

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Done")
    }
}

struct SnippetOnly: AppIntent {
    static let title: LocalizedStringResource = "Snippet only"

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: Text("Done"))
    }
}

struct ValueAndDialog: AppIntent {
    static let title: LocalizedStringResource = "Value and dialog"

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        .result(value: "x", dialog: "Done")
    }
}

struct OpensAnother: AppIntent {
    static let title: LocalizedStringResource = "Opens another"

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: DialogOnly())
    }
}
"""

CONTROLS = """import AppIntents

struct Device: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Device"
    static let defaultQuery = DeviceQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct DeviceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [Device] { [] }
    func entities(matching string: String) async throws -> [Device] { [] }
    func suggestedEntities() async throws -> [Device] { [] }
}

@available(iOS 18, *)
struct RunConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = .init("widgets.run.title", defaultValue: "Run Script")

    @Parameter(title: .init("intents.device.title", defaultValue: "Device"))
    var device: Device?

    @Parameter(
        title: LocalizedStringResource("intents.notify.title", defaultValue: "Notify when run"),
        description: LocalizedStringResource("intents.notify.description", defaultValue: "Shows a notification"),
        default: true
    )
    var notify: Bool

    @Parameter(title: .init("intents.text.title", defaultValue: "Display Text"))
    var text: String?
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct SwitchIntent: SetValueIntent {
    static var title: LocalizedStringResource = .init("intents.switch.title", defaultValue: "Control switch")

    @Parameter(title: .init("intents.switch.device", defaultValue: "Switch"))
    var device: Device

    @Parameter(title: .init("intents.switch.target", defaultValue: "Target state"))
    var value: Bool

    @Parameter(title: .init("intents.switch.toggle", defaultValue: "Toggle"), default: false)
    var toggle: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Done")
    }
}

@available(macOS 13.0, watchOS 9.4, *)
struct UpdateIntent: AppIntent, CustomIntentMigratedAppIntent {
    static let intentClassName = "UpdateSensorsIntent"

    static var title: LocalizedStringResource = .init("intents.update.title", defaultValue: "Update sensors")

    static var description = IntentDescription(.init("intents.update.description", defaultValue: "Send a sensor update"))

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: "")
    }
}
"""

SUMMARIES = """import AppIntents

enum Source: String, AppEnum {
    case entity, complication, other

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Source"
    static let caseDisplayRepresentations: [Source: DisplayRepresentation] = [
        .entity: "Entity",
        .complication: "Complication",
        .other: "Other",
    ]
}

struct CreateEvent: AppIntent {
    static let title: LocalizedStringResource = "Create event"

    static var parameterSummary: some ParameterSummary {
        When(\\.$isAllDay, .equalTo, true) {
            Summary {
                \\.$summary
                \\.$isAllDay
            }
        } otherwise: {
            Summary {
                \\.$summary
                \\.$isAllDay
                \\.$start
            }
        }
    }

    @Parameter(title: "Summary")
    var summary: String

    @Parameter(title: "All day", default: false)
    var isAllDay: Bool

    @Parameter(title: "Start")
    var start: Date?

    func perform() async throws -> some IntentResult { .result() }
}

struct Details: AppIntent {
    static let title: LocalizedStringResource = "Details"

    static var parameterSummary: some ParameterSummary {
        Switch(\\.$source) {
            Case(.entity) {
                When(\\Details.$runScript, .equalTo, true) {
                    Summary {
                        \\.$source
                        \\.$text

                        \\.$runScript
                        \\.$script
                    }
                } otherwise: {
                    Summary {
                        \\.$source
                        \\.$text
                        \\.$runScript
                    }
                }
            }
            Case(.complication) {
                Summary {
                    \\.$source
                    \\.$runScript
                }
            }
            DefaultCase {
                Summary("Show \\(\\.$source)") {
                    \\.$text
                }
            }
        }
    }

    @Parameter(title: "Source", default: .entity)
    var source: Source

    @Parameter(title: "Text")
    var text: String?

    @Parameter(title: "Run script", default: false)
    var runScript: Bool

    @Parameter(title: "Script")
    var script: String?

    func perform() async throws -> some IntentResult { .result() }
}
"""

ENTITIES = """import AppIntents
import CoreSpotlight
import Foundation

enum Domain: String, AppEnum {
    case light, cover

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Domain"
    static let caseDisplayRepresentations: [Domain: DisplayRepresentation] = [.light: "Light", .cover: "Cover"]
}

struct Item: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Item"
    static let defaultQuery = ItemQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct ItemQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [Item] { [] }
    func entities(matching string: String) async throws -> [Item] { [] }
    func suggestedEntities() async throws -> [Item] { [] }
}

struct EntityState: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: .init("intents.state.name", defaultValue: "Entity State")
    )

    @Property(title: .init("intents.state.title", defaultValue: "State"))
    var state: String

    @Property(title: .init("intents.state.unit", defaultValue: "Unit"))
    var unit: String?

    @Property(title: .init("intents.state.active", defaultValue: "Is active"))
    var isActive: Bool

    @Property(title: .init("intents.state.changed", defaultValue: "Last changed"))
    var lastChanged: Date

    @Property(title: "Link")
    var link: URL?

    @Property(title: "Count")
    var count: Int

    @Property(title: "Level")
    var level: Double

    @Property(title: "Tags")
    var tags: [String]

    @Property(title: "Domain")
    var domain: Domain

    @Property(title: "Item")
    var item: Item?

    init() {}

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(state)") }
}

@available(iOS 17, *)
struct Place: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Place"
    static let defaultQuery = PlaceQuery()
    var id: String

    @Property(title: .init("intents.place.name", defaultValue: "Name"))
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(name)") }
}

@available(iOS 17, *)
struct PlaceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Place] { [] }
    func suggestedEntities() async throws -> [Place] { [] }
}

@available(iOS 18.0, *)
extension Place: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet { defaultAttributeSet }
}

struct ShowDetails: OpenIntent {
    static var title: LocalizedStringResource = .init("intents.show.title", defaultValue: "Show details")

    @Parameter(title: "Item")
    var target: Item

    func perform() async throws -> some IntentResult { .result() }
}

struct ReadState: AppIntent {
    static var title: LocalizedStringResource = "Read state"

    func perform() async throws -> some IntentResult & ReturnsValue<EntityState> {
        .result(value: EntityState())
    }
}
"""

SESSIONS = """import AppIntents
import Foundation

struct Script: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Script"
    static let defaultQuery = ScriptQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct ScriptQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [Script] { [] }
    func entities(matching string: String) async throws -> [Script] { [] }
    func suggestedEntities() async throws -> [Script] { [] }
}

@available(iOS 16.1, *)
struct PauseTrack: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause GPX"
    static let description = IntentDescription("Pause recording GPX tracks.")

    public init() {}

    func perform() async throws -> some IntentResult { .result() }
}

struct FocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = .init("intents.focus.title", defaultValue: "Report Focus name")
    static let description = IntentDescription(.init("intents.focus.description", defaultValue: "Reports the Focus name"))
    static let isDiscoverable = false

    @Parameter(title: .init("intents.focus.name", defaultValue: "Focus name"))
    var script: Script?

    var displayRepresentation: DisplayRepresentation { "Focus" }

    func perform() async throws -> some IntentResult { .result() }
}

extension FocusFilter: LiveActivityIntent {}

struct Scripts: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Scripts"
    static var isDiscoverable: Bool = false

    @Parameter(
        title: "Scripts",
        size: [
            .systemSmall: 3,
            .systemMedium: 6,
            .systemLarge: 12,
            .systemExtraLarge: 20,
            .accessoryInline: 1,
            .accessoryCorner: 1,
            .accessoryCircular: 1,
            .accessoryRectangular: 2,
        ]
    )
    var scripts: [Script]?
}

struct CreateEvent: AppIntent {
    static let title: LocalizedStringResource = "Create event"

    @Parameter(title: "Starts", kind: .dateTime)
    var start: Date?

    @Parameter(title: "Day", kind: .date)
    var day: Date

    func perform() async throws -> some IntentResult { .result() }
}
"""

SWEEP = """import AppIntents
import Foundation
import SwiftUI

struct Currency: AppEntity, Hashable, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Currency"
    static var defaultQuery = CurrencyQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct CurrencyQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Currency] { [] }
    func suggestedEntities() async throws -> [Currency] { [] }
}

struct Rate: AppIntent {
    static let title: LocalizedStringResource = "Market Rate"
    static let description = IntentDescription("View the current market rate.")
    static let openAppWhenRun = false

    @Parameter(title: "Currency", description: "Choose your preferred currency.")
    var currency: Currency?

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog & ShowsSnippetView {
        .result(value: 1, dialog: "Rate", view: Text("Rate"))
    }
}

@available(iOS 18.0, visionOS 2.0, *)
private struct SendIntent: AppIntent {
    static let title = LocalizedStringResource("APP_SHORTCUT_SEND", table: "InfoPlist")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "app://send")!))
    }
}

@available(iOS 16.4, visionOS 1.0, *)
struct Shortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        let rate = AppShortcut(
            intent: Rate(),
            phrases: [
                "Get the rate with ${applicationName}",
                "Get the rate in \\(\\.$currency) with ${applicationName}",
            ],
            shortTitle: "Rate",
            systemImageName: "dollarsign.circle"
        )

        if #available(iOS 18.0, visionOS 2.0, *) {
            return [
                rate,
                AppShortcut(
                    intent: SendIntent(),
                    phrases: ["Send with \\(.applicationName)"],
                    shortTitle: LocalizedStringResource("APP_SHORTCUT_SEND", table: "InfoPlist"),
                    systemImageName: "paperplane"
                ),
            ]
        } else {
            return [rate]
        }
    }
}

struct WidgetReload: AppIntent {
    static var title: LocalizedStringResource = "Reload widget"
    static var isDiscoverable: Bool = false
    @Parameter(title: "source")
    var source: String?

    init() {}
    init(source: String?) {
        self.source = source
    }

    func perform() async throws -> some IntentResult { .result() }
}

@available(iOS 16.0, *)
struct WidgetInteraction: AppIntent {
    static var title: LocalizedStringResource = "User Interaction"
    static var isDiscoverable: Bool = false
    @Parameter(title: "source")
    var source: String?
    @Parameter(title: "entryIndex")
    var entryIndex: Int?

    init() {}

    func perform() async throws -> some IntentResult { .result() }
}
"""

MORE = """import AppIntents
import Foundation

@available(iOS 17, *)
enum Level: String, AppEnum {
    case low, high

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Level"
    static let caseDisplayRepresentations: [Level: DisplayRepresentation] = [.low: "Low", .high: "High"]
}

struct Note: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static let defaultQuery = NoteQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct NoteQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [Note] { [] }
    func entities(matching string: String) async throws -> [Note] { [] }
    func suggestedEntities() async throws -> [Note] { [] }
}

struct DeleteNotes: DeleteIntent {
    static let title: LocalizedStringResource = "Delete notes"

    @Parameter(title: "Notes")
    var entities: [Note]

    func perform() async throws -> some IntentResult { .result() }
}

@available(iOS 17, *)
struct Values: AppIntent {
    static let title: LocalizedStringResource = "Values"

    @Parameter(title: "Link")
    var link: URL

    @Parameter(title: "Count", default: 5, inclusiveRange: (1, 10))
    var count: Int

    @Parameter(title: "Distance")
    var distance: Measurement<UnitLength>?

    @Parameter(title: "Level", default: .low)
    var level: Level

    func perform() async throws -> some IntentResult & ReturnsValue<URL> { .result(value: link) }
}
"""

PHRASES = """import AppIntents

enum Mood: String, AppEnum {
    case happy, sad

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let caseDisplayRepresentations: [Mood: DisplayRepresentation] = [.happy: "Happy", .sad: "Sad"]
}

enum Place: String, AppEnum {
    case home, work

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Place"
    static let caseDisplayRepresentations: [Place: DisplayRepresentation] = [.home: "Home", .work: "Work"]
}

struct Log: AppIntent {
    static let title: LocalizedStringResource = "Log"

    @Parameter(title: "Mood")
    var mood: Mood

    @Parameter(title: "Place")
    var place: Place

    func perform() async throws -> some IntentResult { .result() }
}

struct Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: Log(), phrases: ["Log \\(\\.$mood) in \\(.applicationName)", "Log at \\(\\.$place) in \\(.applicationName)"],
                    shortTitle: "Log", systemImageName: "pencil")
    }
}
"""

QUOTING = """import AppIntents

enum Kind: String, AppEnum {
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kind"
    static let caseDisplayRepresentations: [Kind: DisplayRepresentation] = [
        .a: "Note: daily", .b: "Tag #1", .c: "- dash", .d: "123", .e: "true", .f: "@home",
        .g: "100%", .h: "[list]", .i: "{set}", .j: "Say \\"hi\\"", .k: "Café", .l: "back\\\\slash", .m: "*star", .n: "null",
    ]
}

struct Log: AppIntent {
    static let title: LocalizedStringResource = "Log: today's #1 entry"

    @Parameter(title: "Kind")
    var kind: Kind

    func perform() async throws -> some IntentResult { .result() }
}

struct Ask: AppIntent {
    static let title: LocalizedStringResource = "What's new?"
    func perform() async throws -> some IntentResult { .result() }
}

struct Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: Log(), phrases: ["Log a \\(\\.$kind) in \\(.applicationName)", "What's my \\(\\.$kind) in \\(.applicationName)"],
                    shortTitle: "Log", systemImageName: "pencil")
        AppShortcut(intent: Ask(), phrases: ["What's new in \\(.applicationName)?", "Ask \\(.applicationName): \\"news\\" #now"],
                    shortTitle: "Ask", systemImageName: "questionmark")
    }
}
"""

COMMENTS = """import AppIntents
import Foundation

struct AddFeed: AppIntent {
    static let title: LocalizedStringResource = "Add Feed"
    static let description = IntentDescription("Adds a feed.")
    static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource("URL", comment: "Label for a feed URL"))
    var url: URL

    @Parameter(title: "Account", optionsProvider: AccountNames())
    var accountName: String?

    @Parameter(title: LocalizedStringResource("Folder", comment: "Label for choosing the folder"), optionsProvider: FolderNames())
    var folderName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \\(\\.$url) to \\(\\.$accountName)") {
            \\.$folderName
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog { .result(dialog: "Added") }
}

struct AccountNames: DynamicOptionsProvider {
    func results() async throws -> [String] { [] }
}

struct FolderNames: DynamicOptionsProvider {
    @IntentParameterDependency<AddFeed>(\\.$accountName)
    var addFeed

    func results() async throws -> [String] { [] }
}
"""

CASES = {
    # An app with an intent of every common parameter kind, an entity and its query, an enum and
    # App Shortcuts.
    "basic": {"App.swift": APP, "Intents.swift": INTENTS},
    # The same app without App Shortcuts.
    "no-shortcuts": {"App.swift": APP, "Intents.swift": INTENTS[:INTENTS.index("struct Shortcuts")]},
    # Entities whose queries implement different requirements.
    "queries": {"App.swift": APP, "Intents.swift": QUERIES},
    # A widget configuration intent (icecubes' widget extension's forms): entity and string
    # parameters, a static computed property, a query depending on the intent's parameter.
    "widget": {"App.swift": APP, "Intents.swift": WIDGET},
    # icecubes' app intent forms: request dialogs, a description, files with content types and an
    # input connection, arrays of strings.
    "dialogs": {"App.swift": APP, "Intents.swift": DIALOGS},
    # An app that links App Intents and declares none of their types.
    "linked": {"App.swift": APP, "Intents.swift": LINKED},
    # home-assistant's parameter forms: Double with a default and a range, Date, optional Int,
    # Bool defaults, a placemark, String input options, an options provider, entity arrays.
    "types": {"App.swift": APP, "Intents.swift": TYPES},
    # An app with an intent that embeds a WidgetKit extension with a configuration intent
    # (icecubes' app and widgets): the app's task lists the extension's metadata.
    "embedded": {},
    # App Shortcuts with several phrases each, enum and entity parameters in phrases (the entity
    # displayed under another name), and a display name with an apostrophe: the training inputs and outputs.
    "training": {"App.swift": APP, "Intents.swift": TRAINING},
    # icecubes' result types (a dialog, a snippet view, both, with a value, opening an intent) and
    # its enums' forms (computed and nonisolated case representations, an own typeDisplayName).
    "results": {"App.swift": APP, "Intents.swift": RESULTS},
    # home-assistant's control widget forms: a control configuration intent, a set-value intent, a
    # migrated custom intent, `@available` annotations and titles with default values.
    "controls": {"App.swift": APP, "Intents.swift": CONTROLS},
    # home-assistant's parameter summaries: `When` with `otherwise`, `Switch` with cases, a default
    # case and nested `When`, `Summary` blocks listing parameters.
    "summaries": {"App.swift": APP, "Intents.swift": SUMMARIES},
    # home-assistant's entity forms: a transient entity with properties of many types, an indexed
    # entity and its query with `@available`, an open intent, an intent returning an entity.
    "entities": {"App.swift": APP, "Intents.swift": ENTITIES},
    # gomap's live activity intents, home-assistant's focus filter (a live activity intent too, by
    # an extension), a widget configuration's array sized by widget family, dates by kind.
    "sessions": {"App.swift": APP, "Intents.swift": SESSIONS},
    # The RN sweep's forms: expo-widgets' non-discoverable intents, bluewallet's titles from the
    # InfoPlist table, visionOS availability, private intents, and App Shortcuts returned by a
    # computed property behind `if #available`.
    "sweep": {"App.swift": APP, "Intents.swift": SWEEP},
    # B-159's remaining parameter forms: a URL, an Int range, a measurement, an enum with
    # `@available`, a delete intent.
    "more": {"App.swift": APP, "Intents.swift": MORE},
    # A watch app and a static library without App Intents (`watch_project`): arm64_32 binaries.
    "watch": {},
    # An app including a framework's `AppIntentsPackage` (`package_project`).
    "package": {},
    # An app intent with parameters and a result of a framework's entity and enum (`package_project`).
    "dependency": {},
    # One App Shortcut whose phrases use different parameters.
    "phrases": {"App.swift": APP, "Intents.swift": PHRASES},
    # YAML's special characters in titles, synonyms and phrases (bluewallet's "What's …").
    "quoting": {"App.swift": APP, "Intents.swift": QUOTING},
    # netnewswire's intent: titles with translator comments, options providers, one depending on
    # a parameter.
    "comments": {"App.swift": APP, "Intents.swift": COMMENTS},
    # `training`'s app localized (`localized_project`): which locales are trained, with which
    # phrase lists, and which translations they take.
    "localized": {},
}

SETTINGS = {"training": {"INFOPLIST_KEY_CFBundleDisplayName": '"Mike\'s Notes"'}, "controls": {"SWIFT_VERSION": "5.0"}, "entities": {"SWIFT_VERSION": "5.0"}, "sessions": {"SWIFT_VERSION": "5.0"}, "sweep": {"SWIFT_VERSION": "5.0"}}


def project(files, extra=None):
    """An iOS app target compiling `files`, its sources in one group."""
    names = sorted(name for name in files if name.endswith(".swift"))
    objects = "".join(f'\t\tA1{index:022d} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = A2{index:022d} /* {name} */; }};\n'
                      f'\t\tA2{index:022d} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n'
                      for index, name in enumerate(names))
    children = "".join(f"\t\t\t\tA2{index:022d} /* {name} */,\n" for index, name in enumerate(names))
    phase = "".join(f"\t\t\t\tA1{index:022d} /* {name} in Sources */,\n" for index, name in enumerate(names))
    objects += f"""		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{children}				P00000000000000000000001,
			);
			sourceTree = "<group>";
		}};
		F00000000000000000000004 /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{phase}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
    settings = {**loader.APP_SETTINGS, "SWIFT_VERSION": "6.0", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", **(extra or {})}
    objects += loader.product_file("P00000000000000000000001", "App", loader.APPLICATION)
    objects += loader.app_target("C00000000000000000000001", "App", ["F00000000000000000000004 /* Sources */"],
                                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], settings,
                                 product_reference="P00000000000000000000001")
    return loader.project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001 /* App */"], objects)


EXTENSION_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
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

WIDGETS = """import AppIntents
import SwiftUI
import WidgetKit

struct Account: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Account] { [] }
    func suggestedEntities() async throws -> [Account] { [] }
}

struct Configuration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account Widget"
    static let description = IntentDescription("Choose an account")

    @Parameter(title: "Account")
    var account: Account?
}

struct Entry: TimelineEntry {
    let date: Date
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func snapshot(for configuration: Configuration, in context: Context) async -> Entry { Entry(date: .now) }
    func timeline(for configuration: Configuration, in context: Context) async -> Timeline<Entry> { Timeline(entries: [], policy: .never) }
}

struct AccountWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "account", intent: Configuration.self, provider: Provider()) { _ in Text("Account") }
    }
}

@main struct Widgets: WidgetBundle {
    var body: some Widget { AccountWidget() }
}
"""

APP_INTENT = """import AppIntents

struct Refresh: AppIntent {
    static let title: LocalizedStringResource = "Refresh"
    func perform() async throws -> some IntentResult { .result() }
}
"""


def embedding_project():
    """`embedded`: an app with an intent that embeds a WidgetKit extension with a configuration intent."""
    targets = loader.Targets()
    app, _ = targets.add("App", loader.APPLICATION, {"SWIFT_VERSION": "6.0", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment"})
    widgets, product = targets.add("Widgets", loader.APPEX, {"SWIFT_VERSION": "6.0", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "GENERATE_INFOPLIST_FILE": "YES",
                                                             "INFOPLIST_FILE": "Widgets/Info.plist", "SKIP_INSTALL": "YES",
                                                             "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment.widgets", "PRODUCT_NAME": '"$(TARGET_NAME)"'})
    targets.embed(app, product, "Widgets")
    targets.depend(app, widgets, "Widgets")
    children = ""
    for index, (target, paths) in enumerate(((app, ["App.swift", "AppIntent.swift"]), (widgets, ["Widgets/Widgets.swift"]))):
        phase = f"W{index:023d}"
        files = ""
        for number, path in enumerate(paths):
            build, reference = f"Y{index}{number:022d}", f"Z{index}{number:022d}"
            targets.objects += (f'\t\t{build} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n'
                                f'\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {loader.pbx_string(path)}; sourceTree = "<group>"; }};\n')
            files += f"\t\t\t\t{build},\n"
            children += f"\t\t\t\t{reference},\n"
        targets.objects += f"\t\t{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\n{files}\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};\n"
        targets.phases[target].insert(0, phase)
    return targets.project({"App.swift": APP, "AppIntent.swift": APP_INTENT, "Widgets/Widgets.swift": WIDGETS, "Widgets/Info.plist": EXTENSION_PLIST},
                           group_children=children)


LOCALES = ["en", "en-GB", "en-AU", "de", "de-CH", "es", "es-MX", "fr", "fr-CA", "it", "ja", "ko", "nb", "nl", "pt", "pt-BR", "pt-PT",
           "tr", "da", "fi", "ms", "ru", "sv", "th", "zh-Hans", "zh-Hant", "zh-HK", "ca", "pl", "uk"]


def localized_project():
    """`localized`: `training`'s app with its sources and a `.lproj` folder per locale of `LOCALES`
    and Base in a synchronized folder: `de` translates a phrase (`AppShortcuts.strings`), an enum
    case title (`Localizable.strings`) and the display name (`InfoPlist.strings`), `fr` a phrase
    in `Localizable.strings`."""
    targets = loader.Targets()
    app, _ = targets.add("App", loader.APPLICATION, {"SWIFT_VERSION": "6.0", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment",
                                                      "INFOPLIST_KEY_CFBundleDisplayName": '"Mike\'s Notes"'})
    for index, isa in enumerate((loader.SOURCES, loader.RESOURCES)):
        phase = f"W{index:023d}"
        targets.objects += loader.pbx_object(phase, isa, {"buildActionMask": "2147483647", "files": "(\n\t\t\t)", "runOnlyForDeploymentPostprocessing": "0"})
        targets.phases[app].append(phase)
    targets.synchronized = {app: ["S00000000000000000000001"]}
    targets.objects += '\t\tS00000000000000000000001 = {isa = PBXFileSystemSynchronizedRootGroup; path = App; sourceTree = "<group>"; };\n'
    files = {"App/App.swift": APP, "App/Intents.swift": TRAINING}
    for locale in LOCALES + ["Base"]:
        files[f"App/{locale}.lproj/Localizable.strings"] = '"Hello" = "Hello";\n'
    files["App/de.lproj/AppShortcuts.strings"] = '"Search ${applicationName}" = "Suche in ${applicationName}";\n'
    files["App/de.lproj/Localizable.strings"] = '"Hello" = "Hallo";\n"Happy" = "Froh";\n'
    files["App/de.lproj/InfoPlist.strings"] = '"CFBundleDisplayName" = "Notizen";\n'
    files["App/fr.lproj/Localizable.strings"] = '"Hello" = "Bonjour";\n"Find in ${applicationName}" = "Trouver dans ${applicationName}";\n'
    return targets.project(files, group_children="\t\t\t\tS00000000000000000000001,\n", known_regions=[loader.pbx_string(locale) for locale in LOCALES + ["Base"]])


def watch_project():
    """`watch`: a standalone watch app with an intent that depends on a Swift static library
    without App Intents, built for watchOS (arm64 and arm64_32)."""
    targets = loader.Targets()
    common = {"SDKROOT": "watchos", "SWIFT_VERSION": "6.0", "WATCHOS_DEPLOYMENT_TARGET": "11.0", "SUPPORTED_PLATFORMS": '"watchos watchsimulator"'}
    app, _ = targets.add("App", loader.APPLICATION, {**common, "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment", "GENERATE_INFOPLIST_FILE": "YES",
                                                     "INFOPLIST_KEY_WKApplication": "YES", "INFOPLIST_KEY_WKWatchOnly": "YES"}, sdk="watchos")
    library, _ = targets.add("Helpers", loader.STATIC_LIBRARY, {**common, "PRODUCT_NAME": '"$(TARGET_NAME)"'}, sdk="watchos")
    targets.depend(app, library, "Helpers")
    children = ""
    for index, (target, paths) in enumerate(((app, ["App.swift", "Intents.swift"]), (library, ["Helpers.swift"]))):
        phase = f"W{index:023d}"
        files = ""
        for number, path in enumerate(paths):
            build, reference = f"Y{index}{number:022d}", f"Z{index}{number:022d}"
            targets.objects += (f'\t\t{build} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n'
                                f'\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path}; sourceTree = "<group>"; }};\n')
            files += f"\t\t\t\t{build},\n"
            children += f"\t\t\t\t{reference},\n"
        targets.objects += f"\t\t{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\n{files}\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};\n"
        targets.phases[target].insert(0, phase)
    return targets.project({"App.swift": APP, "Intents.swift": APP_INTENT, "Helpers.swift": "public func helper() -> Int { 1 }\n"}, group_children=children)


KIT = """import AppIntents

public struct KitIntent: AppIntent {
    public static let title: LocalizedStringResource = "Kit intent"

    public init() {}

    public func perform() async throws -> some IntentResult { .result() }
}

public struct KitPackage: AppIntentsPackage {}
"""

APP_PACKAGE = """import AppIntents
import Kit

struct AppIntentInApp: AppIntent {
    static let title: LocalizedStringResource = "App intent"

    func perform() async throws -> some IntentResult { .result() }
}

struct AppPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [KitPackage.self] }
}
"""


KIT_TYPES = """import AppIntents

public enum Flavor: String, AppEnum {
    case sweet, sour

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Flavor"
    public static let caseDisplayRepresentations: [Flavor: DisplayRepresentation] = [.sweet: "Sweet", .sour: "Sour"]
}

public struct Fruit: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fruit"
    public static let defaultQuery = FruitQuery()
    public var id: String
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\\(id)") }
    public init(id: String) { self.id = id }
}

public struct FruitQuery: EntityQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [Fruit] { [] }
    public func suggestedEntities() async throws -> [Fruit] { [] }
}

public struct KitPackage: AppIntentsPackage {}
"""

APP_TYPES = """import AppIntents
import Kit

struct Eat: AppIntent {
    static let title: LocalizedStringResource = "Eat"

    @Parameter(title: "Fruit")
    var fruit: Fruit

    @Parameter(title: "Flavor", default: .sweet)
    var flavor: Flavor

    func perform() async throws -> some IntentResult & ReturnsValue<Fruit> { .result(value: fruit) }
}

struct AppPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [KitPackage.self] }
}
"""


def package_project(kit_source=None, app_source=None):
    """`package`: an app that links and embeds a framework with an intent and an
    `AppIntentsPackage`, and includes that package in its own; `dependency`: the same with the
    framework's entity and enum used by the app's intent."""
    targets = loader.Targets()
    common = {"SWIFT_VERSION": "6.0", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"}
    app, _ = targets.add("App", loader.APPLICATION, {**common, "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment"})
    kit, product = targets.add("Kit", loader.FRAMEWORK, {**common, "GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.experiment.kit",
                                                         "PRODUCT_NAME": '"$(TARGET_NAME)"', "SKIP_INSTALL": "YES", "DEFINES_MODULE": "YES"})
    targets.depend(app, kit, "Kit")
    targets.objects += f"""\t\tV0000000000000000000000L = {{isa = PBXBuildFile; fileRef = {product}; }};
\t\tV0000000000000000000000E = {{isa = PBXBuildFile; fileRef = {product}; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};
\t\tV000000000000000000000PL = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (V0000000000000000000000L, ); runOnlyForDeploymentPostprocessing = 0; }};
\t\tV000000000000000000000PE = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 10; files = (V0000000000000000000000E, ); name = "Embed Frameworks"; runOnlyForDeploymentPostprocessing = 0; }};
"""
    targets.phases[app] += ["V000000000000000000000PL", "V000000000000000000000PE"]
    children = ""
    for index, (target, paths) in enumerate(((app, ["App.swift", "AppIntents.swift"]), (kit, ["Kit/Kit.swift"]))):
        phase = f"W{index:023d}"
        files = ""
        for number, path in enumerate(paths):
            build, reference = f"Y{index}{number:022d}", f"Z{index}{number:022d}"
            targets.objects += (f'\t\t{build} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n'
                                f'\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {loader.pbx_string(path)}; sourceTree = "<group>"; }};\n')
            files += f"\t\t\t\t{build},\n"
            children += f"\t\t\t\t{reference},\n"
        targets.objects += f"\t\t{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\n{files}\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};\n"
        targets.phases[target].insert(0, phase)
    return targets.project({"App.swift": APP, "AppIntents.swift": app_source or APP_PACKAGE, "Kit/Kit.swift": kit_source or KIT}, group_children=children)


DESTINATIONS = {"watch": "generic/platform=watchOS"}


TASKS = ("ExtractAppIntentsMetadata", "AppIntentsSSUTraining")


def tasks(log):
    """The (kind, working directory, argv) of each App Intents task in an xcodebuild log."""
    found = []
    for block in log.split("\n\n"):
        lines = block.splitlines()
        if not lines or not lines[0].startswith(TASKS):
            continue
        cwd = next((line.strip()[3:] for line in lines if line.strip().startswith("cd ")), None)
        command = next((line.strip() for line in lines[1:] if "appintents" in line and not line.strip().startswith(("cd ", "export "))), None)
        if command:
            found.append((lines[0].split()[0], cwd, shlex.split(command)))
    return found


def record(out, name, developer):
    case = out / name
    shutil.rmtree(case, ignore_errors=True)
    src = case / "src"
    files = embedding_project() if name == "embedded" else localized_project() if name == "localized" else watch_project() if name == "watch" else package_project() if name == "package" else package_project(KIT_TYPES, APP_TYPES) if name == "dependency" else {**CASES[name], "P.xcodeproj/project.pbxproj": project(CASES[name], SETTINGS.get(name))}
    for path, text in files.items():
        (src / path).parent.mkdir(parents=True, exist_ok=True)
        (src / path).write_text(text)
    derived = case / "DerivedData"
    env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"], "DEVELOPER_DIR": developer, "LANG": "en_US.UTF-8"}
    proc = subprocess.run(["xcodebuild", "-project", "P.xcodeproj", "-scheme", "App", "-configuration", "Release", "-destination", DESTINATIONS.get(name, "generic/platform=iOS"),
                           "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "build"], cwd=src, env=env, capture_output=True, text=True)
    (case / "build.log").write_text(proc.stdout + proc.stderr)
    recorded = []
    for index, (kind, cwd, argv) in enumerate(tasks(proc.stdout)):
        task = case / f"{index}-{kind}"
        inputs = task / "inputs"
        files = {}
        for argument in argv:
            path = Path(argument)
            if path.is_absolute() and str(path).startswith(str(derived)) and path.exists():
                files[argument] = path
                if path.suffix in (".SwiftConstValuesFileList", ".DependencyMetadataFileList", ".DependencyStaticMetadataFileList", ".LinkFileList"):
                    for line in path.read_text().splitlines():
                        if line and Path(line).exists():
                            files[line] = Path(line)
        for original, path in files.items():
            target = inputs / original.lstrip("/")
            target.parent.mkdir(parents=True, exist_ok=True)
            if path.is_dir():
                shutil.copytree(path, target, dirs_exist_ok=True)
            else:
                shutil.copy(path, target)
        (task / "command.json").write_text(json.dumps({"kind": kind, "cwd": cwd, "argv": argv}, indent=2) + "\n")
        recorded.append(kind)
    print(f"{name}: xcodebuild exit {proc.returncode}, tasks {recorded}")


def unordered(value):
    """`extract.actionsdata` with what Xcode writes in set order (`resolvableInputTypes`, and the
    key and value pairs of `typeSpecificMetadata`, whose order changes from build to build of the
    same target) sorted."""
    if isinstance(value, dict):
        def sort(key, item):
            if key == "resolvableInputTypes":
                return sorted((unordered(v) for v in item), key=json.dumps)
            if key == "typeSpecificMetadata" and len(item) % 2 == 0:
                return sorted(([unordered(item[i]), unordered(item[i + 1])] for i in range(0, len(item), 2)), key=json.dumps)
            return unordered(item)
        return {key: sort(key, item) for key, item in value.items()}
    if isinstance(value, list):
        return [unordered(item) for item in value]
    return value


def ssu_blocks(text):
    """root.ssu.yaml with what Xcode writes in set order (the parameter variables, and the locales
    of each corpus and of each variable's definitions) in one order."""
    lines = text.rstrip("\n").split("\n")
    indent = lambda line: len(line) - len(line.lstrip(" "))
    def canonical(lines):
        out, i = [], 0
        while i < len(lines):
            line = lines[i]
            if not line.lstrip(" ").startswith("- "):
                out.append(line)
                i += 1
                continue
            depth, items = indent(line), []
            while i < len(lines) and indent(lines[i]) == depth and lines[i].lstrip(" ").startswith("- "):
                j = i + 1
                while j < len(lines) and indent(lines[j]) > depth:
                    j += 1
                items.append([lines[i]] + canonical(lines[i + 1:j]))
                i = j
            heads = [item[0].lstrip(" ") for item in items]
            if all(head.startswith("- locale: ") for head in heads) or (depth == 0 and all(head.startswith("- name: ") for head in heads)):
                items.sort(key="\n".join)
            out += [line for item in items for line in item]
        return out
    return canonical(lines)


def compare(out, name, nomac):
    case = out / name
    verdicts = []
    for task in sorted(case.glob("*-ExtractAppIntentsMetadata")):
        command = json.loads((task / "command.json").read_text())
        argv = command["argv"]
        options = {argv[i]: argv[i + 1] for i in range(1, len(argv) - 1) if argv[i].startswith("--") and not argv[i + 1].startswith("--")}
        scratch = task / "nomac"
        shutil.rmtree(scratch, ignore_errors=True)
        bundle = scratch / Path(options["--output"]).name
        bundle.mkdir(parents=True)
        if (Path(options["--output"]) / "Info.plist").exists():
            shutil.copy(Path(options["--output"]) / "Info.plist", bundle / "Info.plist")
        replaced = {"--output": str(bundle), "--stringsdata-file": str(scratch / "strings.stringsdata")}
        arguments = [replaced.get(argv[i - 1], a) if i > 0 else a for i, a in enumerate(argv)][1:]
        proc = subprocess.run([nomac, "appintentsmetadataprocessor", *arguments], cwd=command["cwd"], capture_output=True, text=True)
        if proc.returncode != 0:
            verdicts.append(f"{task.name}: nomac exit {proc.returncode}: {proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else ''}")
            continue
        xcode = Path(options["--output"]) / "Metadata.appintents"
        mine = bundle / "Metadata.appintents"
        results = []
        # root.ssu.yaml and nlu/ are the training's.
        for file in sorted({p.name for p in xcode.glob("*") if p.is_file() and p.name != "root.ssu.yaml"} | {p.name for p in mine.glob("*") if p.is_file()}):
            a, b = xcode / file, mine / file
            if not a.exists() or not b.exists():
                results.append(f"{file} only in {'Xcode' if a.exists() else 'nomac'}'s")
            elif a.read_bytes() == b.read_bytes():
                results.append(f"{file} identical")
            elif file in ("extract.actionsdata", "extract.packagedata") and unordered(json.loads(a.read_text())) == unordered(json.loads(b.read_text())):
                results.append(f"{file} identical but for set order")
            elif file == "root.ssu.yaml" and ssu_blocks(a.read_text()) == ssu_blocks(b.read_text()):
                results.append(f"{file} identical but for set order")
            else:
                results.append(f"{file} DIFFERENT")
        strings = Path(options["--stringsdata-file"])
        results.append("stringsdata " + ("identical" if strings.read_bytes() == (scratch / "strings.stringsdata").read_bytes() else "DIFFERENT"))
        verdicts.append(f"{task.name}: " + ", ".join(results))
    for task in sorted(case.glob("*-AppIntentsSSUTraining")):
        verdicts.append(f"{task.name}: " + compare_training(task, nomac))
    print(f"{name}: " + "; ".join(verdicts))


def nlu_contents(path):
    """`nlu.lzfse` decompressed and read as lines: the locale, the bundle identifier, each intent's
    name, parameters (sorted: Xcode writes them in set order, `phrases`) and utterances, and the
    negatives; the header (hash and time) left out."""
    data = subprocess.run(["compression_tool", "-decode", "-a", "lzfse", "-i", str(path), "-o", "/dev/stdout"], capture_output=True, check=True).stdout
    u32 = lambda o: int.from_bytes(data[o:o + 4], "little")
    def field(table, index):
        vtable = table - int.from_bytes(data[table:table + 4], "little", signed=True)
        entry = table + int.from_bytes(data[vtable + 4 + 2 * index:vtable + 6 + 2 * index], "little")
        return entry + u32(entry)
    vector = lambda o: [o + 4 + 4 * j + u32(o + 4 + 4 * j) for j in range(u32(o))]
    string = lambda o: data[o + 4:o + 4 + u32(o)].decode()
    utterances = lambda o: [string(field(field(u, 1), 0)) for u in vector(o)]
    root = u32(0)
    bundle = vector(field(vector(field(root, 3))[0], 1))[0]
    lines = ["locale " + string(field(root, 2)), "bundle " + string(field(bundle, 0))]
    for intent in vector(field(bundle, 1)):
        lines += ["intent " + string(field(intent, 0))]
        lines += sorted("parameter " + string(field(p, 0)) + "=" + string(field(p, 1)) for p in vector(field(intent, 1)))
        lines += ["utterance " + u for u in utterances(field(intent, 2))]
    return lines + ["negative " + u for u in utterances(field(bundle, 2))]


def compare_training(task, nomac):
    """nomac's training on the inputs Xcode's had: `root.ssu.yaml` and each training's contents
    (`nlu_contents`: the header's hash and time left out, the time being the training's and the
    hash a digest of unknown input)."""
    command = json.loads((task / "command.json").read_text())
    argv = command["argv"]
    options = {argv[i]: argv[i + 1] for i in range(1, len(argv) - 1) if argv[i].startswith("--") and not argv[i + 1].startswith("--")}
    xcode = Path(options["--extracted-metadata-path"])
    scratch = task / "nomac"
    shutil.rmtree(scratch, ignore_errors=True)
    bundle = scratch / Path(options["--product-path"]).name
    (bundle / "Metadata.appintents").mkdir(parents=True)
    product = Path(options["--product-path"])
    for strings in product.glob("*.lproj/*.strings"):
        (bundle / strings.parent.name).mkdir(exist_ok=True)
        shutil.copy(strings, bundle / strings.parent.name / strings.name)
    for file in ("extract.actionsdata", "version.json"):
        if (xcode / file).exists():
            shutil.copy(xcode / file, bundle / "Metadata.appintents" / file)
    shutil.copy(options["--infoplist-path"], bundle / "Info.plist")
    replaced = {"--extracted-metadata-path": str(bundle / "Metadata.appintents"), "--product-path": str(bundle), "--infoplist-path": str(bundle / "Info.plist"),
                "--source-file": str(bundle / "Info.plist"), "--temp-dir-path": str(scratch / "ssu")}
    arguments = [replaced.get(argv[i - 1], a) if i > 0 else a for i, a in enumerate(argv)][1:]
    proc = subprocess.run([nomac, "appintentsnltrainingprocessor", *arguments], cwd=command["cwd"], capture_output=True, text=True)
    if proc.returncode != 0:
        return f"nomac exit {proc.returncode}: {proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else ''}"
    mine = bundle / "Metadata.appintents"
    if not (xcode / "root.ssu.yaml").exists():
        return "nothing trained" + (" by either" if not (mine / "root.ssu.yaml").exists() else ", but nomac wrote root.ssu.yaml")
    results = []
    a, b = (xcode / "root.ssu.yaml").read_text(), (mine / "root.ssu.yaml").read_text() if (mine / "root.ssu.yaml").exists() else ""
    results.append("root.ssu.yaml " + ("identical" if a == b else "identical but for set order" if ssu_blocks(a) == ssu_blocks(b) else "DIFFERENT"))
    trainings = {"nlu": (xcode / "nlu", mine / "nlu")} if (xcode / "nlu").exists() else {
        d.parent.name: (d, bundle / d.parent.name / "nlu.appintents") for d in sorted(product.glob("*.lproj/nlu.appintents"))}
    same, different = 0, []
    for name, (a_dir, b_dir) in trainings.items():
        versions = [sorted(p.read_bytes() for p in d.glob("*.version")) for d in (a_dir, b_dir)]
        if (b_dir / "nlu.lzfse").exists() and nlu_contents(a_dir / "nlu.lzfse") == nlu_contents(b_dir / "nlu.lzfse") and versions[0] == versions[1] == [b"\0"]:
            same += 1
        else:
            different.append(name)
    results.append(f"{same} of {len(trainings)} trainings identical but for their header's hash and time, parameter order and .version file's name"
                   + (f", DIFFERENT: {' '.join(different)}" if different else ""))
    return ", ".join(results)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["record", "compare"])
    parser.add_argument("out", type=Path)
    parser.add_argument("cases", nargs="*")
    parser.add_argument("--nomac")
    args = parser.parse_intermixed_args()
    for name in args.cases or list(CASES):
        if args.command == "compare":
            compare(args.out.resolve(), name, args.nomac or sys.exit("error: compare needs --nomac"))
        else:
            record(args.out.resolve(), name, os.environ.get("DEVELOPER_DIR") or sys.exit("error: set DEVELOPER_DIR to the reference Xcode"))


if __name__ == "__main__":
    main()
