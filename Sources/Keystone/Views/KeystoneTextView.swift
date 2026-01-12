//
//  KeystoneTextView.swift
//  Keystone
//
//  SwiftUI wrapper for Runestone's high-performance TextView.
//  Provides the same interface as main branch's KeystoneTextView.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

/// A SwiftUI wrapper for Runestone's high-performance TextView.
/// Provides the same interface as the main branch's KeystoneTextView.
public struct KeystoneTextView: UIViewRepresentable {
    @Binding var text: String
    let language: KeystoneLanguage
    @ObservedObject var configuration: KeystoneConfiguration
    @Binding var cursorPosition: CursorPosition
    @Binding var scrollOffset: CGFloat
    @Binding var matchingBracket: BracketMatch?
    @Binding var scrollToCursor: Bool
    var searchMatches: [SearchMatch]
    var currentMatchIndex: Int
    var undoController: UndoController?

    public init(
        text: Binding<String>,
        language: KeystoneLanguage,
        configuration: KeystoneConfiguration,
        cursorPosition: Binding<CursorPosition>,
        scrollOffset: Binding<CGFloat>,
        matchingBracket: Binding<BracketMatch?>,
        scrollToCursor: Binding<Bool>,
        searchMatches: [SearchMatch] = [],
        currentMatchIndex: Int = 0,
        undoController: UndoController? = nil
    ) {
        self._text = text
        self.language = language
        self._configuration = ObservedObject(wrappedValue: configuration)
        self._cursorPosition = cursorPosition
        self._scrollOffset = scrollOffset
        self._matchingBracket = matchingBracket
        self._scrollToCursor = scrollToCursor
        self.searchMatches = searchMatches
        self.currentMatchIndex = currentMatchIndex
        self.undoController = undoController
    }

    public func makeUIView(context: Context) -> TextView {
        let textView = TextView()

        // Configure the text view
        textView.editorDelegate = context.coordinator

        // Disable auto-correction features for code editing
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no

        // Apply initial configuration
        applyConfiguration(to: textView)

        // Set up language if available
        if let tsLanguage = language.treeSitterLanguage {
            let theme = KeystoneRunestoneTheme(configuration: configuration)
            let state = TextViewState(
                text: text,
                theme: theme,
                language: tsLanguage,
                languageProvider: KeystoneLanguageProvider.shared
            )
            textView.setState(state)
        } else {
            // No tree-sitter language, just set the text with theme
            let theme = KeystoneRunestoneTheme(configuration: configuration)
            textView.theme = theme
            textView.text = text
        }

        // Set up undo controller
        setupUndoController(textView: textView, context: context)

        // Set up code folding
        setupCodeFolding(textView: textView, context: context)

        context.coordinator.textView = textView

        return textView
    }

    private func setupCodeFolding(textView: TextView, context: Context) {
        let coordinator = context.coordinator
        let foldingManager = coordinator.codeFoldingManager

        // Connect the manager to the text view
        textView.codeFoldingManager = foldingManager

        // Set up the fold toggle handler - triggers immediate refresh
        textView.onFoldToggle = { [weak foldingManager, weak textView] lineIndex in
            guard let manager = foldingManager, let tv = textView else { return }
            if let region = manager.regionStarting(atLine: lineIndex) {
                manager.toggleFold(for: region)
                // Force immediate layout refresh after fold state changes
                tv.forceLayoutRefresh()
            }
        }

        // Trigger layout update when fold state changes (for programmatic changes)
        foldingManager.onFoldingChanged = { [weak textView] in
            textView?.forceLayoutRefresh()
        }

        // Initial analysis of text (only for non-large files)
        foldingManager.analyzeText(text)
    }

