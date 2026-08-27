import Core
import XCTest
@testable import App

final class CmuxDetectionTests: XCTestCase {
    func testItem12CmuxOnlyInstallationSelectsCmux() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: false, wezterm: false, warp: false, cmux: true
            ),
            .cmux
        )
    }

    func testItem12NoInstalledTerminalFallsBackToITerm() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: false, wezterm: false, warp: false, cmux: false
            ),
            .iterm
        )
    }

    func testItem12ITermWinsOverCmux() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: true, wezterm: false, warp: false, cmux: true
            ),
            .iterm
        )
    }

    func testItem12WarpWinsOverCmux() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: false, wezterm: false, warp: true, cmux: true
            ),
            .warp
        )
    }
}
