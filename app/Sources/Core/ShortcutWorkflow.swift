import Foundation

public enum SlackThreadShortcutWorkflow {
    public static let name = "Terminal Checkout Slack Thread"

    private static let clipboardActionUUID = "11111111-1111-4111-8111-111111111111"
    private static let urlencodeActionUUID = "22222222-2222-4222-8222-222222222222"
    private static let urlActionUUID = "33333333-3333-4333-8333-333333333333"

    public static func makePropertyListData() throws -> Data {
        let placeholder = "\u{FFFC}"
        let prefix = SlackThreadURLContract.shortcutURLPrefix
        let clipboardToken: [String: Any] = [
            "Value": [
                "string": placeholder,
                "attachmentsByRange": [
                    "{0, 1}": [
                        "OutputName": "Clipboard",
                        "OutputUUID": clipboardActionUUID,
                        "Type": "ActionOutput",
                    ],
                ],
            ],
            "WFSerializationType": "WFTextTokenString",
        ]
        let urlToken: [String: Any] = [
            "Value": [
                "string": prefix + placeholder,
                "attachmentsByRange": [
                    "{\(prefix.utf16.count), 1}": [
                        "OutputName": "URL Encoded Text",
                        "OutputUUID": urlencodeActionUUID,
                        "Type": "ActionOutput",
                    ],
                ],
            ],
            "WFSerializationType": "WFTextTokenString",
        ]
        let actions: [[String: Any]] = [
            action("is.workflow.actions.getclipboard", ["UUID": clipboardActionUUID]),
            action("is.workflow.actions.urlencode", [
                "UUID": urlencodeActionUUID,
                "WFInput": clipboardToken,
            ]),
            action("is.workflow.actions.url", [
                "UUID": urlActionUUID,
                "WFURLActionURL": urlToken,
            ]),
            action("is.workflow.actions.openurl", [
                "WFInput": [
                    "Value": [
                        "OutputName": "URL",
                        "OutputUUID": urlActionUUID,
                        "Type": "ActionOutput",
                    ],
                    "WFSerializationType": "WFTextTokenAttachment",
                ],
            ]),
        ]
        let workflow: [String: Any] = [
            "WFWorkflowActions": actions,
            "WFWorkflowClientVersion": "2302.0.4",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": [
                "WFWorkflowIconGlyphNumber": 59511,
                "WFWorkflowIconStartColor": 4282601983,
            ],
            "WFWorkflowImportQuestions": [],
            "WFWorkflowInputContentItemClasses": [],
            "WFWorkflowTypes": [],
            "WFWorkflowHasShortcutInputVariables": false,
        ]
        return try PropertyListSerialization.data(fromPropertyList: workflow, format: .xml, options: 0)
    }

    private static func action(_ identifier: String, _ parameters: [String: Any]) -> [String: Any] {
        [
            "WFWorkflowActionIdentifier": identifier,
            "WFWorkflowActionParameters": parameters,
        ]
    }
}
