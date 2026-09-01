import Foundation

/// The keys owned by the app for the machine-local cmux placement preset.
///
/// These are deliberately separate values so the setup window can store the selected
/// identity mode, fixed workspace name, and arrangement independently.
public enum CmuxPlacementStorageKey {
    public static let identityMode = "cmuxPlacement.identityMode"
    public static let fixedName = "cmuxPlacement.fixedName"
    public static let arrangement = "cmuxPlacement.arrangement"
}

/// cmux placement addresses workspaces only. Window identity is intentionally not part of this
/// model: every unaddressed operation stays in cmux's current-window scope.
public enum CmuxPlacementIdentityMode: Equatable {
    case alwaysNew
    case fixedName(String)
}

public enum CmuxPlacementArrangement: Equatable {
    case tabPerItem
    case panePerItem
    case workspacePerItem

    public var rawValue: String {
        switch self {
        case .tabPerItem: return "tab"
        case .panePerItem: return "pane"
        case .workspacePerItem: return "workspace-per-item"
        }
    }
}

/// The app's one parsing boundary for the three raw UserDefaults values.
public struct CmuxPlacementPreset: Equatable {
    public let identityMode: CmuxPlacementIdentityMode
    public let arrangement: CmuxPlacementArrangement

    public static let defaultPreset = CmuxPlacementPreset(
        identityMode: .alwaysNew,
        arrangement: .panePerItem
    )

    public init(
        identityMode: CmuxPlacementIdentityMode,
        arrangement: CmuxPlacementArrangement
    ) {
        self.identityMode = identityMode
        self.arrangement = arrangement
    }

    /// Unknown raw values use the fresh-install defaults. An empty fixed name is not a usable
    /// address, so it is interpreted as always-new while preserving a valid arrangement value.
    public static func parse(
        rawIdentityMode: String?,
        rawFixedName: String?,
        rawArrangement: String?
    ) -> CmuxPlacementPreset {
        let arrangement: CmuxPlacementArrangement
        switch rawArrangement ?? "" {
        case CmuxPlacementArrangement.tabPerItem.rawValue:
            arrangement = .tabPerItem
        case CmuxPlacementArrangement.workspacePerItem.rawValue:
            arrangement = .workspacePerItem
        case CmuxPlacementArrangement.panePerItem.rawValue:
            arrangement = .panePerItem
        default:
            arrangement = .panePerItem
        }
        let identityMode: CmuxPlacementIdentityMode
        if rawIdentityMode == "fixed-name", let fixedName = rawFixedName, !fixedName.isEmpty {
            identityMode = .fixedName(fixedName)
        } else {
            identityMode = .alwaysNew
        }
        return CmuxPlacementPreset(identityMode: identityMode, arrangement: arrangement)
    }
}

public let cmuxLayoutLeafCommandByteLimit = 1023
public let cmuxPanePlacementItemLimit = 8

public enum CmuxPlacementCommandRoute: Equatable {
    case inlineLeaf
    case guardedSurfaceSend
}

public enum CmuxLayoutDirection: String, Equatable {
    case horizontal
    case vertical
}

public enum CmuxLayoutLeafCommand: Equatable {
    case inline
    case emptyForGuardedSend
}

/// A layout tree has exactly two children at every branch. There is no split field because the
/// measured even binary split is the cmux contract used by this plan.
public indirect enum CmuxLayoutNode: Equatable {
    case branch(
        direction: CmuxLayoutDirection,
        first: CmuxLayoutNode,
        second: CmuxLayoutNode
    )
    case leaf(itemIndex: Int, command: CmuxLayoutLeafCommand)
}

public struct CmuxLayoutPlan: Equatable {
    public let tree: CmuxLayoutNode
    public let leafItemOrder: [Int]
    public let itemRoutes: [CmuxPlacementCommandRoute]
    public let guardedItemIndices: [Int]

