//
//  KeystoneTextView.swift
//  Keystone
//
//  Platform-specific text view implementations for iOS and macOS.
//

import SwiftUI

#if os(iOS)
import UIKit

/// The SwiftUI wrapper for UITextView on iOS.
public struct KeystoneTextView: UIViewRepresentable {
    @Binding var text: String
    let language: KeystoneLanguage
    @ObservedObject var configuration: KeystoneConfiguration
    @Binding var cursorPosition: CursorPosition
    @Binding var scrollOffset: CGFloat
    @Binding var matchingBracket: BracketMatch?

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
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

        return textView
    }

    public func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true

        let font = UIFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)

        // Update text wrapping
        if configuration.lineWrapping {
            textView.textContainer.lineBreakMode = .byWordWrapping
            textView.textContainer.widthTracksTextView = true
        } else {
            textView.textContainer.lineBreakMode = .byClipping
            textView.textContainer.widthTracksTextView = false
            textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        // Only update if text actually changed
        if textView.text != text {
            let selectedRange = textView.selectedRange
            textView.text = text
            applySyntaxHighlighting(to: textView.textStorage, text: text, font: font)

            // Restore selection
            let newLocation = min(selectedRange.location, text.count)
            textView.selectedRange = NSRange(location: newLocation, length: 0)
        }

        // Apply highlights for matching brackets
        if let match = matchingBracket {
            applyBracketHighlights(to: textView.textStorage, match: match)
        }

        // Update font if needed
        if textView.font?.pointSize != configuration.fontSize {
            textView.font = font
            applySyntaxHighlighting(to: textView.textStorage, text: text, font: font)
        }

        context.coordinator.isUpdating = false
    }

    private func applySyntaxHighlighting(to textStorage: NSTextStorage, text: String, font: UIFont) {
        let theme = configuration.theme
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // Reset to default
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: UIColor(theme.text)
        ], range: fullRange)

        // Apply syntax highlighting based on language
        let highlighter = SyntaxHighlighter(language: language, theme: theme)
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

    // MARK: - Coordinator

    public class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {
        var parent: KeystoneTextView
        var isUpdating = false

        init(_ parent: KeystoneTextView) {
            self.parent = parent
        }

        public func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }

            let newText = textView.text ?? ""

            // Handle character pair insertion
            handleCharacterPairs(textView: textView, newText: newText)

            parent.text = newText
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating else { return }

            let text = textView.text ?? ""
            let selectedRange = textView.selectedRange

            parent.cursorPosition = CursorPosition.from(
                offset: selectedRange.location,
                in: text,
                selectionLength: selectedRange.length
            )
        }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.scrollOffset = scrollView.contentOffset.y
        }

        private func handleCharacterPairs(textView: UITextView, newText: String) {
            // Character pair insertion is handled during typing
            // This is called after text changes
        }

        // Handle character pair insertion
        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard parent.configuration.autoInsertPairs else { return true }

            let currentText = textView.text ?? ""

            // Handle single character input
            if text.count == 1, let char = text.first {
                // Check for skip closing pair
                if parent.configuration.shouldSkipClosingPair(for: char, in: currentText, at: range.location) {
                    // Move cursor past the closing character
                    if let newPosition = textView.position(from: textView.beginningOfDocument, offset: range.location + 1) {
                        textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
                    }
                    return false
                }

                // Check for auto-insert pair
                if let closingChar = parent.configuration.shouldAutoInsertPair(for: char, in: currentText, at: range.location) {
                    // Insert both characters
                    let insertText = String(char) + String(closingChar)
                    if let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                       let end = textView.position(from: start, offset: range.length),
                       let textRange = textView.textRange(from: start, to: end) {
                        textView.replace(textRange, withText: insertText)

                        // Position cursor between the pair
                        if let newPosition = textView.position(from: textView.beginningOfDocument, offset: range.location + 1) {
                            textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
                        }
                        return false
                    }
                }
            }

            // Handle backspace - delete pair
            if text.isEmpty && range.length == 1 {
                if parent.configuration.shouldDeletePair(in: currentText, at: range.location) {
                    // Delete both characters
                    let deleteRange = NSRange(location: range.location - 1, length: 2)
                    if let start = textView.position(from: textView.beginningOfDocument, offset: deleteRange.location),
                       let end = textView.position(from: start, offset: deleteRange.length),
                       let textRange = textView.textRange(from: start, to: end) {
                        textView.replace(textRange, withText: "")
                        return false
                    }
                }
            }

            return true
        }
    }
}

#elseif os(macOS)
import AppKit

/// The SwiftUI wrapper for NSTextView on macOS.
public struct KeystoneTextView: NSViewRepresentable {
    @Binding var text: String
    let language: KeystoneLanguage
    @ObservedObject var configuration: KeystoneConfiguration
    @Binding var cursorPosition: CursorPosition
    @Binding var scrollOffset: CGFloat
    @Binding var matchingBracket: BracketMatch?

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
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

        // Observe scroll changes
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self
        context.coordinator.isUpdating = true

        let font = NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)

        // Update text wrapping
        textView.isHorizontallyResizable = !configuration.lineWrapping
        scrollView.hasHorizontalScroller = !configuration.lineWrapping
        if configuration.lineWrapping {
            textView.textContainer?.widthTracksTextView = true
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        // Only update if text actually changed
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text

            if let textStorage = textView.textStorage {
                applySyntaxHighlighting(to: textStorage, text: text, font: font)
            }

            // Restore selection
            let newLocation = min(selectedRange.location, text.count)
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        }

        // Apply highlights for matching brackets
        if let match = matchingBracket, let textStorage = textView.textStorage {
            applyBracketHighlights(to: textStorage, match: match)
        }

        // Update font if needed
        if textView.font?.pointSize != configuration.fontSize {
            textView.font = font
            if let textStorage = textView.textStorage {
                applySyntaxHighlighting(to: textStorage, text: text, font: font)
            }
        }

        context.coordinator.isUpdating = false
    }

    private func applySyntaxHighlighting(to textStorage: NSTextStorage, text: String, font: NSFont) {
        let theme = configuration.theme
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // Reset to default
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: NSColor(theme.text)
        ], range: fullRange)

        // Apply syntax highlighting based on language
        let highlighter = SyntaxHighlighter(language: language, theme: theme)
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

    // MARK: - Coordinator

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KeystoneTextView
        var isUpdating = false

        init(_ parent: KeystoneTextView) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }

            parent.text = textView.string
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
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            parent.scrollOffset = clipView.bounds.origin.y
        }

        // Handle character pair insertion
        public func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard parent.configuration.autoInsertPairs, let text = text else { return true }

            let currentText = textView.string

            // Handle single character input
            if text.count == 1, let char = text.first {
                // Check for skip closing pair
                if parent.configuration.shouldSkipClosingPair(for: char, in: currentText, at: range.location) {
                    // Move cursor past the closing character
                    textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                    return false
                }

                // Check for auto-insert pair
                if let closingChar = parent.configuration.shouldAutoInsertPair(for: char, in: currentText, at: range.location) {
                    // Insert both characters
                    let insertText = String(char) + String(closingChar)
                    textView.insertText(insertText, replacementRange: range)

                    // Position cursor between the pair
                    textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                    return false
                }
            }

            // Handle backspace - delete pair
            if text.isEmpty && range.length == 1 && range.location > 0 {
                if parent.configuration.shouldDeletePair(in: currentText, at: range.location) {
                    // Delete both characters
                    let deleteRange = NSRange(location: range.location - 1, length: 2)
                    textView.insertText("", replacementRange: deleteRange)
                    return false
                }
            }

            return true
        }
    }
}
#endif
