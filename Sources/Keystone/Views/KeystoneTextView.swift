//
//  KeystoneTextView.swift
//  Keystone
//
//  Platform-specific text view implementations for iOS and macOS.
//  Includes proper line numbers that work with wrapped lines.
//

import SwiftUI

#if os(iOS)
import UIKit

// MARK: - Range Extension

extension Range where Bound == String.Index {
    /// Converts a Range<String.Index> to an NSRange within the given string.
    func nsRange(in string: String) -> NSRange? {
        guard let lowerBound = lowerBound.samePosition(in: string.utf16),
              let upperBound = upperBound.samePosition(in: string.utf16) else { return nil }
        let location = string.utf16.distance(from: string.utf16.startIndex, to: lowerBound)
        let length = string.utf16.distance(from: lowerBound, to: upperBound)
        return NSRange(location: location, length: length)
    }
}

// MARK: - UITextView Extension for NSRange to UITextRange Conversion

extension UITextView {
    /// Converts an NSRange to a UITextRange within this text view.
    func textRange(from range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length) else { return nil }
        return textRange(from: start, to: end)
    }
}

// MARK: - Invisible Character Layout Manager (iOS)

/// Custom layout manager that draws visible symbols for invisible characters.
class InvisibleCharacterLayoutManager: NSLayoutManager {
    /// Color for invisible character symbols.
    var invisibleColor: UIColor = .tertiaryLabel

    /// Whether to show invisible characters.
    var showInvisibles: Bool = false

    /// Symbols for invisible characters.
    private let tabSymbol = "→"
    private let spaceSymbol = "·"
    private let newlineSymbol = "¶"

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        // Draw the regular glyphs first
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        // Draw invisible character symbols if enabled
        guard showInvisibles, let textStorage = textStorage else { return }

        let text = textStorage.string as NSString
        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let symbolAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: invisibleColor
        ]

        enumerateLineFragments(forGlyphRange: glyphsToShow) { [weak self] (rect, usedRect, container, lineGlyphRange, _) in
            guard let self = self else { return }

            for glyphIndex in lineGlyphRange.location..<(lineGlyphRange.location + lineGlyphRange.length) {
                let charIndex = self.characterIndexForGlyph(at: glyphIndex)
                guard charIndex < text.length else { continue }

                let char = text.character(at: charIndex)
                var symbol: String?

                switch char {
                case 0x09: // Tab
                    symbol = self.tabSymbol
                case 0x20: // Space
                    symbol = self.spaceSymbol
                case 0x0A, 0x0D: // Newline / Carriage return
                    symbol = self.newlineSymbol
                default:
                    break
                }

                if let symbol = symbol {
                    var glyphPoint = self.location(forGlyphAt: glyphIndex)
                    glyphPoint.x += origin.x + usedRect.origin.x
                    glyphPoint.y = origin.y + rect.origin.y

                    // Adjust vertical centering
                    let symbolSize = (symbol as NSString).size(withAttributes: symbolAttributes)
                    glyphPoint.y += (rect.height - symbolSize.height) / 2

                    (symbol as NSString).draw(at: glyphPoint, withAttributes: symbolAttributes)
                }
            }
        }
    }
}

/// The SwiftUI wrapper for UITextView on iOS.
public struct KeystoneTextView: UIViewRepresentable {
    @Binding var text: String
    let language: KeystoneLanguage
    @ObservedObject var configuration: KeystoneConfiguration
    @Binding var cursorPosition: CursorPosition
    @Binding var scrollOffset: CGFloat
    @Binding var matchingBracket: BracketMatch?
    /// When set to true, scrolls to make cursor visible, then resets to false
    @Binding var scrollToCursor: Bool
    var searchMatches: [SearchMatch]
    var currentMatchIndex: Int
    var undoController: UndoController?

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> KeystoneTextContainerView {
        let containerView = KeystoneTextContainerView(configuration: configuration)
        containerView.textView.delegate = context.coordinator
        containerView.coordinator = context.coordinator
        context.coordinator.containerView = containerView

        // Connect the undo controller to the container view's undo functionality
        if let undoController = undoController {
            let coordinator = context.coordinator
            undoController.undoAction = { [weak containerView, weak coordinator] in
                containerView?.undo()
                // Sync text immediately after undo to update SwiftUI binding
                coordinator?.syncTextNow()
            }
            undoController.redoAction = { [weak containerView, weak coordinator] in
                containerView?.redo()
                // Sync text immediately after redo to update SwiftUI binding
                coordinator?.syncTextNow()
            }
            undoController.checkUndoState = { [weak containerView] in
                (canUndo: containerView?.canUndo ?? false,
                 canRedo: containerView?.canRedo ?? false)
            }
            // Replace text through UITextView.replace so it properly registers with undo manager
            undoController.replaceTextAction = { [weak containerView] range, replacementText in
                guard let containerView = containerView else { return nil }
                let textView = containerView.textView
                guard range.location + range.length <= textView.textStorage.length else { return nil }

                // Convert NSRange to UITextRange for proper undo registration
                guard let textRange = textView.textRange(from: range) else { return nil }

                // Use UITextView.replace which properly registers with undo manager
                textView.replace(textRange, withText: replacementText)

                // Return the new text
                return textView.text
            }
            // Undo grouping for batching multiple changes
            undoController.beginUndoGroupingAction = { [weak containerView] in
                containerView?.textView.undoManager?.beginUndoGrouping()
            }
            undoController.endUndoGroupingAction = { [weak containerView] in
                containerView?.textView.undoManager?.endUndoGrouping()
            }
            undoController.startUpdating()
        }

        // Code folding disabled for performance testing
        // DispatchQueue.main.async {
        //     containerView.foldingManager.analyze(self.text)
        //     containerView.lineNumberView.setNeedsDisplay()
        // }

        return containerView
    }