    public init(
        tree: CmuxLayoutNode,
        leafItemOrder: [Int],
        itemRoutes: [CmuxPlacementCommandRoute],
        guardedItemIndices: [Int]
    ) {
        self.tree = tree
        self.leafItemOrder = leafItemOrder
        self.itemRoutes = itemRoutes
        self.guardedItemIndices = guardedItemIndices
    }
}

public struct CmuxWorkspaceCreatePlan: Equatable {
    public let operationID: String
    public let title: String?
    public let layout: CmuxLayoutPlan

    public init(
        operationID: String,
        title: String?,
        layout: CmuxLayoutPlan
    ) {
        self.operationID = operationID
        self.title = title
        self.layout = layout
    }
}

public enum CmuxSurfaceSplitDirection: String, Equatable {
    case right
    case down
}

public enum CmuxSplitSurfaceReference: Equatable {
    case root
    case splitResponse(Int)
}

public struct CmuxSurfaceSplitOperation: Equatable {
    public let source: CmuxSplitSurfaceReference
    public let depth: Int
    public let direction: CmuxSurfaceSplitDirection
    public let originalLeafCount: Int
    public let newLeafCount: Int
    public let responseIndex: Int

    public init(
        source: CmuxSplitSurfaceReference,
        depth: Int,
        direction: CmuxSurfaceSplitDirection,
        originalLeafCount: Int,
        newLeafCount: Int,
        responseIndex: Int
    ) {
        self.source = source
        self.depth = depth
        self.direction = direction
        self.originalLeafCount = originalLeafCount
        self.newLeafCount = newLeafCount
        self.responseIndex = responseIndex
    }
}

public struct CmuxFoundWorkspacePanePlan: Equatable {
    public let rootPaneIndex: Int
    public let rootSurfaceIndex: Int
    public let splitOperations: [CmuxSurfaceSplitOperation]
    /// The runtime maps items to surfaces in recursive depth-first leaf order. New surfaces are
    /// represented by the IDs returned from the corresponding split responses.
    public let itemSurfaceOrder: [CmuxSplitSurfaceReference]
    public let itemRoutes: [CmuxPlacementCommandRoute]

    public init(
        rootPaneIndex: Int,
        rootSurfaceIndex: Int,
        splitOperations: [CmuxSurfaceSplitOperation],
        itemSurfaceOrder: [CmuxSplitSurfaceReference],
        itemRoutes: [CmuxPlacementCommandRoute]
    ) {
        self.rootPaneIndex = rootPaneIndex
        self.rootSurfaceIndex = rootSurfaceIndex
        self.splitOperations = splitOperations
        self.itemSurfaceOrder = itemSurfaceOrder
        self.itemRoutes = itemRoutes
    }
}

public struct CmuxPanePlacementPlan: Equatable {
    public let target: CmuxPlacementIdentityMode
    /// Always-new uses this branch; fixed-name uses it only when lookup finds no workspace.
    public let createIfMissing: CmuxWorkspaceCreatePlan?
    /// Fixed-name uses this branch when lookup finds the named workspace.
    public let found: CmuxFoundWorkspacePanePlan?

    public init(
        target: CmuxPlacementIdentityMode,
        createIfMissing: CmuxWorkspaceCreatePlan?,
        found: CmuxFoundWorkspacePanePlan?
    ) {
        self.target = target
        self.createIfMissing = createIfMissing
        self.found = found
    }
}

public struct CmuxTabPlacementPlan: Equatable {
    public let target: CmuxPlacementIdentityMode
    /// Always-new always uses this create. Fixed-name uses it only when lookup finds no workspace.
    public let createIfMissing: CmuxWorkspaceCreatePlan?
    /// Fixed-name selects pane.index 0 in the found workspace; always-new has no found pane.
    public let foundPaneIndex: Int?
    public let surfaceCreateCountWhenWorkspaceCreated: Int
    public let surfaceCreateCountWhenWorkspaceFound: Int
    public let itemRoutes: [CmuxPlacementCommandRoute]

