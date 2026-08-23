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

    private func carriesGeneration(_ response: [String: Any]) -> Bool {
        response[localeResponseKey] != nil
            || response[localeInstallIdResponseKey] != nil
            || response[localeEpochResponseKey] != nil
    }

    /// **A successful command and an answered query carry the generation; a validation failure does
    /// not.** One test, `success == true`, decides all three — the contract the extension reads is
    /// "metadata present or no input at all" (D51), and a rule with no exceptions is the one it can
    /// implement without a table.
    func testOnlyASuccessfulResponseCarriesTheLocaleGeneration() throws {
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

        let rejected = hostResponse(
            json: ["command_template": "z {repo}", "variables": ["evil": "x"]],
            publication: publication, baseDirectory: ""
        ) { _ in }
        XCTAssertEqual(rejected["success"] as? Bool, false)
        XCTAssertNotNil(rejected["error"])
        XCTAssertFalse(carriesGeneration(rejected), "a failure carried a generation")

        // The fourth response is a literal built after JSON serialisation fails, so it never passes
        // through here at all. This pins the rule that would cover it if it ever did.
        let internalError: [String: Any] = ["success": false, "error": "internal error"]
        XCTAssertFalse(carriesGeneration(responseCarryingLocale(internalError, publication: publication)))
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
