//
//  KeystoneEditor.swift
//  Keystone
//
//  The main code editor view component for SwiftUI.
//

import SwiftUI

/// A full-featured code editor view for SwiftUI.
///
/// KeystoneEditor provides syntax highlighting, line numbers, bracket matching,
/// find/replace, symbol keyboard, and many other features expected in a modern code editor.
///
/// Example usage:
/// ```swift
/// @State private var code = "func hello() {\n    print(\"Hello!\")\n}"
/// @StateObject private var config = KeystoneConfiguration()
/// @StateObject private var findReplace = FindReplaceManager()
///
/// var body: some View {
///     KeystoneEditor(text: $code, language: .swift, configuration: config, findReplaceManager: findReplace)
/// }
/// ```
public struct KeystoneEditor: View {
    // MARK: - Properties

    /// The text content being edited.
    @Binding public var text: String

    /// External language binding (optional - for two-way sync with parent)
    private var externalLanguage: Binding<KeystoneLanguage>?

    /// Internal language state that can always be modified
    @State private var internalLanguage: KeystoneLanguage

    /// The effective language (synced with external if provided)
    private var effectiveLanguage: KeystoneLanguage {
        get { internalLanguage }
    }

    /// The editor configuration.
    @ObservedObject public var configuration: KeystoneConfiguration

    /// Find and replace manager.
    @ObservedObject public var findReplaceManager: FindReplaceManager

    /// Callback when the cursor position changes.
    public var onCursorChange: ((CursorPosition) -> Void)?

    /// Callback when the scroll position changes.
    public var onScrollChange: ((CGFloat) -> Void)?

    /// Callback when text changes.
    public var onTextChange: ((String) -> Void)?

    /// Optional external cursor position binding. When provided, allows external control of cursor position.
    /// Useful for features like "scroll to end" in tail follow mode.
    private var externalCursorPosition: Binding<CursorPosition>?

    /// Optional external scroll-to-cursor binding. When set to true externally, scrolls to cursor and resets.
    /// Useful for tail follow mode to scroll to end after updating cursor position.
    private var externalScrollToCursor: Binding<Bool>?

    /// Whether tail follow is enabled. When provided, shows the follow button in the toolbar.
    private var isTailFollowEnabled: Binding<Bool>?

    /// Callback to toggle tail follow mode.
    public var onToggleTailFollow: (() -> Void)?

    /// Callback when line endings should be converted.
    public var onConvertLineEndings: ((LineEnding) -> Void)?

    /// Callback when indentation should be converted.
    public var onConvertIndentation: ((IndentationSettings) -> Void)?

    /// Controller for undo/redo operations (bridges to native text view's undo manager).
    @StateObject private var undoController = UndoController()

    // MARK: - Internal State

    @State private var internalCursorPosition = CursorPosition()

    /// The effective cursor position (external if provided, otherwise internal)
    private var cursorPosition: Binding<CursorPosition> {
        externalCursorPosition ?? $internalCursorPosition
    }
    @State private var scrollOffset: CGFloat = 0
    @State private var lineCount: Int = 1
    @State private var matchingBracket: BracketMatch?

    @State private var internalScrollToCursor = false
    /// The effective scroll-to-cursor binding (external if provided, otherwise internal)
    private var scrollToCursor: Binding<Bool> {
        externalScrollToCursor ?? $internalScrollToCursor
    }
    private var externalShowGoToLine: Binding<Bool>?
    @State private var internalShowGoToLine = false
    private var showGoToLine: Binding<Bool> {
        externalShowGoToLine ?? $internalShowGoToLine
    }
    @State private var goToLineText = ""
    @State private var showSettings = false

    #if os(iOS)
    /// Tracks whether the find/replace search field is focused (for symbol keyboard insertion)
    @State private var isSearchFieldFocused = false
    #endif

    // MARK: - Environment

    @FocusState private var isEditorFocused: Bool

    // MARK: - Initialization

