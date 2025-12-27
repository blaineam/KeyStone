//
//  UndoController.swift
//  Keystone
//
//  Bridges the UITextView/NSTextView undo manager to SwiftUI.
//

import SwiftUI

/// Controller that bridges the native text view's undo manager to SwiftUI.
///
/// This allows the toolbar buttons to properly trigger undo/redo on the actual text view
/// instead of SwiftUI's disconnected environment undo manager.
@MainActor
public class UndoController: ObservableObject {
    /// Whether undo is available.
    @Published public private(set) var canUndo: Bool = false

    /// Whether redo is available.
    @Published public private(set) var canRedo: Bool = false

    /// The undo action closure (set by KeystoneTextView's coordinator).
    var undoAction: (() -> Void)?

    /// The redo action closure (set by KeystoneTextView's coordinator).
    var redoAction: (() -> Void)?

    /// Closure to check undo state (set by KeystoneTextView's coordinator).
    var checkUndoState: (() -> (canUndo: Bool, canRedo: Bool))?

    /// Closure to replace text at a range (set by KeystoneTextView's coordinator).
    /// Parameters: (range: NSRange, replacementText: String) -> new text content
    var replaceTextAction: ((NSRange, String) -> String?)?

    /// Closure to begin an undo grouping (for batching multiple changes).
    var beginUndoGroupingAction: (() -> Void)?

    /// Closure to end an undo grouping.
    var endUndoGroupingAction: (() -> Void)?

    private var updateTimer: Timer?

    public init() {}

    deinit {
        updateTimer?.invalidate()
    }

    /// Performs undo on the text view.
    public func undo() {
        undoAction?()
        updateState()
    }

    /// Performs redo on the text view.
    public func redo() {
        redoAction?()
        updateState()
    }

    /// Replaces text at the specified range. This goes through the text view's
    /// textStorage so the change is properly recorded in the undo history.
    /// - Parameters:
    ///   - range: The NSRange to replace.
    ///   - text: The replacement text.
    /// - Returns: The new full text content, or nil if replacement failed.
    public func replaceText(in range: NSRange, with text: String) -> String? {
        let result = replaceTextAction?(range, text)
        updateState()
        return result
    }

    /// Begins an undo grouping. All changes until `endUndoGrouping()` will be
    /// grouped into a single undo operation.
    public func beginUndoGrouping() {
        beginUndoGroupingAction?()
    }

    /// Ends an undo grouping started by `beginUndoGrouping()`.
    public func endUndoGrouping() {
        endUndoGroupingAction?()
        updateState()
    }

    /// Starts periodic state updates.
    func startUpdating() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateState()
            }
        }
    }

    /// Stops periodic state updates.
    func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    /// Updates the undo/redo state immediately.
    func updateState() {
        if let state = checkUndoState?() {
            if canUndo != state.canUndo {
                canUndo = state.canUndo
            }
            if canRedo != state.canRedo {
                canRedo = state.canRedo
            }
        }
    }
}
