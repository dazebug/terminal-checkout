import Foundation
import XCTest
@testable import Core

private let cmuxGroupedTestBatchID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
private let cmuxGroupedTestRetryID = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!

private func cmuxGroupedTestItemIDs(count: Int) -> [UUID] {
    (0..<count).map { index in
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 101))!
    }
}

private func inlineLeafCommands(in layout: [String: Any]) -> [String] {
    if let children = layout["children"] as? [[String: Any]] {
        return children.flatMap { inlineLeafCommands(in: $0) }
    }
    guard let pane = layout["pane"] as? [String: Any],
          let surface = (pane["surfaces"] as? [[String: Any]])?.first,
          let command = surface["command"] as? String else {
        return []
    }
    return [command]
}

final class CmuxGroupedExecutionTests: XCTestCase {
    private struct Call {
        let method: String
        let params: [String: Any]
    }

    private struct FixtureFailure: Error, CustomStringConvertible {
        let description: String
    }

    func testLayoutJSONUsesMeasuredBinaryShapeAndOmitsSubmitFromLeafCommands() throws {
        let plan = cmuxBalancedLayoutPlan(commandByteCounts: [4, 4])
        let layout = cmuxLayoutJSON(for: plan.tree, commands: ["echo one", "echo two"])

        let branch = try XCTUnwrap(layout["children"] as? [[String: Any]])
        XCTAssertEqual(layout["direction"] as? String, "horizontal")
        XCTAssertEqual(branch.count, 2)
        let firstSurface = try XCTUnwrap(
            ((branch[0]["pane"] as? [String: Any])?["surfaces"] as? [[String: Any]])?.first
        )
        XCTAssertEqual(firstSurface["type"] as? String, "terminal")
        XCTAssertEqual(firstSurface["command"] as? String, "echo one")
        let secondSurface = try XCTUnwrap(
            ((branch[1]["pane"] as? [String: Any])?["surfaces"] as? [[String: Any]])?.first
        )
        XCTAssertEqual(secondSurface["type"] as? String, "terminal")
        XCTAssertEqual(secondSurface["command"] as? String, "echo two")
        XCTAssertFalse(try JSONSerialization.data(withJSONObject: layout).contains(13))
    }

    func testLayoutJSONLeavesCommandOutForGuardedSurfaceSend() throws {
        let plan = cmuxBalancedLayoutPlan(commandByteCounts: [cmuxLayoutLeafCommandByteLimit + 1])
        let layout = cmuxLayoutJSON(
            for: plan.tree,
            commands: [String(repeating: "x", count: cmuxLayoutLeafCommandByteLimit + 1)]
        )

        let pane = try XCTUnwrap(layout["pane"] as? [String: Any])
        let surface = try XCTUnwrap((pane["surfaces"] as? [[String: Any]])?.first)
        XCTAssertEqual(surface["type"] as? String, "terminal")
        XCTAssertNil(surface["command"])
    }

    func testWorkspaceListMatchingRequiresCustomTitleAndChoosesLowestIndex() throws {
        let response: [String: Any] = [
            "workspaces": [
                ["id": "untitled", "index": 0, "has_custom_title": false, "custom_title": "work"],
                ["id": "later", "index": 5, "has_custom_title": true, "custom_title": "work"],
                ["id": "first", "index": 2, "has_custom_title": true, "custom_title": "work"],
                ["id": "other", "index": 1, "has_custom_title": true, "custom_title": "else"],
            ]
        ]

        XCTAssertEqual(try cmuxMatchingWorkspaceID(from: response, named: "work"), "first")
        XCTAssertNil(try cmuxMatchingWorkspaceID(from: response, named: "missing"))
    }

    func testSurfaceListUsesWorkspaceScopeAndPreservesOwningPane() throws {
        let parameters = cmuxSurfaceListParameters(workspaceID: "workspace")
        XCTAssertEqual(parameters["workspace_id"] as? String, "workspace")
        XCTAssertNil(parameters["pane_id"])

        let entries = try cmuxSurfaceListEntries(from: [
            "surfaces": [[
                "id": "surface-1",
                "index_in_pane": 0,
                "pane_id": "pane-1",
            ]]
        ])
        XCTAssertEqual(entries, [
            CmuxSurfaceListEntry(
                surfaceID: "surface-1", indexInPane: 0, paneID: "pane-1"
            )
        ])
    }

