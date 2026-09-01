import Foundation

public typealias CmuxPlacementRPC = (
    _ method: String, _ params: [String: Any]
) throws -> [String: Any]

public typealias CmuxPlacementShellGate = (
    _ surfaceID: String, _ payloadByteCount: Int
) -> CmuxCommandGate

public enum CmuxPlacementExecutionPath: Equatable {
    case layoutCreate
    case foundSplit
    case tabCreate
    case tabFound
    case workspacePerItem
}

public struct CmuxGroupedExecution {
    public let results: [Result<TerminalSessionHandle, Error>]
    public let path: CmuxPlacementExecutionPath
    public let didFallbackToTabs: Bool

    public init(
        results: [Result<TerminalSessionHandle, Error>],
        path: CmuxPlacementExecutionPath,
        didFallbackToTabs: Bool
    ) {
        self.results = results
        self.path = path
        self.didFallbackToTabs = didFallbackToTabs
    }
}

/// The grouped executor receives the one cmux RPC door and the existing shell-reading gate as
/// dependencies. Tests can record the complete sequence without opening a cmux socket; production
/// supplies closures that call cmuxRPC and cmuxAwaitShellReading with the shared runtime context.
public struct CmuxPlacementExecutionDependencies {
    public let cliPath: String
    public let currentSocketPath: () -> String?
    public let rpc: CmuxPlacementRPC
    public let createWorkspace: ([String: Any]) throws -> [String: Any]
    public let shellGate: CmuxPlacementShellGate

    public init(
        cliPath: String,
        currentSocketPath: @escaping () -> String?,
        rpc: @escaping CmuxPlacementRPC,
        createWorkspace: @escaping ([String: Any]) throws -> [String: Any],
        shellGate: @escaping CmuxPlacementShellGate
    ) {
        self.cliPath = cliPath
        self.currentSocketPath = currentSocketPath
        self.rpc = rpc
        self.createWorkspace = createWorkspace
        self.shellGate = shellGate
    }
}

public enum CmuxPlacementResponseError: Error, Equatable, CustomStringConvertible {
    case missingField(String)
    case invalidShape(String)

    public var description: String {
        switch self {
        case .missingField(let field): return "cmux response missing \(field)"
        case .invalidShape(let shape): return "cmux response has invalid \(shape)"
        }
    }
}

public struct CmuxPaneListEntry: Equatable {
    public let paneID: String
    public let index: Int

    public init(paneID: String, index: Int) {
        self.paneID = paneID
        self.index = index
    }
}

public struct CmuxSurfaceListEntry: Equatable {
    public let surfaceID: String
    public let indexInPane: Int

    public init(surfaceID: String, indexInPane: Int) {
        self.surfaceID = surfaceID
        self.indexInPane = indexInPane
    }
}

/// Converts the pure placement tree to the measured cmux layout object. The conversion never adds
/// the submit byte: cmux appends that byte to an inline leaf command itself.
public func cmuxLayoutJSON(
    for node: CmuxLayoutNode, commands: [String]
) -> [String: Any] {
    switch node {
    case .branch(let direction, let first, let second):
        return [
            "direction": direction.rawValue,
            "children": [
                cmuxLayoutJSON(for: first, commands: commands),
                cmuxLayoutJSON(for: second, commands: commands),
            ],
        ]
    case .leaf(let itemIndex, let commandRoute):
        precondition(commands.indices.contains(itemIndex))
        var surface: [String: Any] = ["type": "terminal"]
        if commandRoute == .inline {
            surface["command"] = commands[itemIndex]
        }
        return ["pane": ["surfaces": [surface]]]
    }
}

