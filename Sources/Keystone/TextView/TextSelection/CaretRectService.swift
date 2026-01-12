#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class CaretRectService {
    var stringView: StringView
    var lineManager: LineManager
    var textContainerInset: RunestoneEdgeInsets = .zero
    var showLineNumbers = false

    private let lineControllerStorage: LineControllerStorage
    private let gutterWidthService: GutterWidthService
    private var leadingLineSpacing: CGFloat {
        if showLineNumbers {
            return gutterWidthService.gutterWidth + textContainerInset.left
        } else {
            return textContainerInset.left
        }
    }

    init(stringView: StringView,
         lineManager: LineManager,
         lineControllerStorage: LineControllerStorage,
         gutterWidthService: GutterWidthService) {
        self.stringView = stringView
        self.lineManager = lineManager
        self.lineControllerStorage = lineControllerStorage
        self.gutterWidthService = gutterWidthService
    }

    func caretRect(at location: Int, allowMovingCaretToNextLineFragment: Bool) -> CGRect {
        let safeLocation = min(max(location, 0), stringView.string.length)

        // Guard against inconsistent state where lineManager might not match stringView
        guard let line = lineManager.line(containingCharacterAt: safeLocation) else {
            // Return a safe default rect at origin when structures are stale
            return CGRect(x: leadingLineSpacing, y: textContainerInset.top, width: 2, height: 15)
        }

        let lineController = lineControllerStorage.getOrCreateLineController(for: line)
        let lineLocalLocation = safeLocation - line.location

        // Additional bounds check for line-local location against line's actual length
        let safeLineLocalLocation = max(0, min(lineLocalLocation, line.data.totalLength))

        if allowMovingCaretToNextLineFragment && shouldMoveCaretToNextLineFragment(forLocation: safeLineLocalLocation, in: line) {
            let rect = caretRect(at: location + 1, allowMovingCaretToNextLineFragment: false)
            return CGRect(x: leadingLineSpacing, y: rect.minY, width: rect.width, height: rect.height)
        } else {
            let localCaretRect = lineController.caretRect(atIndex: safeLineLocalLocation)
            let globalYPosition = line.yPosition + localCaretRect.minY
            let globalRect = CGRect(x: localCaretRect.minX, y: globalYPosition, width: localCaretRect.width, height: localCaretRect.height)
            return globalRect.offsetBy(dx: leadingLineSpacing, dy: textContainerInset.top)
        }
    }
}

private extension CaretRectService {
    private func shouldMoveCaretToNextLineFragment(forLocation location: Int, in line: DocumentLineNode) -> Bool {
        let lineController = lineControllerStorage.getOrCreateLineController(for: line)
        guard lineController.numberOfLineFragments > 0 else {
            return false
        }
        guard let lineFragmentNode = lineController.lineFragmentNode(containingCharacterAt: location) else {
            return false
        }
        guard lineFragmentNode.index > 0 else {
            return false
        }
        return location == lineFragmentNode.data.lineFragment?.range.location
    }
}
