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
| Fold regions from the syntax tree | `TreeSitterFoldRegions.swift`, `CodeFoldingManager.applySyntaxTreeRegions` | accurate folds for all tree-sitter languages incl. injections; computed in the parse op |
| Search as you type at any size | `KeystoneEditor` find bar | 150 ms / 400 ms debounce, off main |
| Budgets | `PerformanceBudgetTests` | open < 1 s, keystroke < 50 ms (100 ms inside a minified line), find hand-off < 50 ms |
| Enter Space host on the document API | `CodeEditorView`, `EditorBufferStore` | version-based dirty flag, lazy snapshots |

Known residual: typing deep inside a > 1 MB single line with wrapping still costs
~25–40 ms because the whole line's attributed string and `CTTypesetter` are
rebuilt; only chunked lines would remove that.

## Next

1. macOS keyboard parity: word/line/document movement, shift-extend, delete word,
   page up/down (the Mac view only handled arrows and delete).
2. Multi-cursor: ⌥-click, ⌘D next occurrence, ⌘⇧L all occurrences, ⌥⇧↑/↓, Esc.
3. Outline / go-to-symbol (⌘⇧O) and breadcrumbs from the syntax tree.
4. Command palette (⌘⇧P).
5. Gutter diff markers vs. saved text; indent guides; bracket-pair colours and a
   rendered matching-bracket highlight.
6. Format: prettify / minify (native JSON/XML/CSS; js-beautify + terser in
   JavaScriptCore for JS) with a diff preview.
7. Inline assist (select → instruction → diff → accept/reject) via Ari's local
   API on macOS (`127.0.0.1:8765`, OpenAI-compatible) and Apple Foundation
   Models elsewhere; opt-in per remote in Enter Space.