public func cmuxMatchingWorkspaceID(
    from response: [String: Any], named name: String
) throws -> String? {
    guard let rawWorkspaces = response["workspaces"] else {
        throw CmuxPlacementResponseError.missingField("workspaces")
    }
    guard let workspaces = rawWorkspaces as? [[String: Any]] else {
        throw CmuxPlacementResponseError.invalidShape("workspaces")
    }

    var matches: [(index: Int, workspaceID: String)] = []
    for workspace in workspaces {
        let hasCustomTitle = workspace["has_custom_title"] as? Bool == true
        let customTitle = workspace["custom_title"] as? String
        guard hasCustomTitle, customTitle == name else {
            continue
        }
        guard let index = workspace["index"] as? Int else {
            throw CmuxPlacementResponseError.missingField("index")
        }
        guard let workspaceID = workspace["id"] as? String, !workspaceID.isEmpty else {
            throw CmuxPlacementResponseError.missingField("id")
        }
        matches.append((index: index, workspaceID: workspaceID))
    }
    return matches.min { lhs, rhs in
        lhs.index == rhs.index ? lhs.workspaceID < rhs.workspaceID : lhs.index < rhs.index
    }?.workspaceID
}

public func cmuxPaneListEntries(
    from response: [String: Any]
) throws -> [CmuxPaneListEntry] {
    guard let rawPanes = response["panes"] else {
        throw CmuxPlacementResponseError.missingField("panes")
    }
    guard let panes = rawPanes as? [[String: Any]] else {
        throw CmuxPlacementResponseError.invalidShape("panes")
    }
    return try panes.map { pane in
        guard let paneID = pane["id"] as? String, !paneID.isEmpty else {
            throw CmuxPlacementResponseError.missingField("id")
        }
        guard let index = pane["index"] as? Int else {
            throw CmuxPlacementResponseError.missingField("index")
        }
        return CmuxPaneListEntry(paneID: paneID, index: index)
    }
}

public func cmuxSurfaceListEntries(
    from response: [String: Any]
) throws -> [CmuxSurfaceListEntry] {
    guard let rawSurfaces = response["surfaces"] else {
        throw CmuxPlacementResponseError.missingField("surfaces")
    }
    guard let surfaces = rawSurfaces as? [[String: Any]] else {
        throw CmuxPlacementResponseError.invalidShape("surfaces")
    }
    return try surfaces.map { surface in
        guard let surfaceID = surface["id"] as? String, !surfaceID.isEmpty else {
            throw CmuxPlacementResponseError.missingField("id")
        }
        guard let index = surface["index_in_pane"] as? Int else {
            throw CmuxPlacementResponseError.missingField("index_in_pane")
        }
        return CmuxSurfaceListEntry(surfaceID: surfaceID, indexInPane: index)
    }
}

public func cmuxResolvedSurfaceID(from response: [String: Any]) throws -> String {
    guard let surfaceID = response["surface_id"] as? String, !surfaceID.isEmpty else {
        throw CmuxPlacementResponseError.missingField("surface_id")
    }
    return surfaceID
}

public func cmuxResolveFoundSurfaceIDs(
    rootSurfaceID: String,
    splitResponseSurfaceIDs: [String],
    itemSurfaceOrder: [CmuxSplitSurfaceReference]
) throws -> [String] {
    try itemSurfaceOrder.map { reference in
        switch reference {
        case .root:
            return rootSurfaceID
        case .splitResponse(let index):
            guard splitResponseSurfaceIDs.indices.contains(index) else {
                throw CmuxPlacementResponseError.invalidShape("split response index")
            }
            return splitResponseSurfaceIDs[index]
        }
    }
}

private func groupedFailure(
    count: Int, error: Error
) -> [Result<TerminalSessionHandle, Error>] {
    Array(repeating: .failure(error), count: count)
}

private func failedExecution(
    plan: CmuxPlacementPlan,
    path: CmuxPlacementExecutionPath,
    error: Error
) -> CmuxGroupedExecution {
    CmuxGroupedExecution(
        results: groupedFailure(count: plan.itemCount, error: error),
        path: path,
        didFallbackToTabs: plan.didFallbackToTabs
    )
}