    public func updateUIView(_ containerView: KeystoneTextContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true

        // Track if we're scrolling - used to skip non-essential work
        let isCurrentlyScrolling = context.coordinator.isScrolling

        // Skip most work if user is actively editing OR we're syncing from internal edit
        // This prevents updateUIView from overwriting the text view with stale binding data
        let isUserCurrentlyEditing = context.coordinator.isUserEditing || context.coordinator.isSyncingFromInternalEdit

        // Only update configuration if it actually changed (expensive operation)
        // Returns true if we need to re-highlight (font, line wrap, invisibles changed)
        let configNeedsRehighlight = containerView.updateConfigurationIfNeeded(configuration)

        // Use NSString length for O(1) length check instead of O(n) String.count
        let textStorage = containerView.textView.textStorage
        let currentLength = textStorage.length
        let bindingLength = (text as NSString).length

        // Track if we need to re-highlight or update line numbers
        var needsHighlight = configNeedsRehighlight
        var needsLineNumberUpdate = false

        // CRITICAL: Skip text overwriting if user is editing!
        // The text view has the authoritative text during editing.
        // Only update from binding when it's an external change (file load, undo from outside, etc.)
        //
        // IMPORTANT: Setting textView.text clears the undo history!
        // We only do this on initial load. After that, text changes should come through
        // the text view's own editing which properly registers with undo manager.
        if !isUserCurrentlyEditing {
            // Fast path: if lengths differ, text definitely changed
            let textMightHaveChanged = currentLength != bindingLength

            // Only set text directly on FIRST load (to preserve undo history after that)
            if !context.coordinator.hasSetInitialText {
                if textMightHaveChanged || (currentLength == bindingLength && containerView.textView.text != text) {
                    let selectedRange = containerView.textView.selectedRange
                    containerView.textView.text = text
                    needsHighlight = true
                    needsLineNumberUpdate = true
                    context.coordinator.hasSetInitialText = true

                    // Restore selection using O(1) length
                    let newLocation = min(selectedRange.location, bindingLength)
                    containerView.textView.selectedRange = NSRange(location: newLocation, length: 0)
                }
            } else if textMightHaveChanged || (currentLength == bindingLength && containerView.textView.text != text) {
                // After initial load, only set text if it was genuinely changed externally
                // (e.g., file was reloaded, undo from outside text view)
                // Skip if the text view is the one that made the change
                if !context.coordinator.isSyncingFromInternalEdit {
                    let selectedRange = containerView.textView.selectedRange
                    containerView.textView.text = text
                    needsHighlight = true
                    needsLineNumberUpdate = true

                    let newLocation = min(selectedRange.location, bindingLength)
                    containerView.textView.selectedRange = NSRange(location: newLocation, length: 0)
                }
            }
        }

        // Update font if needed
        if containerView.textView.font?.pointSize != configuration.fontSize {
            let font = UIFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
            containerView.textView.font = font
            needsHighlight = true
            needsLineNumberUpdate = true
        }

        // Only re-highlight when necessary (text changed externally, config changed, or font changed)
        // Use viewport-based highlighting for large files
        if needsHighlight {
            let font = containerView.textView.font ?? UIFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
            let highlighter = context.coordinator.getHighlighter(language: language, theme: configuration.theme)
            applyViewportSyntaxHighlighting(to: containerView, text: text, font: font, highlighter: highlighter)
        }

        // Handle cursor position changes for search navigation or tail follow
        // When scrollToCursor is explicitly true, ALWAYS update cursor and scroll regardless of editing state
        // This ensures search navigation, go-to-line, and tail follow work correctly
        //
        // IMPORTANT: Capture scrollToCursor value FIRST and reset it IMMEDIATELY before doing any work.
        // This prevents SwiftUI update loops caused by async state resets.
        let shouldScrollToCursor = scrollToCursor
        if shouldScrollToCursor {
            // Reset IMMEDIATELY to prevent update loop - do this before any other work
            scrollToCursor = false
        }

        // Only update cursor position when explicitly requested (search, go-to-line, tail follow)
        // The text view IS the source of truth for cursor position - we never sync FROM binding TO text view
        // This prevents feedback loops that cause flickering
        if shouldScrollToCursor {
            let newLocation = min(cursorPosition.offset, bindingLength)
            let newLength = min(cursorPosition.selectionLength, max(0, bindingLength - newLocation))
            let newRange = NSRange(location: newLocation, length: newLength)

            // Set flag to prevent textViewDidChangeSelection from updating cursor position back
            context.coordinator.isSettingCursorProgrammatically = true
            containerView.textView.selectedRange = newRange

            // Scroll to the cursor position
            UIView.performWithoutAnimation {
                containerView.textView.scrollRangeToVisible(newRange)
            }

            // Reset flag after a brief delay to ensure selection change notification has fired
            DispatchQueue.main.async {
                context.coordinator.isSettingCursorProgrammatically = false
            }
        }
        // NOTE: Removed automatic cursor sync from binding to text view
        // This was causing feedback loops: textViewDidChangeSelection -> cursorPosition update ->
        // updateUIView -> selectedRange sync -> textViewDidChangeSelection -> loop

        // Only update line numbers when text actually changed (not on every SwiftUI update)
        if needsLineNumberUpdate {
            containerView.updateLineNumbers()
        }

        // SKIP all highlight work during scrolling to prevent flickering
        // This is a key optimization from Runestone's architecture
        if !isCurrentlyScrolling {
            // Apply bracket highlights
            if let prevMatch = context.coordinator.previousBracketMatch {
                clearBracketHighlights(from: textStorage, match: prevMatch)
            }
            if let match = matchingBracket {
                applyBracketHighlights(to: textStorage, match: match)
                context.coordinator.previousBracketMatch = match
            } else {
                context.coordinator.previousBracketMatch = nil
            }

            // Update current line highlight - only if cursor position changed
            if configuration.highlightCurrentLine {
                if cursorPosition.offset != context.coordinator.lastLineHighlightCursorOffset {
                    context.coordinator.lastLineHighlightCursorOffset = cursorPosition.offset
                    let highlightColor = UIColor(configuration.theme.currentLineHighlight)
                    containerView.updateCurrentLineHighlight(cursorPosition.offset, highlightColor: highlightColor)
                }
            } else {
                context.coordinator.lastLineHighlightCursorOffset = -1
                containerView.clearCurrentLineHighlight()
            }

            // Skip search highlights during active editing (expensive for many matches)
            if !isUserCurrentlyEditing {
                applySearchHighlights(
                    to: textStorage,
                    matches: searchMatches,
                    currentIndex: currentMatchIndex,
                    text: text,
                    coordinator: context.coordinator
                )
            }
        }

        context.coordinator.isUpdating = false
    }

