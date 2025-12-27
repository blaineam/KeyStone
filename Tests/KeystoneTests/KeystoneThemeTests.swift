//
//  KeystoneThemeTests.swift
//  KeystoneTests
//

import XCTest
import SwiftUI
@testable import Keystone

final class KeystoneThemeTests: XCTestCase {

    // MARK: - Theme Lookup Tests

    func testThemeNamedSystem() {
        let theme = KeystoneTheme.theme(named: "System")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .system)
    }

    func testThemeNamedMonokai() {
        let theme = KeystoneTheme.theme(named: "Monokai")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .monokai)
    }

    func testThemeNamedDracula() {
        let theme = KeystoneTheme.theme(named: "Dracula")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .dracula)
    }

    func testThemeNamedOneDark() {
        let theme = KeystoneTheme.theme(named: "One Dark")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .oneDark)
    }

    func testThemeNamedXcodeLight() {
        let theme = KeystoneTheme.theme(named: "Xcode Light")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .xcode)
    }

    func testThemeNamedXcodeDark() {
        let theme = KeystoneTheme.theme(named: "Xcode Dark")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .xcodeDark)
    }

    func testThemeNamedGitHub() {
        let theme = KeystoneTheme.theme(named: "GitHub")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .github)
    }

    func testThemeNamedSolarizedLight() {
        let theme = KeystoneTheme.theme(named: "Solarized Light")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .solarizedLight)
    }

    func testThemeNamedSolarizedDark() {
        let theme = KeystoneTheme.theme(named: "Solarized Dark")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .solarizedDark)
    }

    func testThemeNamedInvalid() {
        let theme = KeystoneTheme.theme(named: "Invalid Theme")
        XCTAssertNil(theme)
    }

    // MARK: - Theme Name Lookup Tests

    func testNameForSystemTheme() {
        let name = KeystoneTheme.name(for: .system)
        XCTAssertEqual(name, "System")
    }

    func testNameForMonokaiTheme() {
        let name = KeystoneTheme.name(for: .monokai)
        XCTAssertEqual(name, "Monokai")
    }

    func testNameForDraculaTheme() {
        let name = KeystoneTheme.name(for: .dracula)
        XCTAssertEqual(name, "Dracula")
    }

    func testNameForCustomTheme() {
        // Custom theme not in allThemes should return "System"
        let customTheme = KeystoneTheme(
            keyword: .red,
            type: .blue,
            string: .green,
            comment: .gray,
            number: .orange,
            function: .purple,
            tag: .teal,
            attribute: .cyan,
            operator: .white,
            property: .yellow
        )
        let name = KeystoneTheme.name(for: customTheme)
        XCTAssertEqual(name, "System")
    }

    // MARK: - Theme Properties Tests

    func testAllThemesCount() {
        XCTAssertEqual(KeystoneTheme.allThemes.count, 9)
    }

    func testMonokaiHasInvisibleCharacterColor() {
        let theme = KeystoneTheme.monokai
        XCTAssertNotNil(theme.invisibleCharacter)
    }

    func testDraculaHasInvisibleCharacterColor() {
        let theme = KeystoneTheme.dracula
        XCTAssertNotNil(theme.invisibleCharacter)
    }

    func testXcodeDarkHasInvisibleCharacterColor() {
        let theme = KeystoneTheme.xcodeDark
        XCTAssertNotNil(theme.invisibleCharacter)
    }

    func testOneDarkHasInvisibleCharacterColor() {
        let theme = KeystoneTheme.oneDark
        XCTAssertNotNil(theme.invisibleCharacter)
    }

    func testGitHubHasInvisibleCharacterColor() {
        let theme = KeystoneTheme.github
        XCTAssertNotNil(theme.invisibleCharacter)
    }

    func testSystemHasInvisibleCharacterColor() {
        let theme = KeystoneTheme.system
        XCTAssertNotNil(theme.invisibleCharacter)
    }

    // MARK: - Default Theme Tests

    func testDefaultThemeEqualsSystem() {
        XCTAssertEqual(KeystoneTheme.default, KeystoneTheme.system)
    }
}
