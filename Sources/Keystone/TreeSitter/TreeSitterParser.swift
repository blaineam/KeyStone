import Foundation
import TreeSitter

protocol TreeSitterParserDelegate: AnyObject {
    func parser(_ parser: TreeSitterParser, bytesAt byteIndex: ByteCount) -> TreeSitterTextProviderResult?
}

/// Thread-local storage for parse timeout tracking
private class ParseTimeoutContext {
    var startTime: CFAbsoluteTime = 0
    var timeoutSeconds: Double = 30
    var didTimeout: Bool = false

    static let threadLocal = ThreadLocal<ParseTimeoutContext>()
}

/// Simple thread-local storage wrapper
private class ThreadLocal<T: AnyObject> {
    private let key = UUID().uuidString

    var value: T? {
        get { Thread.current.threadDictionary[key] as? T }
        set { Thread.current.threadDictionary[key] = newValue }
    }
}

/// C callback for progress - returns true to cancel parsing
private let parseProgressCallback: @convention(c) (UnsafeMutablePointer<TSParseState>?) -> Bool = { _ in
    guard let context = ParseTimeoutContext.threadLocal.value else {
        return false
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - context.startTime
    if elapsed > context.timeoutSeconds {
        context.didTimeout = true
        return true  // Cancel parsing
    }
    return false  // Continue parsing
}

final class TreeSitterParser {
    weak var delegate: TreeSitterParserDelegate?
    let encoding: TSInputEncoding
    var language: OpaquePointer? {
        didSet {
            ts_parser_set_language(pointer, language)
        }
    }
    var canParse: Bool {
        language != nil
    }

    /// Timeout for parsing in seconds. Default is 30 seconds.
    var timeoutSeconds: Double = 30

    /// Returns true if the last parse operation was cancelled due to timeout.
    private(set) var didTimeout = false

    private var pointer: OpaquePointer

    init(encoding: TSInputEncoding) {
        self.encoding = encoding
        self.pointer = ts_parser_new()
    }

    deinit {
        ts_parser_delete(pointer)
    }

    func parse(_ string: NSString, oldTree: TreeSitterTree? = nil) -> TreeSitterTree? {
        didTimeout = false
        guard string.length > 0 else {
            return nil
        }
        guard let stringEncoding = encoding.stringEncoding else {
            return nil
        }

        // Set up timeout context
        let context = ParseTimeoutContext()
        context.startTime = CFAbsoluteTimeGetCurrent()
        context.timeoutSeconds = timeoutSeconds
        context.didTimeout = false
        ParseTimeoutContext.threadLocal.value = context

        var usedLength = 0
        let buffer = string.getAllBytes(withEncoding: stringEncoding, usedLength: &usedLength)
        let bufferLength = usedLength

        // Create a text input that reads from the buffer
        let input = TreeSitterTextInput(encoding: encoding) { byteIndex, _ in
            guard let buffer = buffer else { return nil }
            let index = Int(byteIndex.value)
            if index >= bufferLength {
                return nil
            }
            let remaining = bufferLength - index
            let bytesPointer = UnsafeMutablePointer<Int8>.allocate(capacity: remaining)
            bytesPointer.initialize(from: buffer.advanced(by: index), count: remaining)
            return TreeSitterTextProviderResult(bytes: bytesPointer, length: UInt32(remaining))
        }

        // Create parse options with progress callback for timeout
        let parseOptions = TSParseOptions(
            payload: nil,
            progress_callback: parseProgressCallback
        )

        let newTreePointer = ts_parser_parse_with_options(pointer, oldTree?.pointer, input.makeTSInput(), parseOptions)
        input.deallocate()
        buffer?.deallocate()

        // Check if we timed out
        didTimeout = context.didTimeout
        ParseTimeoutContext.threadLocal.value = nil

        if didTimeout {
            ts_parser_reset(pointer)
            return nil
        }

        if let newTreePointer = newTreePointer {
            return TreeSitterTree(newTreePointer)
        } else {
            return nil
        }
    }

    func parse(oldTree: TreeSitterTree? = nil) -> TreeSitterTree? {
        didTimeout = false

        // Set up timeout context
        let context = ParseTimeoutContext()
        context.startTime = CFAbsoluteTimeGetCurrent()
        context.timeoutSeconds = timeoutSeconds
        context.didTimeout = false
        ParseTimeoutContext.threadLocal.value = context

        let input = TreeSitterTextInput(encoding: encoding) { [weak self] byteIndex, _ in
            if let self = self {
                return self.delegate?.parser(self, bytesAt: byteIndex)
            } else {
                return nil
            }
        }

        // Create parse options with progress callback for timeout
        let parseOptions = TSParseOptions(
            payload: nil,
            progress_callback: parseProgressCallback
        )

        let newTreePointer = ts_parser_parse_with_options(pointer, oldTree?.pointer, input.makeTSInput(), parseOptions)
        input.deallocate()

        // Check if we timed out
        didTimeout = context.didTimeout
        ParseTimeoutContext.threadLocal.value = nil

        if didTimeout {
            ts_parser_reset(pointer)
            return nil
        }

        if let newTreePointer = newTreePointer {
            return TreeSitterTree(newTreePointer)
        } else {
            return nil
        }
    }

    @discardableResult
    func setIncludedRanges(_ ranges: [TreeSitterTextRange]) -> Bool {
        let rawRanges = ranges.map { $0.rawValue }
        return rawRanges.withUnsafeBufferPointer { rangesPointer in
            ts_parser_set_included_ranges(pointer, rangesPointer.baseAddress, UInt32(rawRanges.count))
        }
    }

    func removeAllIncludedRanges() {
        ts_parser_set_included_ranges(pointer, nil, 0)
    }
}

private extension TSInputEncoding {
    var stringEncoding: String.Encoding? {
        switch self {
        case TSInputEncodingUTF8:
            return .utf8
        case TSInputEncodingUTF16LE:
            return .utf16LittleEndian
        case TSInputEncodingUTF16BE:
            return .utf16BigEndian
        default:
            return nil
        }
    }
}