    public func updateUIView(_ textView: TextView, context: Context) {
        context.coordinator.parent = self
        let coordinator = context.coordinator

        // Apply configuration changes first (includes background color)
        applyConfiguration(to: textView)

        // Update theme colors only when theme or font size actually changes
        // This prevents syntax highlighting re-evaluation on every cursor move
        let currentTheme = configuration.theme
        let currentFontSize = configuration.fontSize
        if currentTheme != coordinator.lastSyncedTheme || currentFontSize != coordinator.lastSyncedFontSize {
            coordinator.lastSyncedTheme = currentTheme
            coordinator.lastSyncedFontSize = currentFontSize
            let theme = KeystoneRunestoneTheme(configuration: configuration)
            textView.theme = theme
        }

        // Handle language changes - update syntax highlighting when language changes
        if language != coordinator.lastSyncedLanguage {
            coordinator.lastSyncedLanguage = language
            if let tsLanguage = language.treeSitterLanguage {
                let languageMode = TreeSitterLanguageMode(language: tsLanguage, languageProvider: KeystoneLanguageProvider.shared)
                textView.setLanguageMode(languageMode) { finished in
                    // Only redraw if parsing finished and mode is still current
                    if finished {
                        textView.redisplayVisibleLines()
                    }
                }
            } else {
                textView.setLanguageMode(PlainTextLanguageMode()) { finished in
                    if finished {
                        textView.redisplayVisibleLines()
                    }
                }
            }
        }

        // Handle external text changes (file loads) SAFELY
        // NEVER call setState from updateUIView - it causes crashes because
        // the keyboard queries line structure before RedBlackTree is ready.
        // Instead, we queue the update and apply it when truly safe.
        if textView.text != text && !coordinator.isUpdatingText && text != coordinator.lastSyncedText {
            // Queue the pending text update - will be applied when keyboard is fully dismissed
            let pendingTheme = KeystoneRunestoneTheme(configuration: configuration)
            coordinator.pendingTextUpdate = (text: text, language: language.treeSitterLanguage, theme: pendingTheme)

            // Try to apply immediately only if not editing (keyboard hidden)
            if !textView.isFirstResponder {
                // Use async to avoid state modification during view update
                DispatchQueue.main.async {
                    coordinator.applyPendingTextUpdate()
                }
            }
            // If keyboard is showing, the keyboardDidHide observer will apply the update
        }

        // Update cursor position if it changed externally (e.g., from find navigation)
        // Only update if not currently editing to avoid fighting with user input
        // MUST defer to async to avoid RedBlackTree crash - setting selectedRange
        // triggers keyboard tokenizer which queries line structure before tree is ready
        if coordinator.pendingTextUpdate == nil && !coordinator.isUpdatingCursor && !coordinator.isUpdatingText {
            let expectedRange = NSRange(location: cursorPosition.offset, length: cursorPosition.selectionLength)
            let currentRange = textView.selectedRange
            let isExternalChange = cursorPosition != coordinator.lastSyncedCursorPosition

            if isExternalChange && currentRange != expectedRange && !textView.isUpdatingText {
                DispatchQueue.main.async {
                    // Double-check conditions are still valid
                    guard !coordinator.isUpdatingText && !coordinator.isUpdatingCursor && !textView.isUpdatingText else { return }
                    coordinator.isUpdatingCursor = true
                    coordinator.lastSyncedCursorPosition = self.cursorPosition
                    // Set isUpdatingText on textView to prevent TextInputStringTokenizer
                    // from querying RedBlackTree mid-update (causes assertion failure)
                    textView.isUpdatingText = true
                    textView.selectedRange = expectedRange
                    textView.isUpdatingText = false
                    coordinator.isUpdatingCursor = false
                }
            }
        }

        // Handle scroll to cursor - defer to avoid state modification during update
        if scrollToCursor {
            DispatchQueue.main.async {
                self.scrollToCursor = false
                // Scroll to the cursor position
                let range = NSRange(location: self.cursorPosition.offset, length: self.cursorPosition.selectionLength)
                textView.scrollRangeToVisible(range)
            }
        }

        // Update search match highlighting
        coordinator.updateSearchHighlights(textView: textView, searchMatches: searchMatches, currentMatchIndex: currentMatchIndex)

        // Defer bracket matching update to avoid state modification during view update
        DispatchQueue.main.async {
            coordinator.updateBracketMatch(textView: textView)
        }

        // Track scroll offset
        coordinator.lastScrollOffset = textView.contentOffset.y
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyConfiguration(to textView: TextView) {
        // Background color from theme
        textView.backgroundColor = UIColor(configuration.theme.background)

        // Appearance settings
        textView.showLineNumbers = configuration.showLineNumbers
        textView.showCodeFolding = configuration.showCodeFolding
        textView.lineHeightMultiplier = configuration.lineHeightMultiplier
        textView.isLineWrappingEnabled = configuration.lineWrapping

        // Line selection highlighting
        if configuration.highlightCurrentLine {
            textView.lineSelectionDisplayType = .line
        } else {
            textView.lineSelectionDisplayType = .disabled
        }

        // Invisible characters
        let showInvisibles = configuration.showInvisibleCharacters
        textView.showTabs = showInvisibles
        textView.showSpaces = showInvisibles
        textView.showLineBreaks = showInvisibles

        // Indentation
        switch configuration.indentation.type {
        case .tabs:
            textView.indentStrategy = .tab(length: configuration.indentation.width)
        case .spaces:
            textView.indentStrategy = .space(length: configuration.indentation.width)
        }

        // Character pairs
        if configuration.autoInsertPairs {
            textView.characterPairs = [
                BasicCharacterPair(leading: "(", trailing: ")"),
                BasicCharacterPair(leading: "[", trailing: "]"),
                BasicCharacterPair(leading: "{", trailing: "}"),
                BasicCharacterPair(leading: "\"", trailing: "\""),
                BasicCharacterPair(leading: "'", trailing: "'"),
                BasicCharacterPair(leading: "`", trailing: "`")
            ]
            textView.characterPairTrailingComponentDeletionMode = .disabled
        } else {
            textView.characterPairs = []
        }

        // Line ending
        textView.lineEndings = configuration.lineEnding
    }

    private func setupUndoController(textView: TextView, context: Context) {
        guard let undoController = undoController else { return }

        let coordinator = context.coordinator

        undoController.undoAction = { [weak textView, weak coordinator] in
            textView?.undoManager?.undo()
            coordinator?.syncTextNow()
        }

        undoController.redoAction = { [weak textView, weak coordinator] in
            textView?.undoManager?.redo()
            coordinator?.syncTextNow()
        }

        undoController.checkUndoState = { [weak textView] in
            (canUndo: textView?.undoManager?.canUndo ?? false,
             canRedo: textView?.undoManager?.canRedo ?? false)
        }

        undoController.replaceTextAction = { [weak textView] range, replacementText in
            guard let textView = textView else { return nil }
            guard range.location + range.length <= textView.text.count else { return nil }

            // Use Runestone's replace method to properly update internal state
            textView.replace(range, withText: replacementText)

            return textView.text
        }

        undoController.beginUndoGroupingAction = { [weak textView] in
            textView?.undoManager?.beginUndoGrouping()
        }

        undoController.endUndoGroupingAction = { [weak textView] in
            textView?.undoManager?.endUndoGrouping()
        }

        undoController.startUpdating()
    }

    // MARK: - Coordinator

    @MainActor public class Coordinator: NSObject, TextViewDelegate, UIScrollViewDelegate {
        var parent: KeystoneTextView
        weak var textView: TextView?
        var isUpdatingText = false
        var isUpdatingCursor = false
        var lastScrollOffset: CGFloat = 0
        var lastSyncedText: String = ""
        var lastSyncedCursorPosition: CursorPosition?
        var lastSyncedLanguage: KeystoneLanguage?
        var lastSyncedTheme: KeystoneTheme
        var lastSyncedFontSize: CGFloat
        private var highlightedRanges: [HighlightedRange] = []
        let codeFoldingManager = CodeFoldingManager()
        private var foldingAnalysisWorkItem: DispatchWorkItem?
        /// Debounce timer for cursor position updates to prevent rapid-fire binding updates
        private var cursorUpdateWorkItem: DispatchWorkItem?

        /// Pending text update to apply when safe (keyboard fully dismissed)
        var pendingTextUpdate: (text: String, language: TreeSitterLanguage?, theme: KeystoneRunestoneTheme)?

        init(_ parent: KeystoneTextView) {
            self.parent = parent
            self.lastSyncedText = parent.text
            self.lastSyncedLanguage = parent.language
            self.lastSyncedTheme = parent.configuration.theme
            self.lastSyncedFontSize = parent.configuration.fontSize
            super.init()

            // Observe keyboard dismiss to apply pending updates safely
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidHide),
                name: UIResponder.keyboardDidHideNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func keyboardDidHide() {
            // Apply any pending text updates now that keyboard is fully dismissed
            applyPendingTextUpdate()
        }

        func syncTextNow() {
            guard let textView = textView, !isUpdatingText else { return }
            isUpdatingText = true
            let currentText = textView.text
            parent.text = currentText
            lastSyncedText = currentText
            isUpdatingText = false
        }

        /// Apply pending text update safely - only call when keyboard is fully dismissed
        func applyPendingTextUpdate() {
            guard let pending = pendingTextUpdate, let textView = textView else { return }

            // Clear the pending update first
            pendingTextUpdate = nil

            // Double-check that we still need to update (avoid unnecessary setState calls)
            guard textView.text != pending.text else {
                // Text is already correct, no need to update (preserves undo history)
                lastSyncedText = pending.text
                return
            }

            isUpdatingText = true
            // CRITICAL: Set the tokenizer flag to prevent crashes when keyboard queries line boundaries
            textView.isUpdatingText = true
            defer { textView.isUpdatingText = false }

            // Only use setState (which clears undo history) for initial setup or language changes.
            // For simple text updates, just set the text property to preserve undo history.
            // setState clears undo history, so we should only use it when truly necessary.
            if let language = pending.language {
                // Check if this is really a new language/file (significant text change)
                // or just a minor external update that should preserve undo
                let isSignificantChange = abs(textView.text.count - pending.text.count) > pending.text.count / 2
                    || textView.text.isEmpty
                    || pending.text.isEmpty

                if isSignificantChange {
                    // Major change (like file load) - use setState and clear undo
                    let state = TextViewState(
                        text: pending.text,
                        theme: pending.theme,
                        language: language,
                        languageProvider: KeystoneLanguageProvider.shared
                    )
                    textView.setState(state)
                } else {
                    // Minor change - use setTextPreservingUndo to preserve undo history
                    textView.setTextPreservingUndo(pending.text)
                    textView.theme = pending.theme
                }
            } else {
                // No language, use setTextPreservingUndo to preserve undo history
                textView.setTextPreservingUndo(pending.text)
            }

            lastSyncedText = pending.text
            isUpdatingText = false
        }

        // MARK: - Search Highlighting

        func updateSearchHighlights(textView: TextView, searchMatches: [SearchMatch], currentMatchIndex: Int) {
            guard !searchMatches.isEmpty else {
                // Clear all highlights
                highlightedRanges.removeAll()
                textView.highlightedRanges = []
                return
            }

            // Build new highlights array
            var newHighlights: [HighlightedRange] = []

            for (index, match) in searchMatches.enumerated() {
                let isCurrentMatch = index == currentMatchIndex

                // Use different colors for current match vs other matches
                let backgroundColor: UIColor
                if isCurrentMatch {
                    backgroundColor = UIColor.systemOrange.withAlphaComponent(0.6)
                } else {
                    backgroundColor = UIColor.systemYellow.withAlphaComponent(0.4)
                }

                // Convert Range<String.Index> to NSRange
                let text = textView.text
                let nsRange = NSRange(match.range, in: text)

                let highlightedRange = HighlightedRange(
                    range: nsRange,
                    color: backgroundColor,
                    cornerRadius: 2
                )
                newHighlights.append(highlightedRange)
            }

            // Update the text view's highlighted ranges
            highlightedRanges = newHighlights
            textView.highlightedRanges = newHighlights
        }

        // MARK: - Bracket Matching

        func updateBracketMatch(textView: TextView) {
            let offset = textView.selectedRange.location
            let text = textView.text

            // Find bracket match at cursor
            if let match = BracketMatcher.findMatch(in: text, at: offset) {
                parent.matchingBracket = match
            } else if offset > 0, let match = BracketMatcher.findMatch(in: text, at: offset - 1) {
                parent.matchingBracket = match
            } else {
                parent.matchingBracket = nil
            }
        }

        // MARK: - TextViewDelegate

        public func textViewDidChange(_ textView: TextView) {
            guard !isUpdatingText else { return }

            isUpdatingText = true
            let currentText = textView.text
            parent.text = currentText
            lastSyncedText = currentText
            isUpdatingText = false

            // Debounced code folding analysis - refreshes 2.5s after last change
            // Cancel any pending analysis
            foldingAnalysisWorkItem?.cancel()

            // Schedule new analysis
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.codeFoldingManager.analyzeText(currentText)
            }
            foldingAnalysisWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
        }

        public func textViewDidChangeSelection(_ textView: TextView) {
            // Skip updating cursor binding during multi-step text operations or external updates
            // This prevents SwiftUI state inconsistencies and feedback loops
            guard !isUpdatingText && !isUpdatingCursor && !textView.isUpdatingText else { return }

            let selectedRange = textView.selectedRange
            let text = textView.text
            let newPosition = CursorPosition.from(
                offset: selectedRange.location,
                in: text,
                selectionLength: selectedRange.length
            )

            // Skip if position hasn't actually changed (prevents feedback loops)
            guard newPosition != lastSyncedCursorPosition else { return }

            // Cancel any pending cursor update
            cursorUpdateWorkItem?.cancel()

            // Debounce cursor position updates to prevent rapid-fire binding updates
            // during multi-step operations (like character pairs or comment toggle)
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.isUpdatingText && !self.isUpdatingCursor else { return }
                self.isUpdatingCursor = true
                self.lastSyncedCursorPosition = newPosition
                self.parent.cursorPosition = newPosition
                self.isUpdatingCursor = false
            }
            cursorUpdateWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)

