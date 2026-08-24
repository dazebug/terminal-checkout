import Core
import XCTest
@testable import App

/// The user-facing strings the app draws **outside** the setup window: the menu bar, the automation
/// and installer status lines, and the one `Info.plist` key macOS puts in the permission prompt. The
/// window's own strings are `SetupWindowLayoutTests`' subject; what these cases pin is that nothing
/// outside it went back to a literal, and that the sentences naming a button take that button's
/// label as an argument instead of spelling it out (D28).
///
/// The catalogues are read from the **source** tree: `swift test` runs with no app bundle, and
/// whether `build.sh` copied them is `verify-bundle.sh`'s question.
final class AppMessageTests: XCTestCase {
    private var savedResources: String?

    /// The locales every check below is asked of — **`supportedLocales` itself, not a copy of it**.
    ///
    /// It was a spelled-out list, and while that list held only `en` and `ko` every check here asked
    /// its question of two languages and let the other three past. Even once it named all five it
    /// was a second source of truth: measured, adding a sixth tag to `supportedLocales` left
    /// `SetupWindowLayoutTests` and `CatalogueOwnershipTests` passing without ever drawing or
    /// reading it. Reading the constant means a new language is covered by existing in it.
    ///
    /// The assertions that count *distinct* answers are the ones this matters most for: "the label
    /// changed with the language" is only evidence when every language is in it.
    private var populatedLocales: [String] { supportedLocales }

    private static var sourceResources: String {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/AppMessageTests.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Resources").path
    }

    override func setUp() {
        super.setUp()
        savedResources = AppLocalization.resourcesPath
        AppLocalization.resourcesPath = Self.sourceResources
    }

    override func tearDown() {
        AppLocalization.tagOverrideForTesting = nil
        AppLocalization.resourcesPath = savedResources
        super.tearDown()
    }

    private func value(_ key: String, _ tag: String) -> String {
        AppLocalization.string(key, tag: tag, resources: Self.sourceResources)
    }

    /// The five automation states read their sentence from the catalogue, so the language the window
    /// is drawn in decides them. Two of them name a button, and they name it by **its** catalogue
    /// value — rename the button and the sentence follows.
    func testTheAutomationLabelsComeFromTheCatalogue() {
        var granted: [String] = []
        for tag in populatedLocales {
            AppLocalization.tagOverrideForTesting = tag
            let button = value("app.button.requestItermPermission", tag)

            XCTAssertEqual(AutomationStatus.granted.label, value("app.automation.granted", tag), tag)
            XCTAssertEqual(AutomationStatus.denied.label, value("app.automation.denied", tag), tag)
            XCTAssertEqual(
                AutomationStatus.notDetermined.label,
                String(format: value("app.automation.notDetermined", tag), button), tag
            )
            XCTAssertTrue(AutomationStatus.notDetermined.label.contains(button), tag)
            XCTAssertEqual(
                AutomationStatus.targetNotRunning.label,
                String(format: value("app.automation.targetNotRunning", tag), button), tag
            )
            XCTAssertTrue(AutomationStatus.targetNotRunning.label.contains(button), tag)
            XCTAssertEqual(
                AutomationStatus.unknown(-1743).label,
                String(format: value("app.automation.unknown", tag), -1743), tag
            )
            XCTAssertTrue(AutomationStatus.unknown(-1743).label.contains("-1743"), tag)
            granted.append(AutomationStatus.granted.label)
        }
        // Without this the case would pass just as well on a hardcoded literal, which answers the
        // same in both languages
        XCTAssertEqual(Set(granted).count, populatedLocales.count, "the label did not change with the language")
    }