    /// Applies syntax highlighting only to visible content plus a buffer for smooth scrolling.
    /// For small files (< 5000 chars), highlights the entire document.
    /// For large files, only highlights visible viewport + buffer to maintain 60fps.
    private func applyViewportSyntaxHighlighting(to containerView: KeystoneTextContainerView, text: String, font: UIFont, highlighter: SyntaxHighlighter) {
        let textStorage = containerView.textView.textStorage
        let theme = configuration.theme
        let fullLength = textStorage.length

        // For small files, just highlight everything (fast enough)
        if fullLength < 5000 {
            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: font,
                .foregroundColor: UIColor(theme.text)
            ], range: NSRange(location: 0, length: fullLength))
            highlighter.highlight(textStorage: textStorage, text: text)
            textStorage.endEditing()
            return
        }

        // For large files, only highlight visible portion + buffer
        let textView = containerView.textView
        let visibleRect = textView.bounds
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer

        // Get visible glyph range
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        // Add buffer before and after visible range (2000 chars each side for smooth scrolling)
        let bufferSize = 2000
        let highlightStart = max(0, visibleCharRange.location - bufferSize)
        let highlightEnd = min(fullLength, visibleCharRange.location + visibleCharRange.length + bufferSize)
        let highlightRange = NSRange(location: highlightStart, length: highlightEnd - highlightStart)

        textStorage.beginEditing()

        // Only reset attributes in the range we're highlighting
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: UIColor(theme.text)
        ], range: highlightRange)

        // Apply syntax highlighting only to the visible portion
        // Extract the substring for highlighting
        if let swiftRange = Range(highlightRange, in: text) {
            let substring = String(text[swiftRange])
            highlighter.highlightRange(textStorage: textStorage, text: substring, offset: highlightStart)
        }

        textStorage.endEditing()
    }

    private func applySyntaxHighlighting(to textStorage: NSTextStorage, text: String, font: UIFont, highlighter: SyntaxHighlighter) {
        let theme = configuration.theme
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // Reset to default
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: UIColor(theme.text)
        ], range: fullRange)

        // Apply syntax highlighting using cached highlighter
        highlighter.highlight(textStorage: textStorage, text: text)

        textStorage.endEditing()
    }

    private func applyBracketHighlights(to textStorage: NSTextStorage, match: BracketMatch) {
        let color = UIColor(configuration.theme.matchingBracket)

        if match.openPosition < textStorage.length {
            textStorage.addAttribute(.backgroundColor, value: color, range: NSRange(location: match.openPosition, length: 1))
        }
        if match.closePosition < textStorage.length {
            textStorage.addAttribute(.backgroundColor, value: color, range: NSRange(location: match.closePosition, length: 1))
        }
    }

    private func clearBracketHighlights(from textStorage: NSTextStorage, match: BracketMatch) {
        if match.openPosition < textStorage.length {
            textStorage.removeAttribute(.backgroundColor, range: NSRange(location: match.openPosition, length: 1))
        }
        if match.closePosition < textStorage.length {
            textStorage.removeAttribute(.backgroundColor, range: NSRange(location: match.closePosition, length: 1))
        }
    }

    private func applySearchHighlights(
        to textStorage: NSTextStorage,
        matches: [SearchMatch],
        currentIndex: Int,
        text: String,
        coordinator: Coordinator
    ) {
        let theme = configuration.theme

        // Clear previous search highlights using stored NSRanges
        // This is more reliable than converting SearchMatch.range which uses String.Index
        // that may be invalid after text modifications
        for nsRange in coordinator.appliedSearchHighlightRanges {
            if nsRange.location + nsRange.length <= textStorage.length {
                textStorage.removeAttribute(.backgroundColor, range: nsRange)
            }
        }
        coordinator.appliedSearchHighlightRanges.removeAll()

        // Apply new search highlights and store the NSRanges we applied
        for (index, match) in matches.enumerated() {
            guard let nsRange = match.range.nsRange(in: text),
                  nsRange.location + nsRange.length <= textStorage.length else { continue }

            let color = (index == currentIndex)
                ? UIColor(theme.currentSearchMatch)
                : UIColor(theme.searchMatch)

            textStorage.addAttribute(.backgroundColor, value: color, range: nsRange)
            coordinator.appliedSearchHighlightRanges.append(nsRange)
        }
    }

    // MARK: - Coordinator

    public class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {
        var parent: KeystoneTextView
        var isUpdating = false
        weak var containerView: KeystoneTextContainerView?
        var previousBracketMatch: BracketMatch?

        // Track if initial text has been set - only set text directly on first load
        var hasSetInitialText = false

        // Cached highlighter to avoid recreating TreeSitter parser on every update
        private var cachedHighlighter: SyntaxHighlighter?
        private var cachedLanguage: KeystoneLanguage?
        private var cachedTheme: KeystoneTheme?

        init(_ parent: KeystoneTextView) {
            self.parent = parent
        }

        func getHighlighter(language: KeystoneLanguage, theme: KeystoneTheme) -> SyntaxHighlighter {
            // Only create new highlighter if language or theme changed
            if cachedHighlighter == nil || cachedLanguage != language || cachedTheme != theme {
                cachedHighlighter = SyntaxHighlighter(language: language, theme: theme)
                cachedLanguage = language
                cachedTheme = theme
            }
            return cachedHighlighter!
        }

        // Debounce timer for text sync to avoid triggering SwiftUI on every keystroke
        private var textSyncWorkItem: DispatchWorkItem?
        // Debounce timer for code folding analysis (runs less frequently)
        private var foldingWorkItem: DispatchWorkItem?
        // Track text length to avoid O(n) string comparisons
        private var lastSyncedLength: Int = 0
        // Flag to indicate we're syncing from internal edit (not external change)
        var isSyncingFromInternalEdit = false
        // Flag to indicate user is actively editing - prevents updateUIView from overwriting
        var isUserEditing = false
        /// Stores the actual NSRanges that were applied as search highlights.
        /// Used for clearing highlights reliably when text changes.
        var appliedSearchHighlightRanges: [NSRange] = []
        /// Tracks the last cursor offset used for line highlight to avoid redundant calls
        var lastLineHighlightCursorOffset: Int = -1
        /// Track scroll state to defer updates during scrolling (prevents flickering)
        var isScrolling = false
        var isDragging = false
        var isDecelerating = false

        public func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }

            // IMMEDIATELY mark that user is editing - prevents updateUIView from overwriting
            isUserEditing = true

            // Update line numbers immediately (fast operation - just triggers redisplay)
            containerView?.updateLineNumbersForVisibleArea()

            // Debounce the SwiftUI binding update to avoid triggering expensive updates on every keystroke
            // The actual text editing happens directly in UITextView, this just syncs the binding
            textSyncWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, let textView = self.containerView?.textView else { return }
                // Use textStorage.length for O(1) length check
                let currentLength = textView.textStorage.length
                let selectedRange = textView.selectedRange

                // Only sync if length changed (fast check) OR cursor moved significantly
                let lengthChanged = currentLength != self.lastSyncedLength
                let cursorMoved = selectedRange.location != self.lastSyncedCursorOffset

                if lengthChanged || cursorMoved {
                    // Mark that we're syncing from internal edit so updateUIView can skip work
                    self.isSyncingFromInternalEdit = true

                    if lengthChanged {
                        self.lastSyncedLength = currentLength
                        // Only do O(n) text copy if text actually changed
                        let text = textView.text ?? ""
                        self.parent.text = text

                        // Also sync cursor position using the text we already copied
                        self.lastSyncedCursorOffset = selectedRange.location
                        self.parent.cursorPosition = CursorPosition.from(
                            offset: selectedRange.location,
                            in: text,
                            selectionLength: selectedRange.length
                        )
                    } else if cursorMoved {
                        // Cursor moved but text didn't change - use binding's text
                        self.lastSyncedCursorOffset = selectedRange.location
                        self.parent.cursorPosition = CursorPosition.from(
                            offset: selectedRange.location,
                            in: self.parent.text,
                            selectionLength: selectedRange.length
                        )
                    }

                    // Reset flags after next run loop to ensure updateUIView sees them
                    DispatchQueue.main.async {
                        self.isSyncingFromInternalEdit = false
                        self.isUserEditing = false
                    }
                }
            }
            textSyncWorkItem = workItem
            // Debounce - 250ms to batch keystrokes. O(n) operations happen when this fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)

            // Code folding disabled for performance testing
            // foldingWorkItem?.cancel()
            // let foldingWork = DispatchWorkItem { [weak self] in
            //     guard let self = self, let containerView = self.containerView else { return }
            //     let text = textView.text ?? ""
            //     containerView.foldingManager.analyze(text)
            //     containerView.lineNumberView.setNeedsDisplay()
            // }
            // foldingWorkItem = foldingWork
            // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: foldingWork)
        }

        /// Force sync text immediately (call before operations that need current text)
        func syncTextNow() {
            textSyncWorkItem?.cancel()
            if let textView = containerView?.textView {
                let currentLength = textView.textStorage.length
                if currentLength != lastSyncedLength {
                    lastSyncedLength = currentLength
                    parent.text = textView.text ?? ""
                }
            }
        }

        // Track last synced cursor offset to avoid redundant updates
        private var lastSyncedCursorOffset: Int = 0

        // Flag to prevent feedback loop when programmatically setting cursor position
        var isSettingCursorProgrammatically = false

        // Debounce timer for cursor position updates to prevent rapid SwiftUI re-renders
        private var cursorUpdateWorkItem: DispatchWorkItem?

        public func textViewDidChangeSelection(_ textView: UITextView) {
            // CRITICAL: Skip ALL updates during scrolling or programmatic changes
            guard !isUpdating && !isSettingCursorProgrammatically && !isScrolling else { return }

            let selectedRange = textView.selectedRange

            // Only update if cursor actually moved
            guard selectedRange.location != lastSyncedCursorOffset || selectedRange.length != parent.cursorPosition.selectionLength else { return }

            lastSyncedCursorOffset = selectedRange.location

            // DEBOUNCE cursor position updates to prevent rapid SwiftUI re-render cycles
            // This is critical for preventing the feedback loop that causes flickering
            cursorUpdateWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let currentText = self.containerView?.textView.text ?? ""
                self.parent.cursorPosition = CursorPosition.from(
                    offset: selectedRange.location,
                    in: currentText,
                    selectionLength: selectedRange.length
                )
            }
            cursorUpdateWorkItem = workItem
            // 100ms debounce - enough to batch rapid selection changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
        }

        // Debounce timer for scroll-end syntax highlighting
        private var scrollEndWorkItem: DispatchWorkItem?

        public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isDragging = true
            isScrolling = true
        }

        public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            isDragging = false
            if !decelerate {
                isScrolling = false
            }
        }

        public func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
            isDecelerating = true
        }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // ONLY sync line numbers during scroll - no other state updates
            containerView?.syncLineNumberScroll()
        }

        public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isDecelerating = false
            isScrolling = false
            // Trigger highlighting when scroll deceleration ends
            scrollEndWorkItem?.cancel()
            triggerViewportHighlighting()
        }

        public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            isScrolling = false
            triggerViewportHighlighting()
        }

        private func triggerViewportHighlighting() {
            guard let containerView = containerView else { return }
            let text = containerView.textView.text ?? ""
            let font = containerView.textView.font ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let highlighter = getHighlighter(language: parent.language, theme: parent.configuration.theme)

            // Re-apply viewport-based syntax highlighting
            let textStorage = containerView.textView.textStorage
            let fullLength = textStorage.length

            // Only do viewport highlighting for large files
            guard fullLength >= 5000 else { return }

            let visibleRect = containerView.textView.bounds
            let layoutManager = containerView.textView.layoutManager
            let textContainer = containerView.textView.textContainer

            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

            let bufferSize = 2000
            let highlightStart = max(0, visibleCharRange.location - bufferSize)
            let highlightEnd = min(fullLength, visibleCharRange.location + visibleCharRange.length + bufferSize)
            let highlightRange = NSRange(location: highlightStart, length: highlightEnd - highlightStart)

            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: font,
                .foregroundColor: UIColor(parent.configuration.theme.text)
            ], range: highlightRange)

            if let swiftRange = Range(highlightRange, in: text) {
                let substring = String(text[swiftRange])
                highlighter.highlightRange(textStorage: textStorage, text: substring, offset: highlightStart)
            }
            textStorage.endEditing()
        }

        // Handle character pair insertion
        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let config = parent.configuration
            let nsText = textView.textStorage.string as NSString

            // Handle backspace - delete pair if cursor is between paired brackets
            if text.isEmpty && range.length == 1 && range.location > 0 {
                if config.shouldDeletePair(in: nsText, at: range.location) {
                    // Delete both characters of the pair
                    let extendedRange = NSRange(location: range.location - 1, length: 2)
                    if let textRange = textView.textRange(from: extendedRange) {
                        textView.replace(textRange, withText: "")
                        return false
                    }
                }
                return true
            }

            // Only handle single character insertions
            guard text.count == 1, let char = text.first else {
                return true
            }

            // Check if we should skip over a closing character
            if config.shouldSkipClosingPair(for: char, in: nsText, at: range.location) {
                // Move cursor past the existing closing character instead of inserting
                let newPosition = range.location + 1
                textView.selectedRange = NSRange(location: newPosition, length: 0)
                return false
            }

            // Check if we should auto-insert a closing pair
            if let closingChar = config.shouldAutoInsertPair(for: char, in: nsText, at: range.location) {
                // Insert both the typed character and its pair
                let pairText = String(char) + String(closingChar)
                if let textRange = textView.textRange(from: range) {
                    textView.replace(textRange, withText: pairText)
                    // Position cursor between the pair
                    textView.selectedRange = NSRange(location: range.location + 1, length: 0)
                    return false
                }
            }

            return true
        }
    }
}

/// Container view that holds text view and line number gutter
public class KeystoneTextContainerView: UIView {
    let textView: UITextView
    let lineNumberView: LineNumberGutterView
    var coordinator: KeystoneTextView.Coordinator?
    private var configuration: KeystoneConfiguration

    private let gutterWidth: CGFloat = 56 // Extra space for fold indicators

    // Custom layout manager for invisible characters
    private let invisibleLayoutManager = InvisibleCharacterLayoutManager()

    // Code folding
    public let foldingManager = CodeFoldingManager()
    public var onFoldToggle: ((FoldableRegion) -> Void)?

    // Active layout constraints (for updating when showLineNumbers changes)
    private var activeConstraints: [NSLayoutConstraint] = []

    // MARK: - Undo/Redo

    /// Whether undo is available.
    public var canUndo: Bool {
        textView.undoManager?.canUndo ?? false
    }

