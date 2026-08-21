import Foundation

/// 요청 해석 결과.
/// claudeInputs는 셸 명령이 아니다 — command가 띄운 claude 세션에 순서대로 타이핑할
/// 자유 텍스트라, 셸용 화이트리스트 검증 없이 변수 치환만 거친다 (치환 값 자체는 검증됨).
public struct ResolvedRequest {
    public let command: String
    public let claudeInputs: [String]
}

/// Chrome 확장이 보낸 요청 JSON을 해석한다: { command_template, variables, claude_inputs? }.
/// 어느 터미널에서 실행할지는 앱 설정이 단일 소스라, 요청에 terminal 필드가 섞여 와도 읽지 않는다.
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

    var claudeInputs: [String] = []
    for text in rawInputs {
        let rendered = try renderCommand(
            template: text, variables: variables, appVariables: appVariables
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !rendered.isEmpty { claudeInputs.append(rendered) }
    }
    return ResolvedRequest(command: command, claudeInputs: claudeInputs)
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
    String(describing: error) // CustomStringConvertible 준수 시 description을 그대로 쓴다
}

/// 요청 처리: 해석 → 실행 → 성공/실패 응답 JSON. 실행 함수는 주입받는다 (테스트 용이성).
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
