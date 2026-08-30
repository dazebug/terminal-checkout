import Foundation

/// The result of resolving a request.
/// `claudeInputs` are not shell commands — they are free text to be typed, in order, into the claude session the command started, so they go through variable substitution alone and not the shell whitelist (the substituted values themselves are still validated).
public struct ResolvedRequest {
    public let command: String
    public let claudeInputs: [String]
}

/// The maximum number of item requests one batch may carry. The extension will mirror this value
/// when it learns the batch shape; Core owns the side-effect boundary and therefore enforces it.
public let batchItemLimit = 8

/// The relay waits 180 seconds for a response; reserve 30 seconds for framing and JSON
/// serialization so sequential batch launches stop within the remaining response budget.
public let batchLaunchResponseBudget: TimeInterval = 150

public let batchResponseDeadlineExceededMessage = "not launched — response deadline exceeded"

/// Resolves the request JSON the Chrome extension sent: { command_template, variables, claude_inputs? }.
/// Which terminal to run in has the app's settings as its single source, so a `terminal` field riding along in the request is never read.
///
/// `baseDirectory` follows the same rule — the app hands over **only the stored string**, and
/// validation, normalization, and fragment assembly all happen here in Core. An empty string means
/// not configured, and the rendered result is then byte-identical to what it was before this
/// feature existed.
public func resolveRequest(
    _ json: [String: Any], baseDirectory: String = ""
) throws -> ResolvedRequest {
    guard let template = json["command_template"] as? String, !template.isEmpty else {
        throw CommandError.badRequest("command_template is required")
    }

    let variables = try stringVariables(from: json["variables"] as? [String: Any] ?? [:]) { key in
        "Variable {\(key)} must be a string"
    }
    let rawInputs = try claudeInputTemplates(from: json)
    return try resolveRequestItem(
        commandTemplate: template,
        claudeInputTemplates: rawInputs,
        variables: variables,
        baseDirectory: baseDirectory,
        templateWireKey: "command_template"
    )
}

private struct BatchRequest {
    let commandTemplate: String
    let claudeInputTemplates: [String]
    let itemVariables: [[String: String]]
}

private let batchValidationNotLaunched = "not launched — batch rejected during validation"

private func stringVariables(
    from raw: [String: Any], invalidValue: (String) -> String
) throws -> [String: String] {
    var variables: [String: String] = [:]
    for (key, value) in raw {
        guard let string = value as? String else {
            throw CommandError.badRequest(invalidValue(key))
        }
        variables[key] = string
    }
    return variables
}

private func claudeInputTemplates(from json: [String: Any]) throws -> [String] {
    guard let list = json["claude_inputs"] else { return [] }
    guard let elements = list as? [Any] else {
        throw CommandError.badRequest("claude_inputs must be an array of strings")
    }
    return try elements.map { element in
        guard let text = element as? String else {
            throw CommandError.badRequest("claude_inputs must be an array of strings")
        }
        return text
    }
}

private func parseBatchRequest(_ json: [String: Any]) throws -> BatchRequest {
    if json["command_template"] != nil {
        throw CommandError.badRequest(
            "ambiguous batch request: items cannot be combined with command_template"
        )
    }
    guard let template = json["command"] as? String, !template.isEmpty else {
        throw CommandError.badRequest("command is required")
    }
    guard let rawItems = json["items"] as? [Any] else {
        throw CommandError.badRequest("items must be an array")
    }
    guard !rawItems.isEmpty else {
        throw CommandError.badRequest("items must not be empty")
    }
    guard rawItems.count <= batchItemLimit else {
        throw CommandError.badRequest(
            "items must contain at most \(batchItemLimit) item(s)"
        )
    }

    let rawInputs = try claudeInputTemplates(from: json)
    var itemVariables: [[String: String]] = []
    itemVariables.reserveCapacity(rawItems.count)
    for rawItem in rawItems {
        guard let item = rawItem as? [String: Any] else {
            throw CommandError.badRequest("items must contain objects")
        }
        guard let rawVariables = item["variables"] else {
            throw CommandError.badRequest("items[].variables is required")
        }
        guard let variablesObject = rawVariables as? [String: Any] else {
            throw CommandError.badRequest("items[].variables must be an object of strings")
        }
        let variables = try stringVariables(from: variablesObject) { _ in
            "items[].variables must be an object of strings"
        }
        itemVariables.append(variables)
    }
    return BatchRequest(
        commandTemplate: template,
        claudeInputTemplates: rawInputs,
        itemVariables: itemVariables
    )
}

