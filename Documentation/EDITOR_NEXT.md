# Editor Next — status

Goal: Keystone fast at any file size or complexity, with the Zed features that
make sense for a code editor (not an IDE), shipped in the next Enter Space update.

Branches: Keystone `feat/editor-next` (this repo), Enter Space
`feat/editor-next-host` (worktree `~/Worktrees/Enter Space/editor-next`, which
temporarily points its KeyStone package at this checkout; drop that pbxproj
change and bump `Package.resolved` once this branch is on `main`).

## Done

| Item | Where | Result |
|---|---|---|
| Editor-owned document (`KeystoneDocument`) | `Document/`, `Views/KeystoneEditor.swift`, `Views/KeystoneTextView.swift` | no per-keystroke buffer copies; O(1) `isModified`/`lineCount`/`version`; `text:` binding kept as an adapter |
| Background tree-sitter parsing ≥ 200 KB | `TreeSitterInternalLanguageMode`, `TreeSitterLanguageLayer` | flat 60k-line Swift: 410 ms → 1.6 ms per keystroke; open no longer blocks on the parse; old highlights kept on the edited line |
| Edit-local injection updates (HTML/Markdown) | `TreeSitterLanguageLayer.updateChildLayersNearEdit` | no whole-tree injections query per keystroke > 200 KB |
| Resume typesetting after the edit in long lines | `LineController`, `LineTypesetter` | 1 MB wrapped line: 115 → ~40 ms |
| Chunked long lines (> 20k units, 8,192-unit chunks) | `LineChunk`, `LineController`, `LineTypesetter`, `LineFragment.stringOffset` | keystroke deep inside a 1 MB wrapped line: ~40 → ~6 ms (debug build); the edit's range is passed to the line so it never compares its whole text |
| Fold regions from the syntax tree | `TreeSitterFoldRegions.swift`, `CodeFoldingManager.applySyntaxTreeRegions` | accurate folds for all tree-sitter languages incl. injections; computed in the parse op; iterative walk |
| Search as you type at any size | `KeystoneEditor` find bar | 150 ms / 400 ms debounce, off main |
| Budgets | `PerformanceBudgetTests` | open < 1 s, keystroke < 50 ms (100 ms inside a minified line), find hand-off < 50 ms |
| macOS keyboard parity | `TextInputViewMac` navigation extension, `TextNavigation.swift` | word/line/document movement, ⇧-extension, delete word/line, Tab/⇧Tab indent, Select Word/Line, ⇧-click |
| Multiple cursors (macOS; iPadOS/iOS with a hardware keyboard or pointer) | same + `TextInputView` multi-caret extension | ⌥-click, ⌘D, ⌘⇧L, ⌘⌥↑/↓, Esc; typing/delete/paste/copy/undo across carets; `TextView.selectedRanges` |
| Go to Symbol, breadcrumbs, command palette | `DocumentSymbols.swift`, `FuzzyPicker.swift`, `EditorCommands.swift` | symbols from the tree for every language; ⌘⇧O / ⌘⇧P; host commands via `.commands(_:)` |
| Gutter change markers | `LineDiff.swift`, `KeystoneDocument.changeMarkers`, `GutterBackgroundView` | Myers over line hashes, 0.4 s debounce, reset by `markSaved()` |
| Indent guides, bracket-pair colours, matching-bracket highlight | `LayoutManager`, `LineFragmentRenderer`, `TreeSitterSyntaxHighlighter` | settings toggles + palette commands |
| Format: prettify / minify | `CodeFormatter.swift`, `JavaScriptFormatter.swift` | JSON (+JSONC), CSS, HTML/XML token-based; JavaScript/TypeScript via js-beautify + terser in JavaScriptCore (`Resources/Formatters`), minify is JS-only |
| Inline Assist (⌘I) | `InlineAssist.swift`, `KeystoneEditor` | host supplies the model; proposal is one undo step, Accept/Reject/Try Again |
| Enter Space host | `CodeEditorView`, `EditorBufferStore`, `EditorAssistService`, `EditorAssistSettingsSection` | document API, lazy snapshots, Ari local API (macOS) / Apple on-device model, remote files opt-in, Save/Preview/Version History in the palette |

Known residuals:
- Chunked long lines wrap at chunk boundaries (every 8,192 units) as well as at
  the view width; with wrapping off that adds an early break every ~6 rows of the
  10,000 pt pseudo-width. A keystroke there still creates one `CTTypesetter` for
  the edited chunk (~1 ms) and re-typesets the fragments between the edit and the
  bottom of the viewport.
- TypeScript minify returns nil: terser parses JavaScript only, and stripping
  types first would need a TypeScript compiler (another ~10 MB bundle). JS/TS
  formatting runs synchronously on the main thread; the 2 MB input cap keeps
  that under a second, but the first terser call pays ~0.5 s to load the bundle.
- On iOS, multiple cursors need a hardware keyboard or pointer; the on-screen keyboard
  types into every caret but can't add or move them.
- Symbols refresh automatically up to 500 KB; above that, opening Go to Symbol
  computes them on demand.

## Releases

- 2.7.0 (2026-10-21): everything above except chunked lines and JS/TS formatting.
- 2.8.0 (2026-10-21): chunked long lines; JS/TS prettify/minify via js-beautify + terser.

Manual QA still worth doing: 2 MB inlined HTML on the Mac (typing, ⌘D, folds,
markers), Ari local API round trip, Apple model on iOS.
