// swiftlint:disable file_length
//
//  TextInputViewMac.swift
//  Keystone
//
//  macOS implementation of TextInputView using NSTextInputClient.
//  This provides the same functionality as the iOS TextInputView but uses AppKit APIs.
//

import Combine
#if canImport(AppKit)
import AppKit

protocol TextInputViewMacDelegate: AnyObject {
    func textInputViewWillBeginEditing(_ view: TextInputViewMac)
    func textInputViewDidBeginEditing(_ view: TextInputViewMac)
    func textInputViewDidEndEditing(_ view: TextInputViewMac)
    func textInputViewDidCancelBeginEditing(_ view: TextInputViewMac)
    func textInputViewDidChange(_ view: TextInputViewMac)
    func textInputView(_ view: TextInputViewMac, didReplaceTextIn range: NSRange, replacementLength: Int)
    func textInputViewDidChangeSelection(_ view: TextInputViewMac)
    func textInputView(_ view: TextInputViewMac, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
    func textInputViewDidInvalidateContentSize(_ view: TextInputViewMac)
    func textInputView(_ view: TextInputViewMac, didProposeContentOffsetAdjustment contentOffsetAdjustment: CGPoint)
    func textInputViewDidChangeGutterWidth(_ view: TextInputViewMac)
    func textInputViewDidUpdateMarkedRange(_ view: TextInputViewMac)
    func textInputView(_ view: TextInputViewMac, canReplaceTextIn highlightedRange: HighlightedRange) -> Bool
    func textInputView(_ view: TextInputViewMac, replaceTextIn highlightedRange: HighlightedRange)
    /// Called when syntax parsing times out. The delegate should switch to plaintext mode.
    func textInputViewDidTimeoutParsing(_ view: TextInputViewMac)
}

// swiftlint:disable:next type_body_length
final class TextInputViewMac: NSView, NSTextInputClient {
    // MARK: - NSTextInputClient State

    private var _selectedRange: NSRange?
    /// Cursors beyond the primary (`selection`). Kept only by this view's own commands;
    /// setting `selection` from outside collapses back to one. See the navigation extension.
    fileprivate var secondaryCarets: [CaretSelection] = []
    /// Where the primary selection started, for shift-extension. Nil: its lower bound.
    fileprivate var primaryAnchor: Int?
    fileprivate var isUpdatingSelections = false
    /// ⌥/⇧-click started this drag, so the other carets stay.
    fileprivate var keepSecondariesDuringDrag = false
    private var _markedRange: NSRange?
    private var _markedText: NSAttributedString?

    // MARK: - Text Content

    private(set) var stringView = StringView() {
        didSet {
            if stringView !== oldValue {
                caretRectService.stringView = stringView
                lineManager.stringView = stringView
                lineControllerFactory.stringView = stringView
                lineControllerStorage.stringView = stringView
                layoutManager.stringView = stringView
                indentController.stringView = stringView
                lineMovementController.stringView = stringView
            }
        }
    }

    var string: NSString {
        get { stringView.string }
        set {
            if newValue != stringView.string {
                stringView.string = newValue
                languageMode.parse(newValue)
                startDeferredParseIfNeeded()
                lineManager.rebuild()
                if let oldSelectedRange = selection {
                    selection = safeSelectionRange(from: oldSelectedRange)
                }
                contentSizeService.invalidateContentSize()
                gutterWidthService.invalidateLineNumberWidth()
                invalidateLines()
                layoutManager.setNeedsLayout()
                layoutManager.layoutIfNeeded()
                if !preserveUndoStackWhenSettingString {
                    timedUndoManager.removeAllActions()
                }
            }
        }
    }

    /// The current text selection range.
    var selection: NSRange? {
        get { _selectedRange }
        set {
            let hadSecondaries = !secondaryCarets.isEmpty
            if !isUpdatingSelections {
                secondaryCarets = []
                primaryAnchor = nil
            }
            if newValue == _selectedRange && hadSecondaries && secondaryCarets.isEmpty {
                layoutManager.setNeedsDisplayOnLines()
                needsDisplay = true
                delegate?.textInputViewDidChangeSelection(self)
            }
            if newValue != _selectedRange {
                _selectedRange = newValue
                layoutManager.selectedRange = _selectedRange
                layoutManager.setNeedsLayoutLineSelection()
                needsLayout = true

                // Force line fragment views to redraw to clear any old cursor artifacts
                // The caret is drawn on top of line fragments, so when the cursor moves,
                // the line fragments must redraw to erase the old cursor position
                layoutManager.setNeedsDisplayOnLines()
                needsDisplay = true

                // Restart blink cycle when cursor moves during editing
                if isEditing && (newValue?.length ?? 0) == 0 {
                    restartCaretBlinking()
                }

                delegate?.textInputViewDidChangeSelection(self)
            }
        }
    }

    var hasText: Bool { string.length > 0 }

    // MARK: - Appearance

    var theme: Theme {
        didSet { applyThemeToChildren() }
    }

    var showLineNumbers = false {
        didSet {
            if showLineNumbers != oldValue {
                caretRectService.showLineNumbers = showLineNumbers
                gutterWidthService.showLineNumbers = showLineNumbers
                layoutManager.showLineNumbers = showLineNumbers
                layoutManager.setNeedsLayout()
                needsLayout = true
            }
        }
    }

    var showCodeFolding = false {
        didSet {
            if showCodeFolding != oldValue {
                gutterWidthService.showCodeFolding = showCodeFolding
                layoutManager.showCodeFolding = showCodeFolding
                layoutManager.setNeedsLayout()
                needsLayout = true
            }
        }
    }

    var codeFoldingManager: CodeFoldingManager? {
        get { layoutManager.codeFoldingManager }
        set {
            layoutManager.codeFoldingManager = newValue
            layoutManager.setNeedsLayout()
            deliverSyntaxFoldRegions()
        }
    }
    /// Fold regions from the last parse, kept until a folding manager is attached.
    private var latestSyntaxFoldRegions: [FoldableRegion]?

    var onFoldToggle: ((Int) -> Void)? {
        get { layoutManager.onFoldToggle }
        set { layoutManager.onFoldToggle = newValue }
    }

    var lineSelectionDisplayType: LineSelectionDisplayType {
        get { layoutManager.lineSelectionDisplayType }
        set { layoutManager.lineSelectionDisplayType = newValue }
    }