    /// Whether redo is available.
    public var canRedo: Bool {
        textView.undoManager?.canRedo ?? false
    }

    /// Performs an undo operation.
    public func undo() {
        textView.undoManager?.undo()
    }

    /// Performs a redo operation.
    public func redo() {
        textView.undoManager?.redo()
    }

    /// Replaces text at the given range with new text, properly registering with undo manager.
    /// - Parameters:
    ///   - range: The range to replace (in terms of character offsets).
    ///   - newText: The replacement text.
    public func replaceText(in range: NSRange, with newText: String) {
        // Use UITextView's replace method to properly register with undo
        guard let textRange = textView.textRange(from: range) else { return }
        textView.replace(textRange, withText: newText)
    }

    init(configuration: KeystoneConfiguration) {
        self.configuration = configuration

        // Create text view with custom layout manager for invisible characters
        let textStorage = NSTextStorage()
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        invisibleLayoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(invisibleLayoutManager)

        self.textView = UITextView(frame: .zero, textContainer: textContainer)
        self.lineNumberView = LineNumberGutterView()

        super.init(frame: .zero)

        setupTextView()
        setupLineNumberView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTextView() {
        textView.font = .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        textView.textColor = UIColor(configuration.theme.text)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive

        addSubview(textView)
    }

    private func setupLineNumberView() {
        // Use dynamic color that resolves at draw time - don't use UIColor(Color) as it creates a static snapshot
        lineNumberView.backgroundColor = .clear // Avoid UIView background interfering
        lineNumberView.foldingManager = foldingManager
        lineNumberView.onFoldToggle = { [weak self] region in
            self?.handleFoldToggle(region)
        }
        addSubview(lineNumberView)
    }

    private func handleFoldToggle(_ region: FoldableRegion) {
        foldingManager.toggleFold(region)
        onFoldToggle?(region)
        lineNumberView.setNeedsDisplay()
        textView.setNeedsDisplay()
    }

    private func setupLayout() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        updateLayoutConstraints()
    }

    private func updateLayoutConstraints() {
        // Deactivate old constraints
        NSLayoutConstraint.deactivate(activeConstraints)
        activeConstraints.removeAll()

        if configuration.showLineNumbers {
            activeConstraints = [
                lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor),
                lineNumberView.topAnchor.constraint(equalTo: topAnchor),
                lineNumberView.bottomAnchor.constraint(equalTo: bottomAnchor),
                lineNumberView.widthAnchor.constraint(equalToConstant: gutterWidth),

                textView.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        } else {
            activeConstraints = [
                textView.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(activeConstraints)
    }

    // Track last applied configuration to avoid redundant updates
    private var lastAppliedFontSize: CGFloat = 0
    private var lastAppliedShowLineNumbers: Bool = true
    private var lastAppliedLineWrapping: Bool = true
    private var lastAppliedShowInvisibles: Bool = false

    /// Only update configuration if something actually changed
    /// Returns true if syntax highlighting needs to be reapplied
    @discardableResult
    func updateConfigurationIfNeeded(_ config: KeystoneConfiguration) -> Bool {
        var needsUpdate = false
        var needsRehighlight = false

        if lastAppliedFontSize != config.fontSize { needsUpdate = true; needsRehighlight = true }
        if lastAppliedShowLineNumbers != config.showLineNumbers { needsUpdate = true; needsRehighlight = true }
        if lastAppliedLineWrapping != config.lineWrapping { needsUpdate = true; needsRehighlight = true }
        if lastAppliedShowInvisibles != config.showInvisibleCharacters { needsUpdate = true; needsRehighlight = true }

        if needsUpdate {
            updateConfiguration(config)
            lastAppliedFontSize = config.fontSize
            lastAppliedShowLineNumbers = config.showLineNumbers
            lastAppliedLineWrapping = config.lineWrapping
            lastAppliedShowInvisibles = config.showInvisibleCharacters
        }

        return needsRehighlight
    }

    func updateConfiguration(_ config: KeystoneConfiguration) {
        // Compare against lastApplied values since config might be the same object reference
        let showLineNumbersChanged = lastAppliedShowLineNumbers != config.showLineNumbers
        self.configuration = config

        // Update layout constraints if line numbers visibility changed
        if showLineNumbersChanged {
            updateLayoutConstraints()
            setNeedsLayout()
            layoutIfNeeded()
        }

        lineNumberView.isHidden = !config.showLineNumbers
        // Don't set gutterBackgroundColor from theme - it uses a static snapshot.
        // The dynamic default in LineNumberGutterView handles light/dark mode properly.
        lineNumberView.textColor = UIColor(config.theme.lineNumber)
        lineNumberView.currentLineColor = UIColor.systemBlue
        lineNumberView.fontSize = config.fontSize
        lineNumberView.lineHeight = config.fontSize * config.lineHeightMultiplier

        // Update text color for theme changes
        textView.textColor = UIColor(config.theme.text)

        // Update invisible character settings - invalidate layout to force redraw
        let invisiblesChanged = invisibleLayoutManager.showInvisibles != config.showInvisibleCharacters
        invisibleLayoutManager.showInvisibles = config.showInvisibleCharacters
        invisibleLayoutManager.invisibleColor = UIColor(config.theme.invisibleCharacter)
        if invisiblesChanged {
            // Force complete redraw by invalidating all glyphs
            let fullRange = NSRange(location: 0, length: textView.textStorage.length)
            invisibleLayoutManager.invalidateDisplay(forCharacterRange: fullRange)
            textView.setNeedsDisplay()
        }

        // Update text wrapping and horizontal scrolling
        if config.lineWrapping {
            textView.textContainer.lineBreakMode = .byWordWrapping
            textView.textContainer.widthTracksTextView = true
            textView.isScrollEnabled = true
            textView.showsHorizontalScrollIndicator = false
        } else {
            textView.textContainer.lineBreakMode = .byClipping
            textView.textContainer.widthTracksTextView = false
            // Allow horizontal scrolling by making text container very wide
            textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isScrollEnabled = true
            textView.showsHorizontalScrollIndicator = true
            textView.contentSize = CGSize(
                width: max(textView.contentSize.width, textView.bounds.width * 2),
                height: textView.contentSize.height
            )
        }

        setNeedsLayout()
    }

    // Cached line data to avoid full recalculation on every keystroke
    private var cachedLineData: [(lineNumber: Int, yPosition: CGFloat, height: CGFloat)] = []
    private var cachedTextLength: Int = -1

    func updateLineNumbers() {
        guard configuration.showLineNumbers else { return }

        let text = textView.text ?? ""
        let layoutManager = textView.layoutManager

        var lineData: [(lineNumber: Int, yPosition: CGFloat, height: CGFloat)] = []
        var lineNumber = 1
        var glyphIndex = 0
        let numberOfGlyphs = layoutManager.numberOfGlyphs

        while glyphIndex < numberOfGlyphs {
            var lineRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)

            // Convert to our coordinate system (accounting for text container inset)
            let yPosition = lineRect.origin.y + textView.textContainerInset.top

            // Check if this glyph range starts a new logical line
            let charRange = layoutManager.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil)

            // Only add line number for the first fragment of each logical line
            let isFirstFragmentOfLine: Bool
            if charRange.location == 0 {
                isFirstFragmentOfLine = true
            } else {
                let prevChar = (text as NSString).substring(with: NSRange(location: charRange.location - 1, length: 1))
                isFirstFragmentOfLine = prevChar == "\n"
            }

            if isFirstFragmentOfLine {
                lineData.append((lineNumber: lineNumber, yPosition: yPosition, height: lineRect.height))
                lineNumber += 1
            }

            glyphIndex = NSMaxRange(lineRange)
        }

        // Handle empty text
        if text.isEmpty {
            lineData.append((lineNumber: 1, yPosition: textView.textContainerInset.top, height: configuration.fontSize * configuration.lineHeightMultiplier))
        }

        // Cache the line data
        cachedLineData = lineData
        cachedTextLength = text.count

        lineNumberView.lineData = lineData
        lineNumberView.setNeedsDisplay()
    }

    /// Fast update for visible area only - used during typing to avoid full recalculation
    func updateLineNumbersForVisibleArea() {
        guard configuration.showLineNumbers else { return }
        // During typing, just trigger a redisplay - don't recalculate anything
        // The full recalculation will happen after typing stops (via debounced text sync)
        lineNumberView.setNeedsDisplay()
    }

    /// Tracks the previous line number to avoid redundant gutter updates
    private var previousLineNumber: Int = 0

    func updateCurrentLineHighlight(_ cursorPosition: Int, highlightColor: UIColor?) {
        let text = textView.text ?? ""
        var currentLine = 1

        // Find current line number
        for (index, char) in text.enumerated() {
            if index >= cursorPosition { break }
            if char == "\n" {
                currentLine += 1
            }
        }

        // Early exit if line hasn't changed
        if currentLine == previousLineNumber {
            return
        }

        // Update line number gutter only - NO text view background modification
        // Modifying textStorage.backgroundColor was causing layout thrashing and cursor flickering
        lineNumberView.currentLine = currentLine
        lineNumberView.setNeedsDisplay()
        previousLineNumber = currentLine
    }