    /// The installer's two status groups do the same.
    ///
    /// **One machine only ever reaches one branch of each**, which is why the structural half is
    /// here and not a nicety: measured while writing this, restoring the literal in the `registered`
    /// branch left every assertion green, because under `swift test` `Bundle.main` is the xctest
    /// runner, its `relayPath` never matches the installed manifest, and the run lands in
    /// `wrongPath` every time (on a machine with no manifest it would be `notRegistered`). The
    /// runtime half pins whichever branch this machine takes; the source half covers the four it
    /// cannot reach.
    func testTheInstallerStatusMessagesComeFromTheCatalogue() throws {
        let source = try repoSource("app/Sources/App/Installer.swift")
        // **A constructor and its argument need not be on the same line** (round 17 sweep), and
        // four of the six here are not: `.error(` opens and the argument sits indented on the next
        // line. The spelling this looked for was the quote up against the parenthesis, so those
        // four had no position it could see, and a sentence hardcoded one line down was read by
        // nothing. Swift's whitespace goes into the pattern instead of out of it.
        for constructor in ["ok", "warning", "error"] {
            XCTAssertNil(
                source.range(of: "\\.\(constructor)\\(\\s*\"", options: .regularExpression),
                "a status message is written at the call site instead of read from the catalogue: .\(constructor)("
            )
        }

        for tag in populatedLocales {
            AppLocalization.tagOverrideForTesting = tag
            let register = value("app.button.registerUpdate", tag)
            let install = value("app.button.installInChrome", tag)

            let manifest: Set<String> = [
                value("app.status.manifest.registered", tag),
                String(format: value("app.status.manifest.notRegistered", tag), register),
                String(format: value("app.status.manifest.wrongPath", tag), register),
                String(format: value("app.status.manifest.wrongExtensionID", tag), register),
            ]
            XCTAssertTrue(
                manifest.contains(Installer.manifestState().message),
                "\(tag): \(Installer.manifestState().message) is not one of this catalogue's sentences"
            )

            let folder: Set<String> = [
                value("app.status.extensionFolder.ready", tag),
                String(format: value("app.status.extensionFolder.missing", tag), install),
            ]
            XCTAssertTrue(
                folder.contains(Installer.extensionState().message),
                "\(tag): \(Installer.extensionState().message) is not one of this catalogue's sentences"
            )
        }
    }

    /// **Every sentence that points at a button takes the label as an argument** (D28). A body that
    /// went back to spelling the label out would still read correctly today and drift the moment the
    /// button is renamed or translated differently, so the placeholder is what is pinned.
    func testEverySentenceNamingAButtonTakesItsLabelAsAnArgument() {
        let quoting = [
            "app.automation.notDetermined", "app.automation.targetNotRunning",
            "app.status.manifest.notRegistered", "app.status.manifest.wrongPath",
            "app.status.manifest.wrongExtensionID", "app.status.extensionFolder.missing",
        ]
        for tag in populatedLocales {
            for key in quoting {
                XCTAssertTrue(value(key, tag).contains("%@"), "\(tag)/\(key) no longer takes a label")
            }
        }
    }

    /// The menu bar is built once per language change, and every title in it comes from the
    /// catalogue. The window is not opened here: building the menu means `AppDelegate`, whose launch
    /// path also registers the Native Host manifest over the one this machine is using. So the case
    /// is in two halves — the catalogue answers differently per language, and the call-site half is
    /// a source lint that reads it rather than a literal. Neither half alone would catch a literal
    /// that happens to be Korean.
    func testTheMenuTitlesComeFromTheCatalogue() throws {
        let keys = [
            "app.menu.quit", "app.menu.edit", "app.menu.cut", "app.menu.copy", "app.menu.paste",
            "app.menu.selectAll", "app.menu.window", "app.menu.close",
        ]
        for key in keys {
            let answers = populatedLocales.map { value(key, $0) }
            XCTAssertFalse(answers.contains(key), "\(key) is missing from a catalogue")
            XCTAssertEqual(Set(answers).count, populatedLocales.count, "\(key) answers the same in every language")
        }
        XCTAssertTrue(
            populatedLocales.allSatisfy { value("app.menu.quit", $0).contains("%@") },
            "the quit item stopped taking the app name as an argument"
        )

        let source = try repoSource("app/Sources/App/AppDelegate.swift")
        // **Every way a menu carries a title, and proof that it read some** (round 17 sweep). Two
        // spellings were listed because they are the two this file uses, which leaves
        // `NSMenuItem(title:)` and a `.title =` afterwards as titles no gate would look at. And the
        // filter is the same shape as the locale filter this file already had to fix: one that
        // selects nothing turns the loop into a test that passes by not running. The count is what
        // tells "they all read from the catalogue" apart from "there were none".
        var titles = 0
        for line in source.split(separator: "\n")
        where line.contains("withTitle:") || line.contains("NSMenu(title:")
            || line.contains("NSMenuItem(title:")
            || line.range(of: "\\.title\\s*=(?!=)", options: .regularExpression) != nil {
            titles += 1
            XCTAssertTrue(
                line.contains("localized("),
                "a menu title is written at the call site instead of read from the catalogue: \(line.trimmingCharacters(in: .whitespaces))"
            )
        }
        // Eight lines today; the floor sits below that because what it is here to catch is a filter
        // that reads nothing, not a menu with one item fewer in it.
        XCTAssertGreaterThanOrEqual(titles, 5, "the menu-title scan read \(titles) lines — check the pattern")
    }

