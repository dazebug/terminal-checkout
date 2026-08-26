import Foundation

/// The two successful outcomes of editing cmux.json. The caller can therefore distinguish an
/// explicit no-op from a file that needs to be written without comparing strings at the App layer.
public enum CmuxConfigEditResult: Equatable {
    case unchanged
    case edited(String)
}

public enum CmuxConfigEditError: Error, Equatable, CustomStringConvertible {
    case invalidJSONC

    public var description: String {
        "cmux.json is not valid JSONC"
    }
}

private struct CmuxConfigSpan {
    let start: String.Index
    let end: String.Index
}

private enum CmuxConfigTokenKind {
    case leftBrace
    case rightBrace
    case leftBracket
    case rightBracket
    case colon
    case comma
    case string(String)
    case scalar
}

private struct CmuxConfigToken {
    let kind: CmuxConfigTokenKind
    let span: CmuxConfigSpan
}

private struct CmuxConfigMember {
    let key: String
    let keySpan: CmuxConfigSpan
    let value: CmuxConfigValue
}

private struct CmuxConfigObject {
    let opening: CmuxConfigSpan
    let closing: CmuxConfigSpan
    let members: [CmuxConfigMember]
}

private struct CmuxConfigArray {
    let opening: CmuxConfigSpan
    let closing: CmuxConfigSpan
    let values: [CmuxConfigValue]
}

private indirect enum CmuxConfigValue {
    case object(CmuxConfigObject)
    case array(CmuxConfigArray)
    case string(String, CmuxConfigSpan)
    case scalar(CmuxConfigSpan)

    var span: CmuxConfigSpan {
        switch self {
        case .object(let object):
            return CmuxConfigSpan(start: object.opening.start, end: object.closing.end)
        case .array(let array):
            return CmuxConfigSpan(start: array.opening.start, end: array.closing.end)
        case .string(_, let span), .scalar(let span):
            return span
        }
    }
}

private func cmuxConfigFailure() -> CmuxConfigEditError {
    .invalidJSONC
}

private func cmuxConfigIsValidScalar(_ source: String) -> Bool {
    guard ["true", "false", "null"].contains(source) == false else { return true }
    guard let data = source.data(using: .utf8) else { return false }
    return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
}

private func cmuxConfigTokens(_ source: String) throws -> [CmuxConfigToken] {
    var tokens: [CmuxConfigToken] = []
    var index = source.startIndex

    while index < source.endIndex {
        let character = source[index]
        if character.isWhitespace {
            index = source.index(after: index)
            continue
        }

        if character == "/" {
            let next = source.index(after: index)
            guard next < source.endIndex else { throw cmuxConfigFailure() }
            if source[next] == "/" {
                index = source.index(after: next)
                while index < source.endIndex, source[index] != "\n" {
                    index = source.index(after: index)
                }
                continue
            }
            if source[next] == "*" {
                var cursor = source.index(after: next)
                var closed = false
                while cursor < source.endIndex {
                    let after = source.index(after: cursor)
                    if source[cursor] == "*", after < source.endIndex, source[after] == "/" {
                        index = source.index(after: after)
                        closed = true
                        break
                    }
                    cursor = after
                }
                guard closed else { throw cmuxConfigFailure() }
                continue
            }
            throw cmuxConfigFailure()
        }

        let start = index
        switch character {
        case "{":
            index = source.index(after: index)
            tokens.append(CmuxConfigToken(
                kind: .leftBrace, span: CmuxConfigSpan(start: start, end: index)
            ))
        case "}":
            index = source.index(after: index)
            tokens.append(CmuxConfigToken(
                kind: .rightBrace, span: CmuxConfigSpan(start: start, end: index)
            ))
        case "[":
            index = source.index(after: index)
            tokens.append(CmuxConfigToken(
                kind: .leftBracket, span: CmuxConfigSpan(start: start, end: index)
            ))
        case "]":
            index = source.index(after: index)
            tokens.append(CmuxConfigToken(
                kind: .rightBracket, span: CmuxConfigSpan(start: start, end: index)
            ))
        case ":":
            index = source.index(after: index)
            tokens.append(CmuxConfigToken(
                kind: .colon, span: CmuxConfigSpan(start: start, end: index)
            ))
        case ",":
            index = source.index(after: index)
            tokens.append(CmuxConfigToken(
                kind: .comma, span: CmuxConfigSpan(start: start, end: index)
            ))
        case "\"":
            index = source.index(after: index)
            var escaped = false
            var closed = false
            while index < source.endIndex {
                let current = source[index]
                if current.isNewline { throw cmuxConfigFailure() }
                if escaped {
                    escaped = false
                    index = source.index(after: index)
                    continue
                }
                if current == "\\" {
                    escaped = true
                    index = source.index(after: index)
                    continue
                }
                if current == "\"" {
                    index = source.index(after: index)
                    closed = true
                    break
                }
                index = source.index(after: index)
            }
            guard closed, !escaped else { throw cmuxConfigFailure() }
            let raw = String(source[start..<index])
            guard let data = raw.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(
                      with: data, options: [.fragmentsAllowed]
                  ) as? String else {
                throw cmuxConfigFailure()
            }
            tokens.append(CmuxConfigToken(
                kind: .string(value), span: CmuxConfigSpan(start: start, end: index)
            ))
        default:
            while index < source.endIndex {
                let current = source[index]
                if current.isWhitespace || "{}[]:,".contains(current) || current == "/" {
                    break
                }
                index = source.index(after: index)
            }
            let raw = String(source[start..<index])
            guard !raw.isEmpty, cmuxConfigIsValidScalar(raw) else { throw cmuxConfigFailure() }
            tokens.append(CmuxConfigToken(
                kind: .scalar, span: CmuxConfigSpan(start: start, end: index)
            ))
        }
    }
    return tokens
}