/// Resolves one item after its request-shape parsing has finished. Both the legacy request and the
/// batch request call this function so app-provided variables, sanitization, command rendering,
/// and Claude-input rejection cannot drift into two validation pipelines.
private func resolveRequestItem(
    commandTemplate: String,
    claudeInputTemplates: [String],
    variables: [String: String],
    baseDirectory: String,
    templateWireKey: String
) throws -> ResolvedRequest {
    let appVariables = try appProvidedVariables(
        usedIn: [commandTemplate] + claudeInputTemplates,
        variables: variables,
        baseDirectory: baseDirectory
    )
    let command = try renderCommand(
        template: commandTemplate, variables: variables, appVariables: appVariables
    )
    try rejectNUL(in: command, what: templateWireKey)

    var claudeInputs: [String] = []
    for text in claudeInputTemplates {
        let renderedSource = try renderCommand(
            template: text, variables: variables, appVariables: appVariables
        )
        // The order is contractual: inspect the rendered source before trimming, because trimming
        // first removes edge TAB/CR/LF and lets them pass; a TAB-only input then disappears with a
        // success response.
        try rejectNUL(in: renderedSource, what: "claude_inputs")
        try rejectLineBreaks(in: renderedSource, what: "claude_inputs")
        try rejectControlCharacters(in: renderedSource, what: "claude_inputs")
        let rendered = renderedSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rendered.isEmpty else { continue }
        claudeInputs.append(rendered)
    }
    return ResolvedRequest(command: command, claudeInputs: claudeInputs)
}

/// A NUL cannot be delivered faithfully by either route: on the argv track command substitution
/// **drops** it silently (`pre<NUL>post` → `prepost`, reproduced), and on the injection track it
/// cannot go into the tty input queue at all. Rather than send something altered, reject the
/// request — the extension surfaces this string as the failure.
private func rejectNUL(in text: String, what: String) throws {
    guard text.utf8.contains(0) else { return }
    throw CommandError.badRequest("\(what) must not contain NUL")
}

/// `claude_inputs` are typed only after a marker/reflection check, so a line break would submit
/// before that check on every terminal carrier. `command_template` is different: its CR is the
/// execution contract and an embedded line break deliberately means another shell command.
private func rejectLineBreaks(in text: String, what: String) throws {
    // Character comparison lets the single CRLF Character through; its two Unicode scalars must
    // be inspected separately.
    guard !text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) else {
        throw CommandError.badRequest(
            "\(what) must not contain line breaks: they are submitted before screen reflection can be confirmed"
        )
    }
}

/// Typed claude input must not carry control bytes: they are typed into the terminal, DEL acts as
/// Backspace, and reflection checks only the first 24 characters before the app sends CR. This
/// guard is not used for `command_template`, whose shell execution treats an embedded line break
/// as the user's intentional second command.
private func rejectControlCharacters(in text: String, what: String) throws {
    guard !text.unicodeScalars.contains(where: { scalar in
        scalar.value <= 0x1F || scalar.value == 0x7F
    }) else {
        throw CommandError.badRequest(
            "\(what) must not contain control characters: typed bytes can act as keys (DEL is Backspace), and reflection checks only the first 24 characters before CR"
        )
    }
}

/// The variables only the app knows the value of. Today that is `{cd}` (the repository entry
/// clause) alone.
///
/// A request that doesn't use it doesn't even get the fragment assembled — a command with no
/// `{cd}` being rejected because of a corrupted stored base directory would leave the user with no
/// idea what happened. Conversely, when it *is* used but `repo` is missing, the reason reported is
/// **the thing that is actually absent**, not `{cd}`.
private func appProvidedVariables(
    usedIn texts: [String], variables: [String: String], baseDirectory: String
) throws -> [String: String] {
    // A name the app fills in cannot arrive in a request. `renderCommand` reaches the same verdict
    // (and it is the source of truth for it), but the check has to run **before** assembly —
    // otherwise a request carrying `{"cd": …}` gets rejected for an assembly-stage reason ("repo is
    // missing"), hiding the real problem, which is the name collision
    guard variables[repoEntryVariable] == nil else {
        throw CommandError.unknownVariable(repoEntryVariable)
    }

    let placeholder = "{\(repoEntryVariable)}"
    guard texts.contains(where: { $0.contains(placeholder) }) else { return [:] }
    guard let repo = variables["repo"] else { throw CommandError.variableNotProvided("repo") }
    return [
        repoEntryVariable: try repoEntryCommand(
            repo: repo, owner: variables["owner"], baseDirectory: baseDirectory
        ),
    ]
}

