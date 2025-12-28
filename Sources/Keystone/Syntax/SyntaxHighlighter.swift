//
//  SyntaxHighlighter.swift
//  Keystone
//

import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Handles syntax highlighting for code text using TreeSitter exclusively.
public class SyntaxHighlighter {
    let language: KeystoneLanguage
    let theme: KeystoneTheme
    private var treeSitterHighlighter: TreeSitterHighlighter?

    public init(language: KeystoneLanguage, theme: KeystoneTheme) {
        self.language = language
        self.theme = theme

        // Initialize TreeSitter highlighter
        self.treeSitterHighlighter = TreeSitterHighlighter(language: language, theme: theme)
    }

    /// Whether TreeSitter parsing is available for this language.
    public var isTreeSitterAvailable: Bool {
        treeSitterHighlighter?.isTreeSitterAvailable ?? false
    }

    /// Invalidates the syntax highlighting cache, forcing a re-parse on next highlight call.
    public func invalidateCache() {
        treeSitterHighlighter?.invalidateCache()
    }

    /// Returns true if we have cached highlighting for the given text
    public func hasCachedHighlighting(for text: String) -> Bool {
        treeSitterHighlighter?.hasCachedRanges(for: text) ?? false
    }

    /// Triggers async parsing of the text. Call this to start background parsing.
    /// The completion handler is called when parsing is complete.
    public func parseAsync(_ text: String, completion: @escaping () -> Void) {
        guard let tsHighlighter = treeSitterHighlighter, tsHighlighter.isTreeSitterAvailable else {
            completion()
            return
        }
        tsHighlighter.parseAsync(text) { _ in
            completion()
        }
    }

    /// Applies syntax highlighting to the text storage using cached results.
    /// If no cached results exist, triggers async parsing and returns immediately.
    /// - Parameters:
    ///   - textStorage: The text storage to apply highlighting to.
    ///   - text: The text to parse (should be the FULL document for proper context).
    ///   - offset: The offset in textStorage where highlighting starts.
    ///   - rangeToHighlight: Optional range to limit highlighting to (for viewport optimization).
    ///   - onParseComplete: Optional callback when async parsing completes (for re-highlighting).
    public func highlightRange(
        textStorage: NSTextStorage,
        text: String,
        offset: Int,
        rangeToHighlight: NSRange? = nil,
        onParseComplete: (() -> Void)? = nil
    ) {
        guard !text.isEmpty else { return }
        guard let tsHighlighter = treeSitterHighlighter, tsHighlighter.isTreeSitterAvailable else {
            return
        }

        // Check if we have cached results (non-blocking)
        if tsHighlighter.hasCachedRanges(for: text) {
            // Apply cached pre-converted character ranges (fast path)
            let charRanges = tsHighlighter.getCachedCharRanges()
            applyCharRanges(charRanges, to: textStorage, rangeToHighlight: rangeToHighlight)
            onParseComplete?()
        } else {
            // No cache - trigger async parse
            tsHighlighter.parseAsync(text) { [weak self] charRanges in
                guard let self = self else { return }
                // Apply colors - if text changed, colors may be slightly off but
                // will be corrected on next highlight pass
                if !charRanges.isEmpty && textStorage.length > 0 {
                    textStorage.beginEditing()
                    self.applyCharRanges(charRanges, to: textStorage, rangeToHighlight: rangeToHighlight)
                    textStorage.endEditing()
                }
                onParseComplete?()
            }
        }
    }

    /// Applies pre-converted character ranges to the text storage (fast path)
    private func applyCharRanges(_ ranges: [(range: NSRange, tokenType: TokenType)], to textStorage: NSTextStorage, rangeToHighlight: NSRange?) {
        guard let tsHighlighter = treeSitterHighlighter else { return }
        let storageLength = textStorage.length

        for (nsRange, tokenType) in ranges {
            // Skip if outside the range we're highlighting
            if let limitRange = rangeToHighlight {
                if nsRange.location + nsRange.length < limitRange.location {
                    continue // Before the highlight range
                }
                if nsRange.location > limitRange.location + limitRange.length {
                    continue // After the highlight range
                }
            }

            guard nsRange.location >= 0 && nsRange.location + nsRange.length <= storageLength else { continue }

            let color = tsHighlighter.color(for: tokenType)
            textStorage.addAttribute(.foregroundColor, value: color, range: nsRange)
        }
    }

    /// Applies syntax highlighting to the given text storage using TreeSitter.
    public func highlight(textStorage: NSTextStorage, text: String) {
        guard !text.isEmpty else { return }

        // Only use TreeSitter for syntax highlighting
        guard let tsHighlighter = treeSitterHighlighter, tsHighlighter.isTreeSitterAvailable else {
            // No TreeSitter support for this language - no highlighting applied
            return
        }

        highlightWithTreeSitter(tsHighlighter, textStorage: textStorage, text: text)
    }

    // MARK: - TreeSitter Highlighting

    private func highlightWithTreeSitter(_ highlighter: TreeSitterHighlighter, textStorage: NSTextStorage, text: String) {
        // Check if we have cached results (non-blocking)
        if highlighter.hasCachedRanges(for: text) {
            let charRanges = highlighter.getCachedCharRanges()
            applyCharRanges(charRanges, to: textStorage, rangeToHighlight: nil)
        } else {
            // No cache - trigger async parse
            let expectedLength = textStorage.length
            highlighter.parseAsync(text) { [weak self] charRanges in
                guard let self = self else { return }
                guard textStorage.length == expectedLength else { return }
                textStorage.beginEditing()
                self.applyCharRanges(charRanges, to: textStorage, rangeToHighlight: nil)
                textStorage.endEditing()
            }
        }
    }
}
