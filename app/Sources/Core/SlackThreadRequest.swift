import Foundation

/// Failure categories the app can present in its localized Slack settings section.
public enum SlackThreadRequestError: Error {
    case invalidOuterURL
    case invalidSlackLink
    case slackLinkTooLong
    case workDirectoryNotConfigured
    case invalidWorkDirectory(underlying: Error)
    case workDirectoryUnavailable
    case invalidInstruction
    case appendedPromptUnavailable
}

/// Parses the URL opened by Shortcuts and returns the original Slack link after boundary trimming.
public func parseSlackThreadLink(from outerURL: String) throws -> String {
    guard let components = URLComponents(string: outerURL),
          let scheme = components.scheme,
          scheme.caseInsensitiveCompare(SlackThreadURLContract.scheme) == .orderedSame,
          components.path.isEmpty,
          components.user == nil,
          components.password == nil,
          components.port == nil,
          components.fragment == nil,
          rawAuthority(in: outerURL) == SlackThreadURLContract.host,
          let query = components.percentEncodedQuery,
          let encodedLink = parseOuterQuery(query),
          let decodedLink = encodedLink.removingPercentEncoding,
          !decodedLink.isEmpty else {
        throw SlackThreadRequestError.invalidOuterURL
    }

    let link = decodedLink.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
    guard !link.isEmpty else { throw SlackThreadRequestError.invalidOuterURL }
    guard link.utf8.count <= 512 else { throw SlackThreadRequestError.slackLinkTooLong }
    try validateSlackLink(link)
    return link
}

/// Resolves app-owned settings and the parsed link into the request consumed by `prepareRequest`.
public func resolveSlackThreadRequest(
    outerURL: String,
    workDirectory: String?,
    instruction: String,
    directoryIsValid: (String) -> Bool = { path in
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
) throws -> ResolvedRequest {
    let link = try parseSlackThreadLink(from: outerURL)

    let normalizedWorkDirectory: String?
    do {
        normalizedWorkDirectory = try normalizedBaseDirectory(workDirectory ?? "")
    } catch {
        throw SlackThreadRequestError.invalidWorkDirectory(underlying: error)
    }
    guard let normalizedWorkDirectory else {
        throw SlackThreadRequestError.workDirectoryNotConfigured
    }
    guard directoryIsValid(normalizedWorkDirectory) else {
        throw SlackThreadRequestError.workDirectoryUnavailable
    }

    do {
        try validateClaudeInputBoundary(instruction, what: "slack instruction")
    } catch {
        throw SlackThreadRequestError.invalidInstruction
    }
    let trimmedInstruction = instruction.trimmingCharacters(in: .whitespaces)
    let input = trimmedInstruction.isEmpty ? link : "\(link) \(trimmedInstruction)"

    return ResolvedRequest(
        command: "cd \(normalizedWorkDirectory) && claude",
        claudeInputs: [input]
    )
}

/// Uses the existing request planner but refuses its typed-input fallback for this URL path.
public func prepareSlackThreadRequest(
    _ request: ResolvedRequest,
    loginShell: String = loginShellPath(),
    claudeIsExecutable: Bool = true
) throws -> PreparedRequest {
    let prepared = prepareRequest(
        request,
        loginShell: loginShell,
        claudeIsExecutable: claudeIsExecutable
    )
    guard prepared.claudeInputs.isEmpty else {
        throw SlackThreadRequestError.appendedPromptUnavailable
    }
    return prepared
}

private func parseOuterQuery(_ query: String) -> String? {
    let fields = query.split(separator: "&", omittingEmptySubsequences: false)
    guard fields.count == 1,
          let equals = fields[0].firstIndex(of: "="),
          String(fields[0][..<equals]) == SlackThreadURLContract.queryKey else {
        return nil
    }
    let valueStart = fields[0].index(after: equals)
    let value = String(fields[0][valueStart...])
    return value.isEmpty ? nil : value
}

private func validateSlackLink(_ link: String) throws {
    guard !link.contains("%"),
          let components = URLComponents(string: link),
          let scheme = components.scheme,
          scheme.caseInsensitiveCompare("https") == .orderedSame,
          components.user == nil,
          components.password == nil,
          components.port == nil,
          components.fragment == nil,
          let authority = rawAuthority(in: link),
          !authority.contains("@"),
          !authority.contains(":"),
          let host = components.host?.lowercased(),
          isSlackHost(host),
          validSlackMessagePath(components.path),
          validSlackQuery(components.percentEncodedQuery) else {
        throw SlackThreadRequestError.invalidSlackLink
    }
}

private func isSlackHost(_ host: String) -> Bool {
    let label: Substring
    if host.hasSuffix(".enterprise.slack.com") {
        label = host.dropLast(".enterprise.slack.com".count)
    } else if host.hasSuffix(".slack.com") {
        label = host.dropLast(".slack.com".count)
    } else {
        return false
    }
    guard (1...63).contains(label.utf8.count) else { return false }
    return label.unicodeScalars.allSatisfy { scalar in
        (scalar.value >= 0x61 && scalar.value <= 0x7A)
            || (scalar.value >= 0x30 && scalar.value <= 0x39)
            || scalar.value == 0x2D
    }
}

private func validSlackMessagePath(_ path: String) -> Bool {
    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    guard segments.count == 4,
          segments[0].isEmpty,
          segments[1] == "archives",
          validSlackID(String(segments[2])),
          segments[3].count == 17,
          segments[3].first == "p" else {
        return false
    }
    return segments[3].dropFirst().allSatisfy(isASCIIDigit)
}

private func validSlackQuery(_ query: String?) -> Bool {
    guard let query else { return true }
    guard !query.isEmpty else { return false }

    var seen = Set<String>()
    for field in query.split(separator: "&", omittingEmptySubsequences: false) {
        guard let equals = field.firstIndex(of: "=") else { return false }
        let key = String(field[..<equals])
        let valueStart = field.index(after: equals)
        let value = String(field[valueStart...])
        guard seen.insert(key).inserted else { return false }
        switch key {
        case "thread_ts":
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].count == 10,
                  parts[1].count == 6,
                  parts[0].allSatisfy(isASCIIDigit),
                  parts[1].allSatisfy(isASCIIDigit) else { return false }
        case "cid":
            guard validSlackID(value) else { return false }
        default:
            return false
        }
    }
    return true
}

private func validSlackID(_ value: String) -> Bool {
    let scalars = Array(value.unicodeScalars)
    guard (9...11).contains(scalars.count),
          let first = scalars.first,
          first.value == 0x43 || first.value == 0x47 || first.value == 0x44 else {
        return false
    }
    return scalars.dropFirst().allSatisfy { scalar in
        (scalar.value >= 0x41 && scalar.value <= 0x5A)
            || (scalar.value >= 0x30 && scalar.value <= 0x39)
    }
}

private func isASCIIDigit(_ character: Character) -> Bool {
    character.unicodeScalars.count == 1
        && character.unicodeScalars.first.map { $0.value >= 0x30 && $0.value <= 0x39 } == true
}

private func rawAuthority(in value: String) -> String? {
    guard let schemeSeparator = value.range(of: "://") else { return nil }
    let authorityStart = schemeSeparator.upperBound
    let remainder = value[authorityStart...]
    let authorityEnd = remainder.firstIndex(where: { "/?#".contains($0) }) ?? remainder.endIndex
    return String(remainder[..<authorityEnd])
}