    var showTabs: Bool {
        get { invisibleCharacterConfiguration.showTabs }
        set {
            if newValue != invisibleCharacterConfiguration.showTabs {
                invisibleCharacterConfiguration.showTabs = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }

    var showSpaces: Bool {
        get { invisibleCharacterConfiguration.showSpaces }
        set {
            if newValue != invisibleCharacterConfiguration.showSpaces {
                invisibleCharacterConfiguration.showSpaces = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }

    var showLineBreaks: Bool {
        get { invisibleCharacterConfiguration.showLineBreaks }
        set {
            if newValue != invisibleCharacterConfiguration.showLineBreaks {
                invisibleCharacterConfiguration.showLineBreaks = newValue
                invalidateLines()
                layoutManager.setNeedsLayout()
                layoutManager.setNeedsDisplayOnLines()
                needsLayout = true
            }
        }
    }

    var indentStrategy: IndentStrategy = .tab(length: 2) {
        didSet {
            if indentStrategy != oldValue {
                indentController.indentStrategy = indentStrategy
                layoutManager.setNeedsLayout()
                needsLayout = true
                layoutSubtreeIfNeeded()
            }
        }
    }

    var gutterLeadingPadding: CGFloat = 3 {
        didSet {
            if gutterLeadingPadding != oldValue {
                gutterWidthService.gutterLeadingPadding = gutterLeadingPadding
                layoutManager.setNeedsLayout()
                needsLayout = true
            }
        }
    }

    var gutterTrailingPadding: CGFloat = 3 {
        didSet {
            if gutterTrailingPadding != oldValue {
                gutterWidthService.gutterTrailingPadding = gutterTrailingPadding
                layoutManager.setNeedsLayout()
                needsLayout = true
            }
        }
    }

    var textContainerInset: NSEdgeInsets {
        get { layoutManager.textContainerInset }
        set {
            if newValue.top != layoutManager.textContainerInset.top ||
               newValue.left != layoutManager.textContainerInset.left ||
               newValue.bottom != layoutManager.textContainerInset.bottom ||
               newValue.right != layoutManager.textContainerInset.right {
                caretRectService.textContainerInset = newValue
                selectionRectService.textContainerInset = newValue
                contentSizeService.textContainerInset = newValue
                layoutManager.textContainerInset = newValue
                layoutManager.setNeedsLayout()
                needsLayout = true
            }
        }
    }

    var isLineWrappingEnabled: Bool {
        get { layoutManager.isLineWrappingEnabled }
        set {
            if newValue != layoutManager.isLineWrappingEnabled {
                contentSizeService.isLineWrappingEnabled = newValue
                layoutManager.isLineWrappingEnabled = newValue
                invalidateLines()
                layoutManager.setNeedsLayout()
                layoutManager.layoutIfNeeded()
            }
        }
    }

    var lineBreakMode: LineBreakMode = .byWordWrapping {
        didSet {
            if lineBreakMode != oldValue {
                invalidateLines()
                contentSizeService.invalidateContentSize()
                layoutManager.setNeedsLayout()
                layoutManager.layoutIfNeeded()
            }
        }
    }

    var gutterWidth: CGFloat { gutterWidthService.gutterWidth }

    var lineHeightMultiplier: CGFloat = 1 {
        didSet {
            if lineHeightMultiplier != oldValue {
                selectionRectService.lineHeightMultiplier = lineHeightMultiplier
                layoutManager.lineHeightMultiplier = lineHeightMultiplier
                invalidateLines()
                lineManager.estimatedLineHeight = estimatedLineHeight
                layoutManager.setNeedsLayout()
                needsLayout = true
            }
        }
    }

    var kern: CGFloat = 0 {
        didSet {
            if kern != oldValue {
                invalidateLines()
                pageGuideController.kern = kern
                contentSizeService.invalidateContentSize()
                layoutManager.setNeedsLayout()
                needsLayout = true
            }
        }
    }

    var characterPairs: [CharacterPair] = [] {
        didSet {
            maximumLeadingCharacterPairComponentLength = characterPairs.map(\.leading.utf16.count).max() ?? 0
        }
    }

    var characterPairTrailingComponentDeletionMode: CharacterPairTrailingComponentDeletionMode = .disabled

    var highlightedRanges: [HighlightedRange] {
        get { highlightService.highlightedRanges }
        set {
            if newValue != highlightService.highlightedRanges {
                highlightService.highlightedRanges = newValue
                layoutManager.setNeedsLayout()
                layoutManager.layoutIfNeeded()
            }
        }
    }

    var viewport: CGRect {
        get { layoutManager.viewport }
        set {
            if newValue != layoutManager.viewport {
                layoutManager.viewport = newValue
                layoutManager.setNeedsLayout()
                // Defer layout to avoid blocking the main thread during rapid updates
                needsLayout = true
            }
        }
    }

    var scrollViewWidth: CGFloat = 0 {
        didSet {
            if scrollViewWidth != oldValue {
                contentSizeService.scrollViewWidth = scrollViewWidth
                layoutManager.scrollViewWidth = scrollViewWidth
                if isLineWrappingEnabled {
                    invalidateLines()
                }
                layoutManager.setNeedsLayout()
                // Defer layout to avoid blocking during rapid updates
                needsLayout = true
            }
        }
    }

    var contentSize: CGSize { contentSizeService.contentSize }

    var lineEndings: LineEnding = .lf

    var insertionPointColor: NSColor = .textColor {
        didSet {
            if insertionPointColor != oldValue {
                needsDisplay = true
            }
        }
    }

    var selectionHighlightColor: NSColor = .selectedTextBackgroundColor

    var isEditing = false {
        didSet {
            if isEditing != oldValue {
                layoutManager.isEditing = isEditing
            }
        }
    }

    // MARK: - Delegate

    weak var delegate: TextInputViewMacDelegate?

    // MARK: - Private Properties

    private var languageMode: InternalLanguageMode = PlainTextInternalLanguageMode() {
        didSet {
            if languageMode !== oldValue {
                indentController.languageMode = languageMode
                if let treeSitterLanguageMode = languageMode as? TreeSitterInternalLanguageMode {
                    treeSitterLanguageMode.delegate = self
                    latestSyntaxFoldRegions = treeSitterLanguageMode.foldRegions()
                } else {
                    latestSyntaxFoldRegions = nil
                    codeFoldingManager?.usesSyntaxTreeRegions = false
                }
                deliverSyntaxFoldRegions()
                startDeferredParseIfNeeded()
            }
        }
    }

    private(set) var lineManager: LineManager {
        didSet {
            if lineManager !== oldValue {
                indentController.lineManager = lineManager
                lineMovementController.lineManager = lineManager
                gutterWidthService.lineManager = lineManager
                contentSizeService.lineManager = lineManager
                caretRectService.lineManager = lineManager
                selectionRectService.lineManager = lineManager
                highlightService.lineManager = lineManager
            }
        }
    }

    /// The undo manager used for text editing operations.
    var textUndoManager: UndoManager { timedUndoManager }

    private let lineControllerFactory: LineControllerFactory
    private let lineControllerStorage: LineControllerStorage
    private let layoutManager: LayoutManager
    private let timedUndoManager = TimedUndoManager()
    private let indentController: IndentController
    private let lineMovementController: LineMovementController
    private let pageGuideController = PageGuideController()
    private let gutterWidthService: GutterWidthService
    private let contentSizeService: ContentSizeService
    private let caretRectService: CaretRectService
    private let selectionRectService: SelectionRectService
    private let highlightService: HighlightService
    private let invisibleCharacterConfiguration = InvisibleCharacterConfiguration()
    private var maximumLeadingCharacterPairComponentLength = 0
    private var preserveUndoStackWhenSettingString = false
    private var cancellables: [AnyCancellable] = []
    private var hasPendingFullLayout = false
    /// Flag to indicate a replace operation is in progress - used to skip scroll operations
    /// that could crash due to stale line manager state during large text changes.
    private(set) var isPerformingReplace = false
    private var caretBlinkTimer: Timer?
    private var isCaretVisible = true
    private let caretView = NSView()

    private var estimatedLineHeight: CGFloat {
        theme.font.totalLineHeight * lineHeightMultiplier
    }

    // MARK: - Initialization

    init(theme: Theme) {
        self.theme = theme
        lineManager = LineManager(stringView: stringView)
        highlightService = HighlightService(lineManager: lineManager)
        lineControllerFactory = LineControllerFactory(stringView: stringView,
                                                      highlightService: highlightService,
                                                      invisibleCharacterConfiguration: invisibleCharacterConfiguration)
        lineControllerStorage = LineControllerStorage(stringView: stringView, lineControllerFactory: lineControllerFactory)
        gutterWidthService = GutterWidthService(lineManager: lineManager)
        contentSizeService = ContentSizeService(lineManager: lineManager,
                                                lineControllerStorage: lineControllerStorage,
                                                gutterWidthService: gutterWidthService,
                                                invisibleCharacterConfiguration: invisibleCharacterConfiguration)
        caretRectService = CaretRectService(stringView: stringView,
                                            lineManager: lineManager,
                                            lineControllerStorage: lineControllerStorage,
                                            gutterWidthService: gutterWidthService)
        selectionRectService = SelectionRectService(lineManager: lineManager,
                                                    contentSizeService: contentSizeService,
                                                    gutterWidthService: gutterWidthService,
                                                    caretRectService: caretRectService)
        layoutManager = LayoutManager(lineManager: lineManager,
                                      languageMode: languageMode,
                                      stringView: stringView,
                                      lineControllerStorage: lineControllerStorage,
                                      contentSizeService: contentSizeService,
                                      gutterWidthService: gutterWidthService,
                                      caretRectService: caretRectService,
                                      selectionRectService: selectionRectService,
                                      highlightService: highlightService,
                                      invisibleCharacterConfiguration: invisibleCharacterConfiguration)
        indentController = IndentController(stringView: stringView,
                                            lineManager: lineManager,
                                            languageMode: languageMode,
                                            indentStrategy: indentStrategy,
                                            indentFont: theme.font)
        lineMovementController = LineMovementController(lineManager: lineManager,
                                                        stringView: stringView,
                                                        lineControllerStorage: lineControllerStorage)
        super.init(frame: .zero)

        wantsLayer = true
        applyThemeToChildren()
        indentController.delegate = self
        lineControllerStorage.delegate = self
        gutterWidthService.gutterLeadingPadding = gutterLeadingPadding
        gutterWidthService.gutterTrailingPadding = gutterTrailingPadding
        layoutManager.delegate = self
        // Set up view hierarchy - both textInputView and gutterParentView point to self
        // The gutter will be a subview alongside the text content
        layoutManager.gutterParentView = self
        layoutManager.textInputView = self
        setupCaretView()
        setupContentSizeObserver()
        setupGutterWidthObserver()
    }

    private func setupCaretView() {
        // Caret is now drawn directly in draw() for proper coordinate handling
    }

    private func startCaretBlinking() {
        stopCaretBlinking()
        isCaretVisible = true
        needsDisplay = true
        caretBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            self?.toggleCaretVisibility()
        }
    }

    private func stopCaretBlinking() {
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil
        isCaretVisible = false
        needsDisplay = true
    }

    private func restartCaretBlinking() {
        // Stop any existing timer and start fresh with caret visible
        caretBlinkTimer?.invalidate()
        isCaretVisible = true
        needsDisplay = true

        // Start a new blink timer
        caretBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            self?.toggleCaretVisibility()
        }
    }

    private func toggleCaretVisibility() {
        isCaretVisible.toggle()

        // Force line fragments to redraw so old cursor position is cleared
        // and new cursor position is drawn correctly
        layoutManager.setNeedsDisplayOnLines()
        needsDisplay = true
    }

    private func updateCaretPosition() {
        // Just trigger a redraw - caret is drawn in draw()
        needsDisplay = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // Trigger initial layout when added to window
            if hasPendingFullLayout {
                hasPendingFullLayout = false
                performFullLayout()
            }
            layoutManager.setNeedsLayout()
            layoutManager.layoutIfNeeded()
        }
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        delegate?.textInputViewWillBeginEditing(self)
        let result = super.becomeFirstResponder()
        if result {
            isEditing = true
            startCaretBlinking()
            updateCaretPosition()
            delegate?.textInputViewDidBeginEditing(self)
        } else {
            delegate?.textInputViewDidCancelBeginEditing(self)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            isEditing = false
            stopCaretBlinking()
            delegate?.textInputViewDidEndEditing(self)
        }
        return result
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutManager.layoutIfNeeded()
        layoutManager.layoutLineSelectionIfNeeded()
        // Update caret position AFTER layout completes
        updateCaretPosition()
    }

    override var isFlipped: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for caret in allCarets {
            let sel = caret.range
            if sel.length > 0 {
                // Draw all selection rects without filtering by dirtyRect
                // to ensure complete selection highlighting for wrapped lines
                let rects = selectionRectService.selectionRects(in: sel)
                selectionHighlightColor.setFill()
                for rect in rects {
                    NSBezierPath(rect: rect.rect).fill()
                }
            } else if isEditing && isCaretVisible {
                let caretRect = caretRectService.caretRect(at: sel.location, allowMovingCaretToNextLineFragment: true)
                if caretRect.intersects(dirtyRect) {
                    insertionPointColor.setFill()
                    NSBezierPath(rect: caretRect).fill()
                }
            }
        }
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attributedString = string as? NSAttributedString {
            text = attributedString.string
        } else if let plainString = string as? String {
            text = plainString
        } else {
            return
        }

        // Clear marked text
        _markedRange = nil
        _markedText = nil

        let preparedText = prepareTextForInsertion(text)
        if replacementRange.location == NSNotFound && hasMultipleSelections {
            editAllCarets { range in
                self.insert(preparedText, originalText: text, in: range)
            }
        } else {
            let range = replacementRange.location == NSNotFound ? (selection ?? NSRange(location: stringView.string.length, length: 0)) : replacementRange
            insert(preparedText, originalText: text, in: range)
        }

        layoutSubtreeIfNeeded()
        delegate?.textInputViewDidChangeSelection(self)
    }

