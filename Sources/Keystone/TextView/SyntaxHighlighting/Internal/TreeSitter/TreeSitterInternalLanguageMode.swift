import Foundation
import TreeSitter

protocol TreeSitterLanguageModeDelegate: AnyObject {
    func treeSitterLanguageMode(_ languageMode: TreeSitterInternalLanguageMode, bytesAt byteIndex: ByteCount) -> TreeSitterTextProviderResult?
    /// Called when parsing times out. The delegate should switch to plaintext mode.
    func treeSitterLanguageModeDidTimeout(_ languageMode: TreeSitterInternalLanguageMode)
    /// A background reparse finished; these lines need their highlighting refreshed.
    func treeSitterLanguageMode(_ languageMode: TreeSitterInternalLanguageMode, didReparseLines lines: Set<DocumentLineNode>)
}

/// Tree-sitter parsing and querying for one text view.
///
/// Small documents parse synchronously on each edit, which is sub-millisecond.
/// From ``backgroundParseThreshold`` up, every tree mutation, reparse and highlight
/// query runs on one serial background queue: an edit enqueues a cheap
/// `ts_tree_edit`, a parse runs against a snapshot of the text, and the main thread
/// is never blocked on the parser. Highlights lag the text by at most one parse,
/// which is how Zed and VS Code behave.
final class TreeSitterInternalLanguageMode: InternalLanguageMode {
    /// Documents with at least this many UTF-16 units parse on the background queue.
    nonisolated(unsafe) static var backgroundParseThreshold = 200_000

    weak var delegate: TreeSitterLanguageModeDelegate?
    var canHighlight: Bool { hasTree }
    var prefersAsynchronousHighlighting: Bool { isBackgroundMode }
    /// True when the text was too big to parse synchronously on load. The owning
    /// view calls `parse(_:completion:)` to run that parse in the background.
    private(set) var needsDeferredParse = false

    private let textSource: TreeSitterTextSource
    private var stringView: StringView { textSource.live }
    private let parser: TreeSitterParser
    private let lineManager: LineManager
    private let rootLanguageLayer: TreeSitterLanguageLayer
    /// Serial: tree edits, parses and highlight queries never overlap.
    private let operationQueue = OperationQueue()
    /// Held while trees are read or written, so the main thread can read a tree
    /// between background operations (or skip the read if one is running).
    private let treeLock = NSLock()
    /// Set once a parse has produced a tree; read without the lock.
    private var hasTree = false

    // Main-thread scheduling state for the background pipeline.
    private var isParseInFlight = false
    private var hasEditsSinceSnapshot = false
    // Queue-confined: bytes edited since the last reparse, in current coordinates.
    private var pendingWindow: ByteRange?

    private var isBackgroundMode: Bool {
        stringView.string.length >= Self.backgroundParseThreshold
    }

    init(language: TreeSitterInternalLanguage, languageProvider: TreeSitterLanguageProvider?, stringView: StringView, lineManager: LineManager) {
        self.textSource = TreeSitterTextSource(live: stringView)
        self.lineManager = lineManager
        operationQueue.name = "TreeSitterLanguageMode"
        operationQueue.qualityOfService = .userInitiated
        operationQueue.maxConcurrentOperationCount = 1
        parser = TreeSitterParser(encoding: TSInputEncodingUTF16LE)
        rootLanguageLayer = TreeSitterLanguageLayer(
            language: language,
            languageProvider: languageProvider,
            parser: parser,
            textSource: textSource)
        parser.delegate = self
    }

    deinit {
        operationQueue.cancelAllOperations()
    }

    // MARK: - Parsing