    func testAlreadyCompletedCreateFailureIsTerminalAndNeverAuthorizesLaunchRetry() {
        let error = classifyCmuxCLIFailure(
            "Error: already_completed: workspace.create operation already completed"
        )

        guard case .cmuxRPCFailed = error else {
            return XCTFail("already_completed must remain a typed terminal RPC failure")
        }
        XCTAssertEqual(
            cmuxRecoveryAction(afterFirstFailure: error, launchAttempted: false),
            .rethrow
        )
    }

    func testLayoutExecutionEnumeratesByPaneIndexAndGuardsOnlyOversizeItems() throws {
        let commands = [String(repeating: "x", count: 1024), "echo short"]
        let plan = cmuxPlacementPlan(
            preset: .defaultPreset,
            commandByteCounts: commands.map(\.utf8.count),
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: commands.count)
        )
        var calls: [Call] = []
        let dependencies = makeDependencies(
            rpc: { method, params in
                calls.append(Call(method: method, params: params))
                switch method {
                case cmuxPaneListMethod:
                    return [
                        "panes": [
                            ["id": "pane-0", "index": 0],
                            ["id": "pane-1", "index": 1],
                        ]
                    ]
                case cmuxSurfaceListMethod:
                    XCTAssertNil(params["pane_id"])
                    return [
                        "surfaces": [
                            [
                                "id": "surface-1",
                                "index_in_pane": 0,
                                "pane_id": "pane-1",
                            ],
                            [
                                "id": "surface-0",
                                "index_in_pane": 0,
                                "pane_id": "pane-0",
                            ],
                        ]
                    ]
                case cmuxSurfaceSendTextMethod:
                    return ["queued": false]
                default:
                    return [:]
                }
            },
            createWorkspace: { params in
                calls.append(Call(method: cmuxWorkspaceCreateMethod, params: params))
                return ["workspace_id": "workspace-1", "surface_id": "focused-leaf"]
            }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: commands,
            using: dependencies
        )

        XCTAssertEqual(
            calls.map(\.method),
            [
                cmuxWorkspaceCreateMethod,
                cmuxPaneListMethod,
                cmuxSurfaceListMethod,
                cmuxSurfaceSendTextMethod,
            ]
        )
        let createParams = try XCTUnwrap(calls.first?.params)
        XCTAssertEqual(createParams["focus"] as? Bool, true)
        XCTAssertEqual(createParams["operation_id"] as? String, cmuxGroupedTestBatchID.uuidString)
        XCTAssertNil(createParams["title"])
        XCTAssertEqual(execution.path, .layoutCreate)
        XCTAssertFalse(execution.didFallbackToTabs)