    /// Clears current line highlight
    func clearCurrentLineHighlight() {
        // Only clear gutter highlight - we no longer modify text view background
        lineNumberView.currentLine = 0
        lineNumberView.setNeedsDisplay()
        previousLineNumber = 0
    }

    func syncLineNumberScroll() {
        let newOffset = textView.contentOffset.y
        if lineNumberView.contentOffset != newOffset {
            lineNumberView.contentOffset = newOffset
            // Force immediate redraw for smooth scrolling
            lineNumberView.setNeedsDisplay()
            lineNumberView.layer.displayIfNeeded()
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        updateLineNumbers()
        syncLineNumberScroll()
    }
}

/// Custom view for drawing line numbers with code folding indicators
class LineNumberGutterView: UIView {
    var lineData: [(lineNumber: Int, yPosition: CGFloat, height: CGFloat)] = []
    var currentLine: Int = 1
    var contentOffset: CGFloat = 0
    var fontSize: CGFloat = 14
    var lineHeight: CGFloat = 17
    var textColor: UIColor = .secondaryLabel
    var currentLineColor: UIColor = .systemBlue
    // Use a dynamic color that adapts to light/dark mode
    var gutterBackgroundColor: UIColor = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 0.16, alpha: 1.0)
            : UIColor(white: 0.96, alpha: 1.0)
    }

    // Code folding support
    var foldingManager: CodeFoldingManager?
    var onFoldToggle: ((FoldableRegion) -> Void)?
    private let foldIndicatorWidth: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true // Opaque for better performance
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        // Draw background explicitly to ensure proper dark mode support
        gutterBackgroundColor.setFill()
        UIRectFill(bounds)
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        var yOffset: CGFloat = 0

        for data in lineData {
            // Check if this line is hidden due to folding
            if let manager = foldingManager, manager.isLineHidden(data.lineNumber) {
                continue
            }

            let yPosition = data.yPosition - contentOffset - yOffset

            // Skip if outside visible rect
            if yPosition + data.height < 0 || yPosition > bounds.height { continue }

            let isCurrentLine = data.lineNumber == currentLine
            let color = isCurrentLine ? currentLineColor : textColor

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]

            // Draw line number (leave space for fold indicator)
            let numberString = "\(data.lineNumber)"
            let textRect = CGRect(x: 0, y: yPosition, width: bounds.width - foldIndicatorWidth - 4, height: data.height)
            numberString.draw(in: textRect, withAttributes: attributes)

            // Draw fold indicator if there's a foldable region at this line
            if let manager = foldingManager, let region = manager.region(atLine: data.lineNumber) {
                drawFoldIndicator(
                    at: CGPoint(x: bounds.width - foldIndicatorWidth, y: yPosition),
                    height: data.height,
                    isFolded: manager.isFolded(region)
                )

                // If this region is folded, add placeholder text
                if manager.isFolded(region) {
                    drawFoldedPlaceholder(at: CGPoint(x: 0, y: yPosition), height: data.height, lineCount: region.lineCount - 1)
                }
            }
        }
    }

    private func drawFoldedPlaceholder(at point: CGPoint, height: CGFloat, lineCount: Int) {
        let placeholderFont = UIFont.monospacedSystemFont(ofSize: fontSize * 0.8, weight: .regular)
        let placeholderText = "... \(lineCount) lines"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: placeholderFont,
            .foregroundColor: textColor.withAlphaComponent(0.6)
        ]
        let rect = CGRect(x: 4, y: point.y + height + 2, width: bounds.width - 8, height: height)
        placeholderText.draw(in: rect, withAttributes: attributes)
    }

    private func drawFoldIndicator(at point: CGPoint, height: CGFloat, isFolded: Bool) {
        let size: CGFloat = min(height - 4, 10)
        let rect = CGRect(
            x: point.x + (foldIndicatorWidth - size) / 2,
            y: point.y + (height - size) / 2,
            width: size,
            height: size
        )

        let path = UIBezierPath(roundedRect: rect, cornerRadius: 2)

        // Background
        UIColor.secondarySystemBackground.setFill()
        path.fill()

        // Border
        textColor.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Draw triangle or minus sign
        let symbolPath = UIBezierPath()
        let inset: CGFloat = 2.5
        let centerX = rect.midX
        let centerY = rect.midY

        if isFolded {
            // Right-pointing triangle (collapsed)
            symbolPath.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            symbolPath.addLine(to: CGPoint(x: rect.maxX - inset, y: centerY))
            symbolPath.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
            symbolPath.close()
            textColor.setFill()
            symbolPath.fill()
        } else {
            // Down-pointing triangle (expanded)
            symbolPath.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            symbolPath.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
            symbolPath.addLine(to: CGPoint(x: centerX, y: rect.maxY - inset))
            symbolPath.close()
            textColor.setFill()
            symbolPath.fill()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let manager = foldingManager else { return }

        let location = touch.location(in: self)

        // Check if touch is in the fold indicator area
        if location.x >= bounds.width - foldIndicatorWidth - 4 {
            // Find which line was tapped
            for data in lineData {
                let yPosition = data.yPosition - contentOffset
                if location.y >= yPosition && location.y < yPosition + data.height {
                    if let region = manager.region(atLine: data.lineNumber) {
                        onFoldToggle?(region)
                    }
                    break
                }
            }
        }
    }
}

#elseif os(macOS)
import AppKit

// MARK: - Range Extension (macOS)

extension Range where Bound == String.Index {
    /// Converts a Range<String.Index> to an NSRange within the given string.
    func nsRange(in string: String) -> NSRange? {
        guard let lowerBound = lowerBound.samePosition(in: string.utf16),
              let upperBound = upperBound.samePosition(in: string.utf16) else { return nil }
        let location = string.utf16.distance(from: string.utf16.startIndex, to: lowerBound)
        let length = string.utf16.distance(from: lowerBound, to: upperBound)
        return NSRange(location: location, length: length)
    }
}

// MARK: - Invisible Character Layout Manager (macOS)

/// Custom layout manager that draws visible symbols for invisible characters.
class InvisibleCharacterLayoutManagerMac: NSLayoutManager {
    /// Color for invisible character symbols.
    var invisibleColor: NSColor = .tertiaryLabelColor

    /// Whether to show invisible characters.
    var showInvisibles: Bool = false

    /// Symbols for invisible characters.
    private let tabSymbol = "→"
    private let spaceSymbol = "·"
    private let newlineSymbol = "¶"

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Draw the regular glyphs first
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        // Draw invisible character symbols if enabled
        guard showInvisibles, let textStorage = textStorage else { return }

        let text = textStorage.string as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let symbolAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: invisibleColor
        ]

        enumerateLineFragments(forGlyphRange: glyphsToShow) { [weak self] (rect, usedRect, container, lineGlyphRange, _) in
            guard let self = self else { return }

            for glyphIndex in lineGlyphRange.location..<(lineGlyphRange.location + lineGlyphRange.length) {
                let charIndex = self.characterIndexForGlyph(at: glyphIndex)
                guard charIndex < text.length else { continue }

                let char = text.character(at: charIndex)
                var symbol: String?

                switch char {
                case 0x09: // Tab
                    symbol = self.tabSymbol
                case 0x20: // Space
                    symbol = self.spaceSymbol
                case 0x0A, 0x0D: // Newline / Carriage return
                    symbol = self.newlineSymbol
                default:
                    break
                }

                if let symbol = symbol {
                    var glyphPoint = self.location(forGlyphAt: glyphIndex)
                    glyphPoint.x += origin.x + usedRect.origin.x
                    glyphPoint.y = origin.y + rect.origin.y

                    // Adjust vertical centering
                    let symbolSize = (symbol as NSString).size(withAttributes: symbolAttributes)
                    glyphPoint.y += (rect.height - symbolSize.height) / 2

                    (symbol as NSString).draw(at: glyphPoint, withAttributes: symbolAttributes)
                }
            }
        }
    }
}