    func parse(_ text: NSString) {
        if text.length >= Self.backgroundParseThreshold {
            // Too big to block the main thread on; the view starts a background parse.
            needsDeferredParse = true
            return
        }
        needsDeferredParse = false
        treeLock.withLock {
            rootLanguageLayer.parse(text)
        }
        hasTree = !parser.didTimeout
        if parser.didTimeout {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.treeSitterLanguageModeDidTimeout(self)
            }
        }
    }

    func parse(_ text: NSString, completion: @escaping ((Bool) -> Void)) {
        needsDeferredParse = false
        // Snapshot now: the live buffer may change while the parse runs.
        let snapshot = text.mutableCopy() as! NSMutableString
        operationQueue.cancelAllOperations()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation, weak self] in
            guard let self = self, let operation = operation, !operation.isCancelled else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.treeLock.withLock {
                self.textSource.snapshot = StringView(string: snapshot)
                defer { self.textSource.snapshot = nil }
                self.rootLanguageLayer.parse(snapshot)
            }
            let didTimeout = self.parser.didTimeout
            DispatchQueue.main.async {
                if didTimeout {
                    self.delegate?.treeSitterLanguageModeDidTimeout(self)
                } else if !operation.isCancelled {
                    self.hasTree = true
                }
                completion(!operation.isCancelled && !didTimeout)
                // Edits that arrived during the parse were queued behind it; parse them too.
                self.scheduleBackgroundParseIfNeeded()
            }
        }
        operationQueue.addOperation(operation)
    }

    func textDidChange(_ change: TextChange) -> LineChangeSet {
        let bytesRemoved = change.byteRange.length
        let bytesAdded = change.bytesAdded
        let edit = TreeSitterInputEdit(
            startByte: change.byteRange.location,
            oldEndByte: change.byteRange.location + bytesRemoved,
            newEndByte: change.byteRange.location + bytesAdded,
            startPoint: TreeSitterTextPoint(change.startLinePosition),
            oldEndPoint: TreeSitterTextPoint(change.oldEndLinePosition),
            newEndPoint: TreeSitterTextPoint(change.newEndLinePosition))

        guard isBackgroundMode else {
            let changed = treeLock.withLock { rootLanguageLayer.apply(edit) }
            hasTree = hasTree || !parser.didTimeout
            return lineChangeSet(forChangedByteRanges: changed)
        }

        // Background mode: adjust the trees now (cheap), reparse off the main thread.
        let window = TreeSitterLanguageLayer.window(for: edit)
        operationQueue.addOperation { [weak self] in
            guard let self = self else { return }
            self.treeLock.withLock {
                self.rootLanguageLayer.applyEditWithoutReparse(edit)
            }
            self.pendingWindow = self.pendingWindow.map { TreeSitterLanguageLayer.shift($0, for: edit).union(window) } ?? window
        }
        hasEditsSinceSnapshot = true
        scheduleBackgroundParseIfNeeded()
        // The edited lines are redisplayed by the text edit itself; the rest follows the parse.
        return LineChangeSet()
    }

    /// Runs at most one parse at a time; edits that arrive meanwhile are batched into the next.
    private func scheduleBackgroundParseIfNeeded() {
        guard hasEditsSinceSnapshot, !isParseInFlight else { return }
        isParseInFlight = true
        hasEditsSinceSnapshot = false
        // The parser reads this instead of the live buffer. ~1 ms for a few MB.
        let snapshot = stringView.string.mutableCopy() as! NSMutableString
        operationQueue.addOperation { [weak self] in
            guard let self = self else { return }
            let window = self.pendingWindow
            self.pendingWindow = nil
            let changed: [ByteRange] = self.treeLock.withLock {
                self.textSource.snapshot = StringView(string: snapshot)
                defer { self.textSource.snapshot = nil }
                return self.rootLanguageLayer.reparse(parsing: [], window: window)
            }
            let didTimeout = self.parser.didTimeout
            DispatchQueue.main.async {
                self.isParseInFlight = false
                if didTimeout {
                    self.delegate?.treeSitterLanguageModeDidTimeout(self)
                    return
                }
                self.hasTree = true
                self.delegate?.treeSitterLanguageMode(self, didReparseLines: self.lines(forChangedByteRanges: changed))
                self.scheduleBackgroundParseIfNeeded()
            }
        }
    }

    private func lines(forChangedByteRanges ranges: [ByteRange]) -> Set<DocumentLineNode> {
        var lines: Set<DocumentLineNode> = []
        let length = stringView.string.length
        for range in ranges {
            var nsRange = NSRange(range)
            guard nsRange.location < length else { continue }
            nsRange.length = min(nsRange.length, length - nsRange.location)
            lines.formUnion(lineManager.lines(in: nsRange))
        }
        return lines
    }

    private func lineChangeSet(forChangedByteRanges ranges: [ByteRange]) -> LineChangeSet {
        let lineChangeSet = LineChangeSet()
        for line in lines(forChangedByteRanges: ranges) {
            lineChangeSet.markLineEdited(line)
        }
        return lineChangeSet
    }

    // MARK: - Queries

    func captures(in range: ByteRange) -> [TreeSitterCapture] {
        treeLock.withLock {
            rootLanguageLayer.captures(in: range)
        }
    }

    func createLineSyntaxHighlighter() -> LineSyntaxHighlighter {
        TreeSitterSyntaxHighlighter(stringView: stringView, languageMode: self, operationQueue: operationQueue)
    }

    func currentIndentLevel(of line: DocumentLineNode, using indentStrategy: IndentStrategy) -> Int {
        let measurer = IndentLevelMeasurer(stringView: stringView)
        return measurer.indentLevel(lineStartLocation: line.location, lineTotalLength: line.data.totalLength, tabLength: indentStrategy.tabLength)
    }

    func strategyForInsertingLineBreak(from startLinePosition: LinePosition,
                                       to endLinePosition: LinePosition,
                                       using indentStrategy: IndentStrategy) -> InsertLineBreakIndentStrategy {
        // While a background parse holds the tree, fall back to scope rules without nodes
        // rather than making the Return key wait for the parser.
        let layersAndNodes: (start: TreeSitterLanguageLayer.LayerAndNodeTuple?, end: TreeSitterLanguageLayer.LayerAndNodeTuple?)? = withTreeIfAvailable {
            (rootLanguageLayer.layerAndNode(at: startLinePosition), rootLanguageLayer.layerAndNode(at: endLinePosition))
        }
        let startLayerAndNode = layersAndNodes?.start
        let endLayerAndNode = layersAndNodes?.end
        let scopes = startLayerAndNode?.layer.language.indentationScopes
            ?? endLayerAndNode?.layer.language.indentationScopes
            ?? (layersAndNodes == nil ? rootLanguageLayer.language.indentationScopes : nil)
        if let indentationScopes = scopes {
            let indentController = TreeSitterIndentController(
                indentationScopes: indentationScopes,
                stringView: stringView,
                lineManager: lineManager,
                tabLength: indentStrategy.tabLength)
            return indentController.strategyForInsertingLineBreak(
                between: startLayerAndNode?.node,
                and: endLayerAndNode?.node,
                caretStartPosition: startLinePosition,
                caretEndPosition: endLinePosition)
        } else {
            return InsertLineBreakIndentStrategy(indentLevel: 0, insertExtraLineBreak: false)
        }
    }

    func syntaxNode(at linePosition: LinePosition) -> SyntaxNode? {
        let found: SyntaxNode?? = withTreeIfAvailable {
            if let node = rootLanguageLayer.layerAndNode(at: linePosition)?.node, let type = node.type {
                let startLocation = TextLocation(LinePosition(node.startPoint))
                let endLocation = TextLocation(LinePosition(node.endPoint))
                return SyntaxNode(type: type, startLocation: startLocation, endLocation: endLocation)
            }
            return nil
        }
        return found ?? nil
    }

    func detectIndentStrategy() -> DetectedIndentStrategy {
        let detected: DetectedIndentStrategy? = withTreeIfAvailable {
            if let tree = rootLanguageLayer.tree {
                let detector = TreeSitterIndentStrategyDetector(lineManager: lineManager, tree: tree, stringView: stringView)
                return detector.detect()
            }
            return .unknown
        }
        return detected ?? .unknown
    }

    #if DEBUG
    /// True when no parse is queued, running, or pending. For tests.
    var debugIsParsingIdle: Bool {
        operationQueue.operationCount == 0 && !isParseInFlight && !hasEditsSinceSnapshot && !needsDeferredParse
    }
    #endif

    /// Runs `body` with the tree lock. In background mode it won't wait for a running
    /// parse: it returns nil instead, and callers use a tree-free fallback.
    private func withTreeIfAvailable<T>(_ body: () -> T) -> T? {
        if isBackgroundMode {
            guard treeLock.try() else { return nil }
        } else {
            treeLock.lock()
        }
        defer { treeLock.unlock() }
        return body()
    }
}

extension TreeSitterInternalLanguageMode: TreeSitterParserDelegate {
    func parser(_ parser: TreeSitterParser, bytesAt byteIndex: ByteCount) -> TreeSitterTextProviderResult? {
        if let snapshot = textSource.snapshot {
            return Self.bytes(from: snapshot, at: byteIndex)
        }
        return delegate?.treeSitterLanguageMode(self, bytesAt: byteIndex)
    }

    /// Same chunking as the text views' live provider, against a snapshot.
    static func bytes(from stringView: StringView, at byteIndex: ByteCount) -> TreeSitterTextProviderResult? {
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
}