    /// Creates a new code editor with a language binding for two-way sync.
    /// - Parameters:
    ///   - text: Binding to the text content.
    ///   - language: Binding to the programming language for syntax highlighting.
    ///   - configuration: The editor configuration.
    ///   - findReplaceManager: The find/replace manager.
    ///   - cursorPosition: Optional binding for external cursor position control (e.g., for scroll-to-end).
    ///   - scrollToCursor: Optional binding to trigger scroll to cursor (set to true to scroll, resets to false).
    ///   - showGoToLine: Optional binding to trigger showing the Go To Line dialog.
    ///   - isTailFollowEnabled: Optional binding for tail follow state (shows follow button when provided).
    ///   - onCursorChange: Optional callback when cursor position changes.
    ///   - onScrollChange: Optional callback when scroll position changes.
    ///   - onTextChange: Optional callback when text changes.
    ///   - onToggleTailFollow: Optional callback to toggle tail follow mode.
    ///   - onConvertLineEndings: Optional callback when user requests line ending conversion.
    ///   - onConvertIndentation: Optional callback when user requests indentation conversion.
    public init(
        text: Binding<String>,
        language: Binding<KeystoneLanguage>,
        configuration: KeystoneConfiguration,
        findReplaceManager: FindReplaceManager,
        cursorPosition: Binding<CursorPosition>? = nil,
        scrollToCursor: Binding<Bool>? = nil,
        showGoToLine: Binding<Bool>? = nil,
        isTailFollowEnabled: Binding<Bool>? = nil,
        onCursorChange: ((CursorPosition) -> Void)? = nil,
        onScrollChange: ((CGFloat) -> Void)? = nil,
        onTextChange: ((String) -> Void)? = nil,
        onToggleTailFollow: (() -> Void)? = nil,
        onConvertLineEndings: ((LineEnding) -> Void)? = nil,
        onConvertIndentation: ((IndentationSettings) -> Void)? = nil
    ) {
        self._text = text
        self.externalLanguage = language
        self._internalLanguage = State(initialValue: language.wrappedValue)
        self.configuration = configuration
        self.findReplaceManager = findReplaceManager
        self.externalCursorPosition = cursorPosition
        self.externalScrollToCursor = scrollToCursor
        self.externalShowGoToLine = showGoToLine
        self.isTailFollowEnabled = isTailFollowEnabled
        self.onCursorChange = onCursorChange
        self.onScrollChange = onScrollChange
        self.onTextChange = onTextChange
        self.onToggleTailFollow = onToggleTailFollow
        self.onConvertLineEndings = onConvertLineEndings
        self.onConvertIndentation = onConvertIndentation
    }

