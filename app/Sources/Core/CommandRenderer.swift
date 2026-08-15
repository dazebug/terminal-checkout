import Foundation

public enum CommandError: Error, CustomStringConvertible {
    case invalidCharacters(String)
    case unknownVariable(String)
    case variableNotProvided(String)
    case badRequest(String)

    public var description: String {
        switch self {
        case .invalidCharacters(let value): return "Invalid characters in input: \(value)"
        case .unknownVariable(let name): return "Unknown variable: {\(name)}"
        case .variableNotProvided(let name): return "Variable {\(name)} not provided"
        case .badRequest(let message): return message
        }
    }
}

private let allowedVariables: Set<String> = [
    "repo", "branch", "base", "main", "branch_underbar", "number", "owner",
]

// 허용 문자 화이트리스트 (command injection 방지).
// 파이썬 시절 정규식 `^[a-zA-Z0-9\-_./]+$`와 동일하되, `$`가 끝의 개행 하나를
// 허용하던 구멍까지 막기 위해 문자 단위로 검사한다.
private let allowedValueScalars: Set<Unicode.Scalar> = {
    var set = Set<Unicode.Scalar>()
    for range in [UInt32(0x30)...0x39, UInt32(0x41)...0x5A, UInt32(0x61)...0x7A] {
        for v in range { set.insert(Unicode.Scalar(v)!) }
    }
    for ch in "-_./".unicodeScalars { set.insert(ch) }
    return set
}()

private func sanitizeValue(_ value: String) throws -> String {
    guard !value.isEmpty, value.unicodeScalars.allSatisfy({ allowedValueScalars.contains($0) }) else {
        throw CommandError.invalidCharacters(value)
    }
    return value
}

private let variableRegex = try! NSRegularExpression(pattern: "\\{(\\w+)\\}")

/// command template의 `{var}`를 검증된 변수 값으로 치환한다.
public func renderCommand(template: String, variables: [String: String]) throws -> String {
    var sanitized: [String: String] = [:]
    for (key, value) in variables {
        guard allowedVariables.contains(key) else { throw CommandError.unknownVariable(key) }
        sanitized[key] = try sanitizeValue(value)
    }

    var result = ""
    var last = template.startIndex
    let fullRange = NSRange(template.startIndex..., in: template)
    for match in variableRegex.matches(in: template, range: fullRange) {
        guard let whole = Range(match.range, in: template),
              let nameRange = Range(match.range(at: 1), in: template) else { continue }
        result += template[last..<whole.lowerBound]
        let name = String(template[nameRange])
        guard let value = sanitized[name] else { throw CommandError.variableNotProvided(name) }
        result += value
        last = whole.upperBound
    }
    result += template[last...]
    return result
}