    /// Inserts typed text at one caret, with line-break indentation and character pairs.
    private func insert(_ preparedText: String, originalText text: String, in range: NSRange) {
        guard delegate?.textInputView(self, shouldChangeTextIn: range, replacementText: preparedText) ?? true else {
            return
        }
        if LineEnding(symbol: text) != nil {
            indentController.insertLineBreak(in: range, using: lineEndings)
        } else if let characterPair = characterPairs.first(where: { $0.leading == preparedText }) {
            // Insert both leading and trailing, position cursor between
            let pairedText = preparedText + characterPair.trailing
            replaceText(in: range, with: pairedText)
            let cursorPosition = range.location + preparedText.utf16.count
            setPrimaryRangeDirectly(NSRange(location: cursorPosition, length: 0))
        } else {
            replaceText(in: range, with: preparedText)
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        let attributedString: NSAttributedString

        if let attrString = string as? NSAttributedString {
            text = attrString.string
            attributedString = attrString
        } else if let plainString = string as? String {
            text = plainString
            attributedString = NSAttributedString(string: plainString)
        } else {
            return
        }

        let range = _markedRange ?? self.selection ?? NSRange(location: stringView.string.length, length: 0)

        guard delegate?.textInputView(self, shouldChangeTextIn: range, replacementText: text) ?? true else {
            return
        }

        _markedRange = text.isEmpty ? nil : NSRange(location: range.location, length: text.utf16.count)
        _markedText = text.isEmpty ? nil : attributedString

        replaceText(in: range, with: text)

        let preferredSelectedRange = NSRange(location: range.location + selectedRange.location, length: selectedRange.length)
        _selectedRange = safeSelectionRange(from: preferredSelectedRange)

        delegate?.textInputViewDidUpdateMarkedRange(self)
    }

    func unmarkText() {
        _markedRange = nil
        _markedText = nil
        delegate?.textInputViewDidUpdateMarkedRange(self)
    }

    // NSTextInputClient required method
    @objc func selectedRange() -> NSRange {
        _selectedRange ?? NSRange(location: 0, length: 0)
    }

    func markedRange() -> NSRange {
        _markedRange ?? NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        _markedRange != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let safeRange = safeSelectionRange(from: range)
        actualRange?.pointee = safeRange
        guard let substring = stringView.substring(in: safeRange) else { return nil }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.font,
            .foregroundColor: NSColor.textColor
        ]
        return NSAttributedString(string: substring, attributes: attrs)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.font, .foregroundColor, .backgroundColor]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        let caretRect = caretRectService.caretRect(at: range.location, allowMovingCaretToNextLineFragment: true)

