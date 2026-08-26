import Core
import Foundation
import XCTest
@testable import App

final class CmuxLocalizationTests: XCTestCase {
    func testCmuxTerminalErrorsUseAllFiveCatalogs() {
        let sourceResources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Resources")
            .path
        let oldResources = AppLocalization.resourcesPath
        let oldTag = AppLocalization.tagOverrideForTesting
        defer {
            AppLocalization.resourcesPath = oldResources
            AppLocalization.tagOverrideForTesting = oldTag
        }
        AppLocalization.resourcesPath = sourceResources

        for tag in supportedLocales {
            AppLocalization.tagOverrideForTesting = tag
            let notFound = localizedErrorMessage(TerminalError.cmuxNotFound)
            let denied = localizedErrorMessage(TerminalError.cmuxSocketDenied)
            let failed = localizedErrorMessage(TerminalError.cmuxRPCFailed("surface.read_text"))

            XCTAssertFalse(notFound.hasPrefix("app.error."), "\(tag) returned a raw key")
            XCTAssertFalse(denied.hasPrefix("app.error."), "\(tag) returned a raw key")
            XCTAssertFalse(failed.hasPrefix("app.error."), "\(tag) returned a raw key")
            XCTAssertTrue(failed.contains("surface.read_text"), "\(tag) dropped the RPC method")
        }
    }

    func testCmuxSocketStatusLabelsUseAllFiveCatalogs() {
        let sourceResources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Resources")
            .path
        let oldResources = AppLocalization.resourcesPath
        let oldTag = AppLocalization.tagOverrideForTesting
        defer {
            AppLocalization.resourcesPath = oldResources
            AppLocalization.tagOverrideForTesting = oldTag
        }
        AppLocalization.resourcesPath = sourceResources

        let statuses: [CmuxSocketStatus] = [
            .notInstalled, .notRunning, .denied, .reachable, .failed("probe")
        ]
        for tag in supportedLocales {
            AppLocalization.tagOverrideForTesting = tag
            for status in statuses {
                XCTAssertFalse(
                    status.label.hasPrefix("app.status.cmux."),
                    "\(tag) returned a raw cmux status key for \(status)"
                )
            }
        }
    }
}