            // Update bracket matching immediately (visual feedback)
            updateBracketMatch(textView: textView)
        }

        public func textView(_ textView: TextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            return true
        }

        // MARK: - UIScrollViewDelegate

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.scrollOffset = scrollView.contentOffset.y
        }
    }
}

// MARK: - BasicCharacterPair

/// A basic character pair implementation for bracket matching.
struct BasicCharacterPair: CharacterPair {
    let leading: String
    let trailing: String
}

// MARK: - KeystoneRunestoneTheme

/// Adapts KeystoneTheme colors to Runestone's Theme protocol.
/// Values are cached at init time to avoid actor isolation issues.
class KeystoneRunestoneTheme: Theme {
    // Cached values from configuration
    private let _fontSize: CGFloat
    private let _textColor: UIColor
    private let _backgroundColor: UIColor
    private let _gutterBackgroundColor: UIColor
    private let _lineNumberColor: UIColor
    private let _currentLineHighlight: UIColor
    private let _invisibleCharacter: UIColor
    private let _keywordColor: UIColor
    private let _stringColor: UIColor
    private let _commentColor: UIColor
    private let _typeColor: UIColor
    private let _functionColor: UIColor
    private let _numberColor: UIColor
    private let _operatorColor: UIColor
    private let _propertyColor: UIColor
    private let _attributeColor: UIColor
    private let _tagColor: UIColor