    /// Creates a new code editor with an initial language value.
    /// The language can still be changed via the status bar dropdown.
    public init(
        text: Binding<String>,
        language: KeystoneLanguage = .plainText,
        configuration: KeystoneConfiguration,
        findReplaceManager: FindReplaceManager,
        cursorPosition: Binding<CursorPosition>? = nil,
        scrollToCursor: Binding<Bool>? = nil,
        showGoToLine: Binding<Bool>? = nil,
        isTailFollowEnabled: Binding<Bool>? = nil,
        onCursorChange: ((CursorPosition) -> Void)? = nil,
        onScrollChange: ((CGFloat) -> Void)? = nil,
        onTextChange: ((String) -> Void)? = nil,
        onToggleTailFollow: (() -> Void)? = nil,
        onConvertLineEndings: ((LineEnding) -> Void)? = nil,
        onConvertIndentation: ((IndentationSettings) -> Void)? = nil
    ) {
        self._text = text
        self.externalLanguage = nil
        self._internalLanguage = State(initialValue: language)
        self.configuration = configuration
        self.findReplaceManager = findReplaceManager
        self.externalCursorPosition = cursorPosition
        self.externalScrollToCursor = scrollToCursor
        self.externalShowGoToLine = showGoToLine
        self.isTailFollowEnabled = isTailFollowEnabled
        self.onCursorChange = onCursorChange
        self.onScrollChange = onScrollChange
        self.onTextChange = onTextChange
        self.onToggleTailFollow = onToggleTailFollow
        self.onConvertLineEndings = onConvertLineEndings
        self.onConvertIndentation = onConvertIndentation
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            // Editor toolbar for iOS
            KeystoneEditorToolbarBar(
                configuration: configuration,
                findReplaceManager: findReplaceManager,
                showSymbolKeyboard: $configuration.showSymbolKeyboard,
                undoController: undoController,
                isTailFollowEnabled: isTailFollowEnabled,
                language: internalLanguage,
                onGoToLine: { showGoToLine.wrappedValue = true },
                onShowSettings: { showSettings = true },
                onToggleTailFollow: onToggleTailFollow,
                onToggleComment: toggleComment
            )
            #else
            // Editor toolbar for macOS
            KeystoneEditorToolbarBar(
                configuration: configuration,
                findReplaceManager: findReplaceManager,
                undoController: undoController,
                isTailFollowEnabled: isTailFollowEnabled,
                language: internalLanguage,
                onGoToLine: { showGoToLine.wrappedValue = true },
                onShowSettings: { showSettings = true },
                onToggleTailFollow: onToggleTailFollow,
                onToggleComment: toggleComment
            )
            #endif

            // Find/Replace bar
            if findReplaceManager.isVisible {
                #if os(iOS)
                KeystoneFindReplaceBar(
                    manager: findReplaceManager,
                    text: $text,
                    undoController: undoController,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    onNavigateToMatch: navigateToMatch
                )
                #else
                KeystoneFindReplaceBar(
                    manager: findReplaceManager,
                    text: $text,
                    undoController: undoController,
                    onNavigateToMatch: navigateToMatch
                )
                #endif
            }

            // Main editor area (line numbers are integrated in KeystoneTextView)
            KeystoneTextView(
                text: $text,
                language: internalLanguage,
                configuration: configuration,
                cursorPosition: cursorPosition,
                scrollOffset: $scrollOffset,
                matchingBracket: $matchingBracket,
                scrollToCursor: scrollToCursor,
                searchMatches: findReplaceManager.matches,
                currentMatchIndex: findReplaceManager.currentMatchIndex,
                undoController: undoController
            )
            .focused($isEditorFocused)

            #if os(iOS)
            // Symbol keyboard bar (always visible when enabled, persisted in configuration)
            if configuration.showSymbolKeyboard {
                SymbolKeyboard(
                    indentString: configuration.indentation.indentString,
                    onSymbol: insertSymbol
                )
            }
            #endif

            // Status bar
            EditorStatusBar(
                cursorPosition: cursorPosition.wrappedValue,
                lineCount: lineCount,
                configuration: configuration,
                language: internalLanguage,
                onLanguageChange: { newLanguage in
                    internalLanguage = newLanguage
                    // Sync to external binding if provided
                    externalLanguage?.wrappedValue = newLanguage
                }
            )
        }
        .clipped() // Prevent content from extending beyond bounds
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(configuration.theme.background)
        .onChange(of: externalLanguage?.wrappedValue) { _, newValue in
            // Sync from external binding if it changes
            if let newValue = newValue, newValue != internalLanguage {
                internalLanguage = newValue
            }
        }
        .onChange(of: text) { _, newValue in
            updateLineCount(from: newValue)
            // Only search when find panel is visible (avoid expensive operation on every keystroke)
            if findReplaceManager.isVisible && !findReplaceManager.searchQuery.isEmpty {
                findReplaceManager.search(in: newValue)
            }
            // Update bracket matching when text changes (cursor might be at a bracket)
            updateMatchingBracket()
            onTextChange?(newValue)
        }
        .onChange(of: cursorPosition.wrappedValue) { _, newPosition in
            onCursorChange?(newPosition)
            // Update bracket matching when cursor moves
            updateMatchingBracket()
        }
        .onChange(of: matchingBracket) { _, _ in
            // Force view update when bracket match changes
            // This ensures highlights are applied immediately
        }
        .onChange(of: scrollOffset) { _, newOffset in
            onScrollChange?(newOffset)
        }
        .onAppear {
            updateLineCount(from: text)
        }
        .alert("Go to Line", isPresented: showGoToLine) {
            TextField("Line or Line:Column (e.g., 42 or 42:10)", text: $goToLineText)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
            Button("Cancel", role: .cancel) { }
            Button("Go") {
                parseAndGoToLine(goToLineText)
            }
        } message: {
            Text("Enter line number, or line:column")
        }
        .sheet(isPresented: $showSettings) {
            EditorSettingsView(
                configuration: configuration,
                isPresented: $showSettings,
                onConvertLineEndings: { newEnding in
                    // Convert the text using Keystone's built-in conversion
                    text = LineEnding.convert(text, to: newEnding)
                    // Call external callback if provided (for app-specific handling like marking unsaved)
                    onConvertLineEndings?(newEnding)
                },
                onConvertIndentation: { newIndentation in
                    // Convert the text using Keystone's built-in conversion
                    text = IndentationSettings.convert(text, to: newIndentation)
                    // Call external callback if provided (for app-specific handling like marking unsaved)
                    onConvertIndentation?(newIndentation)
                }
            )
        }
        #if os(macOS)
        .onKeyPress(.escape) {
            if findReplaceManager.isVisible {
                findReplaceManager.hide()
                return .handled
            }
            return .ignored
        }
        #endif
    }

    // MARK: - Public Methods

    /// Shows the find bar.
    public func showFind() {
        findReplaceManager.show()
    }

    /// Shows the find and replace bar.
    public func showFindReplace() {
        findReplaceManager.showReplace = true
        findReplaceManager.show()
    }

    /// Toggles the find bar visibility.
    public func toggleFind() {
        findReplaceManager.toggle()
    }

    /// Shows the go to line dialog.
    public func showGoToLineDialog() {
        goToLineText = ""
        showGoToLine.wrappedValue = true
    }

    #if os(iOS)
    /// Toggles the symbol keyboard and persists the state.
    public func toggleSymbolKeyboard() {
        withAnimation(.easeInOut(duration: 0.2)) {
            configuration.showSymbolKeyboard.toggle()
            configuration.saveToUserDefaults()
        }
    }

    /// Whether the symbol keyboard is currently visible.
    public var isSymbolKeyboardVisible: Bool {
        configuration.showSymbolKeyboard
    }
    #endif

    /// The current cursor position.
    public var currentCursorPosition: CursorPosition {
        cursorPosition.wrappedValue
    }

    /// The current line count.
    public var currentLineCount: Int {
        lineCount
    }

    // MARK: - Private Methods

    private func updateLineCount(from text: String) {
        lineCount = text.filter { $0 == "\n" }.count + 1
    }

    private func updateMatchingBracket() {
        guard configuration.highlightMatchingBrackets else {
            matchingBracket = nil
            return
        }

        let offset = cursorPosition.wrappedValue.offset

        // Check character at cursor position first (cursor is at the start of a bracket)
        if offset < text.count {
            if let match = BracketMatcher.findMatch(in: text, at: offset) {
                matchingBracket = match
                return
            }
        }

        // Then check character before cursor (cursor is after a bracket)
        if offset > 0 {
            if let match = BracketMatcher.findMatch(in: text, at: offset - 1) {
                matchingBracket = match
                return
            }
        }

        matchingBracket = nil
    }

    private func insertSymbol(_ symbol: String) {
        #if os(iOS)
        // If find/replace is visible and search field is focused, insert into search query
        if findReplaceManager.isVisible && isSearchFieldFocused {
            findReplaceManager.searchQuery += symbol
            return
        }
        #endif

        // Insert symbol at cursor position using undoController for proper undo support
        let offset = cursorPosition.wrappedValue.offset
        let insertRange = NSRange(location: offset, length: 0)

        // Check for auto-pair insertion (e.g., typing "{" should also insert "}")
        var textToInsert = symbol
        var cursorAdjustment = symbol.count

        if symbol.count == 1, let char = symbol.first {
            let nsText = text as NSString

            // Check if we should skip over an existing closing character
            if configuration.shouldSkipClosingPair(for: char, in: nsText, at: offset) {
                // Just move cursor past the existing character
                let newOffset = offset + 1
                cursorPosition.wrappedValue = CursorPosition.from(offset: newOffset, in: text, selectionLength: 0)
                return
            }

            // Check if we should auto-insert a closing pair
            if let closingChar = configuration.shouldAutoInsertPair(for: char, in: nsText, at: offset) {
                textToInsert = symbol + String(closingChar)
                cursorAdjustment = 1 // Position cursor between the pair
            }
        }

        // Try to use undoController for proper undo registration
        if let newText = undoController.replaceText(in: insertRange, with: textToInsert) {
            text = newText
        } else {
            // Fallback: direct insertion (no undo support)
            let index = text.index(text.startIndex, offsetBy: min(offset, text.count))
            text.insert(contentsOf: textToInsert, at: index)
        }

        // Update cursor position
        let newOffset = offset + cursorAdjustment
        cursorPosition.wrappedValue = CursorPosition.from(offset: newOffset, in: text, selectionLength: 0)
    }

    /// Toggles comments on the current line or selection.
    private func toggleComment() {
        let cursor = cursorPosition.wrappedValue
        let selectedRange = NSRange(location: cursor.offset, length: cursor.selectionLength)

        guard let result = CommentToggle.toggleCommentWithRange(
            text: text,
            selectedRange: selectedRange,
            language: internalLanguage
        ) else {
            return // Language doesn't support comments
        }

        // Use undo controller for proper undo support - only replace the affected range
        if let newText = undoController.replaceText(in: result.replacedRange, with: result.replacementText) {
            text = newText
        } else {
            // Fallback: apply the change manually
            let nsText = text as NSString
            text = nsText.replacingCharacters(in: result.replacedRange, with: result.replacementText)
        }

        // Note: We don't update cursorPosition here because the text view will maintain
        // the cursor position relative to the edit. The cursor binding will be updated
        // by the text view delegate when the cursor actually moves.
    }

    /// Parses input in format "line" or "line:column" and navigates to that position.
    private func parseAndGoToLine(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let parts = trimmed.split(separator: ":", maxSplits: 1)
        guard let lineNumber = Int(parts[0]) else { return }

        let column: Int
        if parts.count > 1, let col = Int(parts[1]) {
            column = max(1, col)
        } else {
            column = 1
        }

        goToLine(lineNumber, column: column)
    }

    private func goToLine(_ lineNumber: Int, column: Int = 1) {
        guard lineNumber >= 1 && lineNumber <= lineCount else { return }

        var currentLine = 1
        var lineStartOffset = 0
        var lineEndOffset = text.count

        // Find the start of the target line
        for (index, char) in text.enumerated() {
            if currentLine == lineNumber {
                lineStartOffset = index
                // Now find the end of this line
                for (endIndex, endChar) in text.enumerated().dropFirst(index) {
                    if endChar == "\n" {
                        lineEndOffset = endIndex
                        break
                    }
                }
                break
            }
            if char == "\n" {
                currentLine += 1
            }
        }

        // Calculate final offset with column (clamped to line length)
        let lineLength = lineEndOffset - lineStartOffset
        let columnOffset = min(column - 1, lineLength)
        let finalOffset = lineStartOffset + max(0, columnOffset)

        // Update cursor position after a brief delay to ensure the alert has fully dismissed
        Task { @MainActor in
            // Small delay to allow the alert to dismiss
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            // Request scroll to cursor when going to a specific line
            scrollToCursor.wrappedValue = true
            // Set the cursor position
            cursorPosition.wrappedValue = CursorPosition.from(offset: finalOffset, in: text, selectionLength: 0)

            // Focus the editor
            isEditorFocused = true
        }
    }

    private func navigateToMatch(_ match: SearchMatch) {
        // Request scroll to cursor when navigating to a search match
        scrollToCursor.wrappedValue = true
        // Navigate to the match location
        cursorPosition.wrappedValue = CursorPosition.from(
            offset: text.distance(from: text.startIndex, to: match.range.lowerBound),
            in: text,
            selectionLength: match.matchedText.count
        )
    }
}

