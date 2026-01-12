# Keystone v2: Runestone Fork Plan

## Executive Summary

Replace Keystone's UITextView/NSTextView-based architecture with a fork of [Runestone](https://github.com/simonbs/Runestone), adding macOS support and the features needed for Enter Space.

**Why Runestone:**
- Purpose-built for large file editing with O(1) operations
- Uses RedBlackTree for efficient line management (not O(n) scans)
- TreeSitter integration for incremental syntax highlighting
- Viewport-only rendering (only renders visible lines)
- Already has: line numbers, invisible chars, character pairs, search, indentation detection

**Current Keystone Problems (unfixable with UITextView/NSTextView):**
- UITextView does O(n) internal layout on every keystroke
- ensureLayout() is catastrophic for large files
- No way to skip UITextView's internal processing
- "Fast paths" are band-aids, not solutions

---

## Phase 1: Fork & macOS Platform Support

### 1.1 Initial Setup
- [ ] Fork simonbs/Runestone to your GitHub
- [ ] Clone with submodules: `git clone --recursive`
- [ ] Rename to "Keystone" (or keep Runestone name)
- [ ] Update Package.swift for dual-platform support

### 1.2 Platform Abstraction Layer

Runestone uses UIKit exclusively. We need a cross-platform abstraction:

```
Sources/
  Keystone/
    Platform/
      PlatformTypes.swift      # Typealias layer
      iOS/
        PlatformView.swift     # UIView wrapper
        PlatformScrollView.swift
        PlatformTextInput.swift
      macOS/
        PlatformView.swift     # NSView wrapper
        PlatformScrollView.swift
        PlatformTextInput.swift
```

**Key UIKit → AppKit Mappings:**

| UIKit | AppKit | Notes |
|-------|--------|-------|
| UIView | NSView | Different coordinate systems (flipped) |
| UIScrollView | NSScrollView | Different scrolling APIs |
| UITextInput protocol | NSTextInputClient | Text input handling |
| UIColor | NSColor | Color types |
| UIFont | NSFont | Font types |
| CGPoint/CGRect | Same | Core Graphics shared |
| UITouch | NSEvent | Input events |
| UIGestureRecognizer | NSGestureRecognizer | Different APIs |

### 1.3 Core Components to Port

**Priority 1 - Must work for basic editing:**
1. `TextView.swift` (main view) → Create NSView equivalent
2. `TextInputView.swift` → Implement NSTextInputClient
3. `LayoutManager.swift` → Should work (uses Core Text)
4. `LineFragmentView.swift` → Port to NSView
5. `ContentSizeService.swift` → Adapt for NSScrollView

**Priority 2 - Required features:**
6. `Gutter/` → Port line number rendering to NSView
7. `SyntaxHighlighting/` → Should work (TreeSitter is cross-platform)
8. `InvisibleCharacters/` → Port drawing code
9. `CharacterPairs/` → Logic should work, input handling differs

**Priority 3 - Nice to have initially:**
10. `SearchAndReplace/` → Port UI components
11. `PageGuide/` → Simple drawing, easy port

### 1.4 Input Handling Differences

**iOS (UITextInput):**
```swift
protocol UITextInput {
    func insertText(_ text: String)
    func deleteBackward()
    var selectedTextRange: UITextRange? { get set }
    // ... etc
}
```

**macOS (NSTextInputClient):**
```swift
protocol NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange)
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange)
    func unmarkText()
    var selectedRange: NSRange { get }
    // ... etc
}
```

The macOS text input system is more complex (handles IME, dead keys, etc.) but more powerful.

### 1.5 Estimated Effort: Phase 1
- **Platform abstraction layer:** 2-3 days
- **Core TextView port:** 3-5 days
- **Input handling:** 2-3 days
- **Line numbers/gutter:** 1-2 days
- **Testing & debugging:** 3-5 days

**Total Phase 1: ~2-3 weeks**

---