private struct CmuxConfigParser {
    let tokens: [CmuxConfigToken]
    var cursor = 0

    mutating func parseDocument() throws -> CmuxConfigValue {
        guard !tokens.isEmpty else { throw cmuxConfigFailure() }
        let value = try parseValue()
        guard cursor == tokens.count else { throw cmuxConfigFailure() }
        return value
    }

    private mutating func parseValue() throws -> CmuxConfigValue {
        guard let token = tokens[safe: cursor] else { throw cmuxConfigFailure() }
        switch token.kind {
        case .leftBrace:
            return .object(try parseObject())
        case .leftBracket:
            return .array(try parseArray())
        case .string(let value):
            cursor += 1
            return .string(value, token.span)
        case .scalar:
            cursor += 1
            return .scalar(token.span)
        case .rightBrace, .rightBracket, .colon, .comma:
            throw cmuxConfigFailure()
        }
    }

    private mutating func parseObject() throws -> CmuxConfigObject {
        guard let opening = tokens[safe: cursor], case .leftBrace = opening.kind else {
            throw cmuxConfigFailure()
        }
        cursor += 1
        var members: [CmuxConfigMember] = []

        if let closing = tokens[safe: cursor], case .rightBrace = closing.kind {
            cursor += 1
            return CmuxConfigObject(opening: opening.span, closing: closing.span, members: members)
        }

        while true {
            guard let keyToken = tokens[safe: cursor], case .string(let key) = keyToken.kind else {
                throw cmuxConfigFailure()
            }
            cursor += 1
            guard let colon = tokens[safe: cursor], case .colon = colon.kind else {
                throw cmuxConfigFailure()
            }
            cursor += 1
            members.append(CmuxConfigMember(
                key: key, keySpan: keyToken.span, value: try parseValue()
            ))

            guard let separator = tokens[safe: cursor] else { throw cmuxConfigFailure() }
            if case .comma = separator.kind {
                cursor += 1
                if let closing = tokens[safe: cursor], case .rightBrace = closing.kind {
                    cursor += 1
                    return CmuxConfigObject(
                        opening: opening.span, closing: closing.span, members: members
                    )
                }
                continue
            }
            guard case .rightBrace = separator.kind else { throw cmuxConfigFailure() }
            cursor += 1
            return CmuxConfigObject(opening: opening.span, closing: separator.span, members: members)
        }
    }

    private mutating func parseArray() throws -> CmuxConfigArray {
        guard let opening = tokens[safe: cursor], case .leftBracket = opening.kind else {
            throw cmuxConfigFailure()
        }
        cursor += 1
        var values: [CmuxConfigValue] = []

        if let closing = tokens[safe: cursor], case .rightBracket = closing.kind {
            cursor += 1
            return CmuxConfigArray(opening: opening.span, closing: closing.span, values: values)
        }

        while true {
            values.append(try parseValue())
            guard let separator = tokens[safe: cursor] else { throw cmuxConfigFailure() }
            if case .comma = separator.kind {
                cursor += 1
                if let closing = tokens[safe: cursor], case .rightBracket = closing.kind {
                    cursor += 1
                    return CmuxConfigArray(
                        opening: opening.span, closing: closing.span, values: values
                    )
                }
                continue
            }
            guard case .rightBracket = separator.kind else { throw cmuxConfigFailure() }
            cursor += 1
            return CmuxConfigArray(opening: opening.span, closing: separator.span, values: values)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private let cmuxMinimalAutomationConfig = """
{
  "automation": {
    "socketControlMode": "automation"
  }
}
"""

private func cmuxConfigLeadingIndentation(
    in source: String,
    object: CmuxConfigObject
) -> String {
    guard let firstMember = object.members.first else { return "" }
    var index = object.opening.end
    while index < firstMember.keySpan.start, source[index].isWhitespace {
        index = source.index(after: index)
    }
    return String(source[object.opening.end..<index])
}

/// Enables cmux's external automation mode without parsing and reserializing the user's JSONC.
/// Comments, key order, whitespace, and all unrelated bytes therefore remain in the file.
public func cmuxConfigEnablingAutomation(existing: String?) throws -> CmuxConfigEditResult {
    guard let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .edited(cmuxMinimalAutomationConfig + "\n")
    }

    var parser = CmuxConfigParser(tokens: try cmuxConfigTokens(existing))
    let document = try parser.parseDocument()
    guard case .object(let root) = document else { throw cmuxConfigFailure() }

    if let automation = root.members.first(where: { $0.key == "automation" }) {
        guard case .object(let object) = automation.value else { throw cmuxConfigFailure() }
        if let socketMode = object.members.first(where: { $0.key == "socketControlMode" }) {
            if case .string(let value, _) = socketMode.value, value == "automation" {
                return .unchanged
            }
            var edited = existing
            edited.replaceSubrange(
                socketMode.value.span.start..<socketMode.value.span.end,
                with: "\"automation\""
            )
            return .edited(edited)
        }

        let entry = "\"socketControlMode\": \"automation\""
        let insertion: String
        if object.members.isEmpty {
            insertion = entry
        } else {
            insertion = cmuxConfigLeadingIndentation(in: existing, object: object) + entry + ","
        }
        var edited = existing
        edited.insert(contentsOf: insertion, at: object.opening.end)
        return .edited(edited)
    }

    let entry = "\"automation\": {\"socketControlMode\": \"automation\"}"
    let insertion: String
    if root.members.isEmpty {
        insertion = "\n  \(entry)\n"
    } else {
        insertion = cmuxConfigLeadingIndentation(in: existing, object: root) + entry + ","
    }
    var edited = existing
    edited.insert(contentsOf: insertion, at: root.opening.end)
    return .edited(edited)
}
