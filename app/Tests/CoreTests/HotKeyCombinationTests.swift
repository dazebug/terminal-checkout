import XCTest
@testable import Core

final class HotKeyCombinationTests: XCTestCase {
    private let keyC: UInt32 = 0x08

    func testRequiresCommandControlOrOption() {
        XCTAssertNil(HotKeyCombination(keyCode: keyC, modifiers: []))
        XCTAssertNil(HotKeyCombination(keyCode: keyC, modifiers: [.shift]))
        XCTAssertNotNil(HotKeyCombination(keyCode: keyC, modifiers: [.command]))
        XCTAssertNotNil(HotKeyCombination(keyCode: keyC, modifiers: [.control, .shift]))
        XCTAssertNotNil(HotKeyCombination(keyCode: keyC, modifiers: [.option]))
    }

    func testRejectsModifierKeysAndCodesOutsideTheVirtualKeyRange() {
        let all: HotKeyModifiers = [.control, .shift, .command]
        for modifierKey: UInt32 in [0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F] {
            XCTAssertNil(HotKeyCombination(keyCode: modifierKey, modifiers: all), "key code \(modifierKey)")
        }
        XCTAssertNil(HotKeyCombination(keyCode: 0x80, modifiers: all))
        XCTAssertNotNil(HotKeyCombination(keyCode: 0x7F, modifiers: all))
    }

    func testDisplayUsesTheMenuModifierOrder() throws {
        let combination = try XCTUnwrap(HotKeyCombination(keyCode: keyC, modifiers: [.command, .shift, .control]))
        XCTAssertEqual(combination.displayString(keyLabel: "C"), "⌃⇧⌘C")
        let everything = try XCTUnwrap(
            HotKeyCombination(keyCode: keyC, modifiers: [.shift, .command, .option, .control])
        )
        XCTAssertEqual(everything.displayString(keyLabel: "C"), "⌃⌥⇧⌘C")
    }

    func testStoredFormRoundTripsAndRejectsAnythingElse() throws {
        let combination = try XCTUnwrap(HotKeyCombination(keyCode: keyC, modifiers: [.control, .shift, .command]))
        let stored = combination.dictionaryRepresentation
        XCTAssertEqual(stored, ["keyCode": 8, "modifiers": 0x1300])
        XCTAssertEqual(HotKeyCombination(dictionaryRepresentation: stored), combination)
        XCTAssertEqual(
            HotKeyCombination(dictionaryRepresentation: ["keyCode": NSNumber(value: 8), "modifiers": NSNumber(value: 0x1300)]),
            combination
        )

        let rejected: [[String: Any]] = [
            [:],
            ["keyCode": 8],
            ["modifiers": 0x1300],
            ["keyCode": "8", "modifiers": 0x1300],
            ["keyCode": 8, "modifiers": "0x1300"],
            ["keyCode": -1, "modifiers": 0x1300],
            ["keyCode": 8, "modifiers": 0x200],
            ["keyCode": 8, "modifiers": 0x1300 | 0x10000],
            ["keyCode": 0x37, "modifiers": 0x1300],
        ]
        for value in rejected {
            XCTAssertNil(HotKeyCombination(dictionaryRepresentation: value), "\(value)")
        }
    }
}
