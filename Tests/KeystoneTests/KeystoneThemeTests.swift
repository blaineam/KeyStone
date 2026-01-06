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

    func testThemeNamedXcodeLight() {
        let theme = KeystoneTheme.theme(named: "Xcode Light")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .xcodeLight)
    }

    func testThemeNamedXcodeDark() {
        let theme = KeystoneTheme.theme(named: "Xcode Dark")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .xcodeDark)
    }

    func testThemeNamedGitHubLight() {
        let theme = KeystoneTheme.theme(named: "GitHub Light")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .githubLight)
    }

    func testThemeNamedSolarizedLight() {
        let theme = KeystoneTheme.theme(named: "Solarized Light")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .solarizedLight)
    }

    func testThemeNamedOneLight() {
        let theme = KeystoneTheme.theme(named: "One Light")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .oneLight)
    }

    func testThemeNamedTomorrow() {
        let theme = KeystoneTheme.theme(named: "Tomorrow")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .tomorrowLight)
    }

    func testThemeNamedNord() {
        let theme = KeystoneTheme.theme(named: "Nord")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .nord)
    }

    func testThemeNamedGruvboxDark() {
        let theme = KeystoneTheme.theme(named: "Gruvbox Dark")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme, .gruvboxDark)
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
        // 1 adaptive + 5 light + 5 dark = 11 themes
        XCTAssertEqual(KeystoneTheme.allThemes.count, 11)
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

    func testXcodeLightHasInvisibleCharacterColor() {
        let theme = KeystoneTheme.xcodeLight
        XCTAssertNotNil(theme.invisibleCharacter)
    }

    func testGitHubLightHasInvisibleCharacterColor() {
        let theme = KeystoneTheme.githubLight
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
