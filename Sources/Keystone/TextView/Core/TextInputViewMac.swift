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
        }
    }

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
                }
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

        guard let sel = selection else { return }

        if sel.length > 0 {
            // Draw selection highlight
            // Draw all selection rects without filtering by dirtyRect
            // to ensure complete selection highlighting for wrapped lines
            let rects = selectionRectService.selectionRects(in: sel)
            selectionHighlightColor.setFill()
            for rect in rects {
                let selRect = rect.rect
                let path = NSBezierPath(rect: selRect)
                path.fill()
            }
        } else if isEditing && isCaretVisible {
            // Draw caret (insertion point)
            let caretRect = caretRectService.caretRect(at: sel.location, allowMovingCaretToNextLineFragment: true)
            if caretRect.intersects(dirtyRect) {
                insertionPointColor.setFill()
                let path = NSBezierPath(rect: caretRect)
                path.fill()
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
        let range = replacementRange.location == NSNotFound ? (selection ?? NSRange(location: stringView.string.length, length: 0)) : replacementRange

        guard delegate?.textInputView(self, shouldChangeTextIn: range, replacementText: preparedText) ?? true else {
            return
        }

        if LineEnding(symbol: text) != nil {
            indentController.insertLineBreak(in: range, using: lineEndings)
        } else {
            // Check for character pair auto-insertion
            if let characterPair = characterPairs.first(where: { $0.leading == preparedText }) {
                // Insert both leading and trailing, position cursor between
                let pairedText = preparedText + characterPair.trailing
                replaceText(in: range, with: pairedText)
                // Move cursor to between the pair
                let cursorPosition = range.location + preparedText.utf16.count
                selection = NSRange(location: cursorPosition, length: 0)
            } else {
                replaceText(in: range, with: preparedText)
            }
        }

        layoutSubtreeIfNeeded()
        delegate?.textInputViewDidChangeSelection(self)
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
        if selector == #selector(deleteBackward(_:)) {
            deleteBackward(nil)
        } else if selector == #selector(deleteForward(_:)) {
            deleteForward(nil)
        } else if selector == #selector(moveLeft(_:)) {
            moveLeft(nil)
        } else if selector == #selector(moveRight(_:)) {
            moveRight(nil)
        } else if selector == #selector(moveUp(_:)) {
            moveUp(nil)
        } else if selector == #selector(moveDown(_:)) {
            moveDown(nil)
        } else if selector == #selector(insertNewline(_:)) {
            insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        } else if selector == #selector(insertTab(_:)) {
            insertText("\t", replacementRange: NSRange(location: NSNotFound, length: 0))
        } else if selector == #selector(selectAll(_:)) {
            selectAll(nil)
        } else {
            super.doCommand(by: selector)
        }
    }

    // MARK: - Standard Actions

    @objc override func deleteBackward(_ sender: Any?) {
        guard var range = _markedRange ?? _selectedRange, range.location > 0 || range.length > 0 else {
            return
        }

        if range.length == 0 {
            range = NSRange(location: range.location - 1, length: 1)
        }

        let deleteRange = rangeForDeletingText(in: range)

        if deleteRange == _markedRange {
            _markedRange = nil
            _markedText = nil
        }

        guard delegate?.textInputView(self, shouldChangeTextIn: deleteRange, replacementText: "") ?? true else {
            return
        }

        replaceText(in: deleteRange, with: "")
        delegate?.textInputViewDidChangeSelection(self)
    }

    @objc override func deleteForward(_ sender: Any?) {
        guard var range = _selectedRange, range.upperBound < string.length else {
            return
        }

        if range.length == 0 {
            range = NSRange(location: range.location, length: 1)
        }

        guard delegate?.textInputView(self, shouldChangeTextIn: range, replacementText: "") ?? true else {
            return
        }

        replaceText(in: range, with: "")
        delegate?.textInputViewDidChangeSelection(self)
    }

    @objc override func moveLeft(_ sender: Any?) {
        guard let range = _selectedRange else { return }
        let newLocation = max(0, range.location - 1)
        selection = NSRange(location: newLocation, length: 0)
    }

    @objc override func moveRight(_ sender: Any?) {
        guard let range = _selectedRange else { return }
        let newLocation = min(string.length, range.upperBound + 1)
        selection = NSRange(location: newLocation, length: 0)
    }

    @objc override func moveUp(_ sender: Any?) {
        guard let range = _selectedRange else { return }
        if let newLocation = lineMovementController.location(from: range.location, in: .up, offset: 1) {
            selection = NSRange(location: newLocation, length: 0)
        }
    }

    @objc override func moveDown(_ sender: Any?) {
        guard let range = _selectedRange else { return }
        if let newLocation = lineMovementController.location(from: range.location, in: .down, offset: 1) {
            selection = NSRange(location: newLocation, length: 0)
        }
    }

    @objc override func selectAll(_ sender: Any?) {
        selection = NSRange(location: 0, length: string.length)
    }

    @objc func copy(_ sender: Any?) {
        guard let selectedRange = selection, selectedRange.length > 0 else { return }
        let selectedText = stringView.string.substring(with: selectedRange)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
    }

    @objc func cut(_ sender: Any?) {
        guard let selectedRange = selection, selectedRange.length > 0 else { return }
        let selectedText = stringView.string.substring(with: selectedRange)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
        // Delete the selected text
        replaceText(in: selectedRange, with: "")
    }

    @objc func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let pasteString = pasteboard.string(forType: .string) else { return }
        let range = selection ?? NSRange(location: stringView.string.length, length: 0)
        replaceText(in: range, with: pasteString)
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
        } else {
            // Normal character-by-character selection
            let start = min(anchor, index)
            let end = max(anchor, index)
            selection = NSRange(location: start, length: end - start)
        }
    }

    override func mouseUp(with event: NSEvent) {
        selectionAnchor = nil
        wordSelectionMode = false
        lineSelectionMode = false
        originalWordRange = nil
        originalLineRange = nil
    }

    /// Returns the range of the word at the given index
    private func wordRange(at index: Int) -> NSRange {
        let nsString = stringView.string
        let length = nsString.length
        guard index >= 0 && index <= length else {
            return NSRange(location: index, length: 0)
        }

        // Find word boundaries using character sets
        let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

        var start = index
        var end = index

        // Expand backwards to find word start
        while start > 0 {
            let charIndex = start - 1
            let char = nsString.character(at: charIndex)
            guard let scalar = Unicode.Scalar(char), wordCharacters.contains(scalar) else { break }
            start -= 1
        }

        // Expand forwards to find word end
        while end < length {
            let char = nsString.character(at: end)
            guard let scalar = Unicode.Scalar(char), wordCharacters.contains(scalar) else { break }
            end += 1
        }

        return NSRange(location: start, length: end - start)
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

#endif // canImport(AppKit)