public func errorMessage(_ error: Error) -> String {
    String(describing: error) // when the error conforms to CustomStringConvertible this is its description verbatim
}

/// The optional item position is `nil` for legacy requests and non-`nil` for batch entries.
public struct BatchItemPosition {
    public let index: Int
    public let total: Int
}

/// Handles a request: resolve → run → a success/failure response JSON. The batch-position overload is
/// what HostServer uses so each item can be labeled without request re-parsing.
///
/// `notLaunched` fires once per item when the batch is rejected during content validation — the
/// failing items with their own reason, the valid ones with the shared rejection notice. It exists
/// so the per-item observability contract (one timeline per item) holds on the one path where
/// `run` is never reached; a deadline-cut item does not need it because its cut happens inside `run`.
public func handleRequest(
    json: [String: Any], baseDirectory: String = "",
    run: (ResolvedRequest, BatchItemPosition?) throws -> Void,
    notLaunched: ((BatchItemPosition, String) -> Void)? = nil,
    message: (Error) -> String = errorMessage
) -> [String: Any] {
    if json["items"] != nil {
        return handleBatchRequest(
            json: json,
            baseDirectory: baseDirectory,
            run: run,
            notLaunched: notLaunched,
            message: message
        )
    }
    do {
        try run(try resolveRequest(json, baseDirectory: baseDirectory), nil)
        return ["success": true]
    } catch {
        return ["success": false, "error": message(error)]
    }
}

/// Handles a request: resolve → run → a success/failure response JSON. The run function is injected, which is what makes this testable.
public func handleRequest(
    json: [String: Any], baseDirectory: String = "", run: (ResolvedRequest) throws -> Void,
    message: (Error) -> String = errorMessage
) -> [String: Any] {
    return handleRequest(
        json: json, baseDirectory: baseDirectory,
        run: { resolved, _ in try run(resolved) }, message: message
    )
}

private func handleBatchRequest(
    json: [String: Any],
    baseDirectory: String,
    run: (ResolvedRequest, BatchItemPosition?) throws -> Void,
    notLaunched: ((BatchItemPosition, String) -> Void)?,
    message: (Error) -> String
) -> [String: Any] {
    do {
        let batch = try parseBatchRequest(json)
        var resolvedItems = Array<ResolvedRequest?>(
            repeating: nil, count: batch.itemVariables.count
        )
        var validationErrors = Array<String?>(repeating: nil, count: batch.itemVariables.count)

        for index in batch.itemVariables.indices {
            do {
                resolvedItems[index] = try resolveRequestItem(
                    commandTemplate: batch.commandTemplate,
                    claudeInputTemplates: batch.claudeInputTemplates,
                    variables: batch.itemVariables[index],
                    baseDirectory: baseDirectory,
                    templateWireKey: "command"
                )
            } catch {
                validationErrors[index] = message(error)
            }
        }

        if let firstValidationError = validationErrors.compactMap({ $0 }).first {
            var results: [[String: Any]] = []
            results.reserveCapacity(validationErrors.count)
            for index in validationErrors.indices {
                let reason = validationErrors[index] ?? batchValidationNotLaunched
                notLaunched?(
                    BatchItemPosition(index: index + 1, total: validationErrors.count), reason
                )
                results.append(["success": false, "error": reason])
            }
            return [
                "success": false,
                "error": firstValidationError,
                "items": results,
            ]
        }

        var results: [[String: Any]] = []
        results.reserveCapacity(resolvedItems.count)
        var failedCount = 0
        for index in resolvedItems.indices {
            let resolved = resolvedItems[index]
            let position = BatchItemPosition(index: index + 1, total: resolvedItems.count)
            do {
                try run(resolved!, position)
                results.append(["success": true])
            } catch {
                failedCount += 1
                results.append(["success": false, "error": message(error)])
            }
        }
        if failedCount == 0 {
            return ["success": true, "items": results]
        }
        return [
            "success": false,
            "error": "\(failedCount) of \(results.count) items failed",
            "items": results,
        ]
    } catch {
        return ["success": false, "error": message(error)]
    }
}