    @MainActor
    init(configuration: KeystoneConfiguration) {
        let theme = configuration.theme
        _fontSize = configuration.fontSize
        _textColor = UIColor(theme.text)
        _backgroundColor = UIColor(theme.background)
        _gutterBackgroundColor = UIColor(theme.gutterBackground)
        _lineNumberColor = UIColor(theme.lineNumber)
        _currentLineHighlight = UIColor(theme.currentLineHighlight)
        _invisibleCharacter = UIColor(theme.invisibleCharacter)
        _keywordColor = UIColor(theme.keyword)
        _stringColor = UIColor(theme.string)
        _commentColor = UIColor(theme.comment)
        _typeColor = UIColor(theme.type)
        _functionColor = UIColor(theme.function)
        _numberColor = UIColor(theme.number)
        _operatorColor = UIColor(theme.operator)
        _propertyColor = UIColor(theme.property)
        _attributeColor = UIColor(theme.attribute)
        _tagColor = UIColor(theme.tag)
    }

    var font: UIFont {
        .monospacedSystemFont(ofSize: _fontSize, weight: .regular)
    }

    var textColor: UIColor {
        _textColor
    }

    var gutterBackgroundColor: UIColor {
        _gutterBackgroundColor
    }

    var gutterHairlineColor: UIColor {
        UIColor.separator
    }

    var lineNumberColor: UIColor {
        _lineNumberColor
    }

    var lineNumberFont: UIFont {
        .monospacedSystemFont(ofSize: _fontSize * 0.85, weight: .regular)
    }

    var selectedLineBackgroundColor: UIColor {
        _currentLineHighlight
    }

    var selectedLinesLineNumberColor: UIColor {
        _textColor
    }

    var selectedLinesGutterBackgroundColor: UIColor {
        _currentLineHighlight
    }

    var invisibleCharactersColor: UIColor {
        _invisibleCharacter
    }

    var pageGuideHairlineColor: UIColor {
        UIColor.separator
    }

    var pageGuideBackgroundColor: UIColor {
        _backgroundColor.withAlphaComponent(0.5)
    }

    var markedTextBackgroundColor: UIColor {
        UIColor.systemYellow.withAlphaComponent(0.3)
    }