    /// `NSAppleEventsUsageDescription` is the sentence tccd shows when the automation permission is
    /// first asked for. `Info.plist` carries the English one because macOS falls back to it for any
    /// language whose `InfoPlist.strings` says nothing — which is why that value must not go back to
    /// the Korean it once was.
    ///
    /// **The subject is every shipped locale, so that is what is walked.** This used to loop over
    /// the languages *without* a body — `supportedLocales where !populatedLocales.contains(tag)` —
    /// which stopped selecting anything the moment the last three catalogues were filled. The source
    /// half is a lint, while the runtime half covers whichever branch this machine can reach. Measured:
    /// emptying `ja`'s file and rebuilding left `swift test` and `build.sh` both green, because
    /// `verify-bundle.sh` compares source against bundle and lints the syntax but never asks for a
    /// key. Nothing anywhere noticed a language losing the sentence macOS shows when it asks for the
    /// automation permission.
    ///
    /// The values have to be **distinct** as well as present: a catalogue that copied English would
    /// satisfy "has a body" and still show the wrong language in the prompt.
    ///
    /// Reading is asserted separately from content, because a `.strings` file holding only comments
    /// parses to an empty dictionary rather than failing (measured) — so "no such key" has to mean
    /// the file said nothing, not that it could not be read.
    func testTheUsageDescriptionIsWrittenForTheLanguagesThatHaveBodies() throws {
        let key = "NSAppleEventsUsageDescription"
        func infoPlistStrings(_ tag: String) throws -> [String: Any] {
            let path = (Self.sourceResources as NSString)
                .appendingPathComponent("\(tag).lproj/InfoPlist.strings")
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
            return try XCTUnwrap(parsed as? [String: Any], "\(tag) InfoPlist.strings is not a dictionary")
        }

        var bodies: [String: String] = [:]
        for tag in supportedLocales {
            let parsed = try infoPlistStrings(tag)
            XCTAssertFalse(parsed.isEmpty, "\(tag)/InfoPlist.strings says nothing at all")
            let body = try XCTUnwrap(
                parsed[key] as? String,
                "\(tag) has no \(key) — macOS would show that language the Info.plist English instead"
            )
            XCTAssertFalse(body.isEmpty, "\(tag)/\(key) is empty")
            bodies[tag] = body
        }
        XCTAssertEqual(
            Set(bodies.values).count, supportedLocales.count,
            "two locales share a usage description, so one of them is showing another language: \(bodies)"
        )
        let english = try XCTUnwrap(bodies[fallbackLocale])
        let korean = try XCTUnwrap(bodies["ko"])
        XCTAssertNotEqual(english, korean)

        let plistData = try Data(contentsOf: URL(fileURLWithPath: repoPath("app/Info.plist")))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        XCTAssertEqual(
            plist[key] as? String, english,
            "the fallback macOS uses for an unwritten language is not the English sentence"
        )
    }
}

private func repoPath(_ name: String) -> String {
    URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/AppMessageTests.swift
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(name).path
}

private func repoSource(_ name: String) throws -> String {
    try String(contentsOf: URL(fileURLWithPath: repoPath(name)), encoding: .utf8)
}