/// The SwiftUI wrapper for NSTextView on macOS.
public struct KeystoneTextView: NSViewRepresentable {
    @Binding var text: String
    let language: KeystoneLanguage
    @ObservedObject var configuration: KeystoneConfiguration
    @Binding var cursorPosition: CursorPosition
    @Binding var scrollOffset: CGFloat
    @Binding var matchingBracket: BracketMatch?
    /// When set to true, scrolls to make cursor visible, then resets to false
    @Binding var scrollToCursor: Bool
    var searchMatches: [SearchMatch]
    var currentMatchIndex: Int
    var undoController: UndoController?

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> KeystoneTextContainerViewMac {
        let containerView = KeystoneTextContainerViewMac(configuration: configuration)
        containerView.textView.delegate = context.coordinator
        context.coordinator.containerView = containerView

        // Connect the undo controller to the container view's undo functionality
        if let undoController = undoController {
            let coordinator = context.coordinator
            undoController.undoAction = { [weak containerView, weak coordinator] in
                containerView?.undo()
                // Sync text immediately after undo to update SwiftUI binding
                coordinator?.syncTextNow()
            }
            undoController.redoAction = { [weak containerView, weak coordinator] in
                containerView?.redo()
                // Sync text immediately after redo to update SwiftUI binding
                coordinator?.syncTextNow()
            }
            undoController.checkUndoState = { [weak containerView] in
                (canUndo: containerView?.canUndo ?? false,
                 canRedo: containerView?.canRedo ?? false)
            }
            // Replace text through NSTextView.insertText so it properly registers with undo manager
            undoController.replaceTextAction = { [weak containerView] range, replacementText in
                guard let containerView = containerView,
                      let textStorage = containerView.textView.textStorage else { return nil }
                guard range.location + range.length <= textStorage.length else { return nil }

                // Use NSTextView.insertText which properly registers with undo manager
                containerView.textView.insertText(replacementText, replacementRange: range)

                // Return the new text
                return containerView.textView.string
            }
            // Undo grouping for batching multiple changes
            undoController.beginUndoGroupingAction = { [weak containerView] in
                containerView?.textView.undoManager?.beginUndoGrouping()
            }
            undoController.endUndoGroupingAction = { [weak containerView] in
                containerView?.textView.undoManager?.endUndoGrouping()
            }
            undoController.startUpdating()
        }

        // Code folding disabled for performance testing
        // DispatchQueue.main.async {
        //     containerView.foldingManager.analyze(self.text)
        //     containerView.lineNumberView.needsDisplay = true
        // }

        return containerView
    }

    public func updateNSView(_ containerView: KeystoneTextContainerViewMac, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true

        // Check if config changes need rehighlighting
        let configNeedsRehighlight = containerView.updateConfiguration(configuration)

        let font = NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)

        // Track if we need to re-highlight
        var needsHighlight = configNeedsRehighlight

        // Only update if text actually changed
        if containerView.textView.string != text {
            let selectedRange = containerView.textView.selectedRange()
            containerView.textView.string = text
            needsHighlight = true

            // Restore selection
            let newLocation = min(selectedRange.location, text.count)
            containerView.textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        }

        // Update font if needed
        if containerView.textView.font?.pointSize != configuration.fontSize {
            containerView.textView.font = font
            needsHighlight = true
        }

        // Only re-highlight when necessary - use viewport-based highlighting
        if needsHighlight, let textStorage = containerView.textView.textStorage {
            let highlighter = context.coordinator.getHighlighter(language: language, theme: configuration.theme)
            applyViewportSyntaxHighlightingMac(to: containerView, text: text, font: font, highlighter: highlighter)
        }

        // Clear previous bracket highlights
        if let prevMatch = context.coordinator.previousBracketMatch,
           let textStorage = containerView.textView.textStorage {
            clearBracketHighlights(from: textStorage, match: prevMatch)
        }

        // Apply highlights for matching brackets
        if let match = matchingBracket, let textStorage = containerView.textView.textStorage {
            applyBracketHighlights(to: textStorage, match: match)
            context.coordinator.previousBracketMatch = match
        } else {
            context.coordinator.previousBracketMatch = nil
        }

        // Update current line highlight - only if cursor position changed
        if configuration.highlightCurrentLine {
            if cursorPosition.offset != context.coordinator.lastLineHighlightCursorOffset {
                context.coordinator.lastLineHighlightCursorOffset = cursorPosition.offset
                let highlightColor = NSColor(configuration.theme.currentLineHighlight)
                containerView.updateCurrentLineHighlight(cursorPosition.offset, highlightColor: highlightColor)
            }
        } else {
            context.coordinator.lastLineHighlightCursorOffset = -1
            containerView.clearCurrentLineHighlight()
        }

        // Apply search match highlights
        if let textStorage = containerView.textView.textStorage {
            applySearchHighlights(
                to: textStorage,
                matches: searchMatches,
                currentIndex: currentMatchIndex,
                text: text,
                coordinator: context.coordinator
            )
        }

        // Handle cursor position changes for search navigation or tail follow
        // When scrollToCursor is explicitly true, ALWAYS update cursor and scroll
        //
        // IMPORTANT: Capture scrollToCursor value FIRST and reset it IMMEDIATELY before doing any work.
        // This prevents SwiftUI update loops caused by async state resets.
        let shouldScrollToCursor = scrollToCursor
        if shouldScrollToCursor {
            // Reset IMMEDIATELY to prevent update loop - do this before any other work
            scrollToCursor = false
        }

        // Only update cursor position when explicitly requested (search, go-to-line, tail follow)
        // The text view IS the source of truth for cursor position - we never sync FROM binding TO text view
        // This prevents feedback loops that cause flickering
        if shouldScrollToCursor {
            let newLocation = min(cursorPosition.offset, text.count)
            let newLength = min(cursorPosition.selectionLength, text.count - newLocation)
            let newRange = NSRange(location: newLocation, length: newLength)
            containerView.textView.setSelectedRange(newRange)

            // Scroll instantly without animation
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                containerView.textView.scrollRangeToVisible(newRange)
            }
        }
        // NOTE: Removed automatic cursor sync from binding to text view
        // This was causing feedback loops that led to flickering

        containerView.updateLineNumbers()

        context.coordinator.isUpdating = false
    }

    /// Applies syntax highlighting only to visible content plus a buffer for smooth scrolling.
    /// For small files (< 5000 chars), highlights the entire document.
    private func applyViewportSyntaxHighlightingMac(to containerView: KeystoneTextContainerViewMac, text: String, font: NSFont, highlighter: SyntaxHighlighter) {
        guard let textStorage = containerView.textView.textStorage else { return }
        let theme = configuration.theme
        let fullLength = textStorage.length

        // For small files, just highlight everything (fast enough)
        if fullLength < 5000 {
            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: font,
                .foregroundColor: NSColor(theme.text)
            ], range: NSRange(location: 0, length: fullLength))
            highlighter.highlight(textStorage: textStorage, text: text)
            textStorage.endEditing()
            return
        }

        // For large files, only highlight visible portion + buffer
        let textView = containerView.textView
        let visibleRect = containerView.scrollView.documentVisibleRect
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Get visible glyph range
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        // Add buffer before and after visible range (2000 chars each side for smooth scrolling)
        let bufferSize = 2000
        let highlightStart = max(0, visibleCharRange.location - bufferSize)
        let highlightEnd = min(fullLength, visibleCharRange.location + visibleCharRange.length + bufferSize)
        let highlightRange = NSRange(location: highlightStart, length: highlightEnd - highlightStart)

        textStorage.beginEditing()

        // Only reset attributes in the range we're highlighting
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: NSColor(theme.text)
        ], range: highlightRange)

        // Apply syntax highlighting only to the visible portion
        if let swiftRange = Range(highlightRange, in: text) {
            let substring = String(text[swiftRange])
            highlighter.highlightRange(textStorage: textStorage, text: substring, offset: highlightStart)
        }

        textStorage.endEditing()
    }

    private func applySyntaxHighlighting(to textStorage: NSTextStorage, text: String, font: NSFont, highlighter: SyntaxHighlighter) {
        let theme = configuration.theme
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // Reset to default
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: NSColor(theme.text)
        ], range: fullRange)

        // Apply syntax highlighting using cached highlighter
        highlighter.highlight(textStorage: textStorage, text: text)

        textStorage.endEditing()
    }

    private func applyBracketHighlights(to textStorage: NSTextStorage, match: BracketMatch) {
        let color = NSColor(configuration.theme.matchingBracket)

        if match.openPosition < textStorage.length {
            textStorage.addAttribute(.backgroundColor, value: color, range: NSRange(location: match.openPosition, length: 1))
        }
        if match.closePosition < textStorage.length {
            textStorage.addAttribute(.backgroundColor, value: color, range: NSRange(location: match.closePosition, length: 1))
        }
    }

    private func clearBracketHighlights(from textStorage: NSTextStorage, match: BracketMatch) {
        if match.openPosition < textStorage.length {
            textStorage.removeAttribute(.backgroundColor, range: NSRange(location: match.openPosition, length: 1))
        }
        if match.closePosition < textStorage.length {
            textStorage.removeAttribute(.backgroundColor, range: NSRange(location: match.closePosition, length: 1))
        }
    }

    private func applySearchHighlights(
        to textStorage: NSTextStorage,
        matches: [SearchMatch],
        currentIndex: Int,
        text: String,
        coordinator: Coordinator
    ) {
        let theme = configuration.theme

        // Clear previous search highlights using stored NSRanges
        // This is more reliable than converting SearchMatch.range which uses String.Index
        // that may be invalid after text modifications
        for nsRange in coordinator.appliedSearchHighlightRanges {
            if nsRange.location + nsRange.length <= textStorage.length {
                textStorage.removeAttribute(.backgroundColor, range: nsRange)
            }
        }
        coordinator.appliedSearchHighlightRanges.removeAll()

        // Apply new search highlights and store the NSRanges we applied
        for (index, match) in matches.enumerated() {
            guard let nsRange = match.range.nsRange(in: text),
                  nsRange.location + nsRange.length <= textStorage.length else { continue }

            let color = (index == currentIndex)
                ? NSColor(theme.currentSearchMatch)
                : NSColor(theme.searchMatch)

            textStorage.addAttribute(.backgroundColor, value: color, range: nsRange)
            coordinator.appliedSearchHighlightRanges.append(nsRange)
        }
    }

    // MARK: - Coordinator

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KeystoneTextView
        var isUpdating = false
        weak var containerView: KeystoneTextContainerViewMac?
        var previousBracketMatch: BracketMatch?
        /// Stores the actual NSRanges that were applied as search highlights.
        /// Used for clearing highlights reliably when text changes.
        var appliedSearchHighlightRanges: [NSRange] = []
        /// Tracks the last cursor offset used for line highlight to avoid redundant calls
        var lastLineHighlightCursorOffset: Int = -1

        // Cached highlighter to avoid recreating TreeSitter parser on every update
        private var cachedHighlighter: SyntaxHighlighter?
        private var cachedLanguage: KeystoneLanguage?
        private var cachedTheme: KeystoneTheme?

        init(_ parent: KeystoneTextView) {
            self.parent = parent
        }

        func getHighlighter(language: KeystoneLanguage, theme: KeystoneTheme) -> SyntaxHighlighter {
            // Only create new highlighter if language or theme changed
            if cachedHighlighter == nil || cachedLanguage != language || cachedTheme != theme {
                cachedHighlighter = SyntaxHighlighter(language: language, theme: theme)
                cachedLanguage = language
                cachedTheme = theme
            }
            return cachedHighlighter!
        }

        // Debounce timer for code folding analysis (runs less frequently)
        private var foldingWorkItem: DispatchWorkItem?

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// Force sync text immediately (call before operations that need current text)
        func syncTextNow() {
            if let textView = containerView?.textView {
                parent.text = textView.string
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }

            parent.text = textView.string
            containerView?.updateLineNumbers()

            // Code folding disabled for performance testing
            // foldingWorkItem?.cancel()
            // let foldingWork = DispatchWorkItem { [weak self] in
            //     guard let self = self, let containerView = self.containerView else { return }
            //     containerView.foldingManager.analyze(textView.string)
            //     containerView.lineNumberView.needsDisplay = true
            // }
            // foldingWorkItem = foldingWork
            // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: foldingWork)
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }

            let text = textView.string
            let selectedRange = textView.selectedRange()

            parent.cursorPosition = CursorPosition.from(
                offset: selectedRange.location,
                in: text,
                selectionLength: selectedRange.length
            )
            // NOTE: Line highlight is now handled by updateNSView with caching
            // Removed duplicate call here to prevent double updates
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            parent.scrollOffset = clipView.bounds.origin.y
            containerView?.syncLineNumberScroll()
        }

        // Handle character pair insertion
        public func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard let text = text, let textStorage = textView.textStorage else {
                return true
            }

            let config = parent.configuration
            let nsText = textStorage.string as NSString

            // Handle backspace - delete pair if cursor is between paired brackets
            if text.isEmpty && range.length == 1 && range.location > 0 {
                if config.shouldDeletePair(in: nsText, at: range.location) {
                    // Delete both characters of the pair
                    let extendedRange = NSRange(location: range.location - 1, length: 2)
                    textView.insertText("", replacementRange: extendedRange)
                    return false
                }
                return true
            }

            // Only handle single character insertions
            guard text.count == 1, let char = text.first else {
                return true
            }

            // Check if we should skip over a closing character
            if config.shouldSkipClosingPair(for: char, in: nsText, at: range.location) {
                // Move cursor past the existing closing character instead of inserting
                let newPosition = range.location + 1
                textView.setSelectedRange(NSRange(location: newPosition, length: 0))
                return false
            }

            // Check if we should auto-insert a closing pair
            if let closingChar = config.shouldAutoInsertPair(for: char, in: nsText, at: range.location) {
                // Insert both the typed character and its pair
                let pairText = String(char) + String(closingChar)
                textView.insertText(pairText, replacementRange: range)
                // Position cursor between the pair
                textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                return false
            }

            return true
        }
    }
}