        // Convert to screen coordinates
        guard let window = window else { return caretRect }
        let windowRect = convert(caretRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    func characterIndex(for point: NSPoint) -> Int {
        // Convert from screen to local coordinates
        guard let window = window else { return 0 }
        let windowPoint = window.convertPoint(fromScreen: point)
        let localPoint = convert(windowPoint, from: nil)

        return layoutManager.closestIndex(to: localPoint) ?? 0
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        inputContext?.handleEvent(event)
    }

    override func doCommand(by selector: Selector) {
        if !handleStandardKeyBinding(selector) {
            super.doCommand(by: selector)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleEditorKeyEquivalent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Standard Actions

    @objc override func deleteBackward(_ sender: Any?) {
        editAllCarets { range in self.deleteBackward(in: range) }
        delegate?.textInputViewDidChangeSelection(self)
    }

    @objc override func deleteForward(_ sender: Any?) {
        editAllCarets { range in self.deleteForward(in: range) }
        delegate?.textInputViewDidChangeSelection(self)
    }

    private func deleteBackward(in selected: NSRange) {
        var range = _markedRange ?? selected
        guard range.location > 0 || range.length > 0 else { return }
        if range.length == 0 {
            range = NSRange(location: range.location - 1, length: 1)
        }
        let deleteRange = rangeForDeletingText(in: range)
        if deleteRange == _markedRange {
            _markedRange = nil
            _markedText = nil
        }
        guard delegate?.textInputView(self, shouldChangeTextIn: deleteRange, replacementText: "") ?? true else { return }
        replaceText(in: deleteRange, with: "")
    }

    private func deleteForward(in selected: NSRange) {
        var range = selected
        guard range.upperBound < string.length || range.length > 0 else { return }
        if range.length == 0 {
            range = string.rangeOfComposedCharacterSequence(at: range.location)
        }
        guard delegate?.textInputView(self, shouldChangeTextIn: range, replacementText: "") ?? true else { return }
        replaceText(in: range, with: "")
    }

    @objc override func moveLeft(_ sender: Any?) { move(.left, extending: false) }
    @objc override func moveRight(_ sender: Any?) { move(.right, extending: false) }
    @objc override func moveUp(_ sender: Any?) { move(.up, extending: false) }
    @objc override func moveDown(_ sender: Any?) { move(.down, extending: false) }

    @objc override func selectAll(_ sender: Any?) {
        selection = NSRange(location: 0, length: string.length)
    }

    @objc func copy(_ sender: Any?) {
        guard let text = copyableText() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc func cut(_ sender: Any?) {
        guard let text = copyableText() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        editAllCarets { range in
            if range.length > 0 { self.replaceText(in: range, with: "") }
        }
        delegate?.textInputViewDidChangeSelection(self)
    }

    @objc func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let pasteString = pasteboard.string(forType: .string) else { return }
        paste(pasteString)
    }

    /// Pastes `text` at every caret. With as many lines as carets, each caret gets its line.
    func paste(_ text: String) {
        guard hasMultipleSelections else {
            let range = selection ?? NSRange(location: stringView.string.length, length: 0)
            replaceText(in: range, with: text)
            return
        }
        let lines = TextNavigation.lines(forDistributing: text)
        let carets = allCarets
        let distribute = lines.count == carets.count
        var index = carets.count - 1
        editAllCarets { range in
            let piece = distribute ? lines[max(0, index)] : text
            index -= 1
            self.replaceText(in: range, with: piece)
        }
        delegate?.textInputViewDidChangeSelection(self)
    }

    /// Selected text; several selections are joined with line breaks, as in Zed and VS Code.
    func copyableText() -> String? {
        let pieces = allCarets.map(\.range).filter { $0.length > 0 }.map { stringView.string.substring(with: $0) }
        return pieces.isEmpty ? nil : pieces.joined(separator: lineEndings.symbol)
    }

    // MARK: - Mouse Events

    /// The anchor point for mouse selection (where the selection started).
    private var selectionAnchor: Int?
    /// Track whether we're in word/line selection mode from double/triple click
    private var wordSelectionMode = false
    private var lineSelectionMode = false
    /// Original word/line range for extending selection during drag
    private var originalWordRange: NSRange?
    private var originalLineRange: NSRange?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let index = layoutManager.closestIndex(to: point) else { return }

        // Reset selection modes
        wordSelectionMode = false
        lineSelectionMode = false
        originalWordRange = nil
        originalLineRange = nil

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        keepSecondariesDuringDrag = false
        if event.clickCount == 1 && modifiers.contains(.option) {
            // ⌥-click adds a caret (or removes the one already there)
            toggleCaret(at: index)
            selectionAnchor = index
            keepSecondariesDuringDrag = true
            return
        }
        if event.clickCount == 1 && modifiers.contains(.shift) {
            // ⇧-click extends the primary selection from its anchor
            let anchor = primaryCaret?.anchor ?? index
            setCarets(secondaryCarets + [CaretSelection(anchor: anchor, head: index)], primary: secondaryCarets.count)
            selectionAnchor = anchor
            keepSecondariesDuringDrag = true
            return
        }

        switch event.clickCount {
        case 1:
            // Single click - position cursor
            selectionAnchor = index
            selection = NSRange(location: index, length: 0)

        case 2:
            // Double click - select word
            wordSelectionMode = true
            let wordRange = wordRange(at: index)
            originalWordRange = wordRange
            selectionAnchor = wordRange.location
            selection = wordRange

        case 3:
            // Triple click - select entire line
            lineSelectionMode = true
            let lineRange = lineRange(at: index)
            originalLineRange = lineRange
            selectionAnchor = lineRange.location
            selection = lineRange

        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = selectionAnchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = layoutManager.closestIndex(to: point) else { return }

        if lineSelectionMode, let originalRange = originalLineRange {
            // Extend selection by lines
            let currentLineRange = lineRange(at: index)
            let start = min(originalRange.location, currentLineRange.location)
            let end = max(originalRange.upperBound, currentLineRange.upperBound)
            selection = NSRange(location: start, length: end - start)
        } else if wordSelectionMode, let originalRange = originalWordRange {
            // Extend selection by words
            let currentWordRange = wordRange(at: index)
            let start = min(originalRange.location, currentWordRange.location)
            let end = max(originalRange.upperBound, currentWordRange.upperBound)
            selection = NSRange(location: start, length: end - start)
        } else if keepSecondariesDuringDrag {
            // Extending a caret added with ⌥/⇧-click; the others stay put
            setCarets(secondaryCarets + [CaretSelection(anchor: anchor, head: index)], primary: secondaryCarets.count)
        } else {
            // Normal character-by-character selection, remembering the direction
            setCarets([CaretSelection(anchor: anchor, head: index)], primary: 0)
        }
    }

    override func mouseUp(with event: NSEvent) {
        keepSecondariesDuringDrag = false
        selectionAnchor = nil
        wordSelectionMode = false
        lineSelectionMode = false
        originalWordRange = nil
        originalLineRange = nil
    }

    /// Returns the range of the word at the given index
    private func wordRange(at index: Int) -> NSRange {
        TextNavigation.wordRange(at: index, in: stringView.string)
    }

    /// Returns the range of the line at the given index
    private func lineRange(at index: Int) -> NSRange {
        let nsString = stringView.string
        let length = nsString.length
        guard index >= 0 && index <= length else {
            return NSRange(location: index, length: 0)
        }

        var start = index
        var end = index

        // Find line start
        while start > 0 {
            let char = nsString.character(at: start - 1)
            if char == 0x0A || char == 0x0D { break } // \n or \r
            start -= 1
        }

        // Find line end (include the newline character if present)
        while end < length {
            let char = nsString.character(at: end)
            end += 1
            if char == 0x0A || char == 0x0D { break } // \n or \r
        }

        return NSRange(location: start, length: end - start)
    }

    // MARK: - Public Methods

    func setState(_ state: TextViewState, addUndoAction: Bool = false) {
        _ = stringView.string  // oldText, kept for potential future undo support
        _ = state.stringView.string  // newText, kept for potential future undo support
        stringView = state.stringView
        theme = state.theme
        languageMode = state.languageMode
        lineControllerStorage.removeAllLineControllers()
        lineManager = state.lineManager
        lineManager.estimatedLineHeight = estimatedLineHeight
        layoutManager.languageMode = state.languageMode
        layoutManager.lineManager = state.lineManager
        contentSizeService.invalidateContentSize()
        gutterWidthService.invalidateLineNumberWidth()

        if !addUndoAction {
            timedUndoManager.removeAllActions()
        }

        if let oldSelectedRange = selection {
            selection = safeSelectionRange(from: oldSelectedRange)
        }

        if window != nil {
            performFullLayout()
        } else {
            hasPendingFullLayout = true
        }
    }

    func setLanguageMode(_ languageMode: LanguageMode, completion: ((Bool) -> Void)? = nil) {
        // Cancel any ongoing parse operations from previous language mode
        if let treeSitterMode = self.languageMode as? TreeSitterInternalLanguageMode {
            // The deinit will cancel operations, but we also need to ensure
            // the old mode's completion handlers don't run after we switch
        }

        let internalLanguageMode = InternalLanguageModeFactory.internalLanguageMode(
            from: languageMode,
            stringView: stringView,
            lineManager: lineManager)
        self.languageMode = internalLanguageMode
        layoutManager.languageMode = internalLanguageMode

        // Capture the mode we're parsing with to check it's still current in completion
        let parsingMode = internalLanguageMode
        internalLanguageMode.parse(string) { [weak self] finished in
            guard let self = self else {
                completion?(false)
                return
            }
            // Only process completion if this language mode is still current
            // This prevents stale completion handlers from old parses from running
            guard self.languageMode === parsingMode else {
                completion?(false)
                return
            }
            if finished {
                self.invalidateLines()
                self.layoutManager.setNeedsLayout()
                self.layoutManager.layoutIfNeeded()
            }
            completion?(finished)
        }
    }

    func linePosition(at location: Int) -> LinePosition? {
        lineManager.linePosition(at: location)
    }

    func clearSelection() {
        selection = nil
    }

    func moveCaret(to point: CGPoint) {
        if let index = layoutManager.closestIndex(to: point) {
            selection = NSRange(location: index, length: 0)
        }
    }

    func caretRect(at location: Int) -> CGRect {
        caretRectService.caretRect(at: location, allowMovingCaretToNextLineFragment: true)
    }

    func text(in range: NSRange) -> String? {
        stringView.substring(in: range)
    }

    func setTextPreservingUndo(_ newString: NSString) {
        guard newString != stringView.string else { return }
        preserveUndoStackWhenSettingString = true
        string = newString
        preserveUndoStackWhenSettingString = false
    }

    /// Sets the entire text content with proper undo/redo support.
    /// Use this for Replace All operations instead of performReplace.
    func setStringWithUndoAction(_ newString: NSString) {
        guard newString != string else { return }
        guard let oldString = stringView.string.copy() as? NSString else { return }

        let oldSelection = selection
        let duringUndoRedo = timedUndoManager.isPerformingUndoRedo

        // Close any open typing group ONLY if not during undo/redo
        // (During undo/redo, there's no typing group - only NSUndoManager's internal redo group)
        if !duringUndoRedo {
            timedUndoManager.endUndoGrouping()
        }

        // Set the new string while preserving undo stack
        preserveUndoStackWhenSettingString = true
        string = newString
        preserveUndoStackWhenSettingString = false

        // Register undo - calling setStringWithUndoAction creates the redo automatically
        // During undo/redo, NSUndoManager already has a group open, so don't create another
        if !duringUndoRedo {
            timedUndoManager.beginUndoGrouping()
        }
        timedUndoManager.setActionName(L10n.Undo.ActionName.replaceAll)
        timedUndoManager.registerUndo(withTarget: self) { [oldString, oldSelection] textInputView in
            textInputView.setStringWithUndoAction(oldString)
            if let oldSelection = oldSelection {
                textInputView._selectedRange = textInputView.safeSelectionRange(from: oldSelection)
            }
        }
        if !duringUndoRedo {
            timedUndoManager.endUndoGrouping()
        }

        // Restore selection to a safe position
        if let oldSelection = oldSelection {
            _selectedRange = safeSelectionRange(from: oldSelection)
        }

        delegate?.textInputViewDidChange(self)
        delegate?.textInputViewDidChangeSelection(self)
        // Mark for display instead of forcing synchronous layout
        needsDisplay = true
    }

    func forceLayoutRefresh() {
        layoutManager.setNeedsLayout()
        layoutManager.layoutIfNeeded()
    }

    func redisplayVisibleLines() {
        layoutManager.redisplayVisibleLines()
    }

    /// Public method to replace text at a range for find/replace operations.
    /// This creates a standalone undo operation (not coalesced with typing).
    func performReplace(in range: NSRange, with text: String) {
        guard delegate?.textInputView(self, shouldChangeTextIn: range, replacementText: text) ?? true else {
            return
        }

        let oldText = self.text(in: range) ?? ""
        let oldSelection = selection
        let newRange = NSRange(location: range.location, length: (text as NSString).length)

        // Close any open undo group first to prevent coalescing with typing
        timedUndoManager.disableUndoCoalescing()

        // Register undo as a standalone operation
        // The undo handler calls performReplace back with inverse parameters,
        // which automatically registers a redo operation
        timedUndoManager.beginUndoGrouping()
        timedUndoManager.setActionName("Replace")
        timedUndoManager.registerUndo(withTarget: self) { [oldText, newRange, oldSelection] textInputView in
            // Store current state for redo before undoing
            let currentSelection = textInputView.selection

            // Undo: replace the new text back with the old text
            // This will register a redo operation automatically
            textInputView.performReplaceForUndo(in: newRange, with: oldText, restoreSelection: oldSelection, redoRange: range, redoText: text, redoSelection: currentSelection)
        }
        timedUndoManager.endUndoGrouping()

        timedUndoManager.enableUndoCoalescing()

        // Set flag to prevent scroll operations during replace (can crash with stale line manager)
        isPerformingReplace = true
        defer { isPerformingReplace = false }

        // Perform the actual replacement
        let textEditHelper = TextEditHelper(stringView: stringView, lineManager: lineManager, lineEndings: lineEndings)
        let textEditResult = textEditHelper.replaceText(in: range, with: text)
        let lineChangeSet = textEditResult.lineChangeSet
        let languageModeLineChangeSet = languageMode.textDidChange(textEditResult.textChange)
        lineChangeSet.union(with: languageModeLineChangeSet)
        applyLineChangesToLayoutManager(lineChangeSet)

        // Clamp selection to valid bounds - critical when text length changes dramatically
        // (e.g., base64 decode can shrink text from 4M to 2K chars)
        let newTextLength = stringView.string.length
        let safeLocation = min(newRange.upperBound, newTextLength)
        _selectedRange = NSRange(location: safeLocation, length: 0)
        delegate?.textInputView(self, didReplaceTextIn: range, replacementLength: (text as NSString).length)
        delegate?.textInputViewDidChange(self)
        delegate?.textInputViewDidChangeSelection(self)
        if textEditResult.didAddOrRemoveLines {
            delegate?.textInputViewDidInvalidateContentSize(self)
        }
    }

    /// Internal method for undo/redo operations that properly registers the inverse operation.
    /// IMPORTANT: This is called DURING undo/redo execution, so we must NOT call
    /// beginUndoGrouping/endUndoGrouping - NSUndoManager manages groups automatically.
    private func performReplaceForUndo(in range: NSRange, with text: String, restoreSelection: NSRange?, redoRange: NSRange, redoText: String, redoSelection: NSRange?) {
        // Register the inverse operation - NSUndoManager automatically handles this as redo/undo
        // DO NOT call beginUndoGrouping/endUndoGrouping here - we're inside an undo operation
        timedUndoManager.setActionName("Replace")
        timedUndoManager.registerUndo(withTarget: self) { [range, text, restoreSelection, redoRange, redoText, redoSelection] textInputView in
            textInputView.performReplaceForUndo(in: redoRange, with: redoText, restoreSelection: redoSelection, redoRange: range, redoText: text, redoSelection: restoreSelection)
        }

        // Set flag to prevent scroll operations during replace (can crash with stale line manager)
        isPerformingReplace = true
        defer { isPerformingReplace = false }

        // Perform the text replacement
        let textEditHelper = TextEditHelper(stringView: stringView, lineManager: lineManager, lineEndings: lineEndings)
        let textEditResult = textEditHelper.replaceText(in: range, with: text)
        let lineChangeSet = textEditResult.lineChangeSet
        let languageModeLineChangeSet = languageMode.textDidChange(textEditResult.textChange)
        lineChangeSet.union(with: languageModeLineChangeSet)
        applyLineChangesToLayoutManager(lineChangeSet)

        // Clamp restored selection to valid bounds - critical when text length changes dramatically
        let newTextLength = stringView.string.length
        if let restore = restoreSelection {
            let safeLocation = min(max(0, restore.location), newTextLength)
            let maxLength = max(0, newTextLength - safeLocation)
            let safeLength = min(restore.length, maxLength)
            _selectedRange = NSRange(location: safeLocation, length: safeLength)
        } else {
            _selectedRange = NSRange(location: min(newTextLength, 0), length: 0)
        }
        delegate?.textInputViewDidChange(self)
        delegate?.textInputViewDidChangeSelection(self)
        if textEditResult.didAddOrRemoveLines {
            delegate?.textInputViewDidInvalidateContentSize(self)
        }
        // Layout already happens inside applyLineChangesToLayoutManager
        // Only mark for display, don't force synchronous layout
        needsDisplay = true
    }

    // MARK: - Private Methods

    private func applyThemeToChildren() {
        gutterWidthService.font = theme.lineNumberFont
        lineManager.estimatedLineHeight = estimatedLineHeight
        indentController.indentFont = theme.font
        pageGuideController.font = theme.font
        layoutManager.theme = theme
    }

    private func replaceText(in range: NSRange, with newString: String) {
        let nsNewString = newString as NSString
        let currentText = text(in: range) ?? ""
        let newRange = NSRange(location: range.location, length: nsNewString.length)

        addUndoOperation(replacing: newRange, withText: currentText)
        _selectedRange = NSRange(location: newRange.upperBound, length: 0)

        let textEditHelper = TextEditHelper(stringView: stringView, lineManager: lineManager, lineEndings: lineEndings)
        let textEditResult = textEditHelper.replaceText(in: range, with: newString)
        let textChange = textEditResult.textChange
        let lineChangeSet = textEditResult.lineChangeSet
        let languageModeLineChangeSet = languageMode.textDidChange(textChange)
        lineChangeSet.union(with: languageModeLineChangeSet)
        applyLineChangesToLayoutManager(lineChangeSet)

        delegate?.textInputView(self, didReplaceTextIn: range, replacementLength: nsNewString.length)
        delegate?.textInputViewDidChange(self)
        if textEditResult.didAddOrRemoveLines {
            delegate?.textInputViewDidInvalidateContentSize(self)
        }
    }

    private func applyLineChangesToLayoutManager(_ lineChangeSet: LineChangeSet) {
        let didAddOrRemoveLines = !lineChangeSet.insertedLines.isEmpty || !lineChangeSet.removedLines.isEmpty
        if didAddOrRemoveLines {
            contentSizeService.invalidateContentSize()
            for removedLine in lineChangeSet.removedLines {
                lineControllerStorage.removeLineController(withID: removedLine.id)
                contentSizeService.removeLine(withID: removedLine.id)
            }
        }
        let editedLineIDs = Set(lineChangeSet.editedLines.map(\.id))
        layoutManager.redisplayLines(withIDs: editedLineIDs)
        if didAddOrRemoveLines {
            gutterWidthService.invalidateLineNumberWidth()
        }
        layoutManager.setNeedsLayout()
        layoutManager.layoutIfNeeded()
    }

    private func rangeForDeletingText(in range: NSRange) -> NSRange {
        var resultingRange = range
        if range.length == 1, let indentRange = indentController.indentRangeInFrontOfLocation(range.upperBound) {
            resultingRange = indentRange
        } else {
            resultingRange = string.customRangeOfComposedCharacterSequences(for: range)
        }

        if characterPairTrailingComponentDeletionMode == .immediatelyFollowingLeadingComponent
            && maximumLeadingCharacterPairComponentLength > 0
            && resultingRange.length <= maximumLeadingCharacterPairComponentLength {
            let stringToDelete = stringView.substring(in: resultingRange)
            if let characterPair = characterPairs.first(where: { $0.leading == stringToDelete }) {
                let trailingComponentLength = characterPair.trailing.utf16.count
                let trailingComponentRange = NSRange(location: resultingRange.upperBound, length: trailingComponentLength)
                if stringView.substring(in: trailingComponentRange) == characterPair.trailing {
                    let deleteRange = trailingComponentRange.upperBound - resultingRange.lowerBound
                    resultingRange = NSRange(location: resultingRange.lowerBound, length: deleteRange)
                }
            }
        }
        return resultingRange
    }

    private func addUndoOperation(replacing range: NSRange, withText text: String) {
        let oldSelection = selection
        timedUndoManager.beginUndoGrouping()
        timedUndoManager.setActionName(L10n.Undo.ActionName.typing)
        timedUndoManager.registerUndo(withTarget: self) { textInputView in
            textInputView.replaceText(in: range, with: text)
            textInputView.selection = oldSelection
            // Layout already happens inside replaceText via applyLineChangesToLayoutManager
            // Only mark for display, don't force synchronous layout
            textInputView.needsDisplay = true
        }
        // Note: Group is intentionally left open for TimedUndoManager's coalescing behavior
    }

    private func prepareTextForInsertion(_ text: String) -> String {
        var preparedText = text
        let lineEndingsToReplace: [LineEnding] = [.crlf, .cr, .lf].filter { $0 != lineEndings }
        for lineEnding in lineEndingsToReplace {
            preparedText = preparedText.replacingOccurrences(of: lineEnding.symbol, with: lineEndings.symbol)
        }
        return preparedText
    }

    private func safeSelectionRange(from range: NSRange) -> NSRange {
        let stringLength = stringView.string.length
        let cappedLocation = min(max(range.location, 0), stringLength)
        let cappedLength = min(max(range.length, 0), stringLength - cappedLocation)
        return NSRange(location: cappedLocation, length: cappedLength)
    }

    private func invalidateLines() {
        for lineController in lineControllerStorage {
            lineController.lineFragmentHeightMultiplier = lineHeightMultiplier
            lineController.tabWidth = indentController.tabWidth
            lineController.kern = kern
            lineController.lineBreakMode = lineBreakMode
            lineController.invalidateSyntaxHighlighting()
        }
    }

    private func performFullLayout() {
        invalidateLines()
        layoutManager.setNeedsLayout()
        layoutManager.layoutIfNeeded()
    }

    private func setupContentSizeObserver() {
        contentSizeService.$isContentSizeInvalid.filter { $0 }.sink { [weak self] _ in
            if let self = self {
                self.delegate?.textInputViewDidInvalidateContentSize(self)
            }
        }.store(in: &cancellables)
    }

    private func setupGutterWidthObserver() {
        gutterWidthService.didUpdateGutterWidth.sink { [weak self] in
            if let self = self {
                self.needsLayout = true
                self.invalidateLines()
                self.layoutManager.setNeedsLayout()
                self.delegate?.textInputViewDidChangeGutterWidth(self)
            }
        }.store(in: &cancellables)
    }

}

// MARK: - TreeSitterLanguageModeDelegate

extension TextInputViewMac: TreeSitterLanguageModeDelegate {
    func treeSitterLanguageMode(_ languageMode: TreeSitterInternalLanguageMode, bytesAt byteIndex: ByteCount) -> TreeSitterTextProviderResult? {
        guard byteIndex.value >= 0 && byteIndex < stringView.string.byteCount else {
            return nil
        }
        let targetByteCount: ByteCount = 4 * 1_024
        let endByte = min(byteIndex + targetByteCount, stringView.string.byteCount)
        let byteRange = ByteRange(from: byteIndex, to: endByte)
        if let result = stringView.bytes(in: byteRange) {
            return TreeSitterTextProviderResult(bytes: result.bytes, length: UInt32(result.length.value))
        } else {
            return nil
        }
    }

    func treeSitterLanguageModeDidTimeout(_ languageMode: TreeSitterInternalLanguageMode) {
        delegate?.textInputViewDidTimeoutParsing(self)
    }

    func treeSitterLanguageMode(_ languageMode: TreeSitterInternalLanguageMode, didReparseLines lines: Set<DocumentLineNode>) {
        guard languageMode === self.languageMode as AnyObject, !lines.isEmpty else { return }
        layoutManager.redisplayLines(withIDs: Set(lines.map(\.id)))
        layoutManager.setNeedsLayout()
        layoutManager.layoutIfNeeded()
    }

    func treeSitterLanguageMode(_ languageMode: TreeSitterInternalLanguageMode, didComputeFoldRegions regions: [FoldableRegion]) {
        guard languageMode === self.languageMode as AnyObject else { return }
        latestSyntaxFoldRegions = regions
        deliverSyntaxFoldRegions()
    }

    private func deliverSyntaxFoldRegions() {
        guard let regions = latestSyntaxFoldRegions, let manager = codeFoldingManager else { return }
        manager.applySyntaxTreeRegions(regions)
        layoutManager.setNeedsLayout()
    }

    /// Big documents skip the synchronous parse on load; run it in the background and
    /// highlight once it lands. Until then the text renders plain.
    private func startDeferredParseIfNeeded() {
        guard let treeSitterMode = languageMode as? TreeSitterInternalLanguageMode, treeSitterMode.needsDeferredParse else { return }
        let parsingMode = treeSitterMode
        treeSitterMode.parse(string) { [weak self] finished in
            guard let self = self, self.languageMode === parsingMode, finished else { return }
            self.invalidateLines()
            self.layoutManager.setNeedsLayout()
            self.layoutManager.layoutIfNeeded()
        }
    }
}

// MARK: - LineControllerStorageDelegate

extension TextInputViewMac: LineControllerStorageDelegate {
    func lineControllerStorage(_ storage: LineControllerStorage, didCreate lineController: LineController) {
        lineController.delegate = self
        lineController.constrainingWidth = layoutManager.constrainingLineWidth
        lineController.estimatedLineFragmentHeight = theme.font.totalLineHeight
        lineController.lineFragmentHeightMultiplier = lineHeightMultiplier
        lineController.tabWidth = indentController.tabWidth
        lineController.theme = theme
        lineController.lineBreakMode = lineBreakMode
    }
}

// MARK: - LineControllerDelegate

extension TextInputViewMac: LineControllerDelegate {
    func lineSyntaxHighlighter(for lineController: LineController) -> LineSyntaxHighlighter? {
        languageMode.createLineSyntaxHighlighter()
    }

    func lineControllerDidInvalidateLineWidthDuringAsyncSyntaxHighlight(_ lineController: LineController) {
        needsLayout = true
        layoutManager.setNeedsLayout()
    }
}

// MARK: - LayoutManagerDelegate

extension TextInputViewMac: LayoutManagerDelegate {
    func layoutManager(_ layoutManager: LayoutManager, didProposeContentOffsetAdjustment contentOffsetAdjustment: CGPoint) {
        delegate?.textInputView(self, didProposeContentOffsetAdjustment: contentOffsetAdjustment)
    }
}

// MARK: - IndentControllerDelegate

extension TextInputViewMac: IndentControllerDelegate {
    func indentController(_ controller: IndentController, shouldInsert text: String, in range: NSRange) {
        replaceText(in: range, with: text)
    }

    func indentController(_ controller: IndentController, shouldSelect range: NSRange) {
        selection = range
        layoutSubtreeIfNeeded()
    }

    func indentControllerDidUpdateTabWidth(_ controller: IndentController) {
        invalidateLines()
    }
}


// MARK: - Multiple selections & keyboard navigation

extension TextInputViewMac {
    /// Every selection, primary included, sorted by location.
    var allCarets: [CaretSelection] {
        caretsWithPrimary().carets
    }

    var selectedRanges: [NSRange] {
        allCarets.map(\.range)
    }

    var hasMultipleSelections: Bool {
        !secondaryCarets.isEmpty
    }

    fileprivate var primaryCaret: CaretSelection? {
        guard let range = _selectedRange else { return nil }
        if let anchor = primaryAnchor, anchor == range.location || anchor == range.upperBound {
            return CaretSelection(anchor: anchor, head: anchor == range.location ? range.upperBound : range.location)
        }
        return CaretSelection(range: range)
    }

    fileprivate func caretsWithPrimary() -> (carets: [CaretSelection], primary: Int) {
        guard let primary = primaryCaret else { return ([], 0) }
        return CaretSelection.normalized(secondaryCarets + [primary], primary: secondaryCarets.count)
    }

    /// Replaces every selection. `carets[primaryIndex]` becomes the primary.
    func setCarets(_ carets: [CaretSelection], primary primaryIndex: Int) {
        let (normalized, primary) = CaretSelection.normalized(carets.map(clamp), primary: primaryIndex)
        guard !normalized.isEmpty else {
            selection = nil
            return
        }
        let primaryCaret = normalized[primary]
        var others = normalized
        others.remove(at: primary)
        let previousPrimaryRange = _selectedRange
        let secondariesChanged = others != secondaryCarets
        isUpdatingSelections = true
        secondaryCarets = others
        primaryAnchor = primaryCaret.anchor
        selection = primaryCaret.range
        isUpdatingSelections = false
        if secondariesChanged {
            layoutManager.setNeedsDisplayOnLines()
            needsDisplay = true
            if previousPrimaryRange == _selectedRange {
                delegate?.textInputViewDidChangeSelection(self)
            }
        }
    }

    /// Sets the primary range without touching the other carets (used mid-edit).
    fileprivate func setPrimaryRangeDirectly(_ range: NSRange) {
        isUpdatingSelections = true
        selection = range
        isUpdatingSelections = false
    }

    private func clamp(_ caret: CaretSelection) -> CaretSelection {
        let length = stringView.string.length
        return CaretSelection(anchor: max(0, min(caret.anchor, length)), head: max(0, min(caret.head, length)))
    }

    /// Adds a caret at `location`, or removes the one already there. The result is primary.
    func toggleCaret(at location: Int) {
        var carets = allCarets
        if carets.count > 1, let index = carets.firstIndex(where: { $0.isCaret && $0.head == location }) {
            carets.remove(at: index)
            setCarets(carets, primary: carets.count - 1)
        } else {
            carets.append(CaretSelection(caretAt: location))
            setCarets(carets, primary: carets.count - 1)
        }
    }

    /// Esc: back to one cursor.
    func collapseToPrimarySelection() {
        guard hasMultipleSelections, let primary = primaryCaret else { return }
        setCarets([primary], primary: 0)
    }

    /// ⌘D: select the word at the caret, then each further occurrence of the selection.
    func selectNextOccurrence() {
        let string = stringView.string
        let (carets, primaryIndex) = caretsWithPrimary()
        guard carets.indices.contains(primaryIndex) else { return }
        let primary = carets[primaryIndex]
        if primary.isCaret {
            let word = TextNavigation.wordRange(at: primary.head, in: string)
            guard word.length > 0 else { return }
            var updated = carets
            updated[primaryIndex] = CaretSelection(range: word)
            setCarets(updated, primary: primaryIndex)
            return
        }
        let needle = string.substring(with: primary.range)
        let taken = Set(carets.map { $0.range.location })
        var searchFrom = primary.range.upperBound
        for _ in 0..<2 {
            var from = searchFrom
            while from <= string.length {
                let found = string.range(of: needle, options: [], range: NSRange(location: from, length: string.length - from))
                guard found.location != NSNotFound else { break }
                if !taken.contains(found.location) {
                    setCarets(carets + [CaretSelection(range: found)], primary: carets.count)
                    return
                }
                from = found.location + max(1, found.length)
            }
            searchFrom = 0 // wrap around once
        }
        NSSound.beep()
    }

    /// ⌘⇧L: one selection per occurrence of the selected text (or the word at the caret).
    func selectAllOccurrences() {
        let string = stringView.string
        let (carets, primaryIndex) = caretsWithPrimary()
        guard carets.indices.contains(primaryIndex) else { return }
        var primary = carets[primaryIndex]
        if primary.isCaret {
            primary = CaretSelection(range: TextNavigation.wordRange(at: primary.head, in: string))
        }
        guard primary.range.length > 0 else { return }
        let needle = string.substring(with: primary.range)
        var found: [CaretSelection] = []
        var from = 0
        while from <= string.length, found.count < 10_000 {
            let range = string.range(of: needle, options: [], range: NSRange(location: from, length: string.length - from))
            guard range.location != NSNotFound else { break }
            found.append(CaretSelection(range: range))
            from = range.location + max(1, range.length)
        }
        let primaryInFound = found.firstIndex { $0.range == primary.range } ?? found.count - 1
        setCarets(found, primary: primaryInFound)
    }

    /// ⌘⌥↑/↓ and ⌃⇧↑/↓: a caret on the line above the top-most / below the bottom-most one.
    func addCaret(_ direction: RSTextLayoutDirection) {
        let carets = allCarets
        guard let edge = direction == .up ? carets.first : carets.last else { return }
        guard let location = lineMovementController.location(from: edge.head, in: direction, offset: 1), location != edge.head else {
            NSSound.beep()
            return
        }
        setCarets(carets + [CaretSelection(caretAt: location)], primary: carets.count)
    }

    // MARK: Movement

    enum Motion {
        case left, right, wordLeft, wordRight
        case lineStart, lineEnd, lineStartHard, lineEndHard
        case paragraphBackward, paragraphForward
        case documentStart, documentEnd
        case up, down, pageUp, pageDown
    }

    fileprivate var linesPerPage: Int {
        max(1, Int(layoutManager.viewport.height / max(estimatedLineHeight, 1)) - 1)
    }

    /// Content range (no line break) of the line containing `location`.
    fileprivate func lineContentRange(containing location: Int) -> NSRange {
        let length = stringView.string.length
        let line = lineManager.line(containingCharacterAt: min(location, length)) ?? lineManager.line(atRow: lineManager.lineCount - 1)
        return NSRange(location: line.location, length: line.data.length)
    }

    fileprivate func destination(for motion: Motion, from caret: CaretSelection, extending: Bool) -> Int {
        let string = stringView.string
        let length = string.length
        let head = caret.head
        switch motion {
        case .left:
            if !extending && !caret.isCaret { return caret.range.location }
            guard head > 0 else { return 0 }
            return string.rangeOfComposedCharacterSequence(at: head - 1).location
        case .right:
            if !extending && !caret.isCaret { return caret.range.upperBound }
            guard head < length else { return length }
            return string.rangeOfComposedCharacterSequence(at: head).upperBound
        case .wordLeft:
            return TextNavigation.wordStart(before: head, in: string)
        case .wordRight:
            return TextNavigation.wordEnd(after: head, in: string)
        case .lineStart:
            // Smart home: first non-blank column, then the real start
            let content = lineContentRange(containing: head)
            let smart = TextNavigation.firstNonWhitespace(in: content, of: string)
            return head == smart ? content.location : smart
        case .lineStartHard:
            return lineContentRange(containing: head).location
        case .lineEnd, .lineEndHard:
            return lineContentRange(containing: head).upperBound
        case .paragraphBackward:
            let content = lineContentRange(containing: head)
            if head > content.location { return content.location }
            return content.location > 0 ? lineContentRange(containing: content.location - 1).location : 0
        case .paragraphForward:
            let content = lineContentRange(containing: head)
            if head < content.upperBound { return content.upperBound }
            let line = lineManager.line(containingCharacterAt: min(head, length))
            if let line, line.index + 1 < lineManager.lineCount {
                let next = lineManager.line(atRow: line.index + 1)
                return next.location + next.data.length
            }
            return length
        case .documentStart:
            return 0
        case .documentEnd:
            return length
        case .up:
            return lineMovementController.location(from: head, in: .up, offset: 1) ?? 0
        case .down:
            return lineMovementController.location(from: head, in: .down, offset: 1) ?? length
        case .pageUp:
            return lineMovementController.location(from: head, in: .up, offset: linesPerPage) ?? 0
        case .pageDown:
            return lineMovementController.location(from: head, in: .down, offset: linesPerPage) ?? length
        }
    }

    /// Moves every caret; with `extending`, the anchors stay and only the heads move.
    func move(_ motion: Motion, extending: Bool) {
        let (carets, primaryIndex) = caretsWithPrimary()
        guard !carets.isEmpty else { return }
        let moved = carets.map { caret -> CaretSelection in
            let target = destination(for: motion, from: caret, extending: extending)
            return extending ? CaretSelection(anchor: caret.anchor, head: target) : CaretSelection(caretAt: target)
        }
        setCarets(moved, primary: primaryIndex)
    }

    // MARK: Multi-caret editing

    /// Runs `edit` for every selection from last to first, so earlier offsets stay valid,
    /// then puts each caret where its edit left the primary range, shifted by the
    /// length changes of the edits before it. Single selection: just runs `edit`.
    func editAllCarets(_ edit: (NSRange) -> Void) {
        let (carets, primaryIndex) = caretsWithPrimary()
        guard carets.count > 1 else {
            if let only = carets.first { edit(only.range) }
            return
        }
        isUpdatingSelections = true
        var afterEdit: [(range: NSRange, delta: Int)] = Array(repeating: (NSRange(location: 0, length: 0), 0), count: carets.count)
        for (index, caret) in carets.enumerated().reversed() {
            _selectedRange = caret.range
            let before = stringView.string.length
            edit(caret.range)
            afterEdit[index] = (_selectedRange ?? caret.range, stringView.string.length - before)
        }
        isUpdatingSelections = false
        var shift = 0
        var finals: [CaretSelection] = []
        for item in afterEdit {
            finals.append(CaretSelection(range: NSRange(location: item.range.location + shift, length: item.range.length)))
            shift += item.delta
        }
        setCarets(finals, primary: primaryIndex)
    }

    fileprivate func deleteRange(for caret: CaretSelection, motion: Motion) -> NSRange? {
        if !caret.isCaret { return caret.range }
        let target = destination(for: motion, from: caret, extending: true)
        guard target != caret.head else {
            // Already at the boundary: ⌘⌫ at a line start joins with the previous line, ⌃K at a line end joins the next
            switch motion {
            case .lineStartHard, .lineStart, .wordLeft:
                return caret.head > 0 ? NSRange(location: caret.head - 1, length: 1) : nil
            case .lineEndHard, .lineEnd, .wordRight:
                return caret.head < stringView.string.length ? NSRange(location: caret.head, length: 1) : nil
            default:
                return nil
            }
        }
        return NSRange(location: min(target, caret.head), length: abs(target - caret.head))
    }

    fileprivate func delete(_ motion: Motion) {
        editAllCarets { range in
            let caret = CaretSelection(range: range)
            guard let deleteRange = self.deleteRange(for: caret, motion: motion), deleteRange.length > 0 else { return }
            guard self.delegate?.textInputView(self, shouldChangeTextIn: deleteRange, replacementText: "") ?? true else { return }
            self.replaceText(in: deleteRange, with: "")
        }
        delegate?.textInputViewDidChangeSelection(self)
    }

    fileprivate func insertTabOrIndent() {
        let spansLines = allCarets.contains { caret in
            caret.range.length > 0 && lineManager.lines(in: caret.range).count > 1
        }
        if spansLines {
            editAllCarets { range in
                if range.length > 0 { self.indentController.shiftRight(in: range) }
            }
        } else {
            insertText("\t", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    fileprivate func outdent() {
        editAllCarets { range in
            self.indentController.shiftLeft(in: range)
        }
    }

    // MARK: Key bindings

    /// The standard macOS editing selectors (NSStandardKeyBindingResponding). Returns false when unhandled.
    func handleStandardKeyBinding(_ selector: Selector) -> Bool {
        let moves: [Selector: (Motion, Bool)] = [
            #selector(NSResponder.moveLeft(_:)): (.left, false),
            #selector(NSResponder.moveRight(_:)): (.right, false),
            #selector(NSResponder.moveUp(_:)): (.up, false),
            #selector(NSResponder.moveDown(_:)): (.down, false),
            #selector(NSResponder.moveBackward(_:)): (.left, false),
            #selector(NSResponder.moveForward(_:)): (.right, false),
            #selector(NSResponder.moveWordLeft(_:)): (.wordLeft, false),
            #selector(NSResponder.moveWordRight(_:)): (.wordRight, false),
            #selector(NSResponder.moveWordBackward(_:)): (.wordLeft, false),
            #selector(NSResponder.moveWordForward(_:)): (.wordRight, false),
            #selector(NSResponder.moveToBeginningOfLine(_:)): (.lineStart, false),
            #selector(NSResponder.moveToLeftEndOfLine(_:)): (.lineStart, false),
            #selector(NSResponder.moveToEndOfLine(_:)): (.lineEnd, false),
            #selector(NSResponder.moveToRightEndOfLine(_:)): (.lineEnd, false),
            #selector(NSResponder.moveToBeginningOfParagraph(_:)): (.lineStartHard, false),
            #selector(NSResponder.moveToEndOfParagraph(_:)): (.lineEndHard, false),
            #selector(NSResponder.moveToBeginningOfDocument(_:)): (.documentStart, false),
            #selector(NSResponder.moveToEndOfDocument(_:)): (.documentEnd, false),
            #selector(NSResponder.pageUp(_:)): (.pageUp, false),
            #selector(NSResponder.pageDown(_:)): (.pageDown, false),
            #selector(NSResponder.moveLeftAndModifySelection(_:)): (.left, true),
            #selector(NSResponder.moveRightAndModifySelection(_:)): (.right, true),
            #selector(NSResponder.moveUpAndModifySelection(_:)): (.up, true),
            #selector(NSResponder.moveDownAndModifySelection(_:)): (.down, true),
            #selector(NSResponder.moveBackwardAndModifySelection(_:)): (.left, true),
            #selector(NSResponder.moveForwardAndModifySelection(_:)): (.right, true),
            #selector(NSResponder.moveWordLeftAndModifySelection(_:)): (.wordLeft, true),
            #selector(NSResponder.moveWordRightAndModifySelection(_:)): (.wordRight, true),
            #selector(NSResponder.moveWordBackwardAndModifySelection(_:)): (.wordLeft, true),
            #selector(NSResponder.moveWordForwardAndModifySelection(_:)): (.wordRight, true),
            #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)): (.lineStartHard, true),
            #selector(NSResponder.moveToLeftEndOfLineAndModifySelection(_:)): (.lineStartHard, true),
            #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)): (.lineEnd, true),
            #selector(NSResponder.moveToRightEndOfLineAndModifySelection(_:)): (.lineEnd, true),
            #selector(NSResponder.moveToBeginningOfParagraphAndModifySelection(_:)): (.lineStartHard, true),
            #selector(NSResponder.moveToEndOfParagraphAndModifySelection(_:)): (.lineEndHard, true),
            #selector(NSResponder.moveParagraphBackwardAndModifySelection(_:)): (.paragraphBackward, true),
            #selector(NSResponder.moveParagraphForwardAndModifySelection(_:)): (.paragraphForward, true),
            #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)): (.documentStart, true),
            #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)): (.documentEnd, true),
            #selector(NSResponder.pageUpAndModifySelection(_:)): (.pageUp, true),
            #selector(NSResponder.pageDownAndModifySelection(_:)): (.pageDown, true),
        ]
        if let (motion, extending) = moves[selector] {
            move(motion, extending: extending)
            return true
        }
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)):
            deleteBackward(nil)
        case #selector(NSResponder.deleteForward(_:)):
            deleteForward(nil)
        case #selector(NSResponder.deleteWordBackward(_:)):
            delete(.wordLeft)
        case #selector(NSResponder.deleteWordForward(_:)):
            delete(.wordRight)
        case #selector(NSResponder.deleteToBeginningOfLine(_:)), #selector(NSResponder.deleteToBeginningOfParagraph(_:)):
            delete(.lineStartHard)
        case #selector(NSResponder.deleteToEndOfLine(_:)), #selector(NSResponder.deleteToEndOfParagraph(_:)):
            delete(.lineEndHard)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertTabIgnoringFieldEditor(_:)):
            insertTabOrIndent()
        case #selector(NSResponder.insertBacktab(_:)):
            outdent()
        case #selector(NSResponder.selectAll(_:)):
            selectAll(nil)
        case #selector(NSResponder.selectWord(_:)):
            let (carets, primary) = caretsWithPrimary()
            setCarets(carets.map { CaretSelection(range: TextNavigation.wordRange(at: $0.head, in: stringView.string)) }, primary: primary)
        case #selector(NSResponder.selectLine(_:)), #selector(NSResponder.selectParagraph(_:)):
            let (carets, primary) = caretsWithPrimary()
            setCarets(carets.map { CaretSelection(range: lineContentRange(containing: $0.head)) }, primary: primary)
        case #selector(NSResponder.cancelOperation(_:)):
            guard hasMultipleSelections else { return false }
            collapseToPrimarySelection()
        default:
            return false
        }
        return true
    }

    /// Editor shortcuts that are not standard key bindings. Returns false when unhandled.
    func handleEditorKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, key, event.specialKey) {
        case ([.command], "d", _):
            selectNextOccurrence()
        case ([.command, .shift], "l", _):
            selectAllOccurrences()
        case ([.command, .option], _, .upArrow?), ([.control, .shift], _, .upArrow?):
            addCaret(.up)
        case ([.command, .option], _, .downArrow?), ([.control, .shift], _, .downArrow?):
            addCaret(.down)
        default:
            return false
        }
        return true
    }
}

#if DEBUG
extension TextInputViewMac {
    /// Every highlight capture in the document, for tests comparing incremental and fresh parses.
    var debugIsParsingIdle: Bool {
        (languageMode as? TreeSitterInternalLanguageMode)?.debugIsParsingIdle ?? true
    }

    func debugCaptureSignature() -> [String] {
        guard let mode = languageMode as? TreeSitterInternalLanguageMode else { return [] }
        let range = ByteRange(location: ByteCount(0), length: ByteCount(string.length * 2))
        return mode.captures(in: range).map { "\($0.name)@\($0.byteRange.location.value)+\($0.byteRange.length.value)" }.sorted()
    }
}
#endif

#endif // canImport(AppKit)