    // Syntax highlighting colors
    func textColor(for rawHighlightName: String) -> UIColor? {
        // Use HighlightName to parse the raw name (handles dotted names like "keyword.return")
        guard let highlightName = HighlightName(rawHighlightName) else {
            return nil
        }
        switch highlightName {
        case .attribute:
            return _attributeColor
        case .boolean, .constant, .constantBuiltin, .constantCharacter, .symbol:
            return _numberColor
        case .character:
            return _stringColor
        case .comment:
            return _commentColor
        case .conditional, .include, .keyword, .repeat:
            return _keywordColor
        case .constructor, .type, .module, .namespace:
            return _typeColor
        case .delimiter, .punctuation:
            return _textColor
        case .escape:
            return _stringColor
        case .field, .parameter, .property, .variableBuiltin:
            return _propertyColor
        case .float, .number:
            return _numberColor
        case .function, .method:
            return _functionColor
        case .label, .tag:
            return _tagColor
        case .operator:
            return _operatorColor
        case .string:
            return _stringColor
        case .text, .variable:
            return _textColor
        }
    }

    func fontTraits(for rawHighlightName: String) -> FontTraits {
        guard let highlightName = HighlightName(rawHighlightName) else {
            return []
        }
        switch highlightName {
        case .keyword:
            return .bold
        case .comment:
            return .italic
        default:
            return []
        }
    }
}

#elseif canImport(AppKit)
import AppKit

/// macOS implementation using native Runestone TextView for iOS/macOS feature parity.
/// Uses the same high-performance architecture as iOS: TextInputViewMac + NSTextInputClient.
public struct KeystoneTextView: NSViewRepresentable {
    @Binding var text: String
    let language: KeystoneLanguage
    @ObservedObject var configuration: KeystoneConfiguration
    @Binding var cursorPosition: CursorPosition
    @Binding var scrollOffset: CGFloat
    @Binding var matchingBracket: BracketMatch?
    @Binding var scrollToCursor: Bool
    var searchMatches: [SearchMatch]
    var currentMatchIndex: Int
    var undoController: UndoController?
    /// Called when TreeSitter parsing times out (default 30 seconds).
    var onParsingTimeout: (() -> Void)?

    public init(
        text: Binding<String>,
        language: KeystoneLanguage,
        configuration: KeystoneConfiguration,
        cursorPosition: Binding<CursorPosition>,
        scrollOffset: Binding<CGFloat>,
        matchingBracket: Binding<BracketMatch?>,
        scrollToCursor: Binding<Bool>,
        searchMatches: [SearchMatch] = [],
        currentMatchIndex: Int = 0,
        undoController: UndoController? = nil,
        onParsingTimeout: (() -> Void)? = nil
    ) {
        self._text = text
        self.language = language
        self._configuration = ObservedObject(wrappedValue: configuration)
        self._cursorPosition = cursorPosition
        self._scrollOffset = scrollOffset
        self._matchingBracket = matchingBracket
        self._scrollToCursor = scrollToCursor
        self.searchMatches = searchMatches
        self.currentMatchIndex = currentMatchIndex
        self.undoController = undoController
        self.onParsingTimeout = onParsingTimeout
    }

    public func makeNSView(context: Context) -> TextView {
        let textView = TextView()

        // Configure the text view
        textView.editorDelegate = context.coordinator

        // Apply initial configuration
        applyConfiguration(to: textView)

        // Set up language if available
        if let tsLanguage = language.treeSitterLanguage {
            let theme = KeystoneRunestoneThemeMac(configuration: configuration)
            let state = TextViewState(
                text: text,
                theme: theme,
                language: tsLanguage,
                languageProvider: KeystoneLanguageProvider.shared
            )
            textView.setState(state)
        } else {
            // No tree-sitter language, just set the text with theme
            let theme = KeystoneRunestoneThemeMac(configuration: configuration)
            textView.theme = theme
            textView.text = text
        }

        // Set up undo controller
        setupUndoController(textView: textView, context: context)

        // Set up code folding
        setupCodeFolding(textView: textView, context: context)

        context.coordinator.textView = textView

        return textView
    }

    private func setupCodeFolding(textView: TextView, context: Context) {
        let coordinator = context.coordinator
        let foldingManager = coordinator.codeFoldingManager

        // Connect the manager to the text view
        textView.codeFoldingManager = foldingManager

        // Set up the fold toggle handler - triggers immediate refresh
        textView.onFoldToggle = { [weak foldingManager, weak textView] lineIndex in
            guard let manager = foldingManager, let tv = textView else { return }
            if let region = manager.regionStarting(atLine: lineIndex) {
                manager.toggleFold(for: region)
                // Force immediate layout refresh after fold state changes
                tv.forceLayoutRefresh()
            }
        }

        // Trigger layout update when fold state changes (for programmatic changes)
        foldingManager.onFoldingChanged = { [weak textView] in
            textView?.forceLayoutRefresh()
        }

        // Initial analysis of text (only for non-large files)
        foldingManager.analyzeText(text)
    }