/// Container view that holds text view and line number gutter for macOS
public class KeystoneTextContainerViewMac: NSView {
    let scrollView: NSScrollView
    let textView: NSTextView
    let lineNumberView: LineNumberGutterViewMac
    private var configuration: KeystoneConfiguration

    private let gutterWidth: CGFloat = 56 // Extra space for fold indicators

    // Custom layout manager for invisible characters
    private let invisibleLayoutManager = InvisibleCharacterLayoutManagerMac()

    // Code folding
    public let foldingManager = CodeFoldingManager()
    public var onFoldToggle: ((FoldableRegion) -> Void)?

    // Active layout constraints (for updating when showLineNumbers changes)
    private var activeConstraints: [NSLayoutConstraint] = []

    // Track last applied configuration to detect changes (config object might be same reference)
    private var lastAppliedShowLineNumbers: Bool = true
    private var lastAppliedFontSize: CGFloat = 0
    private var lastAppliedLineWrapping: Bool = true
    private var lastAppliedShowInvisibles: Bool = false

    // MARK: - Undo/Redo

    /// Whether undo is available.
    public var canUndo: Bool {
        textView.undoManager?.canUndo ?? false
    }

    /// Whether redo is available.
    public var canRedo: Bool {
        textView.undoManager?.canRedo ?? false
    }

    /// Performs an undo operation.
    public func undo() {
        textView.undoManager?.undo()
    }

    /// Performs a redo operation.
    public func redo() {
        textView.undoManager?.redo()
    }

    /// Replaces text at the given range with new text, properly registering with undo manager.
    /// - Parameters:
    ///   - range: The range to replace (in terms of character offsets).
    ///   - newText: The replacement text.
    public func replaceText(in range: NSRange, with newText: String) {
        // Use NSTextView's insertText to properly register with undo
        textView.insertText(newText, replacementRange: range)
    }

