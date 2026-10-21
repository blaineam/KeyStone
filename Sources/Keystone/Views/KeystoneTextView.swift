//
//  KeystoneTextView.swift
//  Keystone
//
//  SwiftUI wrapper for Runestone's high-performance TextView.
//  Provides the same interface as main branch's KeystoneTextView.
//

import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit

/// A SwiftUI wrapper for Runestone's high-performance TextView.
/// Provides the same interface as the main branch's KeystoneTextView.
public struct KeystoneTextView: UIViewRepresentable {
    let document: KeystoneDocument
    let language: KeystoneLanguage
    @ObservedObject var configuration: KeystoneConfiguration
    @Binding var cursorPosition: CursorPosition
    @Binding var scrollOffset: CGFloat
    @Binding var matchingBracket: BracketMatch?
    @Binding var scrollToCursor: Bool
    var searchMatches: [SearchMatch]
    var currentMatchIndex: Int
    var undoController: UndoController?
    var actions: EditorActions?
    /// A pending inline-assist proposal, highlighted until accepted or rejected.
    var proposedRange: NSRange?
    var onParsingTimeout: (() -> Void)?

    public init(
        document: KeystoneDocument,
        language: KeystoneLanguage,
        configuration: KeystoneConfiguration,
        cursorPosition: Binding<CursorPosition>,
        scrollOffset: Binding<CGFloat>,
        matchingBracket: Binding<BracketMatch?>,
        scrollToCursor: Binding<Bool>,
        searchMatches: [SearchMatch] = [],
        currentMatchIndex: Int = 0,
        undoController: UndoController? = nil,
        actions: EditorActions? = nil,
        proposedRange: NSRange? = nil,
        onParsingTimeout: (() -> Void)? = nil
    ) {
        self.document = document
        self.language = language
        self._configuration = ObservedObject(wrappedValue: configuration)
        self._cursorPosition = cursorPosition
        self._scrollOffset = scrollOffset
        self._matchingBracket = matchingBracket
        self._scrollToCursor = scrollToCursor
        self.searchMatches = searchMatches
        self.currentMatchIndex = currentMatchIndex
        self.undoController = undoController
        self.actions = actions
        self.proposedRange = proposedRange
        self.onParsingTimeout = onParsingTimeout
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
                text: document.text,
                theme: theme,
                language: tsLanguage,
                languageProvider: KeystoneLanguageProvider.shared
            )
            textView.setState(state)
        } else {
            // No tree-sitter language, just set the text with theme
            let theme = KeystoneRunestoneTheme(configuration: configuration)
            textView.theme = theme
            textView.text = document.text
        }

        // Set up undo controller
        setupUndoController(textView: textView, context: context)

        // Set up code folding
        setupCodeFolding(textView: textView, context: context)
        setupActions(textView: textView, context: context)

        context.coordinator.textView = textView
        document.attach(textView) { [weak coordinator = context.coordinator] newText, preservingUndo in
            coordinator?.applyText(newText, preservingUndo: preservingUndo)
        }
        context.coordinator.observeChangeMarkers(of: document, on: textView)

        return textView
    }

    private func setupActions(textView: TextView, context: Context) {
        guard let actions = actions else { return }
        let foldingManager = context.coordinator.codeFoldingManager
        actions.foldAll = { [weak foldingManager, weak textView] in
            foldingManager?.foldAll()
            textView?.forceLayoutRefresh()
        }
        actions.unfoldAll = { [weak foldingManager, weak textView] in
            foldingManager?.unfoldAll()
            textView?.forceLayoutRefresh()
        }
        actions.selectNextOccurrence = { [weak textView] in textView?.selectNextOccurrence() }
        actions.selectAllOccurrences = { [weak textView] in textView?.selectAllOccurrences() }
        actions.addCaretAbove = { [weak textView] in textView?.addCaretAbove() }
        actions.addCaretBelow = { [weak textView] in textView?.addCaretBelow() }
        actions.collapseSelections = { [weak textView] in textView?.collapseSelections() }
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

        // Languages with a syntax tree get fold regions from the parser (delivered when
        // the manager was attached above, or when a background parse lands). The text
        // heuristics are only for plain text.
        if language.treeSitterLanguage == nil {
            let initialText = document.text
            if initialText.utf16.count > KeystoneConfiguration.defaultLargeFileThreshold {
                foldingManager.analyzeTextInBackground(initialText)
            } else {
                foldingManager.analyzeText(initialText)
            }
        }
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
        if currentTheme != coordinator.lastSyncedTheme || currentFontSize != coordinator.lastSyncedFontSize || configuration.colorizeBracketPairs != coordinator.lastSyncedBracketColors {
            coordinator.lastSyncedTheme = currentTheme
            coordinator.lastSyncedFontSize = currentFontSize
            coordinator.lastSyncedBracketColors = configuration.colorizeBracketPairs
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

        // Update cursor position if it changed externally (e.g., from find navigation)
        // Only update if not currently editing to avoid fighting with user input
        // MUST defer to async to avoid RedBlackTree crash - setting selectedRange
        // triggers keyboard tokenizer which queries line structure before tree is ready
        if !coordinator.isUpdatingCursor && !coordinator.isUpdatingText {
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
        coordinator.updateProposalHighlight(textView: textView, range: proposedRange)

        // Defer bracket matching update to avoid state modification during view update
        DispatchQueue.main.async {
            coordinator.updateBracketMatch(textView: textView)
        }

        // Track scroll offset
        coordinator.lastScrollOffset = textView.contentOffset.y
    }

    public static func dismantleUIView(_ textView: TextView, coordinator: Coordinator) {
        coordinator.parent.document.detach(textView)
    }

    public static func dismantleNSView(_ textView: TextView, coordinator: Coordinator) {
        coordinator.parent.document.detach(textView)
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
        textView.showIndentGuides = configuration.showIndentGuides
        textView.showChangeMarkers = configuration.showChangeMarkers
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

        undoController.undoAction = { [weak textView] in
            textView?.undoManager?.undo()
        }

        undoController.redoAction = { [weak textView] in
            textView?.undoManager?.redo()
        }

        undoController.checkUndoState = { [weak textView] in
            (canUndo: textView?.undoManager?.canUndo ?? false,
             canRedo: textView?.undoManager?.canRedo ?? false)
        }

        undoController.replaceTextAction = { [weak textView] range, replacementText in
            guard let textView = textView else { return false }
            guard range.location + range.length <= textView.backingString.length else { return false }

            // Use Runestone's replace method to properly update internal state
            textView.replace(range, withText: replacementText)

            return true
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
        var lastSyncedCursorPosition: CursorPosition?
        var lastSyncedLanguage: KeystoneLanguage?
        var lastSyncedTheme: KeystoneTheme
        var lastSyncedFontSize: CGFloat
        var lastSyncedBracketColors = true
        /// Matching-bracket highlights, merged with the search highlights.
        private var bracketHighlights: [HighlightedRange] = []
        private var proposalHighlights: [HighlightedRange] = []
        private var changeMarkersCancellable: AnyCancellable?
        private var highlightedRanges: [HighlightedRange] = []
        let codeFoldingManager = CodeFoldingManager()
        private var foldingAnalysisWorkItem: DispatchWorkItem?
        /// Debounce timer for cursor position updates to prevent rapid-fire binding updates
        private var cursorUpdateWorkItem: DispatchWorkItem?
        /// Range of the edit the text view just reported; consumed by textViewDidChange.
        var pendingEdit: (range: NSRange, replacementLength: Int)?


        init(_ parent: KeystoneTextView) {
            self.parent = parent
            self.lastSyncedLanguage = parent.language
            self.lastSyncedTheme = parent.configuration.theme
            self.lastSyncedFontSize = parent.configuration.fontSize
            super.init()
        }

        /// Replaces the whole text on behalf of the document (file load, revert, conversion).
        func applyText(_ newText: String, preservingUndo: Bool) {
            guard let textView = textView, textView.text != newText else { return }
            isUpdatingText = true
            // Keep the tokenizer from querying line boundaries mid-replacement.
            textView.isUpdatingText = true
            defer {
                textView.isUpdatingText = false
                isUpdatingText = false
            }
            if preservingUndo {
                textView.setTextPreservingUndo(newText)
            } else if let language = parent.language.treeSitterLanguage {
                let state = TextViewState(
                    text: newText,
                    theme: KeystoneRunestoneTheme(configuration: parent.configuration),
                    language: language,
                    languageProvider: KeystoneLanguageProvider.shared
                )
                textView.setState(state)
            } else {
                textView.text = newText
            }
        }

        // MARK: - Search Highlighting

        func updateSearchHighlights(textView: TextView, searchMatches: [SearchMatch], currentMatchIndex: Int) {
            guard !searchMatches.isEmpty else {
                // Clear all highlights
                highlightedRanges.removeAll()
                applyHighlights(to: textView)
                return
            }

            // Build new highlights array
            var newHighlights: [HighlightedRange] = []
            let text = textView.text

            for (index, match) in searchMatches.enumerated() {
                let isCurrentMatch = index == currentMatchIndex

                // Use different colors for current match vs other matches
                let backgroundColor: UIColor
                if isCurrentMatch {
                    backgroundColor = UIColor.systemOrange.withAlphaComponent(0.6)
                } else {
                    backgroundColor = UIColor.systemYellow.withAlphaComponent(0.4)
                }

                // Matches can be stale — the document may have been edited
                // (e.g. lines deleted) since the search ran. Skip any whose
                // offsets no longer fit instead of trapping on conversion.
                guard let nsRange = match.resolvedNSRange(in: text) else { continue }

                let highlightedRange = HighlightedRange(
                    range: nsRange,
                    color: backgroundColor,
                    cornerRadius: 2
                )
                newHighlights.append(highlightedRange)
            }

            // Update the text view's highlighted ranges
            highlightedRanges = newHighlights
            applyHighlights(to: textView)
        }

        // MARK: - Bracket Matching

        func updateBracketMatch(textView: TextView) {
            var match: BracketMatch?
            if parent.configuration.highlightMatchingBrackets {
                let offset = textView.selectedRange.location
                let text = textView.backingString
                match = BracketMatcher.findMatch(inNSString: text, at: offset)
                if match == nil, offset > 0 {
                    match = BracketMatcher.findMatch(inNSString: text, at: offset - 1)
                }
            }
            if parent.matchingBracket != match {
                parent.matchingBracket = match
            }
            let color = HighlightColor(parent.configuration.theme.matchingBracket)
            let newHighlights = match.map { found in
                [
                    HighlightedRange(id: "bracket-open", range: NSRange(location: found.openPosition, length: 1), color: color, cornerRadius: 2),
                    HighlightedRange(id: "bracket-close", range: NSRange(location: found.closePosition, length: 1), color: color, cornerRadius: 2),
                ]
            } ?? []
            if newHighlights.map(\.range) != bracketHighlights.map(\.range) {
                bracketHighlights = newHighlights
                applyHighlights(to: textView)
            }
        }

        /// Search highlights plus the matching-bracket pair and any pending proposal.
        private func applyHighlights(to textView: TextView) {
            textView.highlightedRanges = highlightedRanges + bracketHighlights + proposalHighlights
        }

        func updateProposalHighlight(textView: TextView, range: NSRange?) {
            let newHighlights = range.map { [HighlightedRange(id: "proposal", range: $0, color: HighlightColor.systemGreen.withAlphaComponent(0.22), cornerRadius: 3)] } ?? []
            if newHighlights.map(\.range) != proposalHighlights.map(\.range) {
                proposalHighlights = newHighlights
                applyHighlights(to: textView)
            }
        }

        /// Keeps the gutter's change markers in step with the document's diff.
        func observeChangeMarkers(of document: KeystoneDocument, on textView: TextView) {
            textView.changeMarkers = document.changeMarkers
            changeMarkersCancellable = document.$changeMarkers.sink { [weak textView] markers in
                textView?.changeMarkers = markers
            }
        }

        // MARK: - TextViewDelegate

        public func textView(_ textView: TextView, didReplaceTextIn range: NSRange, replacementLength: Int) {
            pendingEdit = (range, replacementLength)
        }

        public func textViewDidChange(_ textView: TextView) {
            let edit = pendingEdit
            pendingEdit = nil
            guard !isUpdatingText else { return }

            parent.document.noteEdit(range: edit?.range, replacementLength: edit?.replacementLength)

            // Debounced code folding analysis for plain text - refreshes 2.5s after typing
            // pauses; the snapshot is taken when the work item fires, not per keystroke.
            // Syntax-tree folds come from the parser instead.
            foldingAnalysisWorkItem?.cancel()
            guard !codeFoldingManager.usesSyntaxTreeRegions else { return }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, let textView = self.textView else { return }
                if textView.backingString.length > KeystoneConfiguration.defaultLargeFileThreshold {
                    self.codeFoldingManager.analyzeTextInBackground(textView.text)
                } else {
                    self.codeFoldingManager.analyzeText(textView.text)
                }
            }
            foldingAnalysisWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
        }

        public func textViewDidChangeSelection(_ textView: TextView) {
            // Skip updating cursor binding during multi-step text operations or external updates
            // This prevents SwiftUI state inconsistencies and feedback loops
            guard !isUpdatingText && !isUpdatingCursor && !textView.isUpdatingText else { return }

            let newPosition = CursorPosition.from(textView: textView)

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
    private let _bracketPairColors: [UIColor]
    private let _colorizesBracketPairs: Bool

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
        _bracketPairColors = theme.bracketPairColors.map { UIColor($0) }
        _colorizesBracketPairs = configuration.colorizeBracketPairs
    }

    var font: UIFont {
        .monospacedSystemFont(ofSize: _fontSize, weight: .regular)
    }

    var textColor: UIColor {
        _textColor
    }

    func bracketPairColor(depth: Int) -> UIColor? {
        guard _colorizesBracketPairs, !_bracketPairColors.isEmpty else { return nil }
        return _bracketPairColors[depth % _bracketPairColors.count]
    }

    var colorizesBracketPairs: Bool { _colorizesBracketPairs }

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
    let document: KeystoneDocument
    let language: KeystoneLanguage
    @ObservedObject var configuration: KeystoneConfiguration
    @Binding var cursorPosition: CursorPosition
    @Binding var scrollOffset: CGFloat
    @Binding var matchingBracket: BracketMatch?
    @Binding var scrollToCursor: Bool
    var searchMatches: [SearchMatch]
    var currentMatchIndex: Int
    var undoController: UndoController?
    var actions: EditorActions?
    /// A pending inline-assist proposal, highlighted until accepted or rejected.
    var proposedRange: NSRange?
    /// Called when TreeSitter parsing times out (default 30 seconds).
    var onParsingTimeout: (() -> Void)?

    public init(
        document: KeystoneDocument,
        language: KeystoneLanguage,
        configuration: KeystoneConfiguration,
        cursorPosition: Binding<CursorPosition>,
        scrollOffset: Binding<CGFloat>,
        matchingBracket: Binding<BracketMatch?>,
        scrollToCursor: Binding<Bool>,
        searchMatches: [SearchMatch] = [],
        currentMatchIndex: Int = 0,
        undoController: UndoController? = nil,
        actions: EditorActions? = nil,
        proposedRange: NSRange? = nil,
        onParsingTimeout: (() -> Void)? = nil
    ) {
        self.document = document
        self.language = language
        self._configuration = ObservedObject(wrappedValue: configuration)
        self._cursorPosition = cursorPosition
        self._scrollOffset = scrollOffset
        self._matchingBracket = matchingBracket
        self._scrollToCursor = scrollToCursor
        self.searchMatches = searchMatches
        self.currentMatchIndex = currentMatchIndex
        self.undoController = undoController
        self.actions = actions
        self.proposedRange = proposedRange
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
                text: document.text,
                theme: theme,
                language: tsLanguage,
                languageProvider: KeystoneLanguageProvider.shared
            )
            textView.setState(state)
        } else {
            // No tree-sitter language, just set the text with theme
            let theme = KeystoneRunestoneThemeMac(configuration: configuration)
            textView.theme = theme
            textView.text = document.text
        }

        // Set up undo controller
        setupUndoController(textView: textView, context: context)

        // Set up code folding
        setupCodeFolding(textView: textView, context: context)
        setupActions(textView: textView, context: context)

        context.coordinator.textView = textView
        document.attach(textView) { [weak coordinator = context.coordinator] newText, preservingUndo in
            coordinator?.applyText(newText, preservingUndo: preservingUndo)
        }
        context.coordinator.observeChangeMarkers(of: document, on: textView)

        return textView
    }

    private func setupActions(textView: TextView, context: Context) {
        guard let actions = actions else { return }
        let foldingManager = context.coordinator.codeFoldingManager
        actions.foldAll = { [weak foldingManager, weak textView] in
            foldingManager?.foldAll()
            textView?.forceLayoutRefresh()
        }
        actions.unfoldAll = { [weak foldingManager, weak textView] in
            foldingManager?.unfoldAll()
            textView?.forceLayoutRefresh()
        }
        actions.selectNextOccurrence = { [weak textView] in textView?.selectNextOccurrence() }
        actions.selectAllOccurrences = { [weak textView] in textView?.selectAllOccurrences() }
        actions.addCaretAbove = { [weak textView] in textView?.addCaretAbove() }
        actions.addCaretBelow = { [weak textView] in textView?.addCaretBelow() }
        actions.collapseSelections = { [weak textView] in textView?.collapseSelections() }
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

        // Languages with a syntax tree get fold regions from the parser (delivered when
        // the manager was attached above, or when a background parse lands). The text
        // heuristics are only for plain text.
        if language.treeSitterLanguage == nil {
            let initialText = document.text
            if initialText.utf16.count > KeystoneConfiguration.defaultLargeFileThreshold {
                foldingManager.analyzeTextInBackground(initialText)
            } else {
                foldingManager.analyzeText(initialText)
            }
        }
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
        if currentTheme != coordinator.lastSyncedTheme || currentFontSize != coordinator.lastSyncedFontSize || configuration.colorizeBracketPairs != coordinator.lastSyncedBracketColors {
            coordinator.lastSyncedTheme = currentTheme
            coordinator.lastSyncedFontSize = currentFontSize
            coordinator.lastSyncedBracketColors = configuration.colorizeBracketPairs
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

        // Update cursor position if it changed externally (e.g., from jump to line)
        if !coordinator.isUpdatingCursor && !coordinator.isUpdatingText {
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
        coordinator.updateProposalHighlight(textView: textView, range: proposedRange)

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
        textView.showIndentGuides = configuration.showIndentGuides
        textView.showChangeMarkers = configuration.showChangeMarkers
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

        undoController.undoAction = { [weak textView] in
            textView?.textUndoManager.undo()
        }

        undoController.redoAction = { [weak textView] in
            textView?.textUndoManager.redo()
        }

        undoController.checkUndoState = { [weak textView] in
            (canUndo: textView?.textUndoManager.canUndo ?? false,
             canRedo: textView?.textUndoManager.canRedo ?? false)
        }

        undoController.replaceTextAction = { [weak textView] range, replacementText in
            guard let textView = textView else { return false }
            guard range.location + range.length <= textView.backingString.length else { return false }

            // Use the replace method which properly registers with the undo manager
            textView.replace(range, withText: replacementText)
            return true
        }

        undoController.replaceAllAction = { [weak textView] newText in
            guard let textView = textView else { return false }
            textView.replaceAll(with: newText)
            return true
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
        var lastSyncedCursorPosition: CursorPosition?
        var lastSyncedLanguage: KeystoneLanguage?
        var lastSyncedTheme: KeystoneTheme
        var lastSyncedFontSize: CGFloat
        var lastSyncedBracketColors = true
        /// Matching-bracket highlights, merged with the search highlights.
        private var bracketHighlights: [HighlightedRange] = []
        private var proposalHighlights: [HighlightedRange] = []
        private var changeMarkersCancellable: AnyCancellable?
        private var highlightedRanges: [HighlightedRange] = []
        let codeFoldingManager = CodeFoldingManager()
        private var foldingAnalysisWorkItem: DispatchWorkItem?
        private var cursorUpdateWorkItem: DispatchWorkItem?
        /// Range of the edit the text view just reported; consumed by textViewDidChange.
        var pendingEdit: (range: NSRange, replacementLength: Int)?


        init(_ parent: KeystoneTextView) {
            self.parent = parent
            self.lastSyncedCursorPosition = parent.cursorPosition
            self.lastSyncedLanguage = parent.language
            self.lastSyncedTheme = parent.configuration.theme
            self.lastSyncedFontSize = parent.configuration.fontSize
            super.init()
        }

        /// Replaces the whole text on behalf of the document (file load, revert, conversion).
        func applyText(_ newText: String, preservingUndo: Bool) {
            guard let textView = textView, textView.text != newText else { return }
            isUpdatingText = true
            defer { isUpdatingText = false }
            if preservingUndo {
                textView.setTextPreservingUndo(newText)
            } else if let language = parent.language.treeSitterLanguage {
                let state = TextViewState(
                    text: newText,
                    theme: KeystoneRunestoneThemeMac(configuration: parent.configuration),
                    language: language,
                    languageProvider: KeystoneLanguageProvider.shared
                )
                textView.setState(state)
            } else {
                textView.text = newText
            }
        }

        // MARK: - Search Highlighting

        func updateSearchHighlights(textView: TextView, searchMatches: [SearchMatch], currentMatchIndex: Int) {
            guard !searchMatches.isEmpty else {
                highlightedRanges.removeAll()
                applyHighlights(to: textView)
                return
            }

            var newHighlights: [HighlightedRange] = []
            let text = textView.text

            for (index, match) in searchMatches.enumerated() {
                let isCurrentMatch = index == currentMatchIndex

                let backgroundColor: NSColor
                if isCurrentMatch {
                    backgroundColor = NSColor.systemOrange.withAlphaComponent(0.6)
                } else {
                    backgroundColor = NSColor.systemYellow.withAlphaComponent(0.4)
                }

                // Matches can be stale — the document may have been edited
                // (e.g. lines deleted) since the search ran. Skip any whose
                // offsets no longer fit instead of trapping on conversion.
                guard let nsRange = match.resolvedNSRange(in: text) else { continue }

                let highlightedRange = HighlightedRange(
                    range: nsRange,
                    color: backgroundColor,
                    cornerRadius: 2
                )
                newHighlights.append(highlightedRange)
            }

            highlightedRanges = newHighlights
            applyHighlights(to: textView)
        }

        // MARK: - Bracket Matching

        func updateBracketMatch(textView: TextView) {
            var match: BracketMatch?
            if parent.configuration.highlightMatchingBrackets {
                let offset = textView.selectedRange.location
                let text = textView.backingString
                match = BracketMatcher.findMatch(inNSString: text, at: offset)
                if match == nil, offset > 0 {
                    match = BracketMatcher.findMatch(inNSString: text, at: offset - 1)
                }
            }
            if parent.matchingBracket != match {
                parent.matchingBracket = match
            }
            let color = HighlightColor(parent.configuration.theme.matchingBracket)
            let newHighlights = match.map { found in
                [
                    HighlightedRange(id: "bracket-open", range: NSRange(location: found.openPosition, length: 1), color: color, cornerRadius: 2),
                    HighlightedRange(id: "bracket-close", range: NSRange(location: found.closePosition, length: 1), color: color, cornerRadius: 2),
                ]
            } ?? []
            if newHighlights.map(\.range) != bracketHighlights.map(\.range) {
                bracketHighlights = newHighlights
                applyHighlights(to: textView)
            }
        }

        /// Search highlights plus the matching-bracket pair and any pending proposal.
        private func applyHighlights(to textView: TextView) {
            textView.highlightedRanges = highlightedRanges + bracketHighlights + proposalHighlights
        }

        func updateProposalHighlight(textView: TextView, range: NSRange?) {
            let newHighlights = range.map { [HighlightedRange(id: "proposal", range: $0, color: HighlightColor.systemGreen.withAlphaComponent(0.22), cornerRadius: 3)] } ?? []
            if newHighlights.map(\.range) != proposalHighlights.map(\.range) {
                proposalHighlights = newHighlights
                applyHighlights(to: textView)
            }
        }

        /// Keeps the gutter's change markers in step with the document's diff.
        func observeChangeMarkers(of document: KeystoneDocument, on textView: TextView) {
            textView.changeMarkers = document.changeMarkers
            changeMarkersCancellable = document.$changeMarkers.sink { [weak textView] markers in
                textView?.changeMarkers = markers
            }
        }

        // MARK: - TextViewDelegate

        public func textView(_ textView: TextView, didReplaceTextIn range: NSRange, replacementLength: Int) {
            pendingEdit = (range, replacementLength)
        }

        public func textViewDidChange(_ textView: TextView) {
            let edit = pendingEdit
            pendingEdit = nil
            guard !isUpdatingText else { return }

            parent.document.noteEdit(range: edit?.range, replacementLength: edit?.replacementLength)

            // Debounced code folding analysis for plain text - refreshes 2.5s after typing
            // pauses; the snapshot is taken when the work item fires, not per keystroke.
            // Syntax-tree folds come from the parser instead.
            foldingAnalysisWorkItem?.cancel()
            guard !codeFoldingManager.usesSyntaxTreeRegions else { return }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, let textView = self.textView else { return }
                if textView.backingString.length > KeystoneConfiguration.defaultLargeFileThreshold {
                    self.codeFoldingManager.analyzeTextInBackground(textView.text)
                } else {
                    self.codeFoldingManager.analyzeText(textView.text)
                }
            }
            foldingAnalysisWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
        }

        public func textViewDidChangeSelection(_ textView: TextView) {
            guard !isUpdatingText && !isUpdatingCursor else { return }

            let newPosition = CursorPosition.from(textView: textView)

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
    private let _bracketPairColors: [NSColor]
    private let _colorizesBracketPairs: Bool

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
        _bracketPairColors = theme.bracketPairColors.map { NSColor($0) }
        _colorizesBracketPairs = configuration.colorizeBracketPairs
    }

    var font: NSFont {
        .monospacedSystemFont(ofSize: _fontSize, weight: .regular)
    }

    var textColor: NSColor {
        _textColor
    }

    func bracketPairColor(depth: Int) -> NSColor? {
        guard _colorizesBracketPairs, !_bracketPairColors.isEmpty else { return nil }
        return _bracketPairColors[depth % _bracketPairColors.count]
    }

    var colorizesBracketPairs: Bool { _colorizesBracketPairs }

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


extension CursorPosition {
    /// Line/column for the text view's selection via the editor's line index,
    /// O(log lines) instead of scanning the document up to the caret.
    @MainActor
    static func from(textView: TextView) -> CursorPosition {
        let range = textView.selectedRange
        let location = textView.textLocation(at: range.location)
        return CursorPosition(
            line: (location?.lineNumber ?? 0) + 1,
            column: (location?.column ?? 0) + 1,
            selectionLength: range.length,
            offset: range.location
        )
    }
}