    public func updateNSView(_ textView: TextView, context: Context) {
        context.coordinator.parent = self
        let coordinator = context.coordinator

        // Apply configuration changes first (includes background color)
        applyConfiguration(to: textView)

        // Update theme colors only when theme or font size actually changes
        // This prevents syntax highlighting re-evaluation on every cursor move
        let currentTheme = configuration.theme
        let currentFontSize = configuration.fontSize
        if currentTheme != coordinator.lastSyncedTheme || currentFontSize != coordinator.lastSyncedFontSize {
            coordinator.lastSyncedTheme = currentTheme
            coordinator.lastSyncedFontSize = currentFontSize
            let theme = KeystoneRunestoneThemeMac(configuration: configuration)
            textView.theme = theme
        }

        // Handle language changes - update syntax highlighting when language changes
        if language != coordinator.lastSyncedLanguage {
            coordinator.lastSyncedLanguage = language
            if let tsLanguage = language.treeSitterLanguage {
                let languageMode = TreeSitterLanguageMode(language: tsLanguage, languageProvider: KeystoneLanguageProvider.shared)
                textView.setLanguageMode(languageMode) { finished in
                    // Only redraw if parsing finished and mode is still current
                    if finished {
                        textView.redisplayVisibleLines()
                    }
                }
            } else {
                textView.setLanguageMode(PlainTextLanguageMode()) { finished in
                    if finished {
                        textView.redisplayVisibleLines()
                    }
                }
            }
        }

        // Handle external text changes (file loads)
        if textView.text != text && !coordinator.isUpdatingText && text != coordinator.lastSyncedText {
            // Queue the pending text update - will be applied when safe
            let pendingTheme = KeystoneRunestoneThemeMac(configuration: configuration)
            coordinator.pendingTextUpdate = (text: text, language: language.treeSitterLanguage, theme: pendingTheme)

            // Try to apply immediately
            DispatchQueue.main.async {
                coordinator.applyPendingTextUpdate()
            }
        }

        // Update cursor position if it changed externally (e.g., from jump to line)
        if coordinator.pendingTextUpdate == nil && !coordinator.isUpdatingCursor && !coordinator.isUpdatingText {
            let expectedRange = NSRange(location: cursorPosition.offset, length: cursorPosition.selectionLength)
            let currentRange = textView.selectedRange

            // Check if this is a genuine external change (not from the text view itself)
            let isExternalChange = cursorPosition != coordinator.lastSyncedCursorPosition

            if isExternalChange && currentRange != expectedRange {
                coordinator.isUpdatingCursor = true
                coordinator.lastSyncedCursorPosition = cursorPosition
                textView.selectedRange = expectedRange

                // Handle scroll to cursor (for find/replace and tail follow - center vertically)
                if scrollToCursor {
                    DispatchQueue.main.async {
                        self.scrollToCursor = false
                    }
                    textView.scrollRangeToVisible(expectedRange, centerVertically: true)
                }
                coordinator.isUpdatingCursor = false
            } else if scrollToCursor {
                // Just scroll, no cursor update needed (for find/replace and tail follow - center vertically)
                DispatchQueue.main.async {
                    self.scrollToCursor = false
                }
                textView.scrollRangeToVisible(currentRange, centerVertically: true)
            }
        } else if scrollToCursor {
            // Handle scroll to cursor when there's a pending update (for find/replace - center vertically)
            DispatchQueue.main.async {
                self.scrollToCursor = false
                let range = NSRange(location: self.cursorPosition.offset, length: self.cursorPosition.selectionLength)
                textView.scrollRangeToVisible(range, centerVertically: true)
            }
        }

        // Update search match highlighting
        coordinator.updateSearchHighlights(textView: textView, searchMatches: searchMatches, currentMatchIndex: currentMatchIndex)

        // Defer bracket matching update
        DispatchQueue.main.async {
            coordinator.updateBracketMatch(textView: textView)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyConfiguration(to textView: TextView) {
        // Background color from theme
        textView.editorBackgroundColor = NSColor(configuration.theme.background)

        // Appearance settings
        textView.showLineNumbers = configuration.showLineNumbers
        textView.showCodeFolding = configuration.showCodeFolding
        textView.lineHeightMultiplier = configuration.lineHeightMultiplier
        textView.isLineWrappingEnabled = configuration.lineWrapping

        // Line selection highlighting
        if configuration.highlightCurrentLine {
            textView.lineSelectionDisplayType = .line
        } else {
            textView.lineSelectionDisplayType = .disabled
        }

        // Invisible characters
        let showInvisibles = configuration.showInvisibleCharacters
        textView.showTabs = showInvisibles
        textView.showSpaces = showInvisibles
        textView.showLineBreaks = showInvisibles

        // Indentation
        switch configuration.indentation.type {
        case .tabs:
            textView.indentStrategy = .tab(length: configuration.indentation.width)
        case .spaces:
            textView.indentStrategy = .space(length: configuration.indentation.width)
        }

        // Character pairs
        if configuration.autoInsertPairs {
            textView.characterPairs = [
                BasicCharacterPair(leading: "(", trailing: ")"),
                BasicCharacterPair(leading: "[", trailing: "]"),
                BasicCharacterPair(leading: "{", trailing: "}"),
                BasicCharacterPair(leading: "\"", trailing: "\""),
                BasicCharacterPair(leading: "'", trailing: "'"),
                BasicCharacterPair(leading: "`", trailing: "`")
            ]
            textView.characterPairTrailingComponentDeletionMode = .disabled
        } else {
            textView.characterPairs = []
        }

        // Line ending
        textView.lineEndings = configuration.lineEnding
    }

    private func setupUndoController(textView: TextView, context: Context) {
        guard let undoController = undoController else { return }

        let coordinator = context.coordinator

        undoController.undoAction = { [weak textView, weak coordinator] in
            textView?.textUndoManager.undo()
            coordinator?.syncTextNow()
        }

        undoController.redoAction = { [weak textView, weak coordinator] in
            textView?.textUndoManager.redo()
            coordinator?.syncTextNow()
        }

        undoController.checkUndoState = { [weak textView] in
            (canUndo: textView?.textUndoManager.canUndo ?? false,
             canRedo: textView?.textUndoManager.canRedo ?? false)
        }

        undoController.replaceTextAction = { [weak textView] range, replacementText in
            guard let textView = textView else { return nil }
            guard range.location + range.length <= textView.text.count else { return nil }

            // Use the replace method which properly registers with the undo manager
            textView.replace(range, withText: replacementText)
            return textView.text
        }

        undoController.replaceAllAction = { [weak textView] newText in
            guard let textView = textView else { return nil }
            textView.replaceAll(with: newText)
            return textView.text
        }

        undoController.beginUndoGroupingAction = { [weak textView] in
            textView?.textUndoManager.beginUndoGrouping()
        }

        undoController.endUndoGroupingAction = { [weak textView] in
            textView?.textUndoManager.endUndoGrouping()
        }

        undoController.startUpdating()
    }

    // MARK: - Coordinator

    @MainActor public class Coordinator: NSObject, TextViewDelegate {
        var parent: KeystoneTextView
        weak var textView: TextView?
        var isUpdatingText = false
        var isUpdatingCursor = false
        var lastSyncedText: String = ""
        var lastSyncedCursorPosition: CursorPosition?
        var lastSyncedLanguage: KeystoneLanguage?
        var lastSyncedTheme: KeystoneTheme
        var lastSyncedFontSize: CGFloat
        private var highlightedRanges: [HighlightedRange] = []
        let codeFoldingManager = CodeFoldingManager()
        private var foldingAnalysisWorkItem: DispatchWorkItem?
        private var cursorUpdateWorkItem: DispatchWorkItem?

        /// Pending text update to apply when safe
        var pendingTextUpdate: (text: String, language: TreeSitterLanguage?, theme: KeystoneRunestoneThemeMac)?

        init(_ parent: KeystoneTextView) {
            self.parent = parent
            self.lastSyncedText = parent.text
            self.lastSyncedCursorPosition = parent.cursorPosition
            self.lastSyncedLanguage = parent.language
            self.lastSyncedTheme = parent.configuration.theme
            self.lastSyncedFontSize = parent.configuration.fontSize
            super.init()
        }

        func syncTextNow() {
            guard let textView = textView, !isUpdatingText else { return }
            isUpdatingText = true
            let currentText = textView.text
            parent.text = currentText
            lastSyncedText = currentText
            isUpdatingText = false
        }

        /// Apply pending text update safely
        func applyPendingTextUpdate() {
            guard let pending = pendingTextUpdate, let textView = textView else { return }

            // Clear the pending update first
            pendingTextUpdate = nil

            // Double-check that we still need to update
            guard textView.text != pending.text else {
                lastSyncedText = pending.text
                return
            }

            isUpdatingText = true

            if let language = pending.language {
                // Check if this is a significant change (like file load)
                let isSignificantChange = abs(textView.text.count - pending.text.count) > pending.text.count / 2
                    || textView.text.isEmpty
                    || pending.text.isEmpty

                if isSignificantChange {
                    // Major change - use setState
                    let state = TextViewState(
                        text: pending.text,
                        theme: pending.theme,
                        language: language,
                        languageProvider: KeystoneLanguageProvider.shared
                    )
                    textView.setState(state)
                } else {
                    // Minor change - preserve undo
                    textView.setTextPreservingUndo(pending.text)
                    textView.theme = pending.theme
                }
            } else {
                textView.setTextPreservingUndo(pending.text)
            }

            lastSyncedText = pending.text
            isUpdatingText = false
        }

        // MARK: - Search Highlighting

        func updateSearchHighlights(textView: TextView, searchMatches: [SearchMatch], currentMatchIndex: Int) {
            guard !searchMatches.isEmpty else {
                highlightedRanges.removeAll()
                textView.highlightedRanges = []
                return
            }

            var newHighlights: [HighlightedRange] = []

            for (index, match) in searchMatches.enumerated() {
                let isCurrentMatch = index == currentMatchIndex

                let backgroundColor: NSColor
                if isCurrentMatch {
                    backgroundColor = NSColor.systemOrange.withAlphaComponent(0.6)
                } else {
                    backgroundColor = NSColor.systemYellow.withAlphaComponent(0.4)
                }

                let text = textView.text
                let nsRange = NSRange(match.range, in: text)

                let highlightedRange = HighlightedRange(
                    range: nsRange,
                    color: backgroundColor,
                    cornerRadius: 2
                )
                newHighlights.append(highlightedRange)
            }

            highlightedRanges = newHighlights
            textView.highlightedRanges = newHighlights
        }

        // MARK: - Bracket Matching

        func updateBracketMatch(textView: TextView) {
            let offset = textView.selectedRange.location
            let text = textView.text

            if let match = BracketMatcher.findMatch(in: text, at: offset) {
                parent.matchingBracket = match
            } else if offset > 0, let match = BracketMatcher.findMatch(in: text, at: offset - 1) {
                parent.matchingBracket = match
            } else {
                parent.matchingBracket = nil
            }
        }

        // MARK: - TextViewDelegate

        public func textViewDidChange(_ textView: TextView) {
            guard !isUpdatingText else { return }

            isUpdatingText = true
            let currentText = textView.text
            parent.text = currentText
            lastSyncedText = currentText
            isUpdatingText = false

            // Debounced code folding analysis
            foldingAnalysisWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.codeFoldingManager.analyzeText(currentText)
            }
            foldingAnalysisWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
        }

        public func textViewDidChangeSelection(_ textView: TextView) {
            guard !isUpdatingText && !isUpdatingCursor else { return }

            let selectedRange = textView.selectedRange
            let text = textView.text
            let newPosition = CursorPosition.from(
                offset: selectedRange.location,
                in: text,
                selectionLength: selectedRange.length
            )

            // Only update if actually changed
            guard newPosition != lastSyncedCursorPosition else { return }

            // Cancel any pending cursor update
            cursorUpdateWorkItem?.cancel()

            // Debounce cursor updates to avoid multiple updates per frame
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.isUpdatingText && !self.isUpdatingCursor else { return }
                self.isUpdatingCursor = true
                self.lastSyncedCursorPosition = newPosition
                self.parent.cursorPosition = newPosition
                self.isUpdatingCursor = false
            }
            cursorUpdateWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)

            updateBracketMatch(textView: textView)
        }

