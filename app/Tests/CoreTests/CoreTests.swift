import XCTest
@testable import Core

// MARK: - 명령 렌더링 (변수 치환 + command injection 방지)

final class RenderTests: XCTestCase {
    func testRenderBasic() throws {
        let cmd = try renderCommand(
            template: "z {repo} && git fetch origin && git checkout {branch}",
            variables: ["repo": "remy", "branch": "fix/login"]
        )
        XCTAssertEqual(cmd, "z remy && git fetch origin && git checkout fix/login")
    }

    func testRenderAllVariables() throws {
        let cmd = try renderCommand(
            template: "{repo} {branch} {main} {branch_underbar}",
            variables: ["repo": "r", "branch": "a/b", "main": "develop", "branch_underbar": "a_b"]
        )
        XCTAssertEqual(cmd, "r a/b develop a_b")
    }

    func testAcceptsAllowedCharacters() throws {
        _ = try renderCommand(template: "z {repo}", variables: ["repo": "my-repo_1.2/x"])
    }

    func testRejectsInvalidCharactersInValue() {
        for bad in ["a;rm -rf /", "a b", "한글", "", "a$b", "a`b`", "a\"b", "a&&b|c", "a\nb"] {
            XCTAssertThrowsError(
                try renderCommand(template: "z {repo}", variables: ["repo": bad]),
                "value should be rejected: \(bad)"
            )
        }
    }

    func testRejectsUnknownVariableName() {
        XCTAssertThrowsError(
            try renderCommand(template: "z {repo}", variables: ["repo": "r", "evil": "x"])
        )
    }

    func testRejectsUnprovidedTemplateVariable() {
        XCTAssertThrowsError(
            try renderCommand(template: "git checkout {main}", variables: ["repo": "r"])
        )
    }

    // bash 그룹핑 { …; }는 변수 패턴({word})이 아니므로 그대로 통과해야 한다
    // (기본 checkout 프리셋이 워크트리 fallback에 { } 그룹핑을 사용)
    func testBashGroupingBracesPassThrough() throws {
        let cmd = try renderCommand(
            template: "z {repo} && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }",
            variables: ["repo": "remy", "branch": "ci/x", "branch_underbar": "ci_x"]
        )
        XCTAssertEqual(cmd, "z remy && { git checkout ci/x || cd ../remy-ci_x; }")
    }
}

// MARK: - 요청 해석 (신규 command_template 포맷 + 구 {repo, branch} 포맷)

final class RequestTests: XCTestCase {
    func testTemplateRequest() throws {
        let req: [String: Any] = [
            "command_template": "z {repo} && git checkout {branch}",
            "variables": ["repo": "remy", "branch": "fix/x"],
            "terminal": "wezterm",
        ]
        let r = try resolveRequest(req)
        XCTAssertEqual(r.command, "z remy && git checkout fix/x")
        XCTAssertEqual(r.terminal, "wezterm")
    }

    func testTemplateRequestDefaultsToITerm() throws {
        let req: [String: Any] = [
            "command_template": "z {repo}",
            "variables": ["repo": "remy"],
        ]
        XCTAssertEqual(try resolveRequest(req).terminal, "iterm")
    }

    func testLegacyCheckoutRequest() throws {
        let r = try resolveRequest(["repo": "remy", "branch": "fix/x"])
        XCTAssertEqual(r.command, "z remy && git fetch origin && git checkout fix/x")
        XCTAssertEqual(r.terminal, "iterm")
    }

    func testLegacyOpenRequest() throws {
        XCTAssertEqual(try resolveRequest(["repo": "remy"]).command, "z remy")
    }

    func testLegacySanitizes() {
        XCTAssertThrowsError(try resolveRequest(["repo": "a;b"]))
        XCTAssertThrowsError(try resolveRequest(["repo": "remy", "branch": "x;y"]))
    }

    func testMissingRepoThrows() {
        XCTAssertThrowsError(try resolveRequest([:]))
        XCTAssertThrowsError(try resolveRequest(["unrelated": 1]))
    }
}

// MARK: - 요청 핸들러 (성공/실패 JSON 응답 형태)

final class HandlerTests: XCTestCase {
    func testHandleRequestSuccess() {
        var ran: (cmd: String, terminal: String)?
        let resp = handleRequest(
            json: [
                "command_template": "z {repo}",
                "variables": ["repo": "remy"],
                "terminal": "wezterm",
            ],
            run: { cmd, terminal in ran = (cmd, terminal) }
        )
        XCTAssertEqual(resp["success"] as? Bool, true)
        XCTAssertEqual(ran?.cmd, "z remy")
        XCTAssertEqual(ran?.terminal, "wezterm")
    }

    func testHandleRequestRenderError() {
        var didRun = false
        let resp = handleRequest(
            json: ["command_template": "z {repo}", "variables": ["repo": "a;b"]],
            run: { _, _ in didRun = true }
        )
        XCTAssertEqual(resp["success"] as? Bool, false)
        XCTAssertFalse(didRun)
        XCTAssertTrue((resp["error"] as? String ?? "").contains("Invalid characters"))
    }

