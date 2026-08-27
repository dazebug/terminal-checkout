import Foundation
import XCTest
@testable import App

final class CmuxConfigHelpTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-config-help-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    /// The narrowed button copies a fragment rather than editing the user's config.
    func testItem22ConfigClipboardFragmentContainsAutomationSetting() {
        let fragment = CmuxConfigHelp.cmuxConfigClipboardFragment()
        XCTAssertTrue(fragment.contains("automation"))
        XCTAssertTrue(fragment.contains("\"socketControlMode\": \"automation\""))
    }

    /// A file is opened directly, a missing file reveals its existing directory, and a missing
    /// directory produces no filesystem action.
    func testItem22ConfigRevealTargetChoosesFileDirectoryOrNothing() {
        let config = directory.appendingPathComponent("cmux.json")
        guard case .file(let revealedFile) = CmuxConfigHelp.cmuxConfigRevealTarget(
            configURL: config, fileExists: true, directoryExists: true
        ) else {
            return XCTFail("an existing config must be revealed as a file")
        }
        XCTAssertEqual(revealedFile.path, config.path)

        guard case .directory(let revealedDirectory) = CmuxConfigHelp.cmuxConfigRevealTarget(
            configURL: config, fileExists: false, directoryExists: true
        ) else {
            return XCTFail("an existing config directory must be revealed as a directory")
        }
        XCTAssertEqual(revealedDirectory.path, directory.path)
        XCTAssertEqual(
            CmuxConfigHelp.cmuxConfigRevealTarget(
                configURL: config, fileExists: false, directoryExists: false
            ),
            .nothing
        )
    }
}