    public init(
        target: CmuxPlacementIdentityMode,
        createIfMissing: CmuxWorkspaceCreatePlan?,
        foundPaneIndex: Int?,
        surfaceCreateCountWhenWorkspaceCreated: Int,
        surfaceCreateCountWhenWorkspaceFound: Int,
        itemRoutes: [CmuxPlacementCommandRoute]
    ) {
        self.target = target
        self.createIfMissing = createIfMissing
        self.foundPaneIndex = foundPaneIndex
        self.surfaceCreateCountWhenWorkspaceCreated = surfaceCreateCountWhenWorkspaceCreated
        self.surfaceCreateCountWhenWorkspaceFound = surfaceCreateCountWhenWorkspaceFound
        self.itemRoutes = itemRoutes
    }
}

public struct CmuxWorkspacePerItemPlan: Equatable {
    public let creates: [CmuxWorkspaceCreatePlan]
    public let itemRoutes: [CmuxPlacementCommandRoute]

    public init(
        creates: [CmuxWorkspaceCreatePlan],
        itemRoutes: [CmuxPlacementCommandRoute]
    ) {
        self.creates = creates
        self.itemRoutes = itemRoutes
    }
}

public enum CmuxPlacementPlanRoute: Equatable {
    case pane(CmuxPanePlacementPlan)
    case tab(CmuxTabPlacementPlan)
    case workspacePerItem(CmuxWorkspacePerItemPlan)
}

public struct CmuxPlacementPlan: Equatable {
    public let batchOperationID: UUID
    public let itemCount: Int
    public let requestedArrangement: CmuxPlacementArrangement
    public let effectiveArrangement: CmuxPlacementArrangement
    public let didFallbackToTabs: Bool
    public let route: CmuxPlacementPlanRoute

    public init(
        batchOperationID: UUID,
        itemCount: Int,
        requestedArrangement: CmuxPlacementArrangement,
        effectiveArrangement: CmuxPlacementArrangement,
        didFallbackToTabs: Bool,
        route: CmuxPlacementPlanRoute
    ) {
        self.batchOperationID = batchOperationID
        self.itemCount = itemCount
        self.requestedArrangement = requestedArrangement
        self.effectiveArrangement = effectiveArrangement
        self.didFallbackToTabs = didFallbackToTabs
        self.route = route
    }
}

/// Builds the balanced two-child layout used by a new pane-per-item workspace. Leaves are in
/// depth-first order, which is the order cmux reports through pane.index.
public func cmuxBalancedLayoutPlan(commandByteCounts: [Int]) -> CmuxLayoutPlan {
    precondition(!commandByteCounts.isEmpty)
    precondition(commandByteCounts.count <= cmuxPanePlacementItemLimit)

    let itemRoutes = commandByteCounts.map(commandRoute(forByteCount:))
    let indices = Array(commandByteCounts.indices)[...]
    let tree = makeBalancedLayoutNode(indices: indices, depth: 0, itemRoutes: itemRoutes)
    return CmuxLayoutPlan(
        tree: tree,
        leafItemOrder: Array(indices),
        itemRoutes: itemRoutes,
        guardedItemIndices: itemRoutes.indices.filter { itemRoutes[$0] == .guardedSurfaceSend }
    )
}

