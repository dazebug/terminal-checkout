import Foundation
import XCTest
@testable import Core

private let cmuxPlacementTestBatchID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
private let cmuxPlacementTestOtherBatchID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

private func cmuxPlacementTestItemIDs(count: Int) -> [UUID] {
    (0..<count).map { index in
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!
    }
}

final class CmuxPlacementTests: XCTestCase {
    func testUnknownPresetValuesUseFreshDefaults() {
        let preset = CmuxPlacementPreset.parse(
            rawIdentityMode: "unknown-identity",
            rawFixedName: "unused",
            rawArrangement: "unknown-arrangement"
        )

        XCTAssertEqual(preset, .defaultPreset)
    }

    func testEmptyFixedNameFallsBackToAlwaysNewWithoutChangingArrangement() {
        let preset = CmuxPlacementPreset.parse(
            rawIdentityMode: "fixed-name",
            rawFixedName: "",
            rawArrangement: CmuxPlacementArrangement.tabPerItem.rawValue
        )

        XCTAssertEqual(preset.identityMode, .alwaysNew)
        XCTAssertEqual(preset.arrangement, .tabPerItem)

        let fixed = CmuxPlacementPreset.parse(
            rawIdentityMode: "fixed-name",
            rawFixedName: "work",
            rawArrangement: CmuxPlacementArrangement.panePerItem.rawValue
        )
        XCTAssertEqual(fixed.identityMode, .fixedName("work"))
        XCTAssertEqual(fixed.arrangement, .panePerItem)
    }

    func testDefaultPresetUsesWorkspaceAlwaysNewAndPane() {
        let preset = CmuxPlacementPreset.parse(
            rawIdentityMode: nil,
            rawFixedName: nil,
            rawArrangement: nil
        )

        XCTAssertEqual(preset.identityMode, .alwaysNew)
        XCTAssertEqual(preset.arrangement, .panePerItem)
    }

    func testBalancedLayoutKeepsDepthFirstItemOrderAndAlternatesDirections() {
        XCTAssertEqual(
            cmuxBalancedLayoutPlan(commandByteCounts: [10]).leafItemOrder,
            [0]
        )
        XCTAssertEqual(
            cmuxBalancedLayoutPlan(commandByteCounts: [10, 10]).leafItemOrder,
            [0, 1]
        )

        let eight = cmuxBalancedLayoutPlan(commandByteCounts: Array(repeating: 10, count: 8))
        XCTAssertEqual(eight.leafItemOrder, Array(0..<8))
        XCTAssertEqual(
            branchDirections(in: eight.tree),
            [.horizontal, .vertical, .horizontal, .horizontal, .vertical, .horizontal, .horizontal]
        )
    }

    func testPaneLayoutUsesInlineOnlyThroughThe1023ByteBoundary() {
        let preset = CmuxPlacementPreset(identityMode: .alwaysNew, arrangement: .panePerItem)
        let plan = cmuxPlacementPlan(
            preset: preset,
            commandByteCounts: [1023, 1024, 1025],
            batchOperationID: cmuxPlacementTestBatchID,
            itemOperationIDs: cmuxPlacementTestItemIDs(count: 3)
        )

        guard case .pane(let pane) = plan.route else {
            return XCTFail("expected a pane placement route")
        }
        XCTAssertEqual(pane.createIfMissing?.layout.itemRoutes, [.inlineLeaf, .guardedSurfaceSend, .guardedSurfaceSend])
        XCTAssertEqual(pane.createIfMissing?.layout.guardedItemIndices, [1, 2])
    }

    func testMultibyteCommandSizesUseTheSame1023ByteBoundary() {
        let commands = [
            String(repeating: "a", count: 1020) + "가",
            String(repeating: "a", count: 1021) + "가",
            String(repeating: "a", count: 1022) + "가"
        ]
        XCTAssertEqual(commands.map { $0.utf8.count }, [1023, 1024, 1025])

        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset.defaultPreset,
            commandByteCounts: commands.map { $0.utf8.count },
            batchOperationID: cmuxPlacementTestBatchID,
            itemOperationIDs: cmuxPlacementTestItemIDs(count: 3)
        )