private func enumeratedSurfaceIDs(
    workspaceID: String,
    leafItemOrder: [Int],
    using dependencies: CmuxPlacementExecutionDependencies
) throws -> [String] {
    let paneResponse = try dependencies.rpc(
        cmuxPaneListMethod,
        cmuxPaneListParameters(workspaceID: workspaceID)
    )
    let unsortedPanes = try cmuxPaneListEntries(from: paneResponse)
    guard unsortedPanes.map(\.index).sorted() == Array(0..<unsortedPanes.count),
          Set(unsortedPanes.map(\.index)).count == unsortedPanes.count else {
        throw CmuxPlacementResponseError.invalidShape("pane.index sequence")
    }
    let panes = unsortedPanes.sorted { lhs, rhs in
        lhs.index == rhs.index ? lhs.paneID < rhs.paneID : lhs.index < rhs.index
    }

    var surfaces: [(paneIndex: Int, surfaceIndex: Int, surfaceID: String)] = []
    for pane in panes {
        let response = try dependencies.rpc(
            cmuxSurfaceListMethod,
            cmuxSurfaceListParameters(workspaceID: workspaceID, paneID: pane.paneID)
        )
        let unsortedEntries = try cmuxSurfaceListEntries(from: response)
        guard unsortedEntries.map(\.indexInPane).sorted() == Array(0..<unsortedEntries.count),
              Set(unsortedEntries.map(\.indexInPane)).count == unsortedEntries.count else {
            throw CmuxPlacementResponseError.invalidShape("surface.index_in_pane sequence")
        }
        let entries = unsortedEntries.sorted { lhs, rhs in
            lhs.indexInPane == rhs.indexInPane
                ? lhs.surfaceID < rhs.surfaceID
                : lhs.indexInPane < rhs.indexInPane
        }
        surfaces.append(contentsOf: entries.map {
            (paneIndex: pane.index, surfaceIndex: $0.indexInPane, surfaceID: $0.surfaceID)
        })
    }
    surfaces.sort {
        if $0.paneIndex != $1.paneIndex { return $0.paneIndex < $1.paneIndex }
        if $0.surfaceIndex != $1.surfaceIndex { return $0.surfaceIndex < $1.surfaceIndex }
        return $0.surfaceID < $1.surfaceID
    }

    guard leafItemOrder.count == surfaces.count,
          leafItemOrder.allSatisfy({ surfaces.indices.contains($0) }) else {
        throw CmuxPlacementResponseError.invalidShape("layout surface enumeration")
    }
    return leafItemOrder.map { surfaces[$0].surfaceID }
}

private func firstPaneID(
    from response: [String: Any], expectedIndex: Int
) throws -> String {
    let panes = try cmuxPaneListEntries(from: response)
    let matches = panes.filter { $0.index == expectedIndex }
    guard matches.count == 1, let pane = matches.first else {
        throw CmuxPlacementResponseError.invalidShape("pane.index \(expectedIndex)")
    }
    return pane.paneID
}

private func firstSurfaceID(
    workspaceID: String,
    paneID: String,
    expectedIndex: Int,
    using dependencies: CmuxPlacementExecutionDependencies
) throws -> String {
    let response = try dependencies.rpc(
        cmuxSurfaceListMethod,
        cmuxSurfaceListParameters(workspaceID: workspaceID, paneID: paneID)
    )
    let surfaces = try cmuxSurfaceListEntries(from: response)
    let matches = surfaces.filter { $0.indexInPane == expectedIndex }
    guard matches.count == 1, let surface = matches.first else {
        throw CmuxPlacementResponseError.invalidShape(
            "surface.index_in_pane \(expectedIndex)"
        )
    }
    return surface.surfaceID
}

