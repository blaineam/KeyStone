//
//  TextInputAbstraction.swift
//  Runestone
//
//  Abstraction layer for text input across UIKit (UITextInput) and AppKit (NSTextInputClient).
//  This bridges the fundamental differences in how iOS and macOS handle text input.
//

import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit

// On iOS, we use the native UITextInput types directly
// RunestoneTextPosition, RunestoneTextRange are typealiased in PlatformKit.swift

#elseif canImport(AppKit)
import AppKit

// MARK: - macOS Text Position (Equivalent to UITextPosition)

/// A position within text content, equivalent to UITextPosition on iOS.
/// On macOS, this wraps an integer offset into the text.
public class RunestoneTextPosition: NSObject, Comparable {
    /// The character offset from the beginning of the text
    public let offset: Int

    public init(offset: Int) {
        self.offset = offset
        super.init()
    }

    public static func < (lhs: RunestoneTextPosition, rhs: RunestoneTextPosition) -> Bool {
        lhs.offset < rhs.offset
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RunestoneTextPosition else { return false }
        return offset == other.offset
    }

    public override var hash: Int {
        offset.hashValue
    }
}

// MARK: - macOS Text Range (Equivalent to UITextRange)

/// A range of text content, equivalent to UITextRange on iOS.
/// On macOS, this wraps start and end positions.
public class RunestoneTextRange: NSObject {
    /// The start position of the range
    public let start: RunestoneTextPosition

    /// The end position of the range
    public let end: RunestoneTextPosition

    /// Whether the range is empty (start equals end)
    public var isEmpty: Bool {
        start.offset == end.offset
    }

    /// The NSRange representation
    public var nsRange: NSRange {
        NSRange(location: start.offset, length: end.offset - start.offset)
    }

    /// The length of the range
    public var length: Int {
        end.offset - start.offset
    }

    public init(start: RunestoneTextPosition, end: RunestoneTextPosition) {
        self.start = start
        self.end = end
        super.init()
    }

    public convenience init(range: NSRange) {
        let start = RunestoneTextPosition(offset: range.location)
        let end = RunestoneTextPosition(offset: range.location + range.length)
        self.init(start: start, end: end)
    }

    public convenience init(location: Int, length: Int) {
        let start = RunestoneTextPosition(offset: location)
        let end = RunestoneTextPosition(offset: location + length)
        self.init(start: start, end: end)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RunestoneTextRange else { return false }
        return start == other.start && end == other.end
    }
}

// MARK: - macOS Text Selection Rect (Equivalent to UITextSelectionRect)

/// A rectangle representing selected text, equivalent to UITextSelectionRect on iOS.
public class RunestoneTextSelectionRect: NSObject {
    public let rect: CGRect
    public let writingDirection: NSWritingDirection
    public let containsStart: Bool
    public let containsEnd: Bool
    public let isVertical: Bool

    public init(
        rect: CGRect,
        writingDirection: NSWritingDirection = .leftToRight,
        containsStart: Bool = false,
        containsEnd: Bool = false,
        isVertical: Bool = false
    ) {
        self.rect = rect
        self.writingDirection = writingDirection
        self.containsStart = containsStart
        self.containsEnd = containsEnd
        self.isVertical = isVertical
        super.init()
    }
}

// MARK: - Text Layout Direction (Equivalent to UITextLayoutDirection)

public enum RunestoneTextLayoutDirection: Int {
    case right = 0
    case left = 1
    case up = 2
    case down = 3
}

// MARK: - Text Storage Direction (Equivalent to UITextStorageDirection)

public enum RunestoneTextStorageDirection: Int {
    case forward = 0
    case backward = 1
}

// MARK: - Text Granularity (Equivalent to UITextGranularity)

public enum RunestoneTextGranularity: Int {
    case character = 0
    case word = 1
    case sentence = 2
    case paragraph = 3
    case line = 4
    case document = 5
}

#endif

// MARK: - Cross-Platform Text Range Utilities

extension NSRange {
    #if canImport(UIKit)
    /// Create NSRange from UITextRange
    public init?(_ textRange: UITextRange?, in textInput: UITextInput) {
        guard let textRange = textRange else { return nil }
        let start = textInput.offset(from: textInput.beginningOfDocument, to: textRange.start)
        let end = textInput.offset(from: textInput.beginningOfDocument, to: textRange.end)
        self.init(location: start, length: end - start)
    }
    #elseif canImport(AppKit)
    /// Create NSRange from RunestoneTextRange
    public init(_ textRange: RunestoneTextRange) {
        self.init(location: textRange.start.offset, length: textRange.length)
    }
    #endif
}
