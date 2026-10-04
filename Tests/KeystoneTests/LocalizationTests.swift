//
//  LocalizationTests.swift
//  KeystoneTests
//
//  Guards KeyStone's own string tables: every shipped language must carry
//  every English key with the same format specifiers, and lookups must come
//  from the package bundle (not the host app's catalog).
//

import XCTest
@testable import Keystone

final class LocalizationTests: XCTestCase {

    /// The suite's Big 8 plus Finnish, which KeyStone already shipped.
    private let languages = ["de", "es", "fi", "fr", "it", "ja", "ko", "pt-BR", "zh-Hans"]

    private func table(_ language: String) throws -> [String: String] {
        let path = try XCTUnwrap(
            Bundle.module.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
            "\(language).lproj/Localizable.strings missing from the KeyStone bundle"
        )
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    private func specifiers(_ string: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?l*[d@]")
        let range = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, range: range).map {
            // Drop any positional index so "%1$lld" compares equal to "%lld".
            String(string[Range($0.range, in: string)!]).replacingOccurrences(of: "\\d+\\$", with: "", options: .regularExpression)
        }
    }

    func testEveryLanguageHasEveryEnglishKey() throws {
        let english = try table("en")
        XCTAssertGreaterThan(english.count, 50)
        for language in languages {
            let translated = try table(language)
            let missing = Set(english.keys).subtracting(translated.keys)
            XCTAssertTrue(missing.isEmpty, "\(language) is missing \(missing.sorted())")
            for (key, value) in translated {
                XCTAssertFalse(value.isEmpty, "\(language): empty translation for \(key)")
                XCTAssertEqual(specifiers(key).count, specifiers(value).count,
                               "\(language): format specifiers differ for \(key) → \(value)")
            }
        }
    }

    func testItalianLookupResolvesFromPackageBundle() throws {
        let path = try XCTUnwrap(Bundle.module.path(forResource: "it", ofType: "lproj"))
        let italian = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(italian.localizedString(forKey: "Editor Settings", value: nil, table: nil), "Impostazioni editor")
        XCTAssertEqual(italian.localizedString(forKey: "Width: %lld spaces", value: nil, table: nil), "Larghezza: %lld spazi")
    }
}