private func sourceSurfaceID(
    _ reference: CmuxSplitSurfaceReference,
    rootSurfaceID: String,
    responseSurfaceIDs: [String]
) throws -> String {
    switch reference {
    case .root:
        return rootSurfaceID
    case .splitResponse(let index):
        guard responseSurfaceIDs.indices.contains(index), !responseSurfaceIDs[index].isEmpty else {
            throw CmuxPlacementResponseError.invalidShape("split source reference")
        }
        return responseSurfaceIDs[index]
    }
}

private func sendGuardedCommand(
    _ command: String,
    to surfaceID: String,
    using dependencies: CmuxPlacementExecutionDependencies
) throws {
    let payload = command + claudeSubmitKey
    switch dependencies.shellGate(surfaceID, payload.utf8.count) {
    case .send:
        break
    case .sendDespiteCanonical:
        checkoutLog(
            "cmux pane has not confirmed raw mode; sending "
                + String(payload.utf8.count)
                + " bytes inside the canonical line limit without waiting for raw mode"
        )
    case .waitLonger:
        throw TerminalError.cmuxRPCFailed(
            cmuxSurfaceSendTextMethod + ": shell-reading gate returned waitLonger"
        )
    case .refuseTooLong:
        throw TerminalError.cmuxRPCFailed(
            cmuxSurfaceSendTextMethod + ": payload exceeds the canonical line buffer; nothing was sent"
        )
    }

    let response = try dependencies.rpc(
        cmuxSurfaceSendTextMethod,
        cmuxSurfaceSendTextParameters(surfaceID: surfaceID, text: payload)
    )
    if response["queued"] as? Bool == true {
        checkoutLog("cmux \(cmuxSurfaceSendTextMethod) queued=true")
    }
}

private func itemResults(
    surfaceIDs: [String?],
    commands: [String],
    itemRoutes: [CmuxPlacementCommandRoute],
    workspaceID: String,
    using dependencies: CmuxPlacementExecutionDependencies,
    itemErrors: [Error?] = []
) -> [Result<TerminalSessionHandle, Error>] {
    guard surfaceIDs.count == commands.count,
          itemRoutes.count == commands.count,
          itemErrors.isEmpty || itemErrors.count == commands.count else {
        let error = CmuxPlacementResponseError.invalidShape("item surface mapping")
        return groupedFailure(count: commands.count, error: error)
    }

    return commands.indices.map { index in
        if let error = itemErrors.isEmpty ? nil : itemErrors[index] {
            return .failure(error)
        }
        guard let surfaceID = surfaceIDs[index], !surfaceID.isEmpty else {
            return .failure(
                CmuxPlacementResponseError.invalidShape("surface for item \(index)")
            )
        }
        do {
            if itemRoutes[index] == .guardedSurfaceSend {
                try sendGuardedCommand(
                    commands[index], to: surfaceID, using: dependencies
                )
            }
            return .success(
                TerminalSessionHandle.cmux(
                    surfaceID: surfaceID,
                    workspaceID: workspaceID,
                    cliPath: dependencies.cliPath,
                    socketPath: dependencies.currentSocketPath()
                )
            )
        } catch {
            return .failure(error)
        }
    }
}

private func layoutCommandsAreSafe(
    _ node: CmuxLayoutNode, commands: [String]
) -> Bool {
    switch node {
    case .branch(_, let first, let second):
        return layoutCommandsAreSafe(first, commands: commands)
            && layoutCommandsAreSafe(second, commands: commands)
    case .leaf(let itemIndex, let command):
        guard commands.indices.contains(itemIndex) else { return false }
        switch command {
        case .inline:
            return commands[itemIndex].utf8.count <= cmuxLayoutLeafCommandByteLimit
        case .emptyForGuardedSend:
            return true
        }
    }
}

