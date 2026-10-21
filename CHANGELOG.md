# Changelog

All notable changes to KeyStone are documented here. This project adheres to [Semantic Versioning](https://semver.org/). Releases before 2.6.0 are described by their tags and commit history.

## [2.8.1] - 2026-10-21

### Fixed

- **The macOS editor is an accessibility text area.** `TextInputViewMac` exposed no AX role, so VoiceOver read only the line numbers and XCUITest's `textViews` found nothing. It now reports `AXTextArea` with value, selected text/range (settable), insertion-point line, line ranges, and frames, identifier `keystone-editor`.

## [2.8.0] - 2026-10-21

### Added

- **Format: Prettify / Minify for JavaScript and TypeScript.** `CodeFormatter` now supports `.javascript` and `.typescript` through js-beautify 1.15.4 (MIT) and terser 5.44.0 (BSD-2), bundled as package resources under `Resources/Formatters` and run in-process in JavaScriptCore (`JavaScriptFormatter.swift`): no process, no network. Prettify honours the editor's indent string (spaces or tabs) and ends with a newline; minify strips whitespace and comments but keeps identifiers and statements (`compress: false`, `mangle: false`), so the result prettifies back to the same text. Minify is JavaScript-only (terser does not parse type annotations) and returns nil for TypeScript; inputs over 2 MB and programs with syntax errors return nil instead of throwing. Each library is evaluated lazily, once, on a private serial queue; the first call costs ~40 ms (js-beautify) / ~0.5 s (terser) to load.

### Changed

- **Long lines are stored and typeset in chunks.** A line above `LineController.maximumHighlightedLineLength` (20k UTF-16 units) is split into pieces of at most `LineController.chunkLength` (8,192), each with its own attributed string and `CTTypesetter`. A keystroke rebuilds only the chunk containing it and shifts the rest; the text input views pass the replaced range through `LayoutManager.redisplayLines(withIDs:replacing:)` so the line never compares its whole text, with a memcmp-based prefix/suffix compare as the fallback for unhinted invalidations. Line fragments stay line-local (`LineFragment.stringOffset` carries the chunk base; `xOffset(forLineLocalIndex:)` / `lineLocalIndex(forPosition:)` replace direct `CTLine` index calls in the renderer and caret code), so soft-wrap boundaries may now fall at a chunk boundary in such lines, as in VS Code. Typing at offset 900,000 of the 1 MB minified line with wrapping, line numbers and invisibles on, viewport scrolled there, measures ~5–6 ms per keystroke in a debug build (was 38 ms average, 54 ms worst); with wrapping off ~9 ms (was 25 ms). Lines under the threshold are unchanged. Along the way: typesetting resumes with an in-place truncation instead of rebuilding the fragment map, fragment-tree nodes after the edit are updated in place rather than removed and re-inserted, the line-break suggester and whitespace check read UTF-16 units instead of making one-character substrings, the default paragraph style is cached per tab width, and the known fragment height is kept incrementally.

### Tests

- `ChunkedLineTests` (edits inside, at and across chunk boundaries, hinted and compared reconciliation, a line crossing the threshold both ways, caret round-trips across chunk offsets) and a `PerformanceBudgetTests` budget for typing deep inside the wrapped 1 MB line.

## [2.7.0] - 2026-10-21

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

- **macOS keyboard parity.** The Mac view handled only arrows and Delete. It now implements the standard key bindings: word movement (⌥←/→), smart Home/End, paragraph and document movement, Page Up/Down, every ⇧-extending variant, ⌥⌫/⌥⌦, ⌘⌫, ⌃K, ⇧Tab outdent and Tab indent of multi-line selections, Select Word/Line, and ⇧-click to extend.
- **Multiple cursors.** ⌥-click adds or removes a caret, ⌘D selects the word then each next occurrence, ⌘⇧L selects every occurrence, ⌘⌥↑/↓ (or ⌃⇧↑/↓ on the Mac) add a caret above/below, Esc collapses. Typing, deleting, paste (one line per caret when the counts match), copy (joined) and undo all work across carets. On iPadOS/iOS this needs a hardware keyboard or a pointer (⌥-tap, ⇧-tap): UIKit's selection UI only knows the primary cursor, so Keystone draws the others itself and routes arrow keys, ⌘D/⌘⇧L/⌘⌥↑/↓ and Esc through its own key handling while several carets exist. `TextView.selectedRanges`, `selectNextOccurrence()`, `selectAllOccurrences()`, `addCaretAbove()/Below()`, `toggleCaret(at:)`, `collapseSelections()` on both platforms.

- **Go to Symbol (⌘⇧O), breadcrumbs and a command palette (⌘⇧P).** Symbols (functions, methods, types, headings, JSON/YAML keys, CSS selectors, HTML ids…) come from the syntax tree for every tree-sitter language, refreshed after each parse up to 500 KB and on demand above. The status bar shows the symbol path around the caret. The palette lists every editor command with its shortcut, fuzzy-filtered; hosts add their own with `KeystoneEditor.commands(_:)`. `KeystoneDocument.symbols` / `symbolPath(atOffset:)` / `refreshSymbols()`.

- **Gutter change markers, indent guides, bracket-pair colours, and a visible matching bracket.** `KeystoneDocument.changeMarkers` diffs the buffer against the saved text (Myers over line hashes, off the main thread, ~0.4 s after edits pause, reset by `markSaved()`); the gutter shows added (green), modified (blue) and deleted (red) lines. Indent guides follow the indent strategy and run through blank lines inside a block. Brackets are coloured by nesting depth from the syntax tree (`KeystoneTheme.bracketPairColors`). The matching bracket, which was computed but never drawn, is now highlighted. All three have settings toggles and palette commands.

- **Format: Prettify / Minify** for JSON (JSONC comments kept when prettifying), CSS and HTML/XML, in the command palette. Token-based, so only whitespace (and, when minifying, comments) changes; raw `<script>`/`<style>`/`<pre>` content is re-indented, not reflowed; inline HTML elements stay in their text run. JavaScript/TypeScript are not handled (they need a real parser).
- **Inline Assist (⌘I).** The host supplies the model call with `KeystoneEditor.inlineAssist { request in … }`; Keystone owns the flow: describe the change, the proposal replaces the selection (or the caret's line) as one undo step, highlighted until you Accept (⌘⏎), Reject (⎋) or Try Again. Without a handler the command and button are hidden.

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