        guard case .pane(let pane) = plan.route else {
            return XCTFail("expected a pane placement route")
        }
        XCTAssertEqual(pane.createIfMissing?.layout.itemRoutes, [.inlineLeaf, .guardedSurfaceSend, .guardedSurfaceSend])
    }

    func testPanePlacementFallsBackToTabsAfterEightItems() {
        let identities: [CmuxPlacementIdentityMode] = [.alwaysNew, .fixedName("work")]
        for count in [9, 25] {
            for identity in identities {
                let plan = cmuxPlacementPlan(
                    preset: CmuxPlacementPreset(identityMode: identity, arrangement: .panePerItem),
                    commandByteCounts: Array(repeating: 10, count: count),
                    batchOperationID: cmuxPlacementTestBatchID,
                    itemOperationIDs: cmuxPlacementTestItemIDs(count: count)
                )

                XCTAssertTrue(plan.didFallbackToTabs)
                XCTAssertEqual(plan.itemCount, count)
                XCTAssertEqual(plan.requestedArrangement, .panePerItem)
                XCTAssertEqual(plan.effectiveArrangement, .tabPerItem)
                guard case .tab(let tabs) = plan.route else {
                    return XCTFail("expected a tab fallback route")
                }
                XCTAssertEqual(tabs.target, identity)
                XCTAssertEqual(tabs.itemRoutes, Array(repeating: .guardedSurfaceSend, count: count))
                if case .fixedName = identity {
                    XCTAssertEqual(tabs.foundPaneIndex, 0)
                } else {
                    XCTAssertNil(tabs.foundPaneIndex)
                }
            }
        }
    }

    func testFoundPanePlanUsesTheMeasuredBalancedSplitSequence() {
        let expected: [(Int, [CmuxSurfaceSplitDirection], [Int], [CmuxSplitSurfaceReference])] = [
            (3, [.down, .right], [1, 2], [.root, .splitResponse(1), .splitResponse(0)]),
            (
                5,
                [.down, .right, .down, .right],
                [1, 2, 3, 2],
                [.root, .splitResponse(2), .splitResponse(1), .splitResponse(0), .splitResponse(3)]
            ),
            (
                8,
                [.down, .right, .down, .down, .right, .down, .down],
                [1, 2, 3, 3, 2, 3, 3],
                [
                    .root,
                    .splitResponse(2),
                    .splitResponse(1),
                    .splitResponse(3),
                    .splitResponse(0),
                    .splitResponse(5),
                    .splitResponse(4),
                    .splitResponse(6),
                ]
            )
        ]

        for (count, directions, depths, surfaceOrder) in expected {
            let found = cmuxFoundWorkspacePanePlan(itemCount: count)

            XCTAssertEqual(found.rootPaneIndex, 0)
            XCTAssertEqual(found.rootSurfaceIndex, 0)
            XCTAssertEqual(found.splitOperations.map(\.direction), directions)
            XCTAssertEqual(found.splitOperations.map(\.depth), depths)
            XCTAssertEqual(found.splitOperations.map(\.responseIndex), Array(0..<(count - 1)))
            XCTAssertEqual(found.itemSurfaceOrder.count, count)
            XCTAssertEqual(found.itemSurfaceOrder.first, Optional(CmuxSplitSurfaceReference.root))
            XCTAssertEqual(found.itemSurfaceOrder, surfaceOrder)

            let responseIndices = found.itemSurfaceOrder.compactMap { reference -> Int? in
                guard case .splitResponse(let index) = reference else { return nil }
                return index
            }
            XCTAssertEqual(Set(responseIndices), Set(0..<(count - 1)))
        }
    }

    func testFixedPanePlanCarriesFoundAndCreateBranches() {
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(identityMode: .fixedName("work"), arrangement: .panePerItem),
            commandByteCounts: Array(repeating: 10, count: 5),
            batchOperationID: cmuxPlacementTestBatchID,
            itemOperationIDs: cmuxPlacementTestItemIDs(count: 5)
        )

        guard case .pane(let pane) = plan.route else {
            return XCTFail("expected a pane placement route")
        }
        XCTAssertEqual(pane.target, .fixedName("work"))
        XCTAssertEqual(pane.createIfMissing?.operationID, cmuxPlacementTestBatchID.uuidString)
        XCTAssertEqual(pane.createIfMissing?.title, "work")
        XCTAssertEqual(pane.found?.rootPaneIndex, 0)
        XCTAssertEqual(pane.found?.rootSurfaceIndex, 0)
        XCTAssertEqual(pane.found?.splitOperations.count, 4)
        XCTAssertEqual(
            pane.found?.itemRoutes,
            Array(repeating: .guardedSurfaceSend, count: 5)
        )
    }

    func testTabPlacementCreatesExpectedSurfaceCountsAndGuardsCommands() {
        let fresh = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(identityMode: .alwaysNew, arrangement: .tabPerItem),
            commandByteCounts: Array(repeating: 10, count: 3),
            batchOperationID: cmuxPlacementTestBatchID,
            itemOperationIDs: cmuxPlacementTestItemIDs(count: 3)
        )
        guard case .tab(let freshTabs) = fresh.route else {
            return XCTFail("expected a tab placement route")
        }
        XCTAssertEqual(freshTabs.createIfMissing?.operationID, cmuxPlacementTestBatchID.uuidString)
        XCTAssertEqual(freshTabs.surfaceCreateCountWhenWorkspaceCreated, 2)
        XCTAssertEqual(freshTabs.surfaceCreateCountWhenWorkspaceFound, 0)
        XCTAssertNil(freshTabs.foundPaneIndex)
        XCTAssertEqual(freshTabs.itemRoutes, Array(repeating: .guardedSurfaceSend, count: 3))

        let fixed = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(identityMode: .fixedName("work"), arrangement: .tabPerItem),
            commandByteCounts: Array(repeating: 10, count: 3),
            batchOperationID: cmuxPlacementTestBatchID,
            itemOperationIDs: cmuxPlacementTestItemIDs(count: 3)
        )
        guard case .tab(let fixedTabs) = fixed.route else {
            return XCTFail("expected a tab placement route")
        }
        XCTAssertEqual(fixedTabs.createIfMissing?.title, "work")
        XCTAssertEqual(fixedTabs.foundPaneIndex, 0)
        XCTAssertEqual(fixedTabs.surfaceCreateCountWhenWorkspaceCreated, 2)
        XCTAssertEqual(fixedTabs.surfaceCreateCountWhenWorkspaceFound, 3)
    }

    func testWorkspacePerItemIgnoresIdentityModeAndCreatesCurrentWindowWorkspaces() {
        let itemIDs = cmuxPlacementTestItemIDs(count: 2)
        let plan = cmuxPlacementPlan(
            preset: CmuxPlacementPreset(identityMode: .fixedName("ignored"), arrangement: .workspacePerItem),
            commandByteCounts: [10, 1024],
            batchOperationID: cmuxPlacementTestBatchID,
            itemOperationIDs: itemIDs
        )

        guard case .workspacePerItem(let workspaces) = plan.route else {
            return XCTFail("expected a workspace-per-item route")
        }
        XCTAssertEqual(workspaces.creates.map(\.operationID), itemIDs.map(\.uuidString))
        let noStrings = Array<String?>(repeating: nil, count: 2)
        XCTAssertEqual(workspaces.creates.map(\.title), noStrings)
        XCTAssertEqual(workspaces.creates[0].layout.itemRoutes, [.inlineLeaf])
        XCTAssertEqual(workspaces.creates[1].layout.itemRoutes, [.guardedSurfaceSend])
        XCTAssertEqual(workspaces.itemRoutes, [.inlineLeaf, .guardedSurfaceSend])
    }

    func testPlacementPlansKeepCallerOperationIDStable() {
        let preset = CmuxPlacementPreset.defaultPreset
        let itemIDs = cmuxPlacementTestItemIDs(count: 2)
        let first = cmuxPlacementPlan(
            preset: preset,
            commandByteCounts: [10, 20],
            batchOperationID: cmuxPlacementTestBatchID,
            itemOperationIDs: itemIDs
        )
        let second = cmuxPlacementPlan(
            preset: preset,
            commandByteCounts: [10, 20],
            batchOperationID: cmuxPlacementTestBatchID,
            itemOperationIDs: itemIDs
        )
        let different = cmuxPlacementPlan(
            preset: preset,
            commandByteCounts: [10, 20],
            batchOperationID: cmuxPlacementTestOtherBatchID,
            itemOperationIDs: itemIDs
        )

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual(first.batchOperationID, cmuxPlacementTestBatchID)
    }

    private func branchDirections(in node: CmuxLayoutNode) -> [CmuxLayoutDirection] {
        switch node {
        case .leaf:
            return []
        case .branch(let direction, let first, let second):
            return [direction] + branchDirections(in: first) + branchDirections(in: second)
        }
    }
}
