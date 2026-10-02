import Core
import XCTest

final class URLSchemeRegistrationTests: XCTestCase {
    func testInfoPlistRegistersTheSharedURLSchemeUnderItsBundleIdentifier() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: repositoryPath("app/Info.plist")))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let bundleIdentifier = try XCTUnwrap(plist["CFBundleIdentifier"] as? String)
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(urlTypes.count, 1)

        let urlType = try XCTUnwrap(urlTypes.first)
        XCTAssertEqual(urlType["CFBundleURLName"] as? String, bundleIdentifier)
        let schemes = try XCTUnwrap(urlType["CFBundleURLSchemes"] as? [String])
        XCTAssertEqual(schemes, [SlackThreadURLContract.scheme])
    }
}

private func repositoryPath(_ name: String) -> String {
    URL(fileURLWithPath: #filePath) // <root>/app/Tests/AppTests/URLSchemeRegistrationTests.swift
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(name).path
}