private func executeCreatedLayout(
    _ createPlan: CmuxWorkspaceCreatePlan,
    commands: [String],
    itemRoutes: [CmuxPlacementCommandRoute],
    path: CmuxPlacementExecutionPath,
    plan: CmuxPlacementPlan,
    using dependencies: CmuxPlacementExecutionDependencies
) -> CmuxGroupedExecution {
    do {
        guard layoutCommandsAreSafe(createPlan.layout.tree, commands: commands) else {
            throw CmuxPlacementResponseError.invalidShape("layout command byte bound")
        }
        let response = try dependencies.createWorkspace(
            cmuxWorkspaceCreateParameters(for: createPlan, commands: commands)
        )
        guard let identifiers = cmuxWorkspaceIdentifiers(from: response) else {
            throw CmuxPlacementResponseError.invalidShape(
                cmuxWorkspaceCreateMethod + " identifiers"
            )
        }
        let orderedSurfaceIDs = try enumeratedSurfaceIDs(
            workspaceID: identifiers.workspaceID,
            leafItemOrder: createPlan.layout.leafItemOrder,
            using: dependencies
        )
        let results = itemResults(
            surfaceIDs: orderedSurfaceIDs.map { Optional($0) },
            commands: commands,
            itemRoutes: itemRoutes,
            workspaceID: identifiers.workspaceID,
            using: dependencies
        )
        return CmuxGroupedExecution(
            results: results,
            path: path,
            didFallbackToTabs: plan.didFallbackToTabs
        )
    } catch {
        return failedExecution(plan: plan, path: path, error: error)
    }
}

private func executeFoundSplit(
    _ foundPlan: CmuxFoundWorkspacePanePlan,
    workspaceID: String,
    commands: [String],
    itemRoutes: [CmuxPlacementCommandRoute],
    plan: CmuxPlacementPlan,
    using dependencies: CmuxPlacementExecutionDependencies
) -> CmuxGroupedExecution {
    do {
        let paneResponse = try dependencies.rpc(
            cmuxPaneListMethod,
            cmuxPaneListParameters(workspaceID: workspaceID)
        )
        let paneID = try firstPaneID(from: paneResponse, expectedIndex: foundPlan.rootPaneIndex)
        let rootSurfaceID = try firstSurfaceID(
            workspaceID: workspaceID,
            paneID: paneID,
            expectedIndex: foundPlan.rootSurfaceIndex,
            using: dependencies
        )

        var responseSurfaceIDs = Array(repeating: "", count: foundPlan.splitOperations.count)
        for operation in foundPlan.splitOperations {
            let sourceID = try sourceSurfaceID(
                operation.source,
                rootSurfaceID: rootSurfaceID,
                responseSurfaceIDs: responseSurfaceIDs
            )
            let response = try dependencies.rpc(
                cmuxSurfaceSplitMethod,
                cmuxSurfaceSplitParameters(
                    surfaceID: sourceID, direction: operation.direction
                )
            )
            let surfaceID = try cmuxResolvedSurfaceID(from: response)
            guard responseSurfaceIDs.indices.contains(operation.responseIndex),
                  responseSurfaceIDs[operation.responseIndex].isEmpty else {
                throw CmuxPlacementResponseError.invalidShape("split response index")
            }
            responseSurfaceIDs[operation.responseIndex] = surfaceID
        }

        let orderedSurfaceIDs = try cmuxResolveFoundSurfaceIDs(
            rootSurfaceID: rootSurfaceID,
            splitResponseSurfaceIDs: responseSurfaceIDs,
            itemSurfaceOrder: foundPlan.itemSurfaceOrder
        )
        let results = itemResults(
            surfaceIDs: orderedSurfaceIDs.map { Optional($0) },
            commands: commands,
            itemRoutes: itemRoutes,
            workspaceID: workspaceID,
            using: dependencies
        )
        return CmuxGroupedExecution(
            results: results,
            path: .foundSplit,
            didFallbackToTabs: plan.didFallbackToTabs
        )
    } catch {
        // A split can have already changed the found workspace. Without a measured subtree-to-item
        // oracle, keep the workspace and conservatively close every item result.
        return failedExecution(plan: plan, path: .foundSplit, error: error)
    }
}

