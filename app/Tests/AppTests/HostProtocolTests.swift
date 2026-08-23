import Core
import XCTest
@testable import App

/// What the app puts on the wire, for each of the four responses it can produce.
///
/// The decision is a function of its arguments (`hostResponse`), so the four rows are enumerated
/// here directly. Driving them through the socket instead would need a terminal for the success
/// row, and would make every row depend on whatever this machine has published — the shape of
/// defect item 11 hit, where one branch was all a test could ever reach.
final class HostProtocolTests: XCTestCase {
    private let publication = LocalePublication(
        installId: "install-a", snapshot: LocaleSnapshot(tag: "ko", epoch: 7)
    )

    /// `#filePath` and not `Bundle`: the sources are what this asserts about, and a bundle would
    /// answer with whatever the build happened to copy (D7).
    private var hostServerSourcePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // app
            .appendingPathComponent("Sources/App/HostServer.swift")
            .path
    }

    private func carriesGeneration(_ response: [String: Any]) -> Bool {
        response[localeResponseKey] != nil
            || response[localeInstallIdResponseKey] != nil
            || response[localeEpochResponseKey] != nil
    }

    /// **Every response this app composes carries the generation — the refused one included.**
    ///
    /// This reverses the earlier rule, which attached it to successes only. The argument for that
    /// one was that an exceptionless rule is the one the extension can implement without a table;
    /// the rule was exceptionless and still answered the wrong question. A validation failure can be
    /// the **first successful contact with the running app**: the cold-start query never ran, or
    /// failed, or an older app answered it, and then a button press makes the relay launch this app,
    /// which refuses the command. The app is up and has a language, and under the old rule the only
    /// response that could have said so said nothing.
    ///
    /// The boundary is origin, not outcome, and that is the rule with *fewer* exceptions: what the
    /// app composes carries it, what the app did not compose never reaches this function.
    func testFailureResponseCarriesLocaleGeneration() throws {
        let rejected = hostResponse(
            json: ["command_template": "z {repo}", "variables": ["evil": "x"]],
            publication: publication, baseDirectory: ""
        ) { _ in }
        XCTAssertEqual(rejected["success"] as? Bool, false)
        XCTAssertNotNil(rejected["error"], "the refusal stopped saying why")
        XCTAssertEqual(rejected[localeResponseKey] as? String, "ko")
        XCTAssertEqual(rejected[localeInstallIdResponseKey] as? String, "install-a")
        XCTAssertEqual(rejected[localeEpochResponseKey] as? Int, 7)
    }

    /// The other two responses the app composes, unchanged by the reversal above.
    func testAppComposedResponsesAllCarryTheLocaleGeneration() throws {
        let success = hostResponse(
            json: ["command_template": "z {repo}", "variables": ["repo": "r"]],
            publication: publication, baseDirectory: ""
        ) { _ in }
        XCTAssertEqual(success["success"] as? Bool, true)
        XCTAssertEqual(success[localeResponseKey] as? String, "ko")
        XCTAssertEqual(success[localeInstallIdResponseKey] as? String, "install-a")
        XCTAssertEqual(success[localeEpochResponseKey] as? Int, 7)

        let query = hostResponse(json: ["query": "locale"], publication: publication, baseDirectory: "") { _ in }
        XCTAssertEqual(query["success"] as? Bool, true)
        XCTAssertEqual(query[localeResponseKey] as? String, "ko")
        XCTAssertEqual(query[localeEpochResponseKey] as? Int, 7)
    }

    /// **The internal-error literal is the one response that stays bare, and not by omission.**
    ///
    /// `serve` builds it when `JSONSerialization` could not turn the composed response into bytes.
    /// The app emits it, but it emits it *instead of* a statement about itself — so under a rule that
    /// asks "did the app compose this", it did not. It does not pass through `responseCarryingLocale`
    /// and must not be routed through it: attaching the generation would mean hand-assembling JSON at
    /// the exact point JSON assembly failed, with an install id that would then need escaping.
    ///
    /// The extension reads the absence correctly — no fields, no input to the cache — which is the
    /// truth: a response that could not be composed says nothing about the language.
    func testTheInternalErrorLiteralIsNotComposedAndCarriesNothing() throws {
        let literal = #"{"success":false,"error":"internal error"}"#
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(literal.utf8)) as? [String: Any]
        )
        XCTAssertFalse(carriesGeneration(parsed), "the literal grew a generation")
        // and the source still emits exactly that literal, rather than routing it through the
        // function above — a lint, because the branch needs a failed serialisation to reach
        let source = try String(contentsOfFile: hostServerSourcePath, encoding: .utf8)
        XCTAssertTrue(
            source.contains(#"Data(#"{"success":false,"error":"internal error"}"#),
            "the fallback literal moved; decide again whether it may claim a locale"
        )
    }

    /// **Nothing published yet means no metadata**, on every response. The headless server does not
    /// invent a revision (D49), so a machine whose GUI has never run answers exactly as an older app
    /// does — and the extension treats both the same way, as no input.
    func testNothingPublishedMeansNoMetadata() {
        for json in [["query": "locale"], ["command_template": "z {repo}", "variables": ["repo": "r"]]] as [[String: Any]] {
            let response = hostResponse(json: json, publication: nil, baseDirectory: "") { _ in }
            XCTAssertEqual(response["success"] as? Bool, true)
            XCTAssertFalse(carriesGeneration(response), "\(json) carried a generation from nothing")
        }
    }

    /// **Bookkeeping on this side cannot change a command's answer, and it cannot by construction.**
    ///
    /// The extension had the opposite shape: its cache write was awaited before the response was
    /// judged, so a storage failure turned an already-executed command into a reported failure and
    /// invited a second press — a duplicate run, and for a scheduled claude input a duplicate
    /// delivery, which is what CLAUDE.md spends two rules preventing. Sweeping this side for the
    /// same class found **nothing**, and the reason is worth keeping rather than the count:
    ///
    ///   * `Settings.recordRequestEvidence()` runs before the request is even parsed, and it cannot
    ///     fail — a `UserDefaults` setter does not throw and the notification it posts is `async` on
    ///     another queue. Nothing it does is on the path that builds a response.
    ///   * `LocaleState.publish(...)` returns an optional rather than throwing. `nil` means "nothing
    ///     published yet", which produces a metadata-free response by design (D49), not a failure.
    ///   * `Installer.autoSetup()` is not on this path at all — it runs once at launch.
    ///
    /// So the asymmetry is the API, not the care taken: the browser's storage is a promise that
    /// rejects, and these are not. This test pins the part that is a choice — that a response is
    /// built from the request and the publication, and that a publication of `nil` is an ordinary
    /// answer rather than an error.
    func testBookkeepingCannotFailACommand() throws {
        let command: [String: Any] = ["command_template": "z {repo}", "variables": ["repo": "r"]]
        var ran = 0
        // Nothing published: the bookkeeping has nothing to say, and the command still succeeds
        let withoutPublication = hostResponse(
            json: command, publication: nil, baseDirectory: ""
        ) { _ in ran += 1 }
        XCTAssertEqual(withoutPublication["success"] as? Bool, true, "an unpublished locale failed a command")
        XCTAssertEqual(ran, 1, "the command did not run")
        XCTAssertFalse(carriesGeneration(withoutPublication))

        // ...and the response is otherwise identical to the one with a publication, apart from the
        // three metadata keys — the bookkeeping adds, it never subtracts
        let withPublication = hostResponse(
            json: command, publication: publication, baseDirectory: ""
        ) { _ in ran += 1 }
        let metadata = Set([localeResponseKey, localeInstallIdResponseKey, localeEpochResponseKey])
        let bare = withPublication.filter { !metadata.contains($0.key) }
        XCTAssertEqual(
            bare.keys.sorted(), withoutPublication.keys.sorted(),
            "publishing changed the response beyond its own three keys"
        )
    }

    /// **A query runs no command.** That is the whole reason it exists: the extension needs the
    /// language on a cold start, and the only other way to ask would open a terminal tab.
    func testALocaleQueryRunsNoCommand() {
        var ran = 0
        let query = hostResponse(json: ["query": "locale"], publication: publication, baseDirectory: "") { _ in
            ran += 1
        }
        XCTAssertEqual(ran, 0, "the query path reached the command runner")
        XCTAssertNil(query["error"])

        // And the same closure does run for a command, so the counter is not measuring nothing
        _ = hostResponse(
            json: ["command_template": "z {repo}", "variables": ["repo": "r"]],
            publication: publication, baseDirectory: ""
        ) { _ in ran += 1 }
        XCTAssertEqual(ran, 1)
    }

    /// Anything that does not name the query is a command request — including the shapes an older
    /// extension or a broken one sends. Core's verdict for them is unchanged, which is what keeps
    /// this addition from moving any existing behaviour.
    func testOnlyTheNamedQueryIsAQuery() {
        XCTAssertEqual(hostRequestKind(["query": "locale"]), .localeQuery)
        XCTAssertEqual(hostRequestKind([:]), .command)
        XCTAssertEqual(hostRequestKind(["query": "Locale"]), .command)
        XCTAssertEqual(hostRequestKind(["query": 1]), .command)
        XCTAssertEqual(hostRequestKind(["command_template": "z {repo}"]), .command)

        // The protocol-skew half: a request that names a query but reaches an app that knows nothing
        // about queries is a request with no `command_template`, and that is what it is told.
        let asAnOlderAppWouldSee = handleRequest(json: ["query": "locale"], baseDirectory: "") { _ in }
        XCTAssertEqual(asAnOlderAppWouldSee["success"] as? Bool, false)
        XCTAssertEqual(asAnOlderAppWouldSee["error"] as? String, "command_template is required")
    }

    /// **The socket server reads; it does not publish.** In both processes, because the GUI hosts a
    /// server too: a server publishing as `.interactive` would be a second writer racing the picker
    /// for an epoch, which is the P0 round 10 named and what the launch publisher already occupies.
    ///
    /// This is a **lint**, not a proof — it reads the source rather than the behaviour, and a
    /// different spelling of the same mistake would slip past it. The behavioural half is that the
    /// headless role writes nothing (`testTwoWritersCannotPublishDifferentLocalesAtTheSameEpoch`)
    /// and that two interactive writers cannot collide
    /// (`testTwoInteractiveWritersCannotPublishDifferentTagsAtTheSameEpoch`); what is left uncovered
    /// is only "which role this one call site passes", and that is what this line pins.
    func testTheServerPublishesAsAReaderOnly() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/App/HostServer.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("role: .headless"),
            "the server no longer publishes as a reader"
        )
        XCTAssertFalse(
            source.contains("role: .interactive"),
            "the server publishes as a writer, which races the picker for an epoch"
        )
    }
}