/// Builds the target-addressed split sequence for an already-existing fixed-name workspace.
/// The root is the first surface in pane.index 0. Splits start at depth 1 because that pane is
/// already half-width; the original branch receives ceil(n/2) leaves and the response receives
/// floor(n/2) leaves. Response indices stand for the surface IDs returned by cmux.
public func cmuxFoundWorkspacePanePlan(itemCount: Int) -> CmuxFoundWorkspacePanePlan {
    precondition(itemCount > 0)
    precondition(itemCount <= cmuxPanePlacementItemLimit)

    var splitOperations: [CmuxSurfaceSplitOperation] = []
    var nextResponseIndex = 0
    var itemSurfaceOrder: [CmuxSplitSurfaceReference] = []

    func visit(
        source: CmuxSplitSurfaceReference,
        leafCount: Int,
        depth: Int
    ) {
        guard leafCount > 1 else {
            itemSurfaceOrder.append(source)
            return
        }

        let originalLeafCount = (leafCount + 1) / 2
        let newLeafCount = leafCount / 2
        let response = CmuxSplitSurfaceReference.splitResponse(nextResponseIndex)
        splitOperations.append(
            CmuxSurfaceSplitOperation(
                source: source,
                depth: depth,
                direction: depth.isMultiple(of: 2) ? .right : .down,
                originalLeafCount: originalLeafCount,
                newLeafCount: newLeafCount,
                responseIndex: nextResponseIndex
            )
        )
        nextResponseIndex += 1

        visit(source: source, leafCount: originalLeafCount, depth: depth + 1)
        visit(source: response, leafCount: newLeafCount, depth: depth + 1)
    }

    visit(source: .root, leafCount: itemCount, depth: 1)
    return CmuxFoundWorkspacePanePlan(
        rootPaneIndex: 0,
        rootSurfaceIndex: 0,
        splitOperations: splitOperations,
        itemSurfaceOrder: itemSurfaceOrder,
        itemRoutes: Array(repeating: .guardedSurfaceSend, count: itemCount)
    )
}

/// Produces the pure placement plan consumed by the later cmux execution layer. The caller mints
/// the UUID keys; repeated execution of the same plan reuses those keys for a safe retry.
public func cmuxPlacementPlan(
    preset: CmuxPlacementPreset,
    commandByteCounts: [Int],
    batchOperationID: UUID,
    itemOperationIDs: [UUID]
) -> CmuxPlacementPlan {
    precondition(!commandByteCounts.isEmpty)
    precondition(commandByteCounts.count <= batchItemLimit)
    precondition(itemOperationIDs.count == commandByteCounts.count)

    let itemCount = commandByteCounts.count
    let operationID = batchOperationID.uuidString
    switch preset.arrangement {
    case .panePerItem:
        if itemCount > cmuxPanePlacementItemLimit {
            return CmuxPlacementPlan(
                batchOperationID: batchOperationID,
                itemCount: itemCount,
                requestedArrangement: .panePerItem,
                effectiveArrangement: .tabPerItem,
                didFallbackToTabs: true,
                route: .tab(makeTabPlacementPlan(
                    target: preset.identityMode,
                    commandByteCounts: commandByteCounts,
                    operationID: operationID
                ))
            )
        }

        let panePlan: CmuxPanePlacementPlan
        switch preset.identityMode {
        case .alwaysNew:
            panePlan = CmuxPanePlacementPlan(
                target: .alwaysNew,
                createIfMissing: makeWorkspaceCreatePlan(
                    commandByteCounts: commandByteCounts,
                    operationID: operationID,
                    title: nil
                ),
                found: nil
            )
        case .fixedName(let name):
            panePlan = CmuxPanePlacementPlan(
                target: .fixedName(name),
                createIfMissing: makeWorkspaceCreatePlan(
                    commandByteCounts: commandByteCounts,
                    operationID: operationID,
                    title: name
                ),
                found: cmuxFoundWorkspacePanePlan(itemCount: itemCount)
            )
        }
        return CmuxPlacementPlan(
            batchOperationID: batchOperationID,
            itemCount: itemCount,
            requestedArrangement: .panePerItem,
            effectiveArrangement: .panePerItem,
            didFallbackToTabs: false,
            route: .pane(panePlan)
        )

    case .tabPerItem:
        return CmuxPlacementPlan(
            batchOperationID: batchOperationID,
            itemCount: itemCount,
            requestedArrangement: .tabPerItem,
            effectiveArrangement: .tabPerItem,
            didFallbackToTabs: false,
            route: .tab(makeTabPlacementPlan(
                target: preset.identityMode,
                commandByteCounts: commandByteCounts,
                operationID: operationID
            ))
        )

    case .workspacePerItem:
        return CmuxPlacementPlan(
            batchOperationID: batchOperationID,
            itemCount: itemCount,
            requestedArrangement: .workspacePerItem,
            effectiveArrangement: .workspacePerItem,
            didFallbackToTabs: false,
            route: .workspacePerItem(makeWorkspacePerItemPlan(
                commandByteCounts: commandByteCounts,
                itemOperationIDs: itemOperationIDs
            ))
        )
    }
}