private func lookupWorkspace(
    named name: String,
    using dependencies: CmuxPlacementExecutionDependencies
) throws -> String? {
    let response = try dependencies.rpc(
        cmuxWorkspaceListMethod,
        cmuxWorkspaceListParameters()
    )
    return try cmuxMatchingWorkspaceID(from: response, named: name)
}

private func executePanePlacement(
    _ panePlan: CmuxPanePlacementPlan,
    plan: CmuxPlacementPlan,
    commands: [String],
    using dependencies: CmuxPlacementExecutionDependencies
) -> CmuxGroupedExecution {
    switch panePlan.target {
    case .alwaysNew:
        guard let createPlan = panePlan.createIfMissing else {
            return failedExecution(
                plan: plan,
                path: .layoutCreate,
                error: CmuxPlacementResponseError.invalidShape("pane create plan")
            )
        }
        return executeCreatedLayout(
            createPlan,
            commands: commands,
            itemRoutes: createPlan.layout.itemRoutes,
            path: .layoutCreate,
            plan: plan,
            using: dependencies
        )
    case .fixedName(let name):
        do {
            if let workspaceID = try lookupWorkspace(named: name, using: dependencies) {
                guard let foundPlan = panePlan.found else {
                    return failedExecution(
                        plan: plan,
                        path: .foundSplit,
                        error: CmuxPlacementResponseError.invalidShape("found pane plan")
                    )
                }
                return executeFoundSplit(
                    foundPlan,
                    workspaceID: workspaceID,
                    commands: commands,
                    itemRoutes: foundPlan.itemRoutes,
                    plan: plan,
                    using: dependencies
                )
            }
            guard let createPlan = panePlan.createIfMissing else {
                return failedExecution(
                    plan: plan,
                    path: .layoutCreate,
                    error: CmuxPlacementResponseError.invalidShape("pane create plan")
                )
            }
            return executeCreatedLayout(
                createPlan,
                commands: commands,
                itemRoutes: createPlan.layout.itemRoutes,
                path: .layoutCreate,
                plan: plan,
                using: dependencies
            )
        } catch {
            return failedExecution(plan: plan, path: .layoutCreate, error: error)
        }
    }
}