        let handles = try successfulHandles(from: execution.results)
        XCTAssertEqual(handles.map(surfaceID), ["surface-0", "surface-1"])
        XCTAssertEqual(handles.map(workspaceID), ["workspace-1", "workspace-1"])
        let send = try XCTUnwrap(calls.last)
        XCTAssertEqual(send.params["surface_id"] as? String, "surface-0")
        XCTAssertEqual(send.params["text"] as? String, commands[0] + claudeSubmitKey)
    }

    func testFoundPaneExecutionUsesExplicitSplitTargetsAndMeasuredItemOrder() throws {
        let commands = ["one", "two", "three"]
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(
                identityMode: .fixedName("work"),
                arrangement: .panePerItem
            ),
            commandByteCounts: commands.map(\.utf8.count),
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: commands.count)
        )
        var calls: [Call] = []
        var splitTargets: [String] = []
        var splitDirections: [String] = []
        let dependencies = makeDependencies(
            rpc: { method, params in
                calls.append(Call(method: method, params: params))
                switch method {
                case cmuxWorkspaceListMethod:
                    return [
                        "workspaces": [[
                            "id": "workspace-found",
                            "index": 0,
                            "has_custom_title": true,
                            "custom_title": "work",
                        ]]
                    ]
                case cmuxPaneListMethod:
                    return [
                        "panes": [
                            ["id": "pane-0", "index": 0],
                            ["id": "pane-1", "index": 1],
                        ]
                    ]
                case cmuxSurfaceListMethod:
                    XCTAssertNil(params["pane_id"])
                    return [
                        "surfaces": [
                            [
                                "id": "other-surface",
                                "index_in_pane": 0,
                                "pane_id": "pane-1",
                            ],
                            [
                                "id": "root-surface",
                                "index_in_pane": 0,
                                "pane_id": "pane-0",
                            ],
                        ]
                    ]
                case cmuxSurfaceSplitMethod:
                    splitTargets.append(params["surface_id"] as? String ?? "")
                    splitDirections.append(params["direction"] as? String ?? "")
                    return ["surface_id": splitTargets.count == 1 ? "r0" : "r1"]
                case cmuxSurfaceSendTextMethod:
                    return ["queued": true]
                default:
                    return [:]
                }
            },
            createWorkspace: { _ in
                XCTFail("found workspace must not be created")
                return [:]
            }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: commands,
            using: dependencies
        )

        XCTAssertEqual(
            calls.map(\.method),
            [
                cmuxWorkspaceListMethod,
                cmuxPaneListMethod,
                cmuxSurfaceListMethod,
                cmuxSurfaceSplitMethod,
                cmuxSurfaceSplitMethod,
                cmuxSurfaceSendTextMethod,
                cmuxSurfaceSendTextMethod,
                cmuxSurfaceSendTextMethod,
            ]
        )
        XCTAssertEqual(splitTargets, ["root-surface", "root-surface"])
        XCTAssertEqual(splitDirections, ["down", "right"])
        XCTAssertEqual(execution.path, .foundSplit)
        XCTAssertEqual(
            try successfulHandles(from: execution.results).map(surfaceID),
            ["root-surface", "r1", "r0"]
        )
    }

    func testFoundPaneFailureUsesConservativeAllItemFailureWithoutRollback() throws {
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(
                identityMode: .fixedName("work"),
                arrangement: .panePerItem
            ),
            commandByteCounts: [1, 1, 1],
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: 3)
        )
        var methods: [String] = []
        let dependencies = makeDependencies(
            rpc: { method, params in
                methods.append(method)
                switch method {
                case cmuxWorkspaceListMethod:
                    return [
                        "workspaces": [[
                            "id": "workspace-found",
                            "index": 0,
                            "has_custom_title": true,
                            "custom_title": "work",
                        ]]
                    ]
                case cmuxPaneListMethod:
                    return [
                        "panes": [
                            ["id": "pane-0", "index": 0],
                            ["id": "pane-1", "index": 1],
                        ]
                    ]
                case cmuxSurfaceListMethod:
                    XCTAssertNil(params["pane_id"])
                    return [
                        "surfaces": [
                            [
                                "id": "other-surface",
                                "index_in_pane": 0,
                                "pane_id": "pane-1",
                            ],
                            [
                                "id": "root-surface",
                                "index_in_pane": 0,
                                "pane_id": "pane-0",
                            ],
                        ]
                    ]
                case cmuxSurfaceSplitMethod:
                    throw FixtureFailure(description: "split failed")
                default:
                    return [:]
                }
            },
            createWorkspace: { _ in XCTFail("found workspace must not be created"); return [:] }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: ["one", "two", "three"],
            using: dependencies
        )

        XCTAssertEqual(methods.last, cmuxSurfaceSplitMethod)
        XCTAssertEqual(execution.results.count, 3)
        for result in execution.results {
            guard case .failure = result else {
                return XCTFail("a failed split must fail every item under the conservative policy")
            }
        }
        XCTAssertFalse(methods.contains(cmuxSurfaceSendTextMethod))
    }

    func testCreatedTabsAddressEverySurfaceCreateToTheEnumeratedPane() throws {
        let commands = ["one", "two", "three"]
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(identityMode: .alwaysNew, arrangement: .tabPerItem),
            commandByteCounts: commands.map(\.utf8.count),
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: commands.count)
        )
        var calls: [Call] = []
        let dependencies = makeDependencies(
            rpc: { method, params in
                calls.append(Call(method: method, params: params))
                switch method {
                case cmuxPaneListMethod:
                    return ["panes": [["id": "pane-0", "index": 0]]]
                case cmuxSurfaceCreateMethod:
                    let index = calls.filter { $0.method == cmuxSurfaceCreateMethod }.count
                    return [
                        "workspace_id": "workspace-1",
                        "pane_id": "pane-0",
                        "surface_id": "surface-\(index)",
                    ]
                case cmuxSurfaceSendTextMethod:
                    return ["queued": false]
                default:
                    return [:]
                }
            },
            createWorkspace: { params in
                calls.append(Call(method: cmuxWorkspaceCreateMethod, params: params))
                return ["workspace_id": "workspace-1", "surface_id": "surface-0"]
            }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: commands,
            using: dependencies
        )

        XCTAssertEqual(
            calls.map(\.method),
            [
                cmuxWorkspaceCreateMethod,
                cmuxPaneListMethod,
                cmuxSurfaceCreateMethod,
                cmuxSurfaceCreateMethod,
                cmuxSurfaceSendTextMethod,
                cmuxSurfaceSendTextMethod,
                cmuxSurfaceSendTextMethod,
            ]
        )
        for call in calls where call.method == cmuxSurfaceCreateMethod {
            XCTAssertEqual(call.params["workspace_id"] as? String, "workspace-1")
            XCTAssertEqual(call.params["pane_id"] as? String, "pane-0")
        }
        XCTAssertEqual(execution.path, .tabCreate)
        XCTAssertEqual(
            try successfulHandles(from: execution.results).map(surfaceID),
            ["surface-0", "surface-1", "surface-2"]
        )
    }

    func testFoundTabsUseTheFirstPaneAndCreateOneSurfacePerItem() throws {
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(
                identityMode: .fixedName("work"),
                arrangement: .tabPerItem
            ),
            commandByteCounts: [1, 1],
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: 2)
        )
        var calls: [Call] = []
        let dependencies = makeDependencies(
            rpc: { method, params in
                calls.append(Call(method: method, params: params))
                switch method {
                case cmuxWorkspaceListMethod:
                    return [
                        "workspaces": [[
                            "id": "workspace-found",
                            "index": 1,
                            "has_custom_title": true,
                            "custom_title": "work",
                        ]]
                    ]
                case cmuxPaneListMethod:
                    return [
                        "panes": [
                            ["id": "pane-0", "index": 0],
                            ["id": "pane-1", "index": 1],
                        ]
                    ]
                case cmuxSurfaceCreateMethod:
                    let index = calls.filter { $0.method == cmuxSurfaceCreateMethod }.count
                    return [
                        "workspace_id": "workspace-found",
                        "pane_id": "pane-0",
                        "surface_id": "found-surface-\(index)",
                    ]
                case cmuxSurfaceSendTextMethod:
                    return ["queued": true]
                default:
                    return [:]
                }
            },
            createWorkspace: { _ in XCTFail("found workspace must not be created"); return [:] }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: ["one", "two"],
            using: dependencies
        )

        XCTAssertEqual(
            calls.map(\.method),
            [
                cmuxWorkspaceListMethod,
                cmuxPaneListMethod,
                cmuxSurfaceCreateMethod,
                cmuxSurfaceCreateMethod,
                cmuxSurfaceSendTextMethod,
                cmuxSurfaceSendTextMethod,
            ]
        )
        XCTAssertEqual(execution.path, .tabFound)
        XCTAssertTrue(calls.dropFirst(2).prefix(2).allSatisfy {
            ($0.params["pane_id"] as? String) == "pane-0"
                && ($0.params["workspace_id"] as? String) == "workspace-found"
        })
    }

    func testWorkspacePerItemCreatesIndependentCurrentWindowWorkspaces() throws {
        let commands = ["short", String(repeating: "x", count: 1024)]
        let itemIDs = cmuxGroupedTestItemIDs(count: commands.count)
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(
                identityMode: .fixedName("ignored"),
                arrangement: .workspacePerItem
            ),
            commandByteCounts: commands.map(\.utf8.count),
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: itemIDs
        )
        var calls: [Call] = []
        let dependencies = makeDependencies(
            rpc: { method, params in
                calls.append(Call(method: method, params: params))
                if method == cmuxSurfaceSendTextMethod { return ["queued": false] }
                return [:]
            },
            createWorkspace: { params in
                calls.append(Call(method: cmuxWorkspaceCreateMethod, params: params))
                let index = calls.filter { $0.method == cmuxWorkspaceCreateMethod }.count - 1
                return ["workspace_id": "workspace-\(index)", "surface_id": "surface-\(index)"]
            }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: commands,
            using: dependencies
        )

        XCTAssertEqual(
            calls.map(\.method),
            [
                cmuxWorkspaceCreateMethod,
                cmuxWorkspaceCreateMethod,
                cmuxSurfaceSendTextMethod,
            ]
        )
        let creates = calls.filter { $0.method == cmuxWorkspaceCreateMethod }
        XCTAssertEqual(creates.map { $0.params["operation_id"] as? String }, itemIDs.map(\.uuidString))
        XCTAssertTrue(creates.allSatisfy { ($0.params["title"] as? String) == nil })
        XCTAssertEqual(execution.path, .workspacePerItem)
    }

    func testWorkspacePerItemUsesEachSourceCommandInItsCreateLayout() throws {
        let commands = ["echo tc-e2e-d1", "echo tc-e2e-d2"]
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(
                identityMode: .alwaysNew,
                arrangement: .workspacePerItem
            ),
            commandByteCounts: commands.map(\.utf8.count),
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: commands.count)
        )
        var inlineCommandsByCreate: [[String]] = []
        let dependencies = makeDependencies(
            rpc: { method, _ in
                method == cmuxSurfaceSendTextMethod ? ["queued": false] : [:]
            },
            createWorkspace: { params in
                guard let layout = params["layout"] as? [String: Any] else {
                    XCTFail("workspace.create must carry a layout")
                    return [:]
                }
                inlineCommandsByCreate.append(inlineLeafCommands(in: layout))
                let index = inlineCommandsByCreate.count - 1
                return [
                    "workspace_id": "workspace-\(index)",
                    "surface_id": "surface-\(index)",
                ]
            }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: commands,
            using: dependencies
        )

        XCTAssertEqual(inlineCommandsByCreate, commands.map { [$0] })
        XCTAssertEqual(execution.results.count, commands.count)
        XCTAssertTrue(execution.results.allSatisfy { result in
            if case .success = result { return true }
            return false
        })
    }

    func testWorkspacePerItemRoutesAnOversizedLaterCommandToGuardedSend() throws {
        let commands = ["short", String(repeating: "x", count: 1024)]
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(
                identityMode: .alwaysNew,
                arrangement: .workspacePerItem
            ),
            commandByteCounts: commands.map(\.utf8.count),
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: commands.count)
        )
        var inlineCommandsByCreate: [[String]] = []
        var sentPayloads: [String] = []
        let dependencies = makeDependencies(
            rpc: { method, params in
                if method == cmuxSurfaceSendTextMethod {
                    sentPayloads.append(params["text"] as? String ?? "")
                    return ["queued": false]
                }
                return [:]
            },
            createWorkspace: { params in
                guard let layout = params["layout"] as? [String: Any] else {
                    XCTFail("workspace.create must carry a layout")
                    return [:]
                }
                inlineCommandsByCreate.append(inlineLeafCommands(in: layout))
                let index = inlineCommandsByCreate.count - 1
                return [
                    "workspace_id": "workspace-\(index)",
                    "surface_id": "surface-\(index)",
                ]
            }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: commands,
            using: dependencies
        )

        XCTAssertEqual(inlineCommandsByCreate, [[commands[0]], []])
        XCTAssertEqual(sentPayloads, [commands[1] + claudeSubmitKey])
        XCTAssertEqual(execution.results.count, commands.count)
        XCTAssertTrue(execution.results.allSatisfy { result in
            if case .success = result { return true }
            return false
        })
    }

    func testDeadlineStopsGuardedItemsBeforeSending() throws {
        let commands = [
            String(repeating: "x", count: 1024),
            String(repeating: "y", count: 1024),
        ]
        let plan = cmuxPlacementPlan(
            preset: .defaultPreset,
            commandByteCounts: commands.map(\.utf8.count),
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: commands.count)
        )
        var fakeMonotonicNow: TimeInterval = 0
        var sendCount = 0
        let dependencies = makeDependencies(
            rpc: { method, params in
                switch method {
                case cmuxPaneListMethod:
                    return [
                        "panes": [
                            ["id": "pane-0", "index": 0],
                            ["id": "pane-1", "index": 1],
                        ]
                    ]
                case cmuxSurfaceListMethod:
                    XCTAssertNil(params["pane_id"])
                    return [
                        "surfaces": [
                            [
                                "id": "surface-1",
                                "index_in_pane": 0,
                                "pane_id": "pane-1",
                            ],
                            [
                                "id": "surface-0",
                                "index_in_pane": 0,
                                "pane_id": "pane-0",
                            ],
                        ]
                    ]
                case cmuxSurfaceSendTextMethod:
                    sendCount += 1
                    fakeMonotonicNow = batchLaunchResponseBudget
                    return ["queued": false]
                default:
                    return [:]
                }
            },
            createWorkspace: { _ in
                ["workspace_id": "workspace-1", "surface_id": "surface-0"]
            },
            deadlineExceeded: { fakeMonotonicNow >= batchLaunchResponseBudget }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: commands,
            using: dependencies
        )

        XCTAssertEqual(sendCount, 1, "the deadline must stop the second guarded send")
        XCTAssertEqual(execution.results.count, 2)
        guard case .success = execution.results[0] else {
            return XCTFail("the item before the deadline should still succeed")
        }
        guard case .failure(let error) = execution.results[1] else {
            return XCTFail("the item at the deadline must fail closed")
        }
        XCTAssertEqual(String(describing: error), batchResponseDeadlineExceededMessage)
    }

    func testDeadlineDoesNotRelabelInlineCommandsAlreadyRunByLayoutCreate() throws {
        let commands = ["echo inline-one", "echo inline-two"]
        let plan = cmuxPlacementPlan(
            preset: .defaultPreset,
            commandByteCounts: commands.map(\.utf8.count),
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: commands.count)
        )
        var createCount = 0
        var inlineCommands: [String] = []
        let dependencies = makeDependencies(
            rpc: { method, _ in
                switch method {
                case cmuxPaneListMethod:
                    return [
                        "panes": [
                            ["id": "pane-0", "index": 0],
                            ["id": "pane-1", "index": 1],
                        ]
                    ]
                case cmuxSurfaceListMethod:
                    return [
                        "surfaces": [
                            ["id": "surface-0", "index_in_pane": 0, "pane_id": "pane-0"],
                            ["id": "surface-1", "index_in_pane": 0, "pane_id": "pane-1"],
                        ]
                    ]
                default:
                    return [:]
                }
            },
            createWorkspace: { params in
                createCount += 1
                guard let layout = params["layout"] as? [String: Any] else {
                    XCTFail("workspace.create must carry a layout")
                    return [:]
                }
                inlineCommands = inlineLeafCommands(in: layout)
                return ["workspace_id": "workspace-1", "surface_id": "surface-0"]
            },
            deadlineExceeded: { true }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: commands,
            using: dependencies
        )

        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(inlineCommands, commands)
        XCTAssertTrue(execution.results.allSatisfy { result in
            if case .success = result { return true }
            return false
        }, "a successful layout create must not be contradicted by not-launched results")
    }

    func testDeadlineStopsWorkspacePerItemCreatesBeforeTheNextSideEffect() throws {
        let commands = ["short-one", "short-two", "short-three"]
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(
                identityMode: .alwaysNew,
                arrangement: .workspacePerItem
            ),
            commandByteCounts: commands.map(\.utf8.count),
            batchOperationID: cmuxGroupedTestBatchID,
            itemOperationIDs: cmuxGroupedTestItemIDs(count: commands.count)
        )
        var createCount = 0
        let dependencies = makeDependencies(
            rpc: { method, _ in
                method == cmuxSurfaceSendTextMethod ? ["queued": false] : [:]
            },
            createWorkspace: { _ in
                createCount += 1
                return [
                    "workspace_id": "workspace-\(createCount)",
                    "surface_id": "surface-\(createCount)",
                ]
            },
            deadlineExceeded: { createCount >= 1 }
        )

        let execution = executeCmuxPlacementPlan(
            plan,
            commands: commands,
            using: dependencies
        )

        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(execution.results.count, commands.count)
        guard case .success = execution.results[0] else {
            return XCTFail("the create before the deadline should succeed")
        }
        for result in execution.results.dropFirst() {
            guard case .failure(let error) = result else {
                return XCTFail("items after the deadline must not launch")
            }
            XCTAssertEqual(String(describing: error), batchResponseDeadlineExceededMessage)
        }
    }

    func testCreateRecoveryReusesTheSameOperationParametersAfterMeasuredReachabilityFailure() throws {
        let context = CmuxRuntimeContext(
            cliPath: "/cmux",
            channel: .stable,
            socketPath: "/tmp/old.sock",
            launchAttempted: false
        )
        let params: [String: Any] = [
            "focus": true,
            "operation_id": cmuxGroupedTestRetryID.uuidString,
        ]
        var sockets: [String?] = []
        var attempts = 0
        var launches = 0
        let result = try cmuxCreateWorkspaceWithRecovery(
            context: context,
            params: params,
            rpc: { _, received, socketPath in
                attempts += 1
                sockets.append(socketPath)
                XCTAssertEqual(received["operation_id"] as? String, cmuxGroupedTestRetryID.uuidString)
                if attempts == 1 {
                    throw TerminalError.cmuxNotReachable("Error: Socket not found at /tmp/old.sock")
                }
                return ["workspace_id": "workspace-1", "surface_id": "surface-1"]
            },
            launch: {
                launches += 1
            },
            refreshedSocketPath: { "/tmp/new.sock" }
        )

        XCTAssertEqual(result["workspace_id"] as? String, "workspace-1")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(launches, 1)
        XCTAssertEqual(sockets, ["/tmp/old.sock", "/tmp/new.sock"])
        XCTAssertEqual(context.socketPath, "/tmp/new.sock")
    }

    private func makeDependencies(
        rpc: @escaping CmuxPlacementRPC,
        createWorkspace: @escaping ([String: Any]) throws -> [String: Any],
        deadlineExceeded: @escaping () -> Bool = { false }
    ) -> CmuxPlacementExecutionDependencies {
        CmuxPlacementExecutionDependencies(
            cliPath: "/cmux",
            currentSocketPath: { "/tmp/cmux.sock" },
            rpc: rpc,
            createWorkspace: createWorkspace,
            shellGate: { _, _ in .sendDespiteCanonical },
            deadlineExceeded: deadlineExceeded
        )
    }

    private func successfulHandles(
        from results: [Result<TerminalSessionHandle, Error>],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [TerminalSessionHandle] {
        try results.enumerated().map { index, result in
            guard case .success(let handle) = result else {
                XCTFail("item \(index) failed: \(result)", file: file, line: line)
                throw FixtureFailure(description: "missing successful handle")
            }
            return handle
        }
    }

    private func surfaceID(_ handle: TerminalSessionHandle) -> String {
        guard case .cmux(let surfaceID, _, _, _) = handle else {
            XCTFail("expected a cmux handle")
            return ""
        }
        return surfaceID
    }

    private func workspaceID(_ handle: TerminalSessionHandle) -> String {
        guard case .cmux(_, let workspaceID, _, _) = handle else {
            XCTFail("expected a cmux handle")
            return ""
        }
        return workspaceID
    }
}
