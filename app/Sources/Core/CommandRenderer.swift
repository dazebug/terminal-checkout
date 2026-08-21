import Foundation

/// Why a base directory was rejected. Each surface words it differently (the button response is
/// English, the setup window is Korean until #24), so only the reason travels as a value and every
/// surface builds its own sentence.
public enum BaseDirectoryProblem {
    case notAbsolute
    case invalidCharacters
}

public enum CommandError: Error, CustomStringConvertible {
    case invalidCharacters(String)
    case unknownVariable(String)
    case variableNotProvided(String)
    case badRequest(String)
    case invalidBaseDirectory(BaseDirectoryProblem, String)

    public var description: String {
        switch self {
        case .invalidCharacters(let value): return "Invalid characters in input: \(value)"
        case .unknownVariable(let name): return "Unknown variable: {\(name)}"
        case .variableNotProvided(let name): return "Variable {\(name)} not provided"
        case .badRequest(let message): return message
        case .invalidBaseDirectory(.notAbsolute, let value):
            return "Base directory must be an absolute path: \(value)"
        case .invalidBaseDirectory(.invalidCharacters, let value):
            return "Invalid characters in base directory: \(value)"
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

/// The single place a value is validated. The base directory (`BaseDirectory.swift`) runs through
/// this very function, which is why it is visible module-wide — the moment the verdict exists in
/// two copies, only one of them getting fixed is a matter of time.
func sanitizeValue(_ value: String) throws -> String {
    guard !value.isEmpty, value.unicodeScalars.allSatisfy({ allowedValueScalars.contains($0) }) else {
        throw CommandError.invalidCharacters(value)
    }
    return value
}

private let variableRegex = try! NSRegularExpression(pattern: "\\{(\\w+)\\}")

/// Substitutes `{var}` in a command template with validated variable values.
///
/// `variables` comes from the extension, so every last one of them has to pass the character
/// whitelist. `appVariables` is a shell fragment the app assembled (`{cd}` —
/// `BaseDirectory.swift`): it contains spaces and braces, so it cannot pass that verdict, and
/// there is no reason it should — its ingredients being already-validated values is what earns the
/// exemption. The two dictionaries cannot collide on a name: a fragment name is absent from
/// `allowedVariables`, so a request carrying one is rejected by the loop above first. The merge
/// order is only a safety net.
///
/// Substituted values are never rescanned (matches are taken from the template alone), so there is
/// no path by which a `{…}` inside a fragment gets substituted a second time.
public func renderCommand(
    template: String, variables: [String: String], appVariables: [String: String] = [:]
) throws -> String {
    var values: [String: String] = [:]
    for (key, value) in variables {
        guard allowedVariables.contains(key) else { throw CommandError.unknownVariable(key) }
        values[key] = try sanitizeValue(value)
    }
    for (key, value) in appVariables { values[key] = value }

    var result = ""
    var last = template.startIndex
    let fullRange = NSRange(template.startIndex..., in: template)
    for match in variableRegex.matches(in: template, range: fullRange) {
        guard let whole = Range(match.range, in: template),
              let nameRange = Range(match.range(at: 1), in: template) else { continue }
        result += template[last..<whole.lowerBound]
        let name = String(template[nameRange])
        guard let value = values[name] else { throw CommandError.variableNotProvided(name) }
        result += value
        last = whole.upperBound
    }
    result += template[last...]
    return result
}
