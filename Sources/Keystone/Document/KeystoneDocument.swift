//
//  KeystoneDocument.swift
//  Keystone
//
//  The editor-owned text document. Hosts hold one of these instead of a
//  `String` binding, so a keystroke in a multi-megabyte file no longer copies
//  the whole buffer out to SwiftUI and back.
//

import Foundation
import Combine

/// A text document edited by ``KeystoneEditor``.
///
/// The editor view is the storage while it is on screen; the document forwards
/// reads to it and keeps its own copy only while no view is attached. Reading
/// ``text`` therefore copies the buffer and is O(n): do it when saving, not on
/// every change. Everything a host needs per keystroke is O(1) here:
/// ``version``, ``isModified`` and ``lineCount``.
///
/// ```swift
/// @StateObject var document = KeystoneDocument()
/// ...
/// KeystoneEditor(document: document, language: .swift, configuration: config, findReplaceManager: find)
/// ...
/// document.replaceAll(with: loaded, markSaved: true)   // file load
/// try document.text.write(to: url, ...); document.markSaved()
/// ```
@MainActor
public final class KeystoneDocument: ObservableObject {
    /// One edit, as reported through ``didChange``.
    public struct Change: Sendable, Equatable {
        /// The document version after the edit.
        public let version: Int
        /// The replaced range in the text *before* the edit, in UTF-16 units.
        /// `nil` when the whole document was replaced or the range is unknown.
        public let range: NSRange?
        /// Length of the text that replaced ``range``, in UTF-16 units.
        public let replacementLength: Int?

        public var isWholeDocument: Bool { range == nil }
    }

    /// Number of lines. Published so status bars can show it without scanning the text.
    @Published public private(set) var lineCount: Int = 1

    /// Whether the document has changed since it was created, loaded or ``markSaved()``.
    ///
    /// Undoing back to the saved text does not clear this; it is a version
    /// comparison, not a content comparison, so it costs nothing per keystroke.
    @Published public private(set) var isModified: Bool = false

    /// Incremented on every edit. Compare two versions to find out whether anything happened in between.
    public private(set) var version: Int = 0

    /// The version at the last ``markSaved()`` or load.
    public private(set) var savedVersion: Int = 0

    /// Fires after every edit, on the main thread, with no text attached.
    public let didChange = PassthroughSubject<Change, Never>()

    private var storedText: NSString
    private weak var attachedView: TextView?
    /// Set by the view coordinator; applies a whole-document replacement to the attached view.
    private var applyToView: ((String, _ preservingUndo: Bool) -> Void)?

    public init(text: String = "") {
        storedText = text as NSString
        lineCount = Self.countLines(in: storedText)
    }

    // MARK: - Reading

    /// A snapshot of the full text. O(n): copies the buffer.
    public var text: String {
        get { attachedView?.text ?? (storedText as String) }
        set { replaceAll(with: newValue) }
    }

    /// The live backing storage. Valid until the next edit; for synchronous read-only scans.
    public var backingString: NSString {
        attachedView?.backingString ?? storedText
    }

    /// Length in UTF-16 units. O(1).
    public var utf16Length: Int { backingString.length }

    /// Line and column for a UTF-16 offset. O(log lines) while a view is attached.
    public func position(atOffset offset: Int, selectionLength: Int = 0) -> CursorPosition {
        if let view = attachedView {
            let clamped = max(0, min(offset, view.backingString.length))
            let location = view.textLocation(at: clamped)
            return CursorPosition(
                line: (location?.lineNumber ?? 0) + 1,
                column: (location?.column ?? 0) + 1,
                selectionLength: selectionLength,
                offset: clamped
            )
        }
        return CursorPosition.from(offset: offset, in: storedText as String, selectionLength: selectionLength)
    }

    /// UTF-16 offset of a 1-based line and column, clamped to the line. `nil` if the line doesn't exist.
    public func offset(line: Int, column: Int = 1) -> Int? {
        guard line >= 1, column >= 1 else { return nil }
        if let view = attachedView {
            guard line <= view.lineCount else { return nil }
            let lineStart = view.location(at: TextLocation(lineNumber: line - 1, column: 0)) ?? 0
            let lineLength = view.lengthOfLine(atRow: line - 1)
            return lineStart + min(column - 1, lineLength)
        }
        return Self.offset(line: line, column: column, in: storedText)
    }

    // MARK: - Writing

    /// Replaces the entire text, as for a file load, revert or external change.
    /// - Parameters:
    ///   - newText: The new contents.
    ///   - markSaved: Treat the new contents as the saved state (file load). Default `false`.
    ///   - preservingUndo: Keep the undo stack (draft restore, line-ending conversion). Default `false`: the stack is cleared.
    public func replaceAll(with newText: String, markSaved: Bool = false, preservingUndo: Bool = false) {
        if let apply = applyToView, attachedView != nil {
            apply(newText, preservingUndo)
        } else {
            storedText = newText as NSString
        }
        version += 1
        if markSaved { savedVersion = version }
        refreshDerivedState()
        didChange.send(Change(version: version, range: nil, replacementLength: nil))
    }

    /// Records that the current text has been saved. ``isModified`` becomes `false`.
    public func markSaved() {
        savedVersion = version
        refreshDerivedState()
    }

    // MARK: - View attachment (internal)

    func attach(_ view: TextView, apply: @escaping (String, Bool) -> Void) {
        attachedView = view
        applyToView = apply
        refreshDerivedState()
    }

    func detach(_ view: TextView) {
        guard attachedView === view else { return }
        storedText = view.backingString.copy() as? NSString ?? view.text as NSString
        attachedView = nil
        applyToView = nil
    }

    /// Called by the view coordinator after the view changed its own text.
    func noteEdit(range: NSRange?, replacementLength: Int?) {
        version += 1
        refreshDerivedState()
        didChange.send(Change(version: version, range: range, replacementLength: replacementLength))
    }

    private func refreshDerivedState() {
        let lines = attachedView?.lineCount ?? Self.countLines(in: storedText)
        if lines != lineCount { lineCount = lines }
        let modified = version != savedVersion
        if modified != isModified { isModified = modified }
    }

    // MARK: - Detached helpers

    private static func countLines(in text: NSString) -> Int {
        var count = 1
        let length = text.length
        var i = 0
        while i < length {
            if text.character(at: i) == 0x0A { count += 1 }
            i += 1
        }
        return count
    }

    private static func offset(line: Int, column: Int, in text: NSString) -> Int? {
        let length = text.length
        var currentLine = 1
        var i = 0
        var lineStart = 0
        while currentLine < line {
            guard i < length else { return nil }
            if text.character(at: i) == 0x0A {
                currentLine += 1
                lineStart = i + 1
            }
            i += 1
        }
        var lineEnd = lineStart
        while lineEnd < length, text.character(at: lineEnd) != 0x0A { lineEnd += 1 }
        return lineStart + min(column - 1, lineEnd - lineStart)
    }
}