## Phase 2: Feature Parity with Current Keystone

### 2.1 Already in Runestone
- [x] Syntax highlighting (TreeSitter)
- [x] Line numbers
- [x] Invisible characters
- [x] Character pair insertion
- [x] Line wrapping toggle
- [x] Indentation detection
- [x] Line ending detection
- [x] Basic search (regex)

### 2.2 Needs to be Added

#### Code Folding
**Complexity: Medium-High**

Runestone doesn't have code folding. Need to add:
- `CodeFoldingManager.swift` - Track foldable regions from TreeSitter
- `FoldGutterView.swift` - Fold/unfold indicators in gutter
- `FoldedLineFragment.swift` - Collapsed region display
- Modify `LayoutManager` to skip folded ranges

**TreeSitter provides the fold points** via query captures like `@fold`.

#### Comprehensive Find/Replace
**Complexity: Medium**

Runestone has basic search. Add:
- Find/replace bar UI (SwiftUI overlay)
- Replace single/all functionality
- Match highlighting across document
- Navigation between matches
- Case sensitivity, whole word, regex options

#### Comment Toggling
**Complexity: Low**

- Detect language comment syntax from TreeSitter
- Toggle line comments (// or #)
- Toggle block comments (/* */)
- Handle selection-based commenting

#### Line Indent Conversion
**Complexity: Low**

- Convert tabs to spaces (configurable width)
- Convert spaces to tabs
- Batch convert entire document

#### Line Ending Conversion
**Complexity: Low**

Already has detection. Add:
- Convert CR → LF
- Convert LF → CRLF
- Convert CRLF → LF

#### Nested Syntax Highlighting
**Complexity: Medium**

For `<script>` and `<style>` in HTML:
- TreeSitter supports language injection
- Need to configure HTML parser with JS/CSS sub-parsers
- May need custom TreeSitter queries

#### Follow/Tail Mode
**Complexity: Low**

- Auto-scroll to bottom on text append
- Toggle for enabling/disabling
- Smart detection of "at bottom" state

#### Disk-Based Undo/Redo History
**Complexity: High**

Runestone has `TimedUndoManager`. Need to extend:
- Serialize undo stack to disk
- Lazy load undo history
- Handle large undo stacks efficiently
- Persist across app restarts

### 2.3 Estimated Effort: Phase 2
- **Code folding:** 3-5 days
- **Find/replace enhancement:** 2-3 days
- **Comment toggling:** 1 day
- **Indent/ending conversion:** 1 day
- **Nested highlighting:** 2-3 days
- **Follow/tail mode:** 0.5 days
- **Disk-based undo:** 3-5 days

**Total Phase 2: ~2-3 weeks**

---

## Phase 3: Integration with Enter Space

### 3.1 SwiftUI Wrapper

Create a clean SwiftUI interface:

```swift
public struct KeystoneEditor: View {
    @Binding var text: String
    @Binding var cursorPosition: CursorPosition
    var language: KeystoneLanguage
    var configuration: KeystoneConfiguration

    // Callbacks
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((CursorPosition) -> Void)?
}
```

### 3.2 API Compatibility

Maintain similar API to current Keystone where possible:
- `KeystoneConfiguration` for settings
- `KeystoneLanguage` enum for syntax
- `KeystoneTheme` for colors
- `CursorPosition` struct

### 3.3 Migration Path

1. Keep old Keystone as fallback during development
2. Feature flag to switch between implementations
3. Gradual rollout in Enter Space

---

## Architecture Comparison

### Current Keystone
```
SwiftUI Binding ←→ UITextView/NSTextView
                        ↓
                   TextStorage (O(n) operations)
                        ↓
                   LayoutManager (O(n) ensureLayout)
                        ↓
                   Screen Rendering
```

### Runestone-based Keystone
```
SwiftUI Binding ←→ TextView (custom)
                        ↓
                   StringView (efficient storage)
                        ↓
                   LineManager (RedBlackTree - O(log n))
                        ↓
                   LayoutManager (viewport only)
                        ↓
                   LineFragmentViews (visible lines only)
                        ↓
                   Screen Rendering
```

**Key difference:** Runestone only processes visible content. Current Keystone processes the entire document on every change.

---

## Risk Assessment

### Low Risk
- TreeSitter integration (already works)
- Basic features (line numbers, invisibles)
- SwiftUI wrapper

### Medium Risk
- macOS input handling (NSTextInputClient complexity)
- Code folding (architectural impact)
- Performance parity with iOS

### High Risk
- Edge cases in text editing (selection, undo, IME)
- Scroll synchronization between platforms
- Memory management for very large files (10MB+)

---

## Recommended Approach

### Option A: Incremental Port (Recommended)
1. Start with iOS-only fork, verify everything works
2. Add macOS support incrementally
3. Add features one at a time
4. Integrate into Enter Space once stable

### Option B: Parallel Development
1. Fork and work on macOS support separately
2. Keep current Keystone for production
3. Switch when new version is complete

### Option C: Clean Room
1. Study Runestone's architecture
2. Build new implementation inspired by it
3. More control but much more work

**Recommendation: Option A** - Lower risk, faster feedback loop.

---

## Next Steps

1. **Fork Runestone** to your GitHub account ✅
2. **Clone locally** with `--recursive` flag ✅
3. **Create feature branch** for macOS support ✅
4. **Start with Platform abstraction** layer ✅ (created PlatformImports.swift)

---

## Reality Check: Scope Assessment

After examining Runestone's codebase:

- **90 files** import UIKit directly
- **164 uses** of UIColor
- **53 uses** of UITextPosition (iOS-only type)
- **35 uses** of UITextRange (iOS-only type)
- **13 uses** of UITextInput protocol (completely different from NSTextInputClient)

### The Hard Part: Text Input

iOS uses `UITextInput` protocol with:
- `UITextPosition` - abstract position type
- `UITextRange` - abstract range type
- `selectedTextRange`, `markedTextRange` - for IME support
- Geometric methods like `firstRect(for:)`, `caretRect(for:)`

macOS uses `NSTextInputClient` protocol which is structurally different:
- Uses `NSRange` directly instead of abstract position types
- Different method signatures
- Different IME handling

**This is the core challenge** - you can't just alias types, you need a compatibility layer.

---

## Revised Approach Options

### Option A: Dual Implementation (Recommended)
Keep Runestone for iOS, build a parallel macOS implementation that shares:
- LineManager (pure Swift, no UIKit)
- RedBlackTree (pure Swift)
- TreeSitter integration (cross-platform)
- Syntax highlighting logic (pure Swift)

Build macOS-specific:
- NSTextInputClient-based text view
- NSScrollView container
- AppKit rendering

**Effort: 3-4 weeks for basic editing**

### Option B: Full Port with Abstraction Layer
Port every file with `#if canImport(UIKit)` / `#if canImport(AppKit)` blocks.

**Effort: 4-6 weeks, high risk of bugs**

### Option C: Use Existing Cross-Platform Solution
Consider CodeEditTextView (SwiftUI-native, already macOS) or STTextView (AppKit-native).

**Effort: Evaluate alternatives first**

---

## Recommendation

Given your frustration with Keystone's performance issues stemming from UITextView/NSTextView, and the significant effort to port Runestone:

**I recommend Option A** - Extract Runestone's reusable components (LineManager, RedBlackTree, syntax highlighting) and build a macOS-native text view using NSTextInputClient. This gives you:

1. Runestone's efficient data structures
2. Native macOS text input (better IME support, accessibility)
3. Cleaner separation of concerns
4. Faster path to working code

Would you like me to:
1. Continue with Option A (extract + build macOS native)?
2. Try Option B (full abstraction layer port)?
3. Evaluate Option C (existing solutions like CodeEditTextView)?

Ready to proceed?