// MARK: - Find/Replace Bar

struct KeystoneFindReplaceBar: View {
    @ObservedObject var manager: FindReplaceManager
    @Binding var text: String
    var undoController: UndoController?
    #if os(iOS)
    /// Binding to track search field focus state (for symbol keyboard integration)
    var isSearchFieldFocused: Binding<Bool>?
    #endif
    var onNavigateToMatch: ((SearchMatch) -> Void)?
    @FocusState private var isSearchFocused: Bool

    #if os(iOS)
    private let buttonSize: CGFloat = 44
    private let fontSize: CGFloat = 16
    private let smallFontSize: CGFloat = 14
    private let iconSize: CGFloat = 18
    #else
    private let buttonSize: CGFloat = 24
    private let fontSize: CGFloat = 13
    private let smallFontSize: CGFloat = 11
    private let iconSize: CGFloat = 12
    #endif

    var body: some View {
        VStack(spacing: 6) {
            // Top row: Options, navigation, and close button
            HStack(spacing: 8) {
                // Toggle replace chevron
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { manager.showReplace.toggle() } }) {
                    Image(systemName: manager.showReplace ? "chevron.down" : "chevron.right")
                        .font(.system(size: iconSize, weight: .semibold))
                        .frame(width: buttonSize, height: buttonSize)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // Option toggle buttons
                HStack(spacing: 4) {
                    toggleButtonWithLabel(
                        text: "Aa",
                        tooltip: "Match Case",
                        isActive: manager.options.caseSensitive
                    ) {
                        manager.options.caseSensitive.toggle()
                        manager.search(in: text)
                    }

                    toggleButtonWithLabel(
                        text: "W",
                        tooltip: "Whole Word",
                        isActive: manager.options.wholeWord
                    ) {
                        manager.options.wholeWord.toggle()
                        manager.search(in: text)
                    }

                    toggleButtonWithLabel(
                        text: ".*",
                        tooltip: "Regex",
                        isActive: manager.options.useRegex
                    ) {
                        manager.options.useRegex.toggle()
                        manager.search(in: text)
                    }
                }

                Spacer()

                // Match count
                Text(manager.statusText)
                    .font(.system(size: smallFontSize))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Navigation buttons
                HStack(spacing: 4) {
                    Button(action: {
                        manager.findPrevious()
                        if let match = manager.currentMatch {
                            onNavigateToMatch?(match)
                        }
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: iconSize, weight: .medium))
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.matches.isEmpty)

                    Button(action: {
                        manager.findNext()
                        if let match = manager.currentMatch {
                            onNavigateToMatch?(match)
                        }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: iconSize, weight: .medium))
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.matches.isEmpty)
                }

