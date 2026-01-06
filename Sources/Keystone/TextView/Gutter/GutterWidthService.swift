import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class GutterWidthService {
    var lineManager: LineManager {
        didSet {
            if lineManager !== oldValue {
                _lineNumberWidth = nil
            }
        }
    }
    var font: RunestoneFont = {
        #if canImport(UIKit)
        return UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        #else
        return NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        #endif
    }() {
        didSet {
            if font != oldValue {
                _lineNumberWidth = nil
            }
        }
    }
    var showLineNumbers = false {
        didSet {
            if showLineNumbers != oldValue {
                sendGutterWidthUpdatedIfNeeded()
            }
        }
    }
    var showCodeFolding = false {
        didSet {
            if showCodeFolding != oldValue {
                sendGutterWidthUpdatedIfNeeded()
            }
        }
    }
    /// Width allocated for fold indicator buttons
    var foldIndicatorWidth: CGFloat {
        showCodeFolding ? 16 : 0
    }
    var gutterLeadingPadding: CGFloat = 0
    var gutterTrailingPadding: CGFloat = 0
    var gutterWidth: CGFloat {
        if showLineNumbers || showCodeFolding {
            return lineNumberWidth + foldIndicatorWidth + gutterLeadingPadding + gutterTrailingPadding
        } else {
            return 0
        }
    }
    var gutterMinimumCharacterCount: Int? {
        didSet {
            if gutterMinimumCharacterCount != oldValue {
                _lineNumberWidth = nil
            }
        }
    }
    var lineNumberWidth: CGFloat {
        let lineCount = lineManager.lineCount
        let hasLineCountChanged = lineCount != previousLineCount
        let hasFontChanged = font != previousFont
        if let lineNumberWidth = _lineNumberWidth, !hasLineCountChanged && !hasFontChanged {
            return lineNumberWidth
        } else {
            let lineNumberWidth = computeLineNumberWidth()
            _lineNumberWidth = lineNumberWidth
            previousFont = font
            previousLineCount = lineManager.lineCount
            sendGutterWidthUpdatedIfNeeded()
            return lineNumberWidth
        }
    }
    let didUpdateGutterWidth = PassthroughSubject<Void, Never>()

    private var _lineNumberWidth: CGFloat?
    private var previousLineCount = 0
    private var previousFont: RunestoneFont?
    private var previouslySentGutterWidth: CGFloat?

    init(lineManager: LineManager) {
        self.lineManager = lineManager
    }

    func invalidateLineNumberWidth() {
        _lineNumberWidth = nil
    }
}

private extension GutterWidthService {
    private func computeLineNumberWidth() -> CGFloat {
        let characterCount = "\(lineManager.lineCount)".count
        let wideLineNumberString = String(repeating: "8", count: {
            if let gutterMinimumCharacterCount = gutterMinimumCharacterCount, gutterMinimumCharacterCount > characterCount {
                return gutterMinimumCharacterCount
            }
            return characterCount
        }())
        let wideLineNumberNSString = wideLineNumberString as NSString
        let size = wideLineNumberNSString.size(withAttributes: [.font: font])
        return ceil(size.width)
    }

    private func sendGutterWidthUpdatedIfNeeded() {
        if gutterWidth != previouslySentGutterWidth {
            didUpdateGutterWidth.send()
            previouslySentGutterWidth = gutterWidth
        }
    }
}
