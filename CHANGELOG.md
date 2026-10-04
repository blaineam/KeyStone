# Changelog

All notable changes to KeyStone are documented here. This project adheres to [Semantic Versioning](https://semver.org/). Releases before 2.6.0 are described by their tags and commit history.

## [2.6.0] - 2026-10-04

### Added (localization)

- **The editor UI follows the user's language.** KeyStone's SwiftUI strings (Editor Settings, toolbar tooltips, find & replace bar, status bar, Go to Line, symbol keyboard, line-ending and follow-speed names) were written as plain literals with no bundle, so SwiftUI looked them up in the *host app's* catalog and they stayed English in every language. Every user-facing string now resolves from KeyStone's own bundle (`Text(_:bundle: .module)`, `String(localized:bundle: .module)`), and all 76 are in `en.lproj`.
- **New languages:** Italian, Simplified Chinese, Korean and Brazilian Portuguese, alongside the existing German, Spanish, Finnish, French and Japanese — every language carries every key.
- `IndentationType.localizedName` (new, public) for display; `rawValue` stays the persisted English identifier. The "Plain Text" language name and the "System" theme name are localized too.
- `LocalizationTests` checks every language has every English key with matching format specifiers, and that lookups resolve from the package bundle.

### Fixed

- Crash applying stale search matches after document edits: `SearchMatch` now also records its UTF-16 `NSRange` and every consumer validates it against the current text before use.
- 30 MB+ files are editable without per-keystroke beachballs: the text binding is debounced for large buffers, and line-ending/indentation detection samples only the first 256 KB.

### Docs

- Security hardening notes in the README.