                // Close button
                Button(action: { manager.hide() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: iconSize, weight: .medium))
                        .frame(width: buttonSize, height: buttonSize)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Search field row - full width
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: iconSize))
                TextField("Find", text: $manager.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize))
                    .focused($isSearchFocused)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit {
                        manager.findNext()
                        if let match = manager.currentMatch {
                            onNavigateToMatch?(match)
                        }
                    }
                if !manager.searchQuery.isEmpty {
                    Button(action: { manager.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: iconSize))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(8)

            // Replace row
            if manager.showReplace {
                HStack(spacing: 8) {
                    // Replace field
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.secondary)
                            .font(.system(size: iconSize))
                        TextField("Replace", text: $manager.replaceText)
                            .textFieldStyle(.plain)
                            .font(.system(size: fontSize))
                            #if os(iOS)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            #endif
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(8)

                    // Replace buttons
                    Button("Replace") {
                        performReplaceCurrent()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: smallFontSize, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(6)
                    .disabled(manager.currentMatch == nil)

                    Button("All") {
                        performReplaceAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: smallFontSize, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(6)
                    .disabled(manager.matches.isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.keystoneStatusBar)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: manager.searchQuery) { _, _ in
            manager.search(in: text)
        }
        #if os(iOS)
        .onChange(of: isSearchFocused) { _, newValue in
            // Sync focus state to parent for symbol keyboard integration
            isSearchFieldFocused?.wrappedValue = newValue
        }
        #endif
    }

    private func toggleButtonWithLabel(text: String, tooltip: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: smallFontSize, weight: isActive ? .bold : .medium, design: .monospaced))
                .frame(width: buttonSize, height: buttonSize)
                .foregroundColor(isActive ? .accentColor : .secondary)
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Replace Operations

    private func performReplaceCurrent() {
        guard let match = manager.currentMatch else { return }

        // Calculate NSRange from Swift Range
        let nsRange = NSRange(match.range, in: text)
        let replaceText = manager.replaceText

        // Try to use undoController for proper undo support
        if let undoController = undoController,
           let newText = undoController.replaceText(in: nsRange, with: replaceText) {
            text = newText
            // Defer search to next run loop to allow UI to update first
            Task { @MainActor in
                manager.search(in: self.text)
            }
        } else {
            // Fallback: direct replacement (no undo support)
            if let newText = manager.replaceCurrent(in: text) {
                text = newText
            }
        }
    }

    private func performReplaceAll() {
        guard !manager.matches.isEmpty else { return }

        // Capture search query to check if replacement might create new matches
        let searchQuery = manager.searchQuery
        let replacementText = manager.replaceText

        // Compute the final text with all replacements in memory (fast)
        let finalText = manager.replaceAll(in: text)

        // Try to use undoController for proper undo support
        if let undoController = undoController {
            // Group all changes into a single undo operation
            undoController.beginUndoGrouping()

            // Replace entire content in one operation
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            if let newText = undoController.replaceText(in: fullRange, with: finalText) {
                text = newText
            } else {
                text = finalText
            }

            undoController.endUndoGrouping()

            // Only re-search if the replacement text contains the search query
            // (meaning new matches might have been created by the replacement)
            // Defer to next run loop to allow UI to update first
            if replacementText.localizedCaseInsensitiveContains(searchQuery) {
                Task { @MainActor in
                    manager.search(in: self.text)
                }
            }
        } else {
            // Fallback: direct replacement (no undo support)
            text = finalText
        }
    }
}


