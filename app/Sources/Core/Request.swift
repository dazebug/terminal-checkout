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
public func resolveRequest(_ json: [String: Any]) throws -> ResolvedRequest {
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
    let command = try renderCommand(template: template, variables: variables)
    try rejectNUL(in: command, what: "command_template")

    var claudeInputs: [String] = []
    if let rawInputs = json["claude_inputs"] {
        guard let list = rawInputs as? [Any] else {
            throw CommandError.badRequest("claude_inputs must be an array of strings")
        }
        for element in list {
            guard let text = element as? String else {
                throw CommandError.badRequest("claude_inputs must be an array of strings")
            }
            let rendered = try renderCommand(template: text, variables: variables)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rendered.isEmpty else { continue }
            try rejectNUL(in: rendered, what: "claude_inputs")
            claudeInputs.append(rendered)
        }
    }
    return ResolvedRequest(command: command, claudeInputs: claudeInputs)
}

/// NUL은 어느 경로로도 원문대로 전달할 수 없다: argv 트랙에서는 명령 치환이 조용히 **삭제**하고
/// (`pre<NUL>post` → `prepost`, 재현됨), 주입 트랙에서는 tty 입력 큐에 그대로 넣을 수 없다.
/// 조용히 바꿔 보내느니 요청을 거절한다 — 확장은 이 문자열을 그대로 실패로 표시한다.
private func rejectNUL(in text: String, what: String) throws {
    guard text.utf8.contains(0) else { return }
    throw CommandError.badRequest("\(what) must not contain NUL")
}

public func errorMessage(_ error: Error) -> String {
    String(describing: error) // CustomStringConvertible 준수 시 description을 그대로 쓴다
}

/// 요청 처리: 해석 → 실행 → 성공/실패 응답 JSON. 실행 함수는 주입받는다 (테스트 용이성).
public func handleRequest(json: [String: Any], run: (ResolvedRequest) throws -> Void) -> [String: Any] {
    do {
        try run(try resolveRequest(json))
        return ["success": true]
    } catch {
        return ["success": false, "error": errorMessage(error)]
    }
}
