import Core
import XCTest
@testable import App

final class CmuxDetectionTests: XCTestCase {
    func testItem12CmuxOnlyInstallationSelectsCmux() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: false, wezterm: false, warp: false, cmux: true, cmuxNightly: false
            ),
            .cmux
        )
    }

    func testItem12NoInstalledTerminalFallsBackToITerm() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: false, wezterm: false, warp: false, cmux: false, cmuxNightly: false
            ),
            .iterm
        )
    }

    func testItem12ITermWinsOverCmux() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: true, wezterm: false, warp: false, cmux: true, cmuxNightly: false
            ),
            .iterm
        )
    }

    func testItem12WarpWinsOverCmux() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: false, wezterm: false, warp: true, cmux: true, cmuxNightly: false
            ),
            .warp
        )
    }

    func testNightlyOnlyInstallationSelectsNightly() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: false, wezterm: false, warp: false, cmux: false, cmuxNightly: true
            ),
            .cmuxNightly
        )
    }

    func testStableCmuxWinsOverNightlyInAutoDetection() {
        XCTAssertEqual(
            Settings.terminalForInstalledTerminals(
                iterm: false, wezterm: false, warp: false, cmux: true, cmuxNightly: true
            ),
            .cmux
        )
    }
}
