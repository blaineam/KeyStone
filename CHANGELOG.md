# Changelog

All notable changes to KeyStone are documented here. This project adheres to [Semantic Versioning](https://semver.org/). Releases before 2.6.0 are described by their tags and commit history.

## [Unreleased]

### Added

- **`KeystoneDocument`: the editor owns the text.** Hosts hold a `KeystoneDocument` and use `KeystoneEditor(document:...)` instead of a `String` binding. A keystroke no longer copies the buffer out to SwiftUI and back; per-edit state is O(1): `version`, `isModified` (version-based, no content compare), `lineCount`, and a `didChange` publisher carrying the edited range. `text` is an explicit O(n) snapshot for saving; `replaceAll(with:markSaved:preservingUndo:)` is for loads and reverts. `position(atOffset:)` and `offset(line:column:)` are O(log lines) through the editor's line index. The `text:` initializers still work (Ari uses them) as an adapter over an editor-owned document, pushing a snapshot immediately for ordinary files and once typing pauses for big ones.
- `UndoController.replaceText`/`replaceAll` return `Bool` instead of the whole new text.
- `TextViewDelegate.textView(_:didReplaceTextIn:replacementLength:)` reports the edited range before `textViewDidChange`.

### Changed

- **Tree-sitter parsing runs in the background for documents of 200 KB and up** (`TreeSitterInternalLanguageMode.backgroundParseThreshold`). The incremental reparse and changed-range diff were synchronous on the main thread and O(top-level nodes): 410 ms per keystroke in a flat 60k-line Swift file. Now every tree edit, parse and highlight query runs on one serial queue against a text snapshot, so the main thread only enqueues; highlights lag by at most one parse. Typing in that file measures 1.6 ms, and typing inside a 1 MB minified line with wrapping, line numbers and invisibles on measures about 1 ms (was 240–380 ms). Opening a big file no longer blocks on the full parse either: it renders plain and highlights when the parse lands. The edited line keeps its previous highlighting over the unchanged text until new captures arrive, so nothing flashes to plain. The Return key never waits for a running parse (scope-based indent fallback).
- Go to Line, find-match navigation, symbol insertion, comment toggle and Base64 toggle no longer scan or copy the whole document per operation.

- **Code folding comes from the syntax tree.** Regions are derived from tree-sitter nodes (block-like constructs and anything that opens with a bracket across lines) for every tree-sitter language, including injected ones, computed in the same background parse. Single-line subtrees are never walked, so a minified megabyte line costs nothing. The text heuristics remain for plain text. Fold state survives reparses.
- **Find searches as you type at any file size** (150 ms debounce; 400 ms from 500 KB). The search was already off the main thread; large files were just excluded.
- Typing deep inside a very long wrapped line resumes typesetting after the edit instead of from the line start (115 ms → ~40 ms per keystroke in a 1 MB line).

### Tests

- `KeystoneDocumentTests`, `BackgroundParsingTests` (edits during the initial parse and across reparses converge to a fresh parse, including breaking and restoring a `<script>` tag), and a per-keystroke budget on a flat 20k-line Swift file.

### Fixed (2.6.x)

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
