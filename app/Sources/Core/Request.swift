import Foundation

/// The result of resolving a request.
/// `claudeInputs` are not shell commands — they are free text to be typed, in order, into the claude session the command started, so they go through variable substitution alone and not the shell whitelist (the substituted values themselves are still validated).
public struct ResolvedRequest {
    public let command: String
    public let claudeInputs: [String]
}

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

    let raw = json["variables"] as? [String: Any] ?? [:]
    var variables: [String: String] = [:]
    for (key, value) in raw {
        guard let string = value as? String else {
            throw CommandError.badRequest("Variable {\(key)} must be a string")
        }
        variables[key] = string
    }

    // Collect the raw claude inputs before rendering — `{cd}` may appear only on the input side,
    // so deciding whether to assemble the fragment means looking at the template and the inputs
    // together
    var rawInputs: [String] = []
    if let list = json["claude_inputs"] {
        guard let elements = list as? [Any] else {
            throw CommandError.badRequest("claude_inputs must be an array of strings")
        }
        for element in elements {
            guard let text = element as? String else {
                throw CommandError.badRequest("claude_inputs must be an array of strings")
            }
            rawInputs.append(text)
        }
    }

    let appVariables = try appProvidedVariables(
        usedIn: [template] + rawInputs, variables: variables, baseDirectory: baseDirectory
    )
    let command = try renderCommand(
        template: template, variables: variables, appVariables: appVariables
    )
    try rejectNUL(in: command, what: "command_template")

    var claudeInputs: [String] = []
    for text in rawInputs {
        let rendered = try renderCommand(
            template: text, variables: variables, appVariables: appVariables
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rendered.isEmpty else { continue }
        try rejectNUL(in: rendered, what: "claude_inputs")
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

/// Handles a request: resolve → run → a success/failure response JSON. The run function is injected, which is what makes this testable.
public func handleRequest(
    json: [String: Any], baseDirectory: String = "", run: (ResolvedRequest) throws -> Void
) -> [String: Any] {
    do {
        try run(try resolveRequest(json, baseDirectory: baseDirectory))
        return ["success": true]
    } catch {
        return ["success": false, "error": errorMessage(error)]
    }
}