private func commandRoute(forByteCount byteCount: Int) -> CmuxPlacementCommandRoute {
    byteCount >= 0 && byteCount <= cmuxLayoutLeafCommandByteLimit
        ? .inlineLeaf
        : .guardedSurfaceSend
}

private func makeBalancedLayoutNode(
    indices: ArraySlice<Int>,
    depth: Int,
    itemRoutes: [CmuxPlacementCommandRoute]
) -> CmuxLayoutNode {
    if indices.count == 1 {
        let index = indices[indices.startIndex]
        let command: CmuxLayoutLeafCommand = itemRoutes[index] == .inlineLeaf
            ? .inline
            : .emptyForGuardedSend
        return .leaf(itemIndex: index, command: command)
    }

    let firstCount = (indices.count + 1) / 2
    let splitIndex = indices.index(indices.startIndex, offsetBy: firstCount)
    let first = makeBalancedLayoutNode(
        indices: indices[..<splitIndex],
        depth: depth + 1,
        itemRoutes: itemRoutes
    )
    let second = makeBalancedLayoutNode(
        indices: indices[splitIndex...],
        depth: depth + 1,
        itemRoutes: itemRoutes
    )
    return .branch(
        direction: depth.isMultiple(of: 2) ? .horizontal : .vertical,
        first: first,
        second: second
    )
}

private func makeWorkspaceCreatePlan(
    commandByteCounts: [Int],
    operationID: String,
    title: String?
) -> CmuxWorkspaceCreatePlan {
    CmuxWorkspaceCreatePlan(
        operationID: operationID,
        title: title,
        layout: cmuxBalancedLayoutPlan(commandByteCounts: commandByteCounts)
    )
}

private func makeEmptySurfaceCreatePlan(
    itemIndex: Int,
    operationID: String,
    title: String?
) -> CmuxWorkspaceCreatePlan {
    CmuxWorkspaceCreatePlan(
        operationID: operationID,
        title: title,
        layout: CmuxLayoutPlan(
            tree: .leaf(itemIndex: itemIndex, command: .emptyForGuardedSend),
            leafItemOrder: [itemIndex],
            itemRoutes: [.guardedSurfaceSend],
            guardedItemIndices: [itemIndex]
        )
    )
}

private func makeTabPlacementPlan(
    target: CmuxPlacementIdentityMode,
    commandByteCounts: [Int],
    operationID: String
) -> CmuxTabPlacementPlan {
    let title: String?
    let foundPaneIndex: Int?
    switch target {
    case .alwaysNew:
        title = nil
        foundPaneIndex = nil
    case .fixedName(let name):
        title = name
        foundPaneIndex = 0
    }

    return CmuxTabPlacementPlan(
        target: target,
        createIfMissing: makeEmptySurfaceCreatePlan(
            itemIndex: 0,
            operationID: operationID,
            title: title
        ),
        foundPaneIndex: foundPaneIndex,
        surfaceCreateCountWhenWorkspaceCreated: max(commandByteCounts.count - 1, 0),
        surfaceCreateCountWhenWorkspaceFound: foundPaneIndex == nil ? 0 : commandByteCounts.count,
        itemRoutes: Array(repeating: .guardedSurfaceSend, count: commandByteCounts.count)
    )
}

private func makeWorkspacePerItemPlan(
    commandByteCounts: [Int],
    itemOperationIDs: [UUID]
) -> CmuxWorkspacePerItemPlan {
    let creates = commandByteCounts.indices.map { index in
        makeWorkspaceCreatePlan(
            commandByteCounts: [commandByteCounts[index]],
            operationID: itemOperationIDs[index].uuidString,
            title: nil
        )
    }
    return CmuxWorkspacePerItemPlan(
        creates: creates,
        itemRoutes: commandByteCounts.map(commandRoute(forByteCount:))
    )
}