        public func textView(_ textView: TextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            return true
        }

        public func textViewDidTimeoutParsing(_ textView: TextView) {
            parent.onParsingTimeout?()
        }
    }
}

// MARK: - BasicCharacterPair (macOS)

struct BasicCharacterPair: CharacterPair {
    let leading: String
    let trailing: String
}

// MARK: - KeystoneRunestoneThemeMac

/// Adapts KeystoneTheme colors to Runestone's Theme protocol for macOS.
class KeystoneRunestoneThemeMac: Theme {
    private let _fontSize: CGFloat
    private let _textColor: NSColor
    private let _backgroundColor: NSColor
    private let _gutterBackgroundColor: NSColor
    private let _lineNumberColor: NSColor
    private let _currentLineHighlight: NSColor
    private let _invisibleCharacter: NSColor
    private let _keywordColor: NSColor
    private let _stringColor: NSColor
    private let _commentColor: NSColor
    private let _typeColor: NSColor
    private let _functionColor: NSColor
    private let _numberColor: NSColor
    private let _operatorColor: NSColor
    private let _propertyColor: NSColor
    private let _attributeColor: NSColor
    private let _tagColor: NSColor

    @MainActor
    init(configuration: KeystoneConfiguration) {
        let theme = configuration.theme
        _fontSize = configuration.fontSize
        _textColor = NSColor(theme.text)
        _backgroundColor = NSColor(theme.background)
        _gutterBackgroundColor = NSColor(theme.gutterBackground)
        _lineNumberColor = NSColor(theme.lineNumber)
        _currentLineHighlight = NSColor(theme.currentLineHighlight)
        _invisibleCharacter = NSColor(theme.invisibleCharacter)
        _keywordColor = NSColor(theme.keyword)
        _stringColor = NSColor(theme.string)
        _commentColor = NSColor(theme.comment)
        _typeColor = NSColor(theme.type)
        _functionColor = NSColor(theme.function)
        _numberColor = NSColor(theme.number)
        _operatorColor = NSColor(theme.operator)
        _propertyColor = NSColor(theme.property)
        _attributeColor = NSColor(theme.attribute)
        _tagColor = NSColor(theme.tag)
    }

