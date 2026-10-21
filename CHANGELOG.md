# Changelog

All notable changes to KeyStone are documented here. This project adheres to [Semantic Versioning](https://semver.org/). Releases before 2.6.0 are described by their tags and commit history.

## [Unreleased]

### Fixed

- **Typing in multi-megabyte files (e.g. single-file HTML with minified JS/CSS inlined) is responsive again.** A keystroke in a 2.2 MB file measured 0.74 s in an ordinary line and 1.6 s inside the 1 MB minified line; it is now ~3 ms and ~0.1 s.
  - Edits no longer "jump around and mix with old text": while the debounced binding write was pending, `updateView` mistook the stale binding for an external file load and wrote it back over what had just been typed. The decision lives in `EditorTextSync.isExternalChange` and is covered by tests.
  - Code folding analysis was O(regions × file size) on the main thread (`lineLocation` re-walked every line per region). It is now linear, uses UTF-16 offsets for region ranges, and large buffers analyse on a background queue.
  - No more whole-buffer copies per keystroke or selection change: cursor line/column come from the line index, bracket matching reads the backing `NSString`, and the binding snapshot is taken when typing pauses.
  - HTML (and any language with injections) no longer re-runs the injections query over the whole syntax tree after each edit in documents over 200 KB; only the neighbourhood of the change is queried, untouched layers are shifted rather than reparsed, and a layer around the edit is adopted rather than rebuilt. Tests assert the result equals a fresh parse, including after breaking and restoring a `<script>` tag.
  - Lines longer than 20,000 UTF-16 units are no longer syntax highlighted (`LineController.maximumHighlightedLineLength`), as in VS Code.

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
