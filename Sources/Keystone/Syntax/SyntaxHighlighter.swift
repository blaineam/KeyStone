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

    /// Applies syntax highlighting to a portion of the text storage using TreeSitter.
    /// - Parameters:
    ///   - textStorage: The text storage to apply highlighting to.
    ///   - text: The full document text (TreeSitter requires full context).
    ///   - offset: Unused - kept for API compatibility.
    public func highlightRange(textStorage: NSTextStorage, text: String, offset: Int) {
        // TreeSitter requires full document parsing for accurate results
        highlight(textStorage: textStorage, text: text)
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
        let ranges = highlighter.parse(text)

        for range in ranges {
            guard range.start >= 0 && range.end <= text.utf8.count else { continue }

            // Convert byte offsets to NSRange
            let utf8 = text.utf8
            guard let startIndex = utf8.index(utf8.startIndex, offsetBy: range.start, limitedBy: utf8.endIndex),
                  let endIndex = utf8.index(utf8.startIndex, offsetBy: range.end, limitedBy: utf8.endIndex) else {
                continue
            }

            let startOffset = text.distance(from: text.startIndex, to: String.Index(startIndex, within: text) ?? text.startIndex)
            let endOffset = text.distance(from: text.startIndex, to: String.Index(endIndex, within: text) ?? text.endIndex)
            let nsRange = NSRange(location: startOffset, length: endOffset - startOffset)

            guard nsRange.location >= 0 && nsRange.location + nsRange.length <= textStorage.length else { continue }

            let color = highlighter.color(for: range.tokenType)
            textStorage.addAttribute(.foregroundColor, value: color, range: nsRange)
        }
    }
}