private func executeTabPlacement(
    _ tabPlan: CmuxTabPlacementPlan,
    plan: CmuxPlacementPlan,
    commands: [String],
    using dependencies: CmuxPlacementExecutionDependencies
) -> CmuxGroupedExecution {
    var selectedPath: CmuxPlacementExecutionPath = .tabCreate
    do {
        let workspaceID: String
        var surfaceIDs = Array<String?>(repeating: nil, count: commands.count)
        var itemErrors = Array<Error?>(repeating: nil, count: commands.count)
        let paneID: String
        let path: CmuxPlacementExecutionPath

        switch tabPlan.target {
        case .alwaysNew:
            guard let createPlan = tabPlan.createIfMissing else {
                return failedExecution(
                    plan: plan,
                    path: .tabCreate,
                    error: CmuxPlacementResponseError.invalidShape("tab create plan")
                )
            }
            guard layoutCommandsAreSafe(createPlan.layout.tree, commands: commands) else {
                throw CmuxPlacementResponseError.invalidShape("layout command byte bound")
            }
            let response = try dependencies.createWorkspace(
                cmuxWorkspaceCreateParameters(for: createPlan, commands: commands)
            )
            guard let identifiers = cmuxWorkspaceIdentifiers(from: response) else {
                throw CmuxPlacementResponseError.invalidShape(
                    cmuxWorkspaceCreateMethod + " identifiers"
                )
            }
            workspaceID = identifiers.workspaceID
            surfaceIDs[0] = identifiers.surfaceID
            path = .tabCreate
            selectedPath = path
            if commands.count > 1 {
                let paneResponse = try dependencies.rpc(
                    cmuxPaneListMethod,
                    cmuxPaneListParameters(workspaceID: workspaceID)
                )
                paneID = try firstPaneID(from: paneResponse, expectedIndex: 0)
            } else {
                paneID = ""
            }
        case .fixedName(let name):
            if let workspace = try lookupWorkspace(named: name, using: dependencies) {
                workspaceID = workspace
                path = .tabFound
                selectedPath = path
                let paneResponse = try dependencies.rpc(
                    cmuxPaneListMethod,
                    cmuxPaneListParameters(workspaceID: workspaceID)
                )
                paneID = try firstPaneID(
                    from: paneResponse, expectedIndex: tabPlan.foundPaneIndex ?? 0
                )
            } else {
                guard let createPlan = tabPlan.createIfMissing else {
                    return failedExecution(
                        plan: plan,
                        path: .tabCreate,
                        error: CmuxPlacementResponseError.invalidShape("tab create plan")
                    )
                }
                guard layoutCommandsAreSafe(createPlan.layout.tree, commands: commands) else {
                    throw CmuxPlacementResponseError.invalidShape("layout command byte bound")
                }
                let response = try dependencies.createWorkspace(
                    cmuxWorkspaceCreateParameters(for: createPlan, commands: commands)
                )
                guard let identifiers = cmuxWorkspaceIdentifiers(from: response) else {
                    throw CmuxPlacementResponseError.invalidShape(
                        cmuxWorkspaceCreateMethod + " identifiers"
                    )
                }
                workspaceID = identifiers.workspaceID
                surfaceIDs[0] = identifiers.surfaceID
                path = .tabCreate
                selectedPath = path
                if commands.count > 1 {
                    let paneResponse = try dependencies.rpc(
                        cmuxPaneListMethod,
                        cmuxPaneListParameters(workspaceID: workspaceID)
                    )
                    paneID = try firstPaneID(from: paneResponse, expectedIndex: 0)
                } else {
                    paneID = ""
                }
            }
        }

        let firstSurfaceIndex = surfaceIDs.firstIndex(where: { $0 == nil }) ?? commands.count
        let createStart = path == .tabFound ? 0 : firstSurfaceIndex
        for index in createStart..<commands.count {
            do {
                let response = try dependencies.rpc(
                    cmuxSurfaceCreateMethod,
                    cmuxSurfaceCreateParameters(workspaceID: workspaceID, paneID: paneID)
                )
                surfaceIDs[index] = try cmuxResolvedSurfaceID(from: response)
            } catch {
                itemErrors[index] = error
            }
        }
        let results = itemResults(
            surfaceIDs: surfaceIDs,
            commands: commands,
            itemRoutes: tabPlan.itemRoutes,
            workspaceID: workspaceID,
            using: dependencies,
            itemErrors: itemErrors
        )
        return CmuxGroupedExecution(
            results: results,
            path: path,
            didFallbackToTabs: plan.didFallbackToTabs
        )
    } catch {
        return failedExecution(plan: plan, path: selectedPath, error: error)
    }
}

private func executeWorkspacePerItem(
    _ workspacePlan: CmuxWorkspacePerItemPlan,
    plan: CmuxPlacementPlan,
    commands: [String],
    using dependencies: CmuxPlacementExecutionDependencies
) -> CmuxGroupedExecution {
    guard workspacePlan.creates.count == commands.count,
          workspacePlan.itemRoutes.count == commands.count else {
        return failedExecution(
            plan: plan,
            path: .workspacePerItem,
            error: CmuxPlacementResponseError.invalidShape("workspace-per-item plan")
        )
    }

    var results: [Result<TerminalSessionHandle, Error>] = []
    results.reserveCapacity(commands.count)
    for index in commands.indices {
        do {
            guard layoutCommandsAreSafe(
                workspacePlan.creates[index].layout.tree, commands: commands
            ) else {
                throw CmuxPlacementResponseError.invalidShape("layout command byte bound")
            }
            let response = try dependencies.createWorkspace(
                cmuxWorkspaceCreateParameters(
                    for: workspacePlan.creates[index], commands: commands
                )
            )
            guard let identifiers = cmuxWorkspaceIdentifiers(from: response) else {
                throw CmuxPlacementResponseError.invalidShape(
                    cmuxWorkspaceCreateMethod + " identifiers"
                )
            }
            results.append(contentsOf: itemResults(
                surfaceIDs: [identifiers.surfaceID],
                commands: [commands[index]],
                itemRoutes: [workspacePlan.itemRoutes[index]],
                workspaceID: identifiers.workspaceID,
                using: dependencies
            ))
        } catch {
            results.append(.failure(error))
        }
    }
    return CmuxGroupedExecution(
        results: results,
        path: .workspacePerItem,
        didFallbackToTabs: plan.didFallbackToTabs
    )
}

