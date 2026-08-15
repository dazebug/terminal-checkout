import Foundation

/// Chrome 확장이 보낸 요청 JSON을 (실행할 명령, 대상 터미널)로 해석한다.
/// 신규 포맷 { command_template, variables, terminal }과
/// 구 포맷 { repo, branch? } (하위 호환) 모두 지원.
public func resolveRequest(_ json: [String: Any]) throws -> (command: String, terminal: String) {
    if let template = json["command_template"] as? String, !template.isEmpty {
        let raw = json["variables"] as? [String: Any] ?? [:]
        var variables: [String: String] = [:]
        for (key, value) in raw {
            guard let string = value as? String else {
                throw CommandError.badRequest("Variable {\(key)} must be a string")
            }
            variables[key] = string
        }
        let terminal = json["terminal"] as? String ?? "iterm"
        return (try renderCommand(template: template, variables: variables), terminal)
    }

    guard let repo = json["repo"] as? String else { throw CommandError.missingRepo }
    let safeRepo = try sanitizeValue(repo)
    if let branch = json["branch"] as? String {
        let safeBranch = try sanitizeValue(branch)
        return ("z \(safeRepo) && git fetch origin && git checkout \(safeBranch)", "iterm")
    }
    return ("z \(safeRepo)", "iterm")
}

public func errorMessage(_ error: Error) -> String {
    String(describing: error) // CustomStringConvertible 준수 시 description을 그대로 쓴다
}

/// 요청 처리: 해석 → 실행 → 성공/실패 응답 JSON. 실행 함수는 주입받는다 (테스트 용이성).
public func handleRequest(json: [String: Any], run: (String, String) throws -> Void) -> [String: Any] {
    do {
        let resolved = try resolveRequest(json)
        try run(resolved.command, resolved.terminal)
        return ["success": true]
    } catch {
        return ["success": false, "error": errorMessage(error)]
    }
}
