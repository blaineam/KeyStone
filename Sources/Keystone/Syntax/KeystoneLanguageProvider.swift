//
//  KeystoneLanguageProvider.swift
//  Keystone
//
//  Provides TreeSitter languages on demand for embedded language support.
//

import Foundation

/// Provides TreeSitter languages on demand for embedded language support (e.g., JavaScript in HTML).
public final class KeystoneLanguageProvider: TreeSitterLanguageProvider {
    public static let shared = KeystoneLanguageProvider()

    /// Cache for TreeSitterLanguage instances - avoids repeated query compilation
    private var languageCache: [KeystoneLanguage: TreeSitterLanguage] = [:]
    private let cacheLock = NSLock()

    private init() {}

    /// Get or create a cached TreeSitterLanguage for the given KeystoneLanguage
    private func cachedLanguage(for keystoneLanguage: KeystoneLanguage) -> TreeSitterLanguage? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = languageCache[keystoneLanguage] {
            return cached
        }

        // Create and cache the language
        if let language = keystoneLanguage.treeSitterLanguage {
            languageCache[keystoneLanguage] = language
            return language
        }

        return nil
    }

    public func treeSitterLanguage(named languageName: String) -> TreeSitterLanguage? {
        // Map the language name to KeystoneLanguage and return its TreeSitterLanguage
        let normalizedName = languageName.lowercased()

        let keystoneLanguage: KeystoneLanguage?
        switch normalizedName {
        case "javascript", "js":
            keystoneLanguage = .javascript
        case "typescript", "ts":
            keystoneLanguage = .typescript
        case "css":
            keystoneLanguage = .css
        case "html":
            keystoneLanguage = .html
        case "json":
            keystoneLanguage = .json
        case "python", "py":
            keystoneLanguage = .python
        case "swift":
            keystoneLanguage = .swift
        case "go":
            keystoneLanguage = .go
        case "rust", "rs":
            keystoneLanguage = .rust
        case "c":
            keystoneLanguage = .c
        case "cpp", "c++":
            keystoneLanguage = .cpp
        case "ruby", "rb":
            keystoneLanguage = .ruby
        case "yaml", "yml":
            keystoneLanguage = .yaml
        case "bash", "sh", "shell":
            keystoneLanguage = .shell
        case "markdown", "md":
            keystoneLanguage = .markdown
        case "java":
            keystoneLanguage = .java
        case "sql":
            keystoneLanguage = .sql
        case "php":
            keystoneLanguage = .php
        case "jsdoc":
            keystoneLanguage = .jsdoc
        case "regex":
            keystoneLanguage = .regex
        default:
            keystoneLanguage = nil
        }

        guard let lang = keystoneLanguage else {
            #if DEBUG
            print("[KeystoneLanguageProvider] Unknown language: '\(normalizedName)'")
            #endif
            return nil
        }

        return cachedLanguage(for: lang)
    }
}