private func failurePath(for plan: CmuxPlacementPlan) -> CmuxPlacementExecutionPath {
    switch plan.route {
    case .pane:
        return .layoutCreate
    case .tab:
        return .tabCreate
    case .workspacePerItem:
        return .workspacePerItem
    }
}

/// Executes one already-computed placement plan. The plan is the only placement decision; this
/// layer only resolves measured cmux identifiers, performs the selected RPC sequence, and returns
/// one session handle or failure for each source item.
public func executeCmuxPlacementPlan(
    _ plan: CmuxPlacementPlan,
    commands: [String],
    using dependencies: CmuxPlacementExecutionDependencies
) -> CmuxGroupedExecution {
    guard commands.count == plan.itemCount, !commands.isEmpty else {
        return failedExecution(
            plan: plan,
            path: failurePath(for: plan),
            error: CmuxPlacementResponseError.invalidShape("command count")
        )
    }

    switch plan.route {
    case .pane(let panePlan):
        return executePanePlacement(
            panePlan, plan: plan, commands: commands, using: dependencies
        )
    case .tab(let tabPlan):
        return executeTabPlacement(
            tabPlan, plan: plan, commands: commands, using: dependencies
        )
    case .workspacePerItem(let workspacePlan):
        return executeWorkspacePerItem(
            workspacePlan, plan: plan, commands: commands, using: dependencies
        )
    }
}

/// Production entry point for a precomputed plan. The runtime context and all its RPC closures
/// reuse runInCmux's socket pin, no-preflight, launch, and keyed-create retry rules.
public func runCmuxBatch(
    _ requests: [ResolvedRequest],
    plan: CmuxPlacementPlan,
    channel: CmuxChannel = .stable
) -> CmuxGroupedExecution {
    let commands = requests.map(\.command)
    guard commands.count == plan.itemCount, !commands.isEmpty else {
        return failedExecution(
            plan: plan,
            path: failurePath(for: plan),
            error: CmuxPlacementResponseError.invalidShape("command count")
        )
    }

    do {
        let context = try makeCmuxRuntimeContext(channel: channel)
        let invoke: CmuxRPCWithSocket = { method, params, socketPath in
            try cmuxRPC(
                cli: context.cliPath,
                method: method,
                params: params,
                socketPath: socketPath
            )
        }
        let dependencies = CmuxPlacementExecutionDependencies(
            cliPath: context.cliPath,
            currentSocketPath: { context.socketPath },
            rpc: { method, params in try invoke(method, params, context.socketPath) },
            createWorkspace: { params in
                try cmuxCreateWorkspaceWithRecovery(
                    context: context, params: params, rpc: invoke
                )
            },
            shellGate: { surfaceID, byteCount in
                cmuxAwaitShellReading(
                    cliPath: context.cliPath,
                    socketPath: context.socketPath,
                    surfaceID: surfaceID,
                    payloadByteCount: byteCount
                )
            }
        )
        return executeCmuxPlacementPlan(plan, commands: commands, using: dependencies)
    } catch {
        return failedExecution(
            plan: plan,
            path: failurePath(for: plan),
            error: error
        )
    }
}