    var font: NSFont {
        .monospacedSystemFont(ofSize: _fontSize, weight: .regular)
    }

    var textColor: NSColor {
        _textColor
    }

    var gutterBackgroundColor: NSColor {
        _gutterBackgroundColor
    }

    var gutterHairlineColor: NSColor {
        NSColor.separatorColor
    }

    var lineNumberColor: NSColor {
        _lineNumberColor
    }

    var lineNumberFont: NSFont {
        .monospacedSystemFont(ofSize: _fontSize * 0.85, weight: .regular)
    }

    var selectedLineBackgroundColor: NSColor {
        _currentLineHighlight
    }

    var selectedLinesLineNumberColor: NSColor {
        _textColor
    }

    var selectedLinesGutterBackgroundColor: NSColor {
        _currentLineHighlight
    }

    var invisibleCharactersColor: NSColor {
        _invisibleCharacter
    }

    var pageGuideHairlineColor: NSColor {
        NSColor.separatorColor
    }

    var pageGuideBackgroundColor: NSColor {
        _backgroundColor.withAlphaComponent(0.5)
    }

    var markedTextBackgroundColor: NSColor {
        NSColor.systemYellow.withAlphaComponent(0.3)
    }

    func textColor(for rawHighlightName: String) -> NSColor? {
        guard let highlightName = HighlightName(rawHighlightName) else {
            return nil
        }
        switch highlightName {
        case .attribute:
            return _attributeColor
        case .boolean, .constant, .constantBuiltin, .constantCharacter, .symbol:
            return _numberColor
        case .character:
            return _stringColor
        case .comment:
            return _commentColor
        case .conditional, .include, .keyword, .repeat:
            return _keywordColor
        case .constructor, .type, .module, .namespace:
            return _typeColor
        case .delimiter, .punctuation:
            return _textColor
        case .escape:
            return _stringColor
        case .field, .parameter, .property, .variableBuiltin:
            return _propertyColor
        case .float, .number:
            return _numberColor
        case .function, .method:
            return _functionColor
        case .label, .tag:
            return _tagColor
        case .operator:
            return _operatorColor
        case .string:
            return _stringColor
        case .text, .variable:
            return _textColor
        }
    }

    func fontTraits(for rawHighlightName: String) -> FontTraits {
        guard let highlightName = HighlightName(rawHighlightName) else {
            return []
        }
        switch highlightName {
        case .keyword:
            return .bold
        case .comment:
            return .italic
        default:
            return []
        }
    }
}

#endif