    init(configuration: KeystoneConfiguration) {
        self.configuration = configuration
        self.scrollView = NSScrollView()
        self.lineNumberView = LineNumberGutterViewMac()

        // Create text view with custom layout manager for invisible characters
        let textStorage = NSTextStorage()
        let textContainer = NSTextContainer(containerSize: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        invisibleLayoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(invisibleLayoutManager)

        self.textView = NSTextView(frame: .zero, textContainer: textContainer)

        super.init(frame: .zero)

        setupTextView()
        setupLineNumberView()
        setupLayout()
        setupScrollObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTextView() {
        textView.font = .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        textView.textColor = NSColor(configuration.theme.text)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !configuration.lineWrapping

        if configuration.lineWrapping {
            textView.textContainer?.widthTracksTextView = true
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !configuration.lineWrapping
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        addSubview(scrollView)
    }

    private func setupLineNumberView() {
        lineNumberView.wantsLayer = true
        lineNumberView.layer?.backgroundColor = NSColor.clear.cgColor // Avoid layer background interfering
        // Use dynamic color that resolves at draw time - don't use NSColor(Color) as it creates a static snapshot
        lineNumberView.foldingManager = foldingManager
        lineNumberView.onFoldToggle = { [weak self] region in
            self?.handleFoldToggle(region)
        }
        addSubview(lineNumberView)
    }

    private func handleFoldToggle(_ region: FoldableRegion) {
        foldingManager.toggleFold(region)
        onFoldToggle?(region)
        lineNumberView.needsDisplay = true
        textView.needsDisplay = true
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        updateLayoutConstraints()
    }

    private func updateLayoutConstraints() {
        // Deactivate old constraints
        NSLayoutConstraint.deactivate(activeConstraints)
        activeConstraints.removeAll()

        if configuration.showLineNumbers {
            activeConstraints = [
                lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor),
                lineNumberView.topAnchor.constraint(equalTo: topAnchor),
                lineNumberView.bottomAnchor.constraint(equalTo: bottomAnchor),
                lineNumberView.widthAnchor.constraint(equalToConstant: gutterWidth),

                scrollView.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: topAnchor),
                scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        } else {
            activeConstraints = [
                scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
                scrollView.topAnchor.constraint(equalTo: topAnchor),
                scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(activeConstraints)
    }

    private func setupScrollObserver() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        syncLineNumberScroll()
    }

    /// Updates configuration and returns true if syntax highlighting needs to be reapplied
    @discardableResult
    func updateConfiguration(_ config: KeystoneConfiguration) -> Bool {
        var needsRehighlight = false

        // Compare against lastApplied values since config might be the same object reference
        let showLineNumbersChanged = lastAppliedShowLineNumbers != config.showLineNumbers
        let fontSizeChanged = lastAppliedFontSize != config.fontSize
        let lineWrappingChanged = lastAppliedLineWrapping != config.lineWrapping
        let invisiblesChanged = lastAppliedShowInvisibles != config.showInvisibleCharacters

        // Track what needs rehighlighting - any visual config change should trigger this
        if fontSizeChanged || showLineNumbersChanged || lineWrappingChanged || invisiblesChanged {
            needsRehighlight = true
        }

        self.configuration = config

        // Update layout constraints if line numbers visibility changed
        if showLineNumbersChanged {
            lastAppliedShowLineNumbers = config.showLineNumbers
            updateLayoutConstraints()
            needsLayout = true
            layoutSubtreeIfNeeded()
        }

        // Update tracking variables
        lastAppliedFontSize = config.fontSize
        lastAppliedLineWrapping = config.lineWrapping
        lastAppliedShowInvisibles = config.showInvisibleCharacters

        lineNumberView.isHidden = !config.showLineNumbers
        // Don't set gutterBackgroundColor from theme - it uses a static snapshot.
        // The dynamic default in LineNumberGutterViewMac handles light/dark mode properly.
        lineNumberView.textColor = NSColor(config.theme.lineNumber)
        lineNumberView.currentLineColor = NSColor.controlAccentColor
        lineNumberView.fontSize = config.fontSize
        lineNumberView.lineHeight = config.fontSize * config.lineHeightMultiplier

        // Update text color for theme changes
        textView.textColor = NSColor(config.theme.text)

        // Update invisible character settings - invalidate layout to force redraw
        invisibleLayoutManager.showInvisibles = config.showInvisibleCharacters
        invisibleLayoutManager.invisibleColor = NSColor(config.theme.invisibleCharacter)
        if invisiblesChanged {
            // Force complete redraw by invalidating all glyphs
            let fullRange = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
            invisibleLayoutManager.invalidateDisplay(forCharacterRange: fullRange)
            textView.needsDisplay = true
        }

        textView.isHorizontallyResizable = !config.lineWrapping
        scrollView.hasHorizontalScroller = !config.lineWrapping
        if config.lineWrapping {
            textView.textContainer?.widthTracksTextView = true
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        needsLayout = true

        return needsRehighlight
    }

    func updateLineNumbers() {
        guard configuration.showLineNumbers, let layoutManager = textView.layoutManager else { return }

        let text = textView.string

        // NOTE: Code folding analysis disabled for performance
        // The current implementation only hides line numbers, not actual text content
        // To properly implement code folding, we would need to modify the text container
        // or use text attachment/exclusion paths

        var lineData: [(lineNumber: Int, yPosition: CGFloat, height: CGFloat)] = []
        var lineNumber = 1
        var glyphIndex = 0
        let numberOfGlyphs = layoutManager.numberOfGlyphs

        while glyphIndex < numberOfGlyphs {
            var lineRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)

            let yPosition = lineRect.origin.y + textView.textContainerInset.height

            let charRange = layoutManager.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil)

            let isFirstFragmentOfLine: Bool
            if charRange.location == 0 {
                isFirstFragmentOfLine = true
            } else {
                let prevChar = (text as NSString).substring(with: NSRange(location: charRange.location - 1, length: 1))
                isFirstFragmentOfLine = prevChar == "\n"
            }

            if isFirstFragmentOfLine {
                lineData.append((lineNumber: lineNumber, yPosition: yPosition, height: lineRect.height))
                lineNumber += 1
            }

            glyphIndex = NSMaxRange(lineRange)
        }

        if text.isEmpty {
            lineData.append((lineNumber: 1, yPosition: textView.textContainerInset.height, height: configuration.fontSize * configuration.lineHeightMultiplier))
        }

        lineNumberView.lineData = lineData
        lineNumberView.needsDisplay = true
    }

    /// Tracks the previous line number to avoid redundant gutter updates
    private var previousLineNumber: Int = 0

    func updateCurrentLineHighlight(_ cursorPosition: Int, highlightColor: NSColor?) {
        let text = textView.string
        var currentLine = 1

        // Find current line number
        for (index, char) in text.enumerated() {
            if index >= cursorPosition { break }
            if char == "\n" {
                currentLine += 1
            }
        }

        // Early exit if line hasn't changed
        if currentLine == previousLineNumber {
            return
        }

        // Update line number gutter only - NO text view background modification
        // Modifying textStorage.backgroundColor was causing layout thrashing and cursor flickering
        lineNumberView.currentLine = currentLine
        lineNumberView.needsDisplay = true
        previousLineNumber = currentLine
    }

    /// Clears current line highlight
    func clearCurrentLineHighlight() {
        // Only clear gutter highlight - we no longer modify text view background
        lineNumberView.currentLine = 0
        lineNumberView.needsDisplay = true
        previousLineNumber = 0
    }

    func syncLineNumberScroll() {
        let newOffset = scrollView.contentView.bounds.origin.y
        if lineNumberView.contentOffset != newOffset {
            lineNumberView.contentOffset = newOffset
            // Force immediate redraw for smooth scrolling
            lineNumberView.needsDisplay = true
            lineNumberView.displayIfNeeded()
        }
    }

    public override func layout() {
        super.layout()
        updateLineNumbers()
        syncLineNumberScroll()
    }
}

/// Custom view for drawing line numbers with code folding on macOS
class LineNumberGutterViewMac: NSView {
    var lineData: [(lineNumber: Int, yPosition: CGFloat, height: CGFloat)] = []
    var currentLine: Int = 1
    var contentOffset: CGFloat = 0
    var fontSize: CGFloat = 14
    var lineHeight: CGFloat = 17
    var textColor: NSColor = .secondaryLabelColor
    var currentLineColor: NSColor = .controlAccentColor
    // Use a dynamic color that adapts to light/dark mode
    var gutterBackgroundColor: NSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.16, alpha: 1.0)
            : NSColor(white: 0.96, alpha: 1.0)
    }

    // Code folding support
    var foldingManager: CodeFoldingManager?
    var onFoldToggle: ((FoldableRegion) -> Void)?
    private let foldIndicatorWidth: CGFloat = 12

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw background explicitly to ensure proper dark mode support
        gutterBackgroundColor.setFill()
        bounds.fill()

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        for data in lineData {
            // Check if this line is hidden due to folding
            if let manager = foldingManager, manager.isLineHidden(data.lineNumber) {
                continue
            }

            // Since isFlipped is true, y starts from top - same as iOS
            let yPosition = data.yPosition - contentOffset

            // Skip if outside visible rect
            if yPosition + data.height < 0 || yPosition > bounds.height { continue }

            let isCurrentLine = data.lineNumber == currentLine
            let color = isCurrentLine ? currentLineColor : textColor

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]

            // Draw line number (leave space for fold indicator)
            let numberString = "\(data.lineNumber)"
            let textRect = NSRect(x: 0, y: yPosition, width: bounds.width - foldIndicatorWidth - 4, height: data.height)
            numberString.draw(in: textRect, withAttributes: attributes)

            // Draw fold indicator if there's a foldable region at this line
            if let manager = foldingManager, let region = manager.region(atLine: data.lineNumber) {
                drawFoldIndicator(
                    at: CGPoint(x: bounds.width - foldIndicatorWidth, y: yPosition),
                    height: data.height,
                    isFolded: manager.isFolded(region)
                )

                // If this region is folded, add placeholder text
                if manager.isFolded(region) {
                    drawFoldedPlaceholder(at: CGPoint(x: 0, y: yPosition), height: data.height, lineCount: region.lineCount - 1)
                }
            }
        }
    }

    private func drawFoldedPlaceholder(at point: CGPoint, height: CGFloat, lineCount: Int) {
        let placeholderFont = NSFont.monospacedSystemFont(ofSize: fontSize * 0.8, weight: .regular)
        let placeholderText = "... \(lineCount) lines"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: placeholderFont,
            .foregroundColor: textColor.withAlphaComponent(0.6)
        ]
        let rect = NSRect(x: 4, y: point.y + height + 2, width: bounds.width - 8, height: height)
        placeholderText.draw(in: rect, withAttributes: attributes)
    }

    private func drawFoldIndicator(at point: CGPoint, height: CGFloat, isFolded: Bool) {
        let size: CGFloat = min(height - 4, 10)
        let rect = NSRect(
            x: point.x + (foldIndicatorWidth - size) / 2,
            y: point.y + (height - size) / 2,
            width: size,
            height: size
        )

        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)

        // Background
        NSColor.controlBackgroundColor.setFill()
        path.fill()

        // Border
        textColor.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Draw triangle
        let symbolPath = NSBezierPath()
        let inset: CGFloat = 2.5

        if isFolded {
            // Right-pointing triangle (collapsed)
            symbolPath.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            symbolPath.line(to: CGPoint(x: rect.maxX - inset, y: rect.midY))
            symbolPath.line(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
            symbolPath.close()
            textColor.setFill()
            symbolPath.fill()
        } else {
            // Down-pointing triangle (expanded)
            symbolPath.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            symbolPath.line(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
            symbolPath.line(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
            symbolPath.close()
            textColor.setFill()
            symbolPath.fill()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let manager = foldingManager else { return }

        let location = convert(event.locationInWindow, from: nil)

        // Check if click is in the fold indicator area
        if location.x >= bounds.width - foldIndicatorWidth - 4 {
            // Find which line was clicked
            for data in lineData {
                let yPosition = data.yPosition - contentOffset
                if location.y >= yPosition && location.y < yPosition + data.height {
                    if let region = manager.region(atLine: data.lineNumber) {
                        onFoldToggle?(region)
                    }
                    break
                }
            }
        }
    }
}
#endif
