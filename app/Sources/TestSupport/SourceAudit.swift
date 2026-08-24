import Foundation

// Test-only source reads cross this boundary so every caller has to name the contract it audits.
public enum SourceAuditClaim: String, CaseIterable, Sendable {
    case sourceOrder
    case sourceStructure
    case sourceLiteral
    case sourceLifecycle
}

public struct SourceAuditSite: Equatable, Sendable {
    public let path: String
    public let claim: SourceAuditClaim
    public let callerFile: String
    public let callerLine: UInt

    public init(path: String, claim: SourceAuditClaim, callerFile: String, callerLine: UInt) {
        self.path = path
        self.claim = claim
        self.callerFile = callerFile
        self.callerLine = callerLine
    }
}

public struct AuditedSource: Sendable {
    public let text: String
    public let site: SourceAuditSite

    public init(text: String, site: SourceAuditSite) {
        self.text = text
        self.site = site
    }
}

public func auditSource(
    _ path: String,
    claim: SourceAuditClaim,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> AuditedSource {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let site = SourceAuditSite(
        path: path,
        claim: claim,
        callerFile: "\(file)",
        callerLine: line
    )
    return AuditedSource(text: text, site: site)
}
