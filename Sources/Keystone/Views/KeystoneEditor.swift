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

    /// The document given by the host, or nil when this editor was created with a `text` binding.
    private var externalDocument: KeystoneDocument?
    /// The document this editor owns when created with a `text` binding.
    @StateObject private var ownedDocument: KeystoneDocument
    /// The document being edited.
    public var document: KeystoneDocument { externalDocument ?? ownedDocument }

    /// The `text` binding of the legacy initializers, kept in step with ``document``.
    private var legacyText: Binding<String>?
    /// The last value pushed into `legacyText`, so SwiftUI echoing it back is not taken for a host change.
    @State private var lastPushedLegacyText: String?
    @State private var legacyPushWorkItem: DispatchWorkItem?
    /// Coalesces re-running the current search after edits.
    @State private var researchWorkItem: DispatchWorkItem?
    /// UTF-16 length above which the legacy binding is written only once typing pauses.
    private static let legacyPushDebounceThreshold = 1_500_000

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

    /// Callback when text changes (legacy `text:` initializers). Receives the full text; prefer ``onChange``.
    public var onTextChange: ((String) -> Void)?

    /// Callback after every edit, with no text attached. Read ``document`` for what you need.
    public var onChange: ((KeystoneDocument.Change) -> Void)?

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

    /// Callback when language is automatically changed (e.g., to plaintext for large base64).
    /// The string parameter contains a user-friendly reason message.
    public var onAutoLanguageChange: ((KeystoneLanguage, String) -> Void)?

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
    @State private var showOutline = false
    @State private var showCommandPalette = false
    /// Bumped when the symbols change, so breadcrumbs re-render without a caret move.
    @State private var symbolsVersion = 0
    @State private var editorActions = EditorActions()
    /// Commands the host adds to the palette (``commands(_:)``).
    private var additionalCommands: [EditorCommand] = []
    /// Host-provided model call for inline assist (``inlineAssist(_:)``).
    private var inlineAssistHandler: InlineAssistHandler?
    @State private var assistPhase: InlineAssistPhase = .idle
    @State private var assistInstruction = ""
    @State private var assistTask: Task<Void, Never>?
    @State private var proposedRange: NSRange?

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
        onConvertIndentation: ((IndentationSettings) -> Void)? = nil,
        onAutoLanguageChange: ((KeystoneLanguage, String) -> Void)? = nil
    ) {
        self.legacyText = text
        self.externalDocument = nil
        self._ownedDocument = StateObject(wrappedValue: KeystoneDocument(text: text.wrappedValue))
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
        self.onAutoLanguageChange = onAutoLanguageChange
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
        onConvertIndentation: ((IndentationSettings) -> Void)? = nil,
        onAutoLanguageChange: ((KeystoneLanguage, String) -> Void)? = nil
    ) {
        self.legacyText = text
        self.externalDocument = nil
        self._ownedDocument = StateObject(wrappedValue: KeystoneDocument(text: text.wrappedValue))
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
        self.onAutoLanguageChange = onAutoLanguageChange
    }

    /// Creates a code editor for a host-owned document. This is the fast path for
    /// large files: no text is copied per keystroke.
    /// - Parameters:
    ///   - document: The document to edit. Load text with `document.replaceAll(with:markSaved:)`, save with `document.text` then `document.markSaved()`.
    ///   - language: Binding to the language, for two-way sync with the host.
    ///   - onChange: Called after every edit with a ``KeystoneDocument/Change``.
    public init(
        document: KeystoneDocument,
        language: Binding<KeystoneLanguage>,
        configuration: KeystoneConfiguration,
        findReplaceManager: FindReplaceManager,
        cursorPosition: Binding<CursorPosition>? = nil,
        scrollToCursor: Binding<Bool>? = nil,
        showGoToLine: Binding<Bool>? = nil,
        isTailFollowEnabled: Binding<Bool>? = nil,
        onCursorChange: ((CursorPosition) -> Void)? = nil,
        onScrollChange: ((CGFloat) -> Void)? = nil,
        onChange: ((KeystoneDocument.Change) -> Void)? = nil,
        onToggleTailFollow: (() -> Void)? = nil,
        onConvertLineEndings: ((LineEnding) -> Void)? = nil,
        onConvertIndentation: ((IndentationSettings) -> Void)? = nil,
        onAutoLanguageChange: ((KeystoneLanguage, String) -> Void)? = nil
    ) {
        self.legacyText = nil
        self.externalDocument = document
        self._ownedDocument = StateObject(wrappedValue: KeystoneDocument())
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
        self.onChange = onChange
        self.onToggleTailFollow = onToggleTailFollow
        self.onConvertLineEndings = onConvertLineEndings
        self.onConvertIndentation = onConvertIndentation
        self.onAutoLanguageChange = onAutoLanguageChange
    }

    /// Creates a code editor for a host-owned document with an initial language value.
    public init(
        document: KeystoneDocument,
        language: KeystoneLanguage = .plainText,
        configuration: KeystoneConfiguration,
        findReplaceManager: FindReplaceManager,
        cursorPosition: Binding<CursorPosition>? = nil,
        scrollToCursor: Binding<Bool>? = nil,
        showGoToLine: Binding<Bool>? = nil,
        isTailFollowEnabled: Binding<Bool>? = nil,
        onCursorChange: ((CursorPosition) -> Void)? = nil,
        onScrollChange: ((CGFloat) -> Void)? = nil,
        onChange: ((KeystoneDocument.Change) -> Void)? = nil,
        onToggleTailFollow: (() -> Void)? = nil,
        onConvertLineEndings: ((LineEnding) -> Void)? = nil,
        onConvertIndentation: ((IndentationSettings) -> Void)? = nil,
        onAutoLanguageChange: ((KeystoneLanguage, String) -> Void)? = nil
    ) {
        self.legacyText = nil
        self.externalDocument = document
        self._ownedDocument = StateObject(wrappedValue: KeystoneDocument())
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
        self.onChange = onChange
        self.onToggleTailFollow = onToggleTailFollow
        self.onConvertLineEndings = onConvertLineEndings
        self.onConvertIndentation = onConvertIndentation
        self.onAutoLanguageChange = onAutoLanguageChange
    }

    // MARK: - Body Components

    @ViewBuilder
    private var editorToolbar: some View {
        #if os(iOS)
        KeystoneEditorToolbarBar(
            configuration: configuration,
            findReplaceManager: findReplaceManager,
            showSymbolKeyboard: $configuration.showSymbolKeyboard,
            undoController: undoController,
            isTailFollowEnabled: isTailFollowEnabled,
            language: internalLanguage,
            onGoToLine: { showGoToLine.wrappedValue = true },
            onShowOutline: { showOutline = true },
            onShowCommandPalette: { showCommandPalette = true },
            onInlineAssist: inlineAssistHandler == nil ? nil : { startInlineAssist() },
            onShowSettings: { showSettings = true },
            onToggleTailFollow: onToggleTailFollow,
            onToggleComment: toggleComment,
            onToggleBase64: toggleBase64
        )
        #else
        KeystoneEditorToolbarBar(
            configuration: configuration,
            findReplaceManager: findReplaceManager,
            undoController: undoController,
            isTailFollowEnabled: isTailFollowEnabled,
            language: internalLanguage,
            onGoToLine: { showGoToLine.wrappedValue = true },
            onShowOutline: { showOutline = true },
            onShowCommandPalette: { showCommandPalette = true },
            onInlineAssist: inlineAssistHandler == nil ? nil : { startInlineAssist() },
            onShowSettings: { showSettings = true },
            onToggleTailFollow: onToggleTailFollow,
            onToggleComment: toggleComment,
            onToggleBase64: toggleBase64
        )
        #endif
    }

    @ViewBuilder
    private var findReplaceBarView: some View {
        if findReplaceManager.isVisible {
            #if os(iOS)
            KeystoneFindReplaceBar(
                manager: findReplaceManager,
                document: document,
                undoController: undoController,
                isLargeFile: configuration.isLargeFileMode,
                isSearchFieldFocused: $isSearchFieldFocused,
                onNavigateToMatch: navigateToMatch
            )
            #else
            KeystoneFindReplaceBar(
                manager: findReplaceManager,
                document: document,
                undoController: undoController,
                isLargeFile: configuration.isLargeFileMode,
                onNavigateToMatch: navigateToMatch
            )
            #endif
        }
    }

    @ViewBuilder
    private var mainEditorView: some View {
        KeystoneTextView(
            document: document,
            language: internalLanguage,
            configuration: configuration,
            cursorPosition: cursorPosition,
            scrollOffset: $scrollOffset,
            matchingBracket: $matchingBracket,
            scrollToCursor: scrollToCursor,
            searchMatches: findReplaceManager.matches,
            currentMatchIndex: findReplaceManager.currentMatchIndex,
            undoController: undoController,
            actions: editorActions,
            proposedRange: proposedRange,
            onParsingTimeout: {
                if internalLanguage != .plainText {
                    internalLanguage = .plainText
                    externalLanguage?.wrappedValue = .plainText
                    onAutoLanguageChange?(.plainText, "Content is too large for syntax highlighting. Switched to Plain Text.")
                }
            }
        )
        .focused($isEditorFocused)
    }

    @ViewBuilder
    private var symbolKeyboardView: some View {
        #if os(iOS)
        if configuration.showSymbolKeyboard {
            SymbolKeyboard(
                indentString: configuration.indentation.indentString,
                onSymbol: insertSymbol
            )
        }
        #endif
    }

    @ViewBuilder
    private var statusBarView: some View {
        let _ = symbolsVersion
        EditorStatusBar(
            cursorPosition: cursorPosition.wrappedValue,
            lineCount: lineCount,
            configuration: configuration,
            language: internalLanguage,
            breadcrumbs: document.symbolPath(atOffset: cursorPosition.wrappedValue.offset).map(\.name),
            onLanguageChange: { newLanguage in
                internalLanguage = newLanguage
                externalLanguage?.wrappedValue = newLanguage
            },
            onBreadcrumbTap: { showOutline = true }
        )
    }

    private var editorSettingsSheet: some View {
        EditorSettingsView(
            configuration: configuration,
            isPresented: $showSettings,
            onConvertLineEndings: { newEnding in
                document.replaceAll(with: LineEnding.convert(document.text, to: newEnding), preservingUndo: true)
                onConvertLineEndings?(newEnding)
            },
            onConvertIndentation: { newIndentation in
                document.replaceAll(with: IndentationSettings.convert(document.text, to: newIndentation), preservingUndo: true)
                onConvertIndentation?(newIndentation)
            }
        )
    }

    @ViewBuilder
    private var editorContent: some View {
        VStack(spacing: 0) {
            editorToolbar
            findReplaceBarView
            if assistPhase != .idle {
                InlineAssistBar(
                    phase: assistPhase,
                    instruction: $assistInstruction,
                    onSubmit: submitInlineAssist,
                    onCancel: cancelInlineAssist,
                    onAccept: acceptProposal,
                    onReject: rejectProposal,
                    onRetry: { rejectProposalKeepingInstruction(); assistPhase = .prompting }
                )
            }
            mainEditorView
            symbolKeyboardView
            statusBarView
        }
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(configuration.theme.background)
        .onChange(of: externalLanguage?.wrappedValue) { _, newValue in
            if let newValue = newValue, newValue != internalLanguage {
                internalLanguage = newValue
            }
        }
        .onReceive(document.didChange) { change in
            handleDocumentChange(change)
        }
        .onReceive(document.$lineCount) { count in
            if count != lineCount { lineCount = count }
        }
        .onReceive(document.$symbols) { _ in
            symbolsVersion &+= 1
        }
        .onChange(of: legacyText?.wrappedValue) { _, newValue in
            handleLegacyTextChange(newValue)
        }
        .onChange(of: cursorPosition.wrappedValue) { _, newPosition in
            onCursorChange?(newPosition)
        }
        .onChange(of: matchingBracket) { _, _ in }
        .onChange(of: scrollOffset) { _, newOffset in
            onScrollChange?(newOffset)
        }
        .onAppear {
            lineCount = document.lineCount
            let document = self.document
            undoController.onUndoRedo = { [weak findReplaceManager] in
                guard let manager = findReplaceManager, manager.isVisible else { return }
                Task { @MainActor in
                    manager.search(in: document.text)
                }
            }
        }
    }

    // MARK: - Body

    public var body: some View {
        editorContent
            .overlay(alignment: .top) { pickerOverlay }
            .alert(String(localized: "Go to Line", bundle: .module), isPresented: showGoToLine) {
                TextField(String(localized: "Line or Line:Column (e.g., 42 or 42:10)", bundle: .module), text: $goToLineText)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) { }
                Button(String(localized: "Go", bundle: .module)) {
                    parseAndGoToLine(goToLineText)
                }
            } message: {
                Text("Enter line number, or line:column", bundle: .module)
            }
            .sheet(isPresented: $showSettings) {
                editorSettingsSheet
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

    // MARK: - Pickers

    @ViewBuilder
    private var pickerOverlay: some View {
        if showOutline || showCommandPalette {
            ZStack(alignment: .top) {
                // Click outside closes
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissPickers() }
                Group {
                    if showOutline {
                        SymbolOutlineView(document: document, onSelect: jump(to:), onDismiss: dismissPickers)
                    } else {
                        CommandPaletteView(commands: paletteCommands, onDismiss: dismissPickers)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.top, 52)
                .padding(.horizontal, 16)
            }
        }
    }

    private func dismissPickers() {
        showOutline = false
        showCommandPalette = false
        isEditorFocused = true
    }

    private func jump(to symbol: DocumentSymbol) {
        dismissPickers()
        cursorPosition.wrappedValue = document.position(atOffset: symbol.selectionRange.location, selectionLength: symbol.selectionRange.length)
        scrollToCursor.wrappedValue = true
    }

    /// Everything the palette offers, in display order.
    private var paletteCommands: [EditorCommand] {
        func toggle(_ id: String, _ title: String, _ image: String, _ isOn: Bool, _ flip: @escaping () -> Void) -> EditorCommand {
            EditorCommand(id: id, title: title, subtitle: isOn ? String(localized: "On", bundle: .module) : String(localized: "Off", bundle: .module), systemImage: image) {
                flip()
                configuration.saveToUserDefaults()
            }
        }
        var commands: [EditorCommand] = [
            EditorCommand(id: "find", title: String(localized: "Find", bundle: .module), systemImage: "magnifyingglass", shortcut: "⌘F") { findReplaceManager.show() },
            EditorCommand(id: "replace", title: String(localized: "Find and Replace", bundle: .module), systemImage: "arrow.triangle.2.circlepath") { showFindReplace() },
            EditorCommand(id: "gotoLine", title: String(localized: "Go to Line…", bundle: .module), systemImage: "arrow.right.to.line", shortcut: "⌘L") { showGoToLineDialog() },
            EditorCommand(id: "gotoSymbol", title: String(localized: "Go to Symbol…", bundle: .module), systemImage: "list.bullet.indent", shortcut: "⌘⇧O") { showOutline = true },
            toggle("lineNumbers", String(localized: "Line Numbers", bundle: .module), "list.number", configuration.showLineNumbers) { configuration.showLineNumbers.toggle() },
            toggle("wordWrap", String(localized: "Word Wrap", bundle: .module), "text.justify.left", configuration.lineWrapping) { configuration.lineWrapping.toggle() },
            toggle("invisibles", String(localized: "Invisible Characters", bundle: .module), "eye", configuration.showInvisibleCharacters) { configuration.showInvisibleCharacters.toggle() },
            toggle("folding", String(localized: "Code Folding", bundle: .module), "chevron.down.square", configuration.showCodeFolding) { configuration.showCodeFolding.toggle() },
            toggle("currentLine", String(localized: "Highlight Current Line", bundle: .module), "rectangle.lefthalf.inset.filled", configuration.highlightCurrentLine) { configuration.highlightCurrentLine.toggle() },
            toggle("brackets", String(localized: "Highlight Matching Brackets", bundle: .module), "curlybraces", configuration.highlightMatchingBrackets) { configuration.highlightMatchingBrackets.toggle() },
            EditorCommand(id: "foldAll", title: String(localized: "Fold All", bundle: .module), systemImage: "arrow.down.right.and.arrow.up.left") { editorActions.foldAll?() },
            EditorCommand(id: "unfoldAll", title: String(localized: "Unfold All", bundle: .module), systemImage: "arrow.up.left.and.arrow.down.right") { editorActions.unfoldAll?() },
        ]
        if internalLanguage.supportsComments {
            commands.append(EditorCommand(id: "comment", title: String(localized: "Toggle Comment", bundle: .module), systemImage: "text.bubble", shortcut: "⌘/") { toggleComment() })
        }
        commands.append(EditorCommand(id: "base64", title: String(localized: "Toggle Base64", bundle: .module), systemImage: "arrow.triangle.2.circlepath", shortcut: "⌘⇧B") { toggleBase64() })
        if CodeFormatter.supports(internalLanguage) {
            commands.append(EditorCommand(id: "prettify", title: String(localized: "Format: Prettify", bundle: .module), systemImage: "text.alignleft") { formatDocument(.prettify) })
            commands.append(EditorCommand(id: "minify", title: String(localized: "Format: Minify", bundle: .module), systemImage: "arrow.down.right.and.arrow.up.left.rectangle") { formatDocument(.minify) })
        }
        if inlineAssistHandler != nil {
            commands.insert(EditorCommand(id: "inlineAssist", title: String(localized: "Inline Assist…", bundle: .module), subtitle: String(localized: "Describe a change to the selection", bundle: .module), systemImage: "sparkles", shortcut: "⌘I") { startInlineAssist() }, at: 0)
        }
        commands += [
            EditorCommand(id: "selectNext", title: String(localized: "Select Next Occurrence", bundle: .module), systemImage: "text.cursor", shortcut: "⌘D") { editorActions.selectNextOccurrence?() },
            EditorCommand(id: "selectAllOcc", title: String(localized: "Select All Occurrences", bundle: .module), systemImage: "text.cursor", shortcut: "⌘⇧L") { editorActions.selectAllOccurrences?() },
            EditorCommand(id: "caretAbove", title: String(localized: "Add Cursor Above", bundle: .module), systemImage: "arrow.up.to.line", shortcut: "⌘⌥↑") { editorActions.addCaretAbove?() },
            EditorCommand(id: "caretBelow", title: String(localized: "Add Cursor Below", bundle: .module), systemImage: "arrow.down.to.line", shortcut: "⌘⌥↓") { editorActions.addCaretBelow?() },
        ]
        for ending in LineEnding.allCases where ending != configuration.lineEnding {
            commands.append(EditorCommand(id: "lineEnding.\(ending.rawValue)", title: String(localized: "Convert Line Endings to \(ending.rawValue.uppercased())", bundle: .module), systemImage: "return") {
                configuration.lineEnding = ending
                configuration.saveToUserDefaults()
                document.replaceAll(with: LineEnding.convert(document.text, to: ending), preservingUndo: true)
                onConvertLineEndings?(ending)
            })
        }
        let indentChoices: [IndentationSettings] = [IndentationSettings(type: .spaces, width: 2), IndentationSettings(type: .spaces, width: 4), IndentationSettings(type: .tabs, width: 4)]
        for choice in indentChoices where choice != configuration.indentation {
            let label = choice.type == .tabs ? String(localized: "Tabs", bundle: .module) : String(localized: "\(choice.width) Spaces", bundle: .module)
            commands.append(EditorCommand(id: "indent.\(choice.type.rawValue).\(choice.width)", title: String(localized: "Convert Indentation to \(label)", bundle: .module), systemImage: "increase.indent") {
                configuration.indentation = choice
                configuration.saveToUserDefaults()
                document.replaceAll(with: IndentationSettings.convert(document.text, to: choice), preservingUndo: true)
                onConvertIndentation?(choice)
            })
        }
        commands.append(EditorCommand(id: "settings", title: String(localized: "Editor Settings…", bundle: .module), systemImage: "gearshape") { showSettings = true })
        for language in KeystoneLanguage.allCases where language != internalLanguage {
            commands.append(EditorCommand(id: "language.\(language.rawValue)", title: String(localized: "Language: \(language.displayName)", bundle: .module), systemImage: "chevron.left.forwardslash.chevron.right") {
                internalLanguage = language
                externalLanguage?.wrappedValue = language
            })
        }
        return additionalCommands + commands
    }

    // MARK: - Format

    private func formatDocument(_ operation: CodeFormatter.Operation) {
        let current = document.text
        guard let formatted = CodeFormatter.format(current, language: internalLanguage, operation: operation, indent: configuration.indentation.indentString),
              formatted != current else { return }
        let caretOffset = cursorPosition.wrappedValue.offset
        document.replaceAll(with: formatted, preservingUndo: true)
        cursorPosition.wrappedValue = document.position(atOffset: min(caretOffset, document.utf16Length))
    }

    // MARK: - Inline assist

    private func startInlineAssist() {
        guard inlineAssistHandler != nil else { return }
        if case .reviewing = assistPhase { return }
        assistPhase = .prompting
    }

    private func submitInlineAssist() {
        guard let handler = inlineAssistHandler else { return }
        let instruction = assistInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        let cursor = cursorPosition.wrappedValue
        var range = NSRange(location: cursor.offset, length: cursor.selectionLength)
        if range.length == 0, let lineStart = document.offset(line: cursor.line), let nextLineStart = document.offset(line: cursor.line + 1) ?? Optional(document.utf16Length) {
            // Nothing selected: rewrite the caret's line.
            var end = nextLineStart
            let backing = document.backingString
            while end > lineStart, end - 1 < backing.length, backing.character(at: end - 1) == 0x0A || backing.character(at: end - 1) == 0x0D { end -= 1 }
            range = NSRange(location: lineStart, length: max(0, end - lineStart))
        }
        let backing = document.backingString
        guard range.location + range.length <= backing.length else { return }
        let before = NSRange(location: max(0, range.location - 2_000), length: min(2_000, range.location))
        let afterStart = range.upperBound
        let after = NSRange(location: afterStart, length: min(2_000, backing.length - afterStart))
        let request = InlineAssistRequest(
            instruction: instruction,
            selectedText: backing.substring(with: range),
            selectionRange: range,
            language: internalLanguage,
            contextBefore: backing.substring(with: before),
            contextAfter: backing.substring(with: after),
            documentLength: backing.length
        )
        assistPhase = .running
        let original = request.selectedText
        assistTask = Task { @MainActor in
            do {
                let replacement = try await handler(request)
                guard !Task.isCancelled else { return }
                applyProposal(replacement, replacing: range, original: original)
            } catch is CancellationError {
                assistPhase = .idle
            } catch {
                assistPhase = .failed(error.localizedDescription)
            }
        }
    }

    private func applyProposal(_ replacement: String, replacing range: NSRange, original: String) {
        guard document.backingString.length >= range.upperBound, document.backingString.substring(with: range) == original else {
            assistPhase = .failed(String(localized: "The text changed while the model was working.", bundle: .module))
            return
        }
        undoController.beginUndoGrouping()
        let applied = undoController.replaceText(in: range, with: replacement)
        undoController.endUndoGrouping()
        guard applied else {
            assistPhase = .failed(String(localized: "Could not apply the change.", bundle: .module))
            return
        }
        let newRange = NSRange(location: range.location, length: (replacement as NSString).length)
        proposedRange = newRange
        assistPhase = .reviewing(ProposedEdit(range: newRange, originalText: original, replacementText: replacement))
        cursorPosition.wrappedValue = document.position(atOffset: newRange.upperBound)
        scrollToCursor.wrappedValue = true
    }

    private func acceptProposal() {
        proposedRange = nil
        assistPhase = .idle
        assistInstruction = ""
        isEditorFocused = true
    }

    private func rejectProposalKeepingInstruction() {
        if case .reviewing(let proposal) = assistPhase {
            undoController.beginUndoGrouping()
            undoController.replaceText(in: proposal.range, with: proposal.originalText)
            undoController.endUndoGrouping()
            cursorPosition.wrappedValue = document.position(atOffset: proposal.range.location, selectionLength: (proposal.originalText as NSString).length)
        }
        proposedRange = nil
    }

    private func rejectProposal() {
        rejectProposalKeepingInstruction()
        assistPhase = .idle
        assistInstruction = ""
        isEditorFocused = true
    }

    private func cancelInlineAssist() {
        assistTask?.cancel()
        assistTask = nil
        if case .reviewing = assistPhase { rejectProposalKeepingInstruction() }
        assistPhase = .idle
        isEditorFocused = true
    }

    // MARK: - Public Methods

    /// Provides the model call behind Inline Assist (⌘I). Without it the command is hidden.
    public func inlineAssist(_ handler: @escaping InlineAssistHandler) -> KeystoneEditor {
        var copy = self
        copy.inlineAssistHandler = handler
        return copy
    }

    /// Adds host commands to the command palette, listed first.
    public func commands(_ extra: [EditorCommand]) -> KeystoneEditor {
        var copy = self
        copy.additionalCommands = extra
        return copy
    }

    /// Shows Go to Symbol (⌘⇧O).
    public func showSymbolOutline() {
        showOutline = true
    }

    /// Shows the command palette (⌘⇧P).
    public func showCommandPaletteView() {
        showCommandPalette = true
    }

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

    private func handleDocumentChange(_ change: KeystoneDocument.Change) {
        if findReplaceManager.isVisible && !findReplaceManager.searchQuery.isEmpty {
            // The search runs off the main thread; only the snapshot is taken here,
            // so coalesce it to once per typing pause.
            researchWorkItem?.cancel()
            let manager = findReplaceManager
            let document = self.document
            let work = DispatchWorkItem { manager.search(in: document.text) }
            researchWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
        onChange?(change)
        if legacyText != nil {
            scheduleLegacyPush()
        }
    }

    /// The legacy `text` binding gets a snapshot right away for ordinary files and
    /// once typing pauses for big ones; copying the buffer per keystroke is what
    /// made those files unusable.
    private func scheduleLegacyPush() {
        legacyPushWorkItem?.cancel()
        legacyPushWorkItem = nil
        if document.utf16Length < Self.legacyPushDebounceThreshold {
            pushLegacyText()
        } else {
            let work = DispatchWorkItem { pushLegacyText() }
            legacyPushWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func pushLegacyText() {
        guard let binding = legacyText else { return }
        let snapshot = document.text
        lastPushedLegacyText = snapshot
        binding.wrappedValue = snapshot
        onTextChange?(snapshot)
    }

    /// A host wrote the legacy binding (file load, revert). Our own pushes come
    /// back through here too and are ignored.
    private func handleLegacyTextChange(_ newValue: String?) {
        guard let newValue, legacyText != nil else { return }
        if let last = lastPushedLegacyText, last == newValue { return }
        legacyPushWorkItem?.cancel()
        legacyPushWorkItem = nil
        lastPushedLegacyText = newValue
        // Match the old heuristic: a wholesale change (file load) resets undo, a small one keeps it.
        let currentLength = document.utf16Length
        let newLength = newValue.utf16.count
        let isSignificant = currentLength == 0 || newLength == 0 || abs(currentLength - newLength) > newLength / 2
        document.replaceAll(with: newValue, preservingUndo: !isSignificant)
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
            let nsText = document.backingString

            // Check if we should skip over an existing closing character
            if configuration.shouldSkipClosingPair(for: char, in: nsText, at: offset) {
                // Just move cursor past the existing character
                cursorPosition.wrappedValue = document.position(atOffset: offset + 1)
                return
            }

            // Check if we should auto-insert a closing pair
            if let closingChar = configuration.shouldAutoInsertPair(for: char, in: nsText, at: offset) {
                textToInsert = symbol + String(closingChar)
                cursorAdjustment = 1 // Position cursor between the pair
            }
        }

        guard undoController.replaceText(in: insertRange, with: textToInsert) else { return }

        // Update cursor position
        cursorPosition.wrappedValue = document.position(atOffset: offset + cursorAdjustment)
    }

    /// Toggles comments on the current line or selection.
    private func toggleComment() {
        let cursor = cursorPosition.wrappedValue
        let selectedRange = NSRange(location: cursor.offset, length: cursor.selectionLength)

        // One snapshot of the text; the result carries the range to replace and the new cursor.
        guard let result = CommentToggle.toggleCommentWithRange(
            text: document.text,
            selectedRange: selectedRange,
            language: internalLanguage
        ) else {
            return // Language doesn't support comments
        }

        guard undoController.replaceText(in: result.replacedRange, with: result.replacementText) else { return }

        // Keep a multi-line selection covering the same lines: it grows or shrinks by the length delta.
        let delta = (result.replacementText as NSString).length - result.replacedRange.length
        let newSelectionLength = cursor.selectionLength > 0 ? max(0, cursor.selectionLength + delta) : 0
        cursorPosition.wrappedValue = document.position(
            atOffset: newSelectionLength > 0 ? result.replacedRange.location : result.newCursorOffset,
            selectionLength: newSelectionLength
        )
    }

    /// Toggles Base64 encoding/decoding on the current selection.
    private func toggleBase64() {
        let cursor = cursorPosition.wrappedValue
        let selectedRange = NSRange(location: cursor.offset, length: cursor.selectionLength)

        // Need a selection to encode/decode
        guard selectedRange.length > 0 else {
            return
        }

        guard let result = Base64Toggle.toggleBase64WithRange(
            text: document.text,
            selectedRange: selectedRange
        ) else {
            return
        }

        // If encoding (result is longer than input) and result is large,
        // switch to plaintext first to prevent TreeSitter from hanging
        let isEncoding = result.replacementText.count > selectedRange.length
        let isLargeResult = result.replacementText.count > 100_000
        let needsLanguageSwitch = isEncoding && isLargeResult && internalLanguage != .plainText

        // Capture what we need for the closure - undoController is a class so it stays valid
        let undoCtrl = undoController
        let cursorBinding = cursorPosition
        let document = self.document
        let replacedRange = result.replacedRange
        let replacementText = result.replacementText

        // Helper to apply the text change
        let applyChange: () -> Void = {
            // Use undoController to properly register in undo/redo history
            guard undoCtrl.replaceText(in: replacedRange, with: replacementText) else { return }
            let length = document.utf16Length
            let safeOffset = min(replacedRange.location, length)
            let safeLength = min((replacementText as NSString).length, max(0, length - safeOffset))
            // Select the replacement text
            cursorBinding.wrappedValue = document.position(atOffset: safeOffset, selectionLength: safeLength)
        }

        if needsLanguageSwitch {
            // Switch to plaintext first
            internalLanguage = .plainText
            externalLanguage?.wrappedValue = .plainText
            onAutoLanguageChange?(.plainText, "Content too large for syntax highlighting. Switched to Plain Text.")

            // Delay the text change to allow SwiftUI to propagate the language change
            // This ensures TreeSitter is in plaintext mode before we insert large base64 content
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                applyChange()
            }
        } else {
            applyChange()
        }
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
        // Clamp line number to valid range (1 to lineCount, minimum 1)
        let maxLine = max(1, document.lineCount)
        let targetLine = min(max(1, lineNumber), maxLine)
        guard let offset = document.offset(line: targetLine, column: column) else { return }

        // Set cursor position and scroll (no delay needed - alert dismisses synchronously)
        cursorPosition.wrappedValue = document.position(atOffset: offset)
        scrollToCursor.wrappedValue = true
        isEditorFocused = true
    }

    private func navigateToMatch(_ match: SearchMatch) {
        // The match may be stale if the document was edited after the search —
        // resolve against the current text rather than trusting its indices.
        guard let range = match.resolvedNSRange(inBacking: document.backingString) else { return }
        // Request scroll to cursor when navigating to a search match
        scrollToCursor.wrappedValue = true
        cursorPosition.wrappedValue = document.position(atOffset: range.location, selectionLength: range.length)
    }
}

// MARK: - Find/Replace Bar

struct KeystoneFindReplaceBar: View {
    @ObservedObject var manager: FindReplaceManager
    let document: KeystoneDocument
    var undoController: UndoController?
    var isLargeFile: Bool = false
    #if os(iOS)
    /// Binding to track search field focus state (for symbol keyboard integration)
    var isSearchFieldFocused: Binding<Bool>?
    #endif
    var onNavigateToMatch: ((SearchMatch) -> Void)?
    @FocusState private var isSearchFocused: Bool

    /// Debounce task for search-as-you-type
    @State private var searchDebounceTask: DispatchWorkItem?
    /// Search-as-you-type delay. The search itself runs off the main thread; only the
    /// text snapshot is taken on it, so big files get a slightly longer pause.
    private var autoSearchDelay: TimeInterval { isLargeFile ? 0.4 : 0.15 }

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
                        tooltip: String(localized: "Match Case", bundle: .module),
                        isActive: manager.options.caseSensitive
                    ) {
                        manager.options.caseSensitive.toggle()
                        // Only auto-search for small files
                        manager.search(in: document.text)
                    }

                    toggleButtonWithLabel(
                        text: "W",
                        tooltip: String(localized: "Whole Word", bundle: .module),
                        isActive: manager.options.wholeWord
                    ) {
                        manager.options.wholeWord.toggle()
                        manager.search(in: document.text)
                    }

                    toggleButtonWithLabel(
                        text: ".*",
                        tooltip: String(localized: "Regex", bundle: .module),
                        isActive: manager.options.useRegex
                    ) {
                        manager.options.useRegex.toggle()
                        manager.search(in: document.text)
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
                TextField(String(localized: "Find", bundle: .module), text: $manager.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize))
                    .focused($isSearchFocused)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit {
                        // If we have matches, cycle to next; otherwise search first
                        if !manager.matches.isEmpty {
                            manager.findNext()
                        } else {
                            manager.search(in: document.text)
                        }
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
                        TextField(String(localized: "Replace", bundle: .module), text: $manager.replaceText)
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
                    Button(String(localized: "Replace", bundle: .module)) {
                        performReplaceCurrent()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: smallFontSize, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(6)
                    .disabled(manager.currentMatch == nil)

                    Button(String(localized: "All", bundle: .module)) {
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
        .onChange(of: manager.searchQuery) { _, newValue in
            manager.queryDidChange()

            // Cancel any pending debounce
            searchDebounceTask?.cancel()
            searchDebounceTask = nil

            // Search as you type (after 3+ characters); the work is off the main thread.
            if newValue.count >= FindReplaceManager.minimumSearchLength {
                let task = DispatchWorkItem { [manager, document] in
                    manager.search(in: document.text)
                }
                searchDebounceTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + autoSearchDelay, execute: task)
            }
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

        // The match is only valid for the text that was searched. If the
        // document changed since (edit while the find bar is open), refresh
        // the search instead of replacing whatever now sits at stale offsets.
        guard let nsRange = match.resolvedNSRange(inBacking: document.backingString) else {
            manager.search(in: document.text)
            return
        }
        let replaceText = manager.replaceText

        if let undoController = undoController, undoController.replaceText(in: nsRange, with: replaceText) {
            // Defer search to next run loop to allow UI to update first
            let document = self.document
            Task { @MainActor in
                manager.search(in: document.text)
            }
        } else if let newText = manager.replaceCurrent(in: document.text) {
            // Fallback: whole-document replacement (no undo support)
            document.replaceAll(with: newText, preservingUndo: true)
        }
    }

    private func performReplaceAll() {
        guard !manager.matches.isEmpty else { return }

        // Capture search query to check if replacement might create new matches
        let searchQuery = manager.searchQuery
        let replacementText = manager.replaceText

        // Compute the final text with all replacements in memory (fast)
        let finalText = manager.replaceAll(in: document.text)

        if let undoController = undoController, undoController.replaceAll(with: finalText) {
            // Replaced through the text view, with undo.
        } else {
            document.replaceAll(with: finalText, preservingUndo: true)
        }

        // Only re-search if the replacement text contains the search query
        // (meaning new matches might have been created by the replacement)
        if replacementText.localizedCaseInsensitiveContains(searchQuery) {
            let document = self.document
            Task { @MainActor in
                manager.search(in: document.text)
            }
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
                    Label(String(localized: "Undo", bundle: .module), systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
                .keyboardShortcut("z", modifiers: .command)
            }

            if let onRedo = onRedo {
                Button(action: onRedo) {
                    Label(String(localized: "Redo", bundle: .module), systemImage: "arrow.uturn.forward")
                }
                .disabled(!canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            Divider()

            // Find
            Button(action: { findReplaceManager.toggle() }) {
                Label(String(localized: "Find", bundle: .module), systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)

            // Go to Line
            Button(action: onShowGoToLine) {
                Label(String(localized: "Go to Line", bundle: .module), systemImage: "arrow.right.to.line")
            }
            .keyboardShortcut("g", modifiers: .command)

            Divider()

            // Line Numbers
            Button(action: {
                configuration.showLineNumbers.toggle()
                configuration.saveToUserDefaults()
            }) {
                Label(String(localized: "Line Numbers", bundle: .module), systemImage: "list.number")
            }

            // Line Wrap
            Button(action: {
                configuration.lineWrapping.toggle()
                configuration.saveToUserDefaults()
            }) {
                Label(String(localized: "Line Wrap", bundle: .module), systemImage: "text.justify.left")
            }

            #if os(iOS)
            if let onToggleSymbolKeyboard = onToggleSymbolKeyboard {
                Button(action: onToggleSymbolKeyboard) {
                    Label(String(localized: "Symbols", bundle: .module), systemImage: "keyboard")
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
    var onShowOutline: (() -> Void)?
    var onShowCommandPalette: (() -> Void)?
    var onInlineAssist: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onToggleTailFollow: (() -> Void)?
    var onToggleComment: (() -> Void)?
    var onToggleBase64: (() -> Void)?

    /// Local state to track tail follow - synced with binding for proper SwiftUI updates
    @State private var tailFollowActive: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Undo
            toolbarButton(icon: "arrow.uturn.backward", tooltip: String(localized: "Undo", bundle: .module), enabled: undoController.canUndo) {
                undoController.undo()
            }

            // Redo
            toolbarButton(icon: "arrow.uturn.forward", tooltip: String(localized: "Redo", bundle: .module), enabled: undoController.canRedo) {
                undoController.redo()
            }

            // Toggle Comment (only show if language supports comments)
            if language.supportsComments {
                toolbarButton(icon: "text.bubble", tooltip: String(localized: "Toggle Comment (⌘/)", bundle: .module), enabled: true) {
                    onToggleComment?()
                }
            }

            // Toggle Base64 encode/decode
            toolbarButton(icon: "arrow.triangle.2.circlepath", tooltip: String(localized: "Toggle Base64 (⌘⇧B)", bundle: .module), enabled: true) {
                onToggleBase64?()
            }

            Divider().frame(height: 18)

            // Find
            toolbarButton(icon: "magnifyingglass", tooltip: String(localized: "Find", bundle: .module), enabled: true, isActive: findReplaceManager.isVisible) {
                findReplaceManager.toggle()
            }

            // Go to Line
            toolbarButton(icon: "arrow.right.to.line", tooltip: String(localized: "Go to Line", bundle: .module), enabled: true) {
                onGoToLine?()
            }

            // Go to Symbol
            toolbarButton(icon: "list.bullet.indent", tooltip: String(localized: "Go to Symbol (⌘⇧O)", bundle: .module), enabled: true) {
                onShowOutline?()
            }

            // Commands
            toolbarButton(icon: "command", tooltip: String(localized: "Commands (⌘⇧P)", bundle: .module), enabled: true) {
                onShowCommandPalette?()
            }

            // Inline assist (only when the host provides a model)
            if let onInlineAssist {
                toolbarButton(icon: "sparkles", tooltip: String(localized: "Inline Assist (⌘I)", bundle: .module), enabled: true) {
                    onInlineAssist()
                }
            }

            Divider().frame(height: 18)

            // Line Numbers
            toolbarButton(icon: "list.number", tooltip: String(localized: "Line Numbers", bundle: .module), enabled: true, isActive: configuration.showLineNumbers) {
                configuration.showLineNumbers.toggle()
                configuration.saveToUserDefaults()
            }

            // Line Wrap
            toolbarButton(icon: "text.justify.left", tooltip: String(localized: "Word Wrap", bundle: .module), enabled: true, isActive: configuration.lineWrapping) {
                configuration.lineWrapping.toggle()
                configuration.saveToUserDefaults()
            }

            // Invisible Characters
            toolbarButton(icon: "eye", tooltip: String(localized: "Invisible Characters", bundle: .module), enabled: true, isActive: configuration.showInvisibleCharacters) {
                configuration.showInvisibleCharacters.toggle()
                configuration.saveToUserDefaults()
            }

            // Tail Follow (only show if callback is provided)
            if let onToggleTailFollow = onToggleTailFollow {
                Divider().frame(height: 18)

                toolbarButton(
                    icon: tailFollowActive ? "stop.circle" : "play.circle",
                    tooltip: tailFollowActive ? String(localized: "Stop Following", bundle: .module) : String(localized: "Follow File", bundle: .module),
                    enabled: true,
                    isActive: tailFollowActive
                ) {
                    onToggleTailFollow()
                }
            }

            Spacer()

            // Settings (right aligned)
            toolbarButton(icon: "gearshape", tooltip: String(localized: "Editor Settings", bundle: .module), enabled: true) {
                onShowSettings?()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.keystoneStatusBar)
        .onAppear {
            tailFollowActive = isTailFollowEnabled?.wrappedValue ?? false
        }
        .onChange(of: isTailFollowEnabled?.wrappedValue) { _, newValue in
            tailFollowActive = newValue ?? false
        }
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
                // Cmd+Shift+O: Go to Symbol
                Button("", action: { onShowOutline?() })
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                // Cmd+Shift+P: Command palette
                Button("", action: { onShowCommandPalette?() })
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                // Cmd+I: Inline assist
                if let onInlineAssist {
                    Button("", action: { onInlineAssist() })
                        .keyboardShortcut("i", modifiers: .command)
                }
                // Cmd+/: Toggle Comment (only if language supports comments)
                if language.supportsComments, let onToggleComment = onToggleComment {
                    Button("", action: { onToggleComment() })
                        .keyboardShortcut("/", modifiers: .command)
                }
                // Cmd+Shift+B: Toggle Base64 encode/decode
                if let onToggleBase64 = onToggleBase64 {
                    Button("", action: { onToggleBase64() })
                        .keyboardShortcut("b", modifiers: [.command, .shift])
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
    var onShowOutline: (() -> Void)?
    var onShowCommandPalette: (() -> Void)?
    var onInlineAssist: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onToggleTailFollow: (() -> Void)?
    var onToggleComment: (() -> Void)?
    var onToggleBase64: (() -> Void)?

    /// Local state to track tail follow - synced with binding for proper SwiftUI updates
    @State private var tailFollowActive: Bool = false

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

                // Toggle Base64 encode/decode
                toolbarButton(icon: "arrow.triangle.2.circlepath", enabled: true) {
                    onToggleBase64?()
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

                // Go to Symbol
                toolbarButton(icon: "list.bullet.indent", enabled: true) {
                    onShowOutline?()
                }

                // Commands
                toolbarButton(icon: "command", enabled: true) {
                    onShowCommandPalette?()
                }

                if let onInlineAssist {
                    toolbarButton(icon: "sparkles", enabled: true) {
                        onInlineAssist()
                    }
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
                        icon: tailFollowActive ? "stop.circle" : "play.circle",
                        enabled: true,
                        isActive: tailFollowActive
                    ) {
                        onToggleTailFollow()
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(Color.keystoneStatusBar)
        .onAppear {
            tailFollowActive = isTailFollowEnabled?.wrappedValue ?? false
        }
        .onChange(of: isTailFollowEnabled?.wrappedValue) { _, newValue in
            tailFollowActive = newValue ?? false
        }
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
        @StateObject private var document = KeystoneDocument(text: "func hello() {\n    print(\"Hello, World!\")\n}\n\nhello()")
        @StateObject private var config = KeystoneConfiguration()
        @StateObject private var findReplace = FindReplaceManager()

        var body: some View {
            KeystoneEditor(
                document: document,
                language: .swift,  // Uses constant, but language can still be changed via dropdown
                configuration: config,
                findReplaceManager: findReplace
            )
            .frame(minHeight: 400)
        }
    }

    return PreviewWrapper()
}