// MARK: - Toolbar Content

/// Provides toolbar items for KeystoneEditor.
public struct KeystoneEditorToolbar: View {
    @ObservedObject var configuration: KeystoneConfiguration
    @ObservedObject var findReplaceManager: FindReplaceManager
    var onShowGoToLine: () -> Void
    var onToggleSymbolKeyboard: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var canUndo: Bool
    var canRedo: Bool

    public var body: some View {
        Group {
            // Undo/Redo
            if let onUndo = onUndo {
                Button(action: onUndo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
                .keyboardShortcut("z", modifiers: .command)
            }

            if let onRedo = onRedo {
                Button(action: onRedo) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            Divider()

            // Find
            Button(action: { findReplaceManager.toggle() }) {
                Label("Find", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)

            // Go to Line
            Button(action: onShowGoToLine) {
                Label("Go to Line", systemImage: "arrow.right.to.line")
            }
            .keyboardShortcut("g", modifiers: .command)

            Divider()

            // Line Numbers
            Button(action: {
                configuration.showLineNumbers.toggle()
                configuration.saveToUserDefaults()
            }) {
                Label("Line Numbers", systemImage: "list.number")
            }

            // Line Wrap
            Button(action: {
                configuration.lineWrapping.toggle()
                configuration.saveToUserDefaults()
            }) {
                Label("Line Wrap", systemImage: "text.justify.left")
            }

            #if os(iOS)
            if let onToggleSymbolKeyboard = onToggleSymbolKeyboard {
                Button(action: onToggleSymbolKeyboard) {
                    Label("Symbols", systemImage: "keyboard")
                }
            }
            #endif
        }
    }

    public init(
        configuration: KeystoneConfiguration,
        findReplaceManager: FindReplaceManager,
        onShowGoToLine: @escaping () -> Void,
        onToggleSymbolKeyboard: (() -> Void)? = nil,
        onUndo: (() -> Void)? = nil,
        onRedo: (() -> Void)? = nil,
        canUndo: Bool = false,
        canRedo: Bool = false
    ) {
        self.configuration = configuration
        self.findReplaceManager = findReplaceManager
        self.onShowGoToLine = onShowGoToLine
        self.onToggleSymbolKeyboard = onToggleSymbolKeyboard
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.canUndo = canUndo
        self.canRedo = canRedo
    }
}

// MARK: - macOS Toolbar Bar

#if os(macOS)
/// A horizontal toolbar bar for the editor on macOS.
struct KeystoneEditorToolbarBar: View {
    @ObservedObject var configuration: KeystoneConfiguration
    @ObservedObject var findReplaceManager: FindReplaceManager
    @ObservedObject var undoController: UndoController
    var isTailFollowEnabled: Binding<Bool>?
    var language: KeystoneLanguage = .plainText
    var onGoToLine: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onToggleTailFollow: (() -> Void)?
    var onToggleComment: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // Undo
            toolbarButton(icon: "arrow.uturn.backward", tooltip: "Undo", enabled: undoController.canUndo) {
                undoController.undo()
            }

            // Redo
            toolbarButton(icon: "arrow.uturn.forward", tooltip: "Redo", enabled: undoController.canRedo) {
                undoController.redo()
            }

            // Toggle Comment (only show if language supports comments)
            if language.supportsComments {
                toolbarButton(icon: "text.bubble", tooltip: "Toggle Comment (⌘/)", enabled: true) {
                    onToggleComment?()
                }
            }

            Divider().frame(height: 18)

            // Find
            toolbarButton(icon: "magnifyingglass", tooltip: "Find", enabled: true, isActive: findReplaceManager.isVisible) {
                findReplaceManager.toggle()
            }

            // Go to Line
            toolbarButton(icon: "arrow.right.to.line", tooltip: "Go to Line", enabled: true) {
                onGoToLine?()
            }

            Divider().frame(height: 18)

            // Line Numbers
            toolbarButton(icon: "list.number", tooltip: "Line Numbers", enabled: true, isActive: configuration.showLineNumbers) {
                configuration.showLineNumbers.toggle()
                configuration.saveToUserDefaults()
            }

            // Line Wrap
            toolbarButton(icon: "text.justify.left", tooltip: "Word Wrap", enabled: true, isActive: configuration.lineWrapping) {
                configuration.lineWrapping.toggle()
                configuration.saveToUserDefaults()
            }

            // Invisible Characters
            toolbarButton(icon: "eye", tooltip: "Invisible Characters", enabled: true, isActive: configuration.showInvisibleCharacters) {
                configuration.showInvisibleCharacters.toggle()
                configuration.saveToUserDefaults()
            }

            // Tail Follow (only show if callback is provided)
            if let onToggleTailFollow = onToggleTailFollow {
                Divider().frame(height: 18)

                toolbarButton(
                    icon: isTailFollowEnabled?.wrappedValue == true ? "stop.circle" : "play.circle",
                    tooltip: isTailFollowEnabled?.wrappedValue == true ? "Stop Following" : "Follow File",
                    enabled: true,
                    isActive: isTailFollowEnabled?.wrappedValue == true
                ) {
                    onToggleTailFollow()
                }
            }

            Spacer()

            // Settings (right aligned)
            toolbarButton(icon: "gearshape", tooltip: "Editor Settings", enabled: true) {
                onShowSettings?()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.keystoneStatusBar)
        // Keyboard shortcuts
        .background {
            VStack(spacing: 0) {
                // Cmd+Z: Undo
                Button("", action: { undoController.undo() })
                    .keyboardShortcut("z", modifiers: .command)
                // Cmd+Shift+Z: Redo
                Button("", action: { undoController.redo() })
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                // Cmd+F: Find
                Button("", action: { findReplaceManager.toggle() })
                    .keyboardShortcut("f", modifiers: .command)
                // Cmd+G: Find Next
                Button("", action: {
                    if !findReplaceManager.matches.isEmpty { findReplaceManager.findNext() }
                })
                    .keyboardShortcut("g", modifiers: .command)
                // Cmd+Shift+G: Find Previous
                Button("", action: {
                    if !findReplaceManager.matches.isEmpty { findReplaceManager.findPrevious() }
                })
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                // Cmd+L: Go to Line
                Button("", action: { onGoToLine?() })
                    .keyboardShortcut("l", modifiers: .command)
                // Cmd+/: Toggle Comment (only if language supports comments)
                if language.supportsComments, let onToggleComment = onToggleComment {
                    Button("", action: { onToggleComment() })
                        .keyboardShortcut("/", modifiers: .command)
                }
                // Cmd+Shift+T: Toggle follow (if available)
                if let onToggleTailFollow = onToggleTailFollow {
                    Button("", action: { onToggleTailFollow() })
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    private func toolbarButton(icon: String, tooltip: String, enabled: Bool, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
                .foregroundColor(isActive ? .accentColor : (enabled ? .primary : .secondary.opacity(0.5)))
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(tooltip)
    }
}
#endif

// MARK: - iOS Toolbar Bar

#if os(iOS)
/// A horizontal toolbar bar for the editor on iOS with touch-friendly buttons.
struct KeystoneEditorToolbarBar: View {
    @ObservedObject var configuration: KeystoneConfiguration
    @ObservedObject var findReplaceManager: FindReplaceManager
    @Binding var showSymbolKeyboard: Bool
    @ObservedObject var undoController: UndoController
    var isTailFollowEnabled: Binding<Bool>?
    var language: KeystoneLanguage = .plainText
    var onGoToLine: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onToggleTailFollow: (() -> Void)?
    var onToggleComment: (() -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Undo
                toolbarButton(icon: "arrow.uturn.backward", enabled: undoController.canUndo) {
                    undoController.undo()
                }

                // Redo
                toolbarButton(icon: "arrow.uturn.forward", enabled: undoController.canRedo) {
                    undoController.redo()
                }

                // Toggle Comment (only show if language supports comments)
                if language.supportsComments {
                    toolbarButton(icon: "text.bubble", enabled: true) {
                        onToggleComment?()
                    }
                }

                Divider().frame(height: 24)

                // Find
                toolbarButton(icon: "magnifyingglass", enabled: true, isActive: findReplaceManager.isVisible) {
                    findReplaceManager.toggle()
                }

                // Go to Line
                toolbarButton(icon: "arrow.right.to.line", enabled: true) {
                    onGoToLine?()
                }

                Divider().frame(height: 24)

                // Line Numbers - use consistent icon, active state shows selection
                toolbarButton(icon: "list.number", enabled: true, isActive: configuration.showLineNumbers) {
                    configuration.showLineNumbers.toggle()
                    configuration.saveToUserDefaults()
                }

                // Line Wrap - use consistent icon, active state shows selection
                toolbarButton(icon: "text.justify.left", enabled: true, isActive: configuration.lineWrapping) {
                    configuration.lineWrapping.toggle()
                    configuration.saveToUserDefaults()
                }

                // Invisible Characters
                toolbarButton(icon: "eye", enabled: true, isActive: configuration.showInvisibleCharacters) {
                    configuration.showInvisibleCharacters.toggle()
                    configuration.saveToUserDefaults()
                }

                Divider().frame(height: 24)

                // Symbol Keyboard Toggle (persisted)
                toolbarButton(icon: "keyboard", enabled: true, isActive: showSymbolKeyboard) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSymbolKeyboard.toggle()
                        configuration.saveToUserDefaults()
                    }
                }

                // Settings
                toolbarButton(icon: "gearshape", enabled: true) {
                    onShowSettings?()
                }

                // Tail Follow (only show if callback is provided)
                if let onToggleTailFollow = onToggleTailFollow {
                    Divider().frame(height: 24)

                    toolbarButton(
                        icon: isTailFollowEnabled?.wrappedValue == true ? "stop.circle" : "play.circle",
                        enabled: true,
                        isActive: isTailFollowEnabled?.wrappedValue == true
                    ) {
                        onToggleTailFollow()
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(Color.keystoneStatusBar)
    }

    private func toolbarButton(icon: String, enabled: Bool, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 36)
                .foregroundColor(isActive ? .accentColor : (enabled ? .primary : .secondary.opacity(0.5)))
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
#endif

// MARK: - Preview

#Preview("Keystone Editor") {
    struct PreviewWrapper: View {
        @State private var text = "func hello() {\n    print(\"Hello, World!\")\n}\n\nhello()"
        @StateObject private var config = KeystoneConfiguration()
        @StateObject private var findReplace = FindReplaceManager()

        var body: some View {
            KeystoneEditor(
                text: $text,
                language: .swift,  // Uses constant, but language can still be changed via dropdown
                configuration: config,
                findReplaceManager: findReplace
            )
            .frame(minHeight: 400)
        }
    }

    return PreviewWrapper()
}