    func testHandleRequestRunError() {
        struct Boom: Error, CustomStringConvertible { var description: String { "boom" } }
        let resp = handleRequest(
            json: ["command_template": "z {repo}", "variables": ["repo": "remy"]],
            run: { _, _ in throw Boom() }
        )
        XCTAssertEqual(resp["success"] as? Bool, false)
        XCTAssertEqual(resp["error"] as? String, "boom")
    }
}

// MARK: - AppleScript 이스케이프

final class AppleScriptTests: XCTestCase {
    func testEscapeQuotesAndBackslashes() {
        XCTAssertEqual(escapeForAppleScript(#"say "hi" \ now"#), #"say \"hi\" \\ now"#)
    }

    func testEscapeNewline() {
        XCTAssertEqual(escapeForAppleScript("a\nb"), #"a\nb"#)
    }

    func testITermScriptEmbedsEscapedCommand() {
        let script = iTermScript(for: #"echo "hi""#)
        XCTAssertTrue(script.contains(#"write text "echo \"hi\"""#))
        // 이름("iTerm2")이 아닌 번들 ID로 타게팅해야 한다 — 앱 파일명이 iTerm.app이거나
        // 복사본(iTerm Rosetta.app 등)으로 LaunchServices 이름 해석이 꼬여도 동작하도록 (-1728 방지)
        XCTAssertTrue(script.contains(#"tell application id "com.googlecode.iterm2""#))
        XCTAssertFalse(script.contains(#"tell application "iTerm2""#))
    }
}

// MARK: - Extension ID (unpacked 확장: SHA-256(절대경로) 앞 32 hex → a-p)

final class ExtensionIDTests: XCTestCase {
    func testKnownVectors() {
        // 벡터는 기존 install.sh의 파이썬 구현으로 계산한 값
        XCTAssertEqual(extensionID(forPath: "/Users/test/extension"), "ommholjeknmifgidochbhocolnejiema")
        XCTAssertEqual(extensionID(forPath: "/tmp/e"), "cinkehcaekebplmoijecmdfmflcnboch")
    }

    func testIDIsStable() {
        XCTAssertEqual(extensionID(forPath: "/tmp/e"), extensionID(forPath: "/tmp/e"))
    }
}

// MARK: - Native Host manifest JSON

final class ManifestTests: XCTestCase {
    func testManifestJSON() throws {
        let relayPath = "/Applications/Terminal Checkout.app/Contents/MacOS/terminal-checkout-relay"
        let data = nativeHostManifestJSON(relayPath: relayPath, extensionIDs: ["abcdefgh"])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["name"] as? String, "com.dazebug.terminal_checkout")
        XCTAssertEqual(obj["type"] as? String, "stdio")
        XCTAssertEqual(obj["path"] as? String, relayPath)
        XCTAssertEqual(obj["allowed_origins"] as? [String], ["chrome-extension://abcdefgh/"])
    }

    // Web Store 전환 대비: store ID + 개발용 ID 병기 지원
    func testManifestJSONMultipleOrigins() throws {
        let data = nativeHostManifestJSON(relayPath: "/x", extensionIDs: ["aaa", "bbb"])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            obj["allowed_origins"] as? [String],
            ["chrome-extension://aaa/", "chrome-extension://bbb/"]
        )
    }
}

// MARK: - Native Messaging 프레이밍 (4바이트 LE 길이 + JSON)

final class FramingTests: XCTestCase {
    func testFrameMessage() {
        let framed = frameMessage(Data(#"{"a":1}"#.utf8))
        XCTAssertEqual(framed.prefix(4), Data([7, 0, 0, 0]))
        XCTAssertEqual(framed.count, 11)
    }

    func testReadFramedFromPipe() throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(frameMessage(Data("hello".utf8)))
        pipe.fileHandleForWriting.write(frameMessage(Data("world!".utf8)))
        pipe.fileHandleForWriting.closeFile()
        let fd = pipe.fileHandleForReading.fileDescriptor
        XCTAssertEqual(readFramedMessage(fromFD: fd), Data("hello".utf8))
        XCTAssertEqual(readFramedMessage(fromFD: fd), Data("world!".utf8))
        XCTAssertNil(readFramedMessage(fromFD: fd)) // EOF
    }
}

// MARK: - 경로 상수

final class PathsTests: XCTestCase {
    func testSocketPathEnvOverride() {
        setenv("TERMINAL_CHECKOUT_SOCKET", "/tmp/tc-test.sock", 1)
        defer { unsetenv("TERMINAL_CHECKOUT_SOCKET") }
        XCTAssertEqual(defaultSocketPath(), "/tmp/tc-test.sock")
    }

    func testSocketPathDefault() {
        unsetenv("TERMINAL_CHECKOUT_SOCKET")
        XCTAssertTrue(defaultSocketPath().hasSuffix("/Library/Application Support/TerminalCheckout/host.sock"))
    }
}
