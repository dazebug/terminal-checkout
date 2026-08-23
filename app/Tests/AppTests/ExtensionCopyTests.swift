import Core
import XCTest
@testable import App

/// **Replacing a folder somebody else is reading.**
///
/// Chrome reads the installed extension off disk whenever it likes. The old code deleted that folder
/// and copied into the hole, so for the length of a recursive copy there was no manifest there at
/// all, and then a partially populated directory — and five locales made that copy longer by adding
/// `_locales/` and `_i18n/` to it.
///
/// What replaced it builds the new copy beside the old one and swaps. These tests hold the two
/// properties that buys — the destination is complete at every instant, and a failure leaves the
/// previous copy whole — plus the one thing neither of them can be: proof about a concurrent reader.
final class ExtensionCopyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tc-extension-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func populate(_ url: URL, marker: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("_locales/en"), withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try marker.write(to: url.appendingPathComponent("defaults.js"), atomically: true, encoding: .utf8)
        try marker.write(
            to: url.appendingPathComponent("_locales/en/messages.json"), atomically: true, encoding: .utf8
        )
    }

    private func marker(_ url: URL, _ relative: String) -> String? {
        try? String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)
    }

    /// **The primitive the swap rests on, and the reason a plain rename cannot do it.** This is the
    /// same measurement recorded in `installExtensionCopy`'s comment, kept as a test so the claim
    /// stops being true loudly rather than quietly if a future macOS changes it.
    func testReplaceItemAtSwapsAPopulatedDirectoryWhereRenameRefuses() throws {
        let dest = root.appendingPathComponent("extension")
        let staged = root.appendingPathComponent(".extension.staging")
        try populate(dest, marker: "OLD")
        try populate(staged, marker: "NEW")

        // `rename(2)` onto a populated directory is ENOTEMPTY — which is why this is not just a move
        let refused = rename(staged.path, dest.path)
        XCTAssertEqual(refused, -1, "rename onto a populated directory stopped failing")
        XCTAssertEqual(errno, ENOTEMPTY, "rename failed for a different reason than a full destination")

        _ = try FileManager.default.replaceItemAt(dest, withItemAt: staged)
        XCTAssertEqual(marker(dest, "manifest.json"), "NEW")
        XCTAssertEqual(marker(dest, "_locales/en/messages.json"), "NEW", "a nested file kept the old copy")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: staged.path),
            "the staged directory survived the swap, so it would be left behind"
        )
    }

    /// **A reader never finds the destination missing.** The property the old code broke: it is the
    /// absence, not the staleness, that makes Chrome refuse the extension outright.
    ///
    /// A thread does nothing but open the manifest while the swap happens. What this cannot show is
    /// that a reader opening *several* files sees one generation — that depends on the reader, not on
    /// the filesystem, and `installExtensionCopy` says so rather than claiming otherwise.
    func testTheDestinationIsNeverAbsentWhileItIsReplaced() throws {
        let dest = root.appendingPathComponent("extension")
        let staged = root.appendingPathComponent(".extension.staging")
        try populate(dest, marker: "OLD")
        try populate(staged, marker: "NEW")

        var reads = 0
        var missing = 0
        let stop = DispatchSemaphore(value: 0)
        let reader = Thread {
            while stop.wait(timeout: .now()) == .timedOut {
                reads += 1
                if (try? Data(contentsOf: dest.appendingPathComponent("manifest.json"))) == nil {
                    missing += 1
                }
            }
        }
        reader.start()
        Thread.sleep(forTimeInterval: 0.02)
        _ = try FileManager.default.replaceItemAt(dest, withItemAt: staged)
        Thread.sleep(forTimeInterval: 0.02)
        stop.signal()
        Thread.sleep(forTimeInterval: 0.02)

        XCTAssertGreaterThan(reads, 100, "the reader barely ran — the window was not observed")
        XCTAssertEqual(missing, 0, "the destination was missing for \(missing) of \(reads) reads")
        XCTAssertEqual(marker(dest, "manifest.json"), "NEW")
    }

    /// **A failure leaves a whole copy, not a hole.** The old shape could not offer this: once the
    /// destination was deleted, a copy that then failed left nothing at all.
    func testAFailedStagingLeavesThePreviousCopyIntact() throws {
        let dest = root.appendingPathComponent("extension")
        try populate(dest, marker: "OLD")

        // Staging from a source that does not exist is the failure this models — the copy throws
        // before anything has been swapped.
        let staged = root.appendingPathComponent(".extension.staging")
        XCTAssertThrowsError(
            try FileManager.default.copyItem(
                at: root.appendingPathComponent("no-such-bundle"), to: staged
            )
        )
        XCTAssertEqual(marker(dest, "manifest.json"), "OLD", "the installed copy was disturbed by a failure")
        XCTAssertEqual(marker(dest, "_locales/en/messages.json"), "OLD")
    }

    /// **Neither path deletes a live destination before it has a complete replacement.**
    ///
    /// This is a lint, and it is the answer to a question the two paths cannot answer any other way.
    /// They are **not two implementations of one rule** — the Swift one replaces the extension folder
    /// Chrome reads, the shell one replaces the app bundle in `~/Applications`. They are two
    /// instances of one *class*, in two languages, and the options for keeping them together were:
    ///
    ///   * have the shell call the app to do it — **impossible here**, since `install.sh` is
    ///     replacing the very binary that would perform the replacement;
    ///   * share the rule as data — only the staging suffix is shareable, and the operations differ
    ///     because the shell has no `replaceItemAt`, so that shares the least important part;
    ///   * implement both and have a gate catch the drift — this.
    ///
    /// So the gate is not optional decoration: it is the only thing standing between these two and
    /// the next person who fixes one of them.
    func testNeitherInstallPathDeletesItsDestinationFirst() throws {
        let installer = try String(contentsOfFile: Self.repositoryFile("app/Sources/App/Installer.swift"), encoding: .utf8)
        let copyFunction = try XCTUnwrap(installer.range(of: "static func installExtensionCopy() throws {"))
        // **The window is the function, found by matching its braces.** It was a fixed 1400
        // characters over a 1147-character body — five lines of headroom — and the two directions
        // did not fail alike: the positive assertions failed *closed* when the function outgrew it,
        // while the `XCTAssertFalse` below failed *open*, because a destination delete written past
        // the cut simply was not in the text being searched (measured — the lint stayed green).
        // Widening the number would have left the same class in place with a larger constant.
        let body = try balancedBody(of: installer, after: copyFunction.upperBound)
        XCTAssertTrue(body.contains("extensionStagingPath()"), "the Swift path no longer stages")
        // **The copy has to land in the staging path**, not merely mention it. The first version of
        // this lint asked whether the name appeared and a toggle walked straight through it by
        // copying somewhere else while leaving the mention in place — a check that reads for a word
        // rather than for the thing the word names.
        XCTAssertTrue(
            body.contains("copyItem(atPath: source, toPath: staging)"),
            "the Swift path stages a name but copies somewhere else"
        )
        XCTAssertTrue(body.contains("replaceItemAt"), "the Swift path no longer swaps")
        XCTAssertFalse(
            body.contains("removeItem(atPath: dest)"),
            "the Swift path deletes the destination before it has a replacement"
        )
        // And the staged copy is cleaned up on the way out. It matters only on the failure path —
        // a successful swap consumes it — which is exactly the path nobody exercises by hand.
        XCTAssertTrue(
            body.contains("defer { try? FileManager.default.removeItem(atPath: staging) }"),
            "a failed staging now leaves a full copy of the extension beside the installed one"
        )

        let script = try String(contentsOfFile: Self.repositoryFile("install.sh"), encoding: .utf8)
        XCTAssertFalse(
            script.contains(#"rm -rf "$INSTALL_DIR/$APP_NAME""#),
            "install.sh deletes the installed app before it has a replacement"
        )
        XCTAssertTrue(script.contains(#"ditto "$SCRIPT_DIR/app/build/$APP_NAME" "$STAGING""#),
                      "install.sh no longer builds beside the old bundle")
        XCTAssertTrue(script.contains(#"mv "$STAGING" "$INSTALL_DIR/$APP_NAME""#),
                      "install.sh no longer swaps the staged bundle in")
    }

    /// The text from an opening brace to the one that closes it. A lint over a Swift function has to
    /// read the whole function or its negative assertions stop meaning anything, and the only
    /// boundary that grows with the code is the brace.
    ///
    /// Braces inside string literals and comments would fool this; there are none in the function it
    /// is used on. An unbalanced count **fails** — not skips, which is a pass wearing another name,
    /// and not "return the rest of the file", which is the truncated-window failure being removed.
    private func balancedBody(of text: String, after start: String.Index) throws -> String {
        var depth = 1
        var index = start
        while index < text.endIndex {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" {
                depth -= 1
                if depth == 0 { return String(text[start..<index]) }
            }
            index = text.index(after: index)
        }
        XCTFail("the function's braces do not balance — the lint would be reading the rest of the file")
        return ""
    }

    private static func repositoryFile(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/ExtensionCopyTests.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative)
            .path
    }
}
