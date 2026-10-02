import Foundation
import XCTest
@testable import Core

final class ShortcutWorkflowTests: XCTestCase {
    private let placeholder = "\u{FFFC}"

    func testActionOrderAndOutputConnections() throws {
        let actions = try workflowActions()

        XCTAssertEqual(
            actions.compactMap { $0["WFWorkflowActionIdentifier"] as? String },
            [
                "is.workflow.actions.getclipboard",
                "is.workflow.actions.urlencode",
                "is.workflow.actions.url",
                "is.workflow.actions.openurl",
            ]
        )

        let clipboardUUID = try parameters(actions[0])["UUID"] as? String
        let encodingUUID = try parameters(actions[1])["UUID"] as? String
        let urlUUID = try parameters(actions[2])["UUID"] as? String
        XCTAssertEqual(try attachment(in: parameters(actions[1])[
            "WFInput"] as! [String: Any], range: "{0, 1}")["OutputUUID"] as? String, clipboardUUID)
        XCTAssertEqual(try attachment(in: parameters(actions[2])[
            "WFURLActionURL"] as! [String: Any], range: "{\(SlackThreadURLContract.shortcutURLPrefix.utf16.count), 1}")["OutputUUID"] as? String, encodingUUID)
        let openURLInput = try parameters(actions[3])["WFInput"] as! [String: Any]
        let openURLValue = try XCTUnwrap(openURLInput["Value"] as? [String: Any])
        XCTAssertEqual(openURLValue["OutputUUID"] as? String, urlUUID)
        XCTAssertEqual(openURLValue["OutputName"] as? String, "URL")
        XCTAssertEqual(openURLInput["WFSerializationType"] as? String, "WFTextTokenAttachment")
        XCTAssertEqual(Set([clipboardUUID, encodingUUID, urlUUID].compactMap { $0 }).count, 3)
    }

    func testURLencodeUsesTextTokenStringForClipboardAttachment() throws {
        let actions = try workflowActions()
        let input = try parameters(actions[1])["WFInput"] as! [String: Any]
        let value = input["Value"] as! [String: Any]
        let attachments = value["attachmentsByRange"] as! [String: Any]
        let clipboard = attachments["{0, 1}"] as! [String: Any]

        XCTAssertEqual(input["WFSerializationType"] as? String, "WFTextTokenString")
        XCTAssertEqual(value["string"] as? String, placeholder)
        XCTAssertEqual(clipboard["OutputName"] as? String, "Clipboard")
        XCTAssertEqual(clipboard["Type"] as? String, "ActionOutput")
    }

    func testURLActionUsesSharedPrefixAndCalculatedUTF16AttachmentRange() throws {
        let actions = try workflowActions()
        let urlAction = try parameters(actions[2])["WFURLActionURL"] as! [String: Any]
        let value = urlAction["Value"] as! [String: Any]
        let rangeKey = "{\(SlackThreadURLContract.shortcutURLPrefix.utf16.count), 1}"
        let attachment = (value["attachmentsByRange"] as! [String: Any])[rangeKey] as! [String: Any]

        XCTAssertEqual(urlAction["WFSerializationType"] as? String, "WFTextTokenString")
        XCTAssertEqual(value["string"] as? String, SlackThreadURLContract.shortcutURLPrefix + placeholder)
        XCTAssertEqual(attachment["OutputName"] as? String, "URL Encoded Text")
        XCTAssertEqual(attachment["Type"] as? String, "ActionOutput")
    }

    func testWorkflowMetadataIsExactAndContainsNoUserSettings() throws {
        var format = PropertyListSerialization.PropertyListFormat.binary
        let data = try SlackThreadShortcutWorkflow.makePropertyListData()
        let root = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any]
        )

        XCTAssertEqual(format, .xml)
        XCTAssertEqual(
            Set(root.keys),
            Set([
                "WFWorkflowActions", "WFWorkflowClientVersion", "WFWorkflowMinimumClientVersion",
                "WFWorkflowMinimumClientVersionString", "WFWorkflowIcon", "WFWorkflowImportQuestions",
                "WFWorkflowInputContentItemClasses", "WFWorkflowTypes", "WFWorkflowHasShortcutInputVariables",
            ])
        )
        XCTAssertEqual(root["WFWorkflowClientVersion"] as? String, "2302.0.4")
        XCTAssertEqual(root["WFWorkflowMinimumClientVersion"] as? Int, 900)
        XCTAssertEqual(root["WFWorkflowMinimumClientVersionString"] as? String, "900")
        XCTAssertEqual(root["WFWorkflowHasShortcutInputVariables"] as? Bool, false)
        XCTAssertTrue(try XCTUnwrap(root["WFWorkflowImportQuestions"] as? [Any]).isEmpty)
        XCTAssertTrue(try XCTUnwrap(root["WFWorkflowInputContentItemClasses"] as? [Any]).isEmpty)
        XCTAssertTrue(try XCTUnwrap(root["WFWorkflowTypes"] as? [Any]).isEmpty)
        XCTAssertEqual(
            root["WFWorkflowIcon"] as? [String: Int],
            ["WFWorkflowIconGlyphNumber": 59511, "WFWorkflowIconStartColor": 4282601983]
        )

        let strings = allStrings(in: root)
        XCTAssertFalse(strings.contains { $0.localizedCaseInsensitiveContains("workDirectory") })
        XCTAssertFalse(strings.contains { $0.localizedCaseInsensitiveContains("instruction") })
        XCTAssertFalse(strings.contains { $0.hasPrefix("https://") })
    }

    func testWorkflowDataIsDeterministic() throws {
        XCTAssertEqual(
            try SlackThreadShortcutWorkflow.makePropertyListData(),
            try SlackThreadShortcutWorkflow.makePropertyListData()
        )
    }

    func testWorkflowURLPrefixComesFromSharedContract() throws {
        let appDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: appDirectory.appendingPathComponent("Sources/Core/ShortcutWorkflow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("SlackThreadURLContract.shortcutURLPrefix"))
        XCTAssertFalse(source.contains("terminal-checkout://slack-thread?url="))
    }

    private func workflowActions(file: StaticString = #filePath, line: UInt = #line) throws -> [[String: Any]] {
        var format = PropertyListSerialization.PropertyListFormat.binary
        let root = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: SlackThreadShortcutWorkflow.makePropertyListData(), options: [], format: &format
            ) as? [String: Any], file: file, line: line
        )
        return try XCTUnwrap(root["WFWorkflowActions"] as? [[String: Any]], file: file, line: line)
    }

    private func parameters(
        _ action: [String: Any], file: StaticString = #filePath, line: UInt = #line
    ) throws -> [String: Any] {
        try XCTUnwrap(action["WFWorkflowActionParameters"] as? [String: Any], file: file, line: line)
    }

    private func attachment(
        in token: [String: Any], range: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> [String: Any] {
        let value = try XCTUnwrap(token["Value"] as? [String: Any], file: file, line: line)
        let attachments = try XCTUnwrap(value["attachmentsByRange"] as? [String: Any], file: file, line: line)
        return try XCTUnwrap(attachments[range] as? [String: Any], file: file, line: line)
    }

    private func allStrings(in value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { allStrings(in: $0.key) + allStrings(in: $0.value) }
        }
        if let array = value as? [Any] { return array.flatMap(allStrings(in:)) }
        return []
    }
}
