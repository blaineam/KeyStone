//
//  UndoHistory.swift
//  Keystone
//
//  Undo/redo history management with optional persistence.
//

import Foundation

/// Represents a single edit operation for undo/redo.
public struct EditOperation: Codable, Equatable, Sendable {
    /// Unique identifier for this operation.
    public let id: UUID
    /// The text before the edit.
    public let oldText: String
    /// The text after the edit.
    public let newText: String
    /// The cursor position before the edit.
    public let oldCursorOffset: Int
    /// The cursor position after the edit.
    public let newCursorOffset: Int
    /// Timestamp of the edit.
    public let timestamp: Date
    /// Description of the edit type.
    public let editType: EditType

    public init(
        id: UUID = UUID(),
        oldText: String,
        newText: String,
        oldCursorOffset: Int,
        newCursorOffset: Int,
        timestamp: Date = Date(),
        editType: EditType = .general
    ) {
        self.id = id
        self.oldText = oldText
        self.newText = newText
        self.oldCursorOffset = oldCursorOffset
        self.newCursorOffset = newCursorOffset
        self.timestamp = timestamp
        self.editType = editType
    }
}

/// Types of edit operations.
public enum EditType: String, Codable, Sendable {
    case insert
    case delete
    case replace
    case paste
    case cut
    case general
}

/// Manages undo/redo history with optional persistence.
@MainActor
public class UndoHistoryManager: ObservableObject {
    /// Stack of operations that can be undone.
    @Published public private(set) var undoStack: [EditOperation] = []

    /// Stack of operations that can be redone.
    @Published public private(set) var redoStack: [EditOperation] = []

    /// Maximum number of operations to keep in history.
    public var maxHistorySize: Int = 100

    /// Whether persistence is enabled.
    public var persistenceEnabled: Bool = false

    /// The file identifier for persistence.
    private var fileIdentifier: String?

    /// Whether there are operations to undo.
    public var canUndo: Bool { !undoStack.isEmpty }

    /// Whether there are operations to redo.
    public var canRedo: Bool { !redoStack.isEmpty }

    public init() {}

    /// Configures the manager for a specific file.
    /// - Parameters:
    ///   - fileIdentifier: A unique identifier for the file (e.g., file path hash).
    ///   - persistenceEnabled: Whether to persist history to disk.
    public func configure(forFile fileIdentifier: String, persistenceEnabled: Bool = false) {
        self.fileIdentifier = fileIdentifier
        self.persistenceEnabled = persistenceEnabled

        if persistenceEnabled {
            loadHistory()
        }
    }

    /// Records an edit operation.
    /// - Parameter operation: The operation to record.
    public func recordEdit(_ operation: EditOperation) {
        undoStack.append(operation)

        // Clear redo stack when new edit is made
        redoStack.removeAll()

        // Trim history if needed
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst(undoStack.count - maxHistorySize)
        }

        // Persist if enabled
        if persistenceEnabled {
            saveHistory()
        }
    }

    /// Records an edit with the given parameters.
    /// - Parameters:
    ///   - oldText: The text before the edit.
    ///   - newText: The text after the edit.
    ///   - oldCursorOffset: Cursor position before edit.
    ///   - newCursorOffset: Cursor position after edit.
    ///   - editType: The type of edit.
    public func recordEdit(
        oldText: String,
        newText: String,
        oldCursorOffset: Int,
        newCursorOffset: Int,
        editType: EditType = .general
    ) {
        let operation = EditOperation(
            oldText: oldText,
            newText: newText,
            oldCursorOffset: oldCursorOffset,
            newCursorOffset: newCursorOffset,
            editType: editType
        )
        recordEdit(operation)
    }

    /// Performs an undo operation.
    /// - Returns: The operation that was undone, or nil if nothing to undo.
    public func undo() -> EditOperation? {
        guard let operation = undoStack.popLast() else { return nil }

        redoStack.append(operation)

        if persistenceEnabled {
            saveHistory()
        }

        return operation
    }

    /// Performs a redo operation.
    /// - Returns: The operation that was redone, or nil if nothing to redo.
    public func redo() -> EditOperation? {
        guard let operation = redoStack.popLast() else { return nil }

        undoStack.append(operation)

        if persistenceEnabled {
            saveHistory()
        }

        return operation
    }

    /// Clears all history.
    public func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()

        if persistenceEnabled {
            deletePersistedHistory()
        }
    }

    /// Merges recent similar operations to reduce history size.
    /// This combines consecutive typing operations into single operations.
    public func mergeRecentOperations() {
        guard undoStack.count >= 2 else { return }

        let recent = undoStack.suffix(2)
        guard let last = recent.last, let secondLast = recent.dropLast().last else { return }

        // Merge if operations are within 1 second of each other and same type
        let timeDiff = last.timestamp.timeIntervalSince(secondLast.timestamp)
        if timeDiff < 1.0 && last.editType == secondLast.editType && last.editType == .insert {
            // Create merged operation
            let merged = EditOperation(
                oldText: secondLast.oldText,
                newText: last.newText,
                oldCursorOffset: secondLast.oldCursorOffset,
                newCursorOffset: last.newCursorOffset,
                editType: .insert
            )

            // Remove last two and add merged
            undoStack.removeLast(2)
            undoStack.append(merged)
        }
    }

    // MARK: - Persistence

    private var historyFileURL: URL? {
        guard let identifier = fileIdentifier else { return nil }

        let hash = identifier.hash
        let fileName = "keystone_history_\(hash).json"

        #if os(iOS)
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        #else
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Keystone")
        #endif

        guard let dir = directory else { return nil }

        // Create directory if needed
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        return dir.appendingPathComponent(fileName)
    }

    private func saveHistory() {
        guard let url = historyFileURL else { return }

        let history = PersistedHistory(
            undoStack: undoStack,
            redoStack: redoStack
        )

        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: url)
        } catch {
            print("Failed to save undo history: \(error)")
        }
    }

    private func loadHistory() {
        guard let url = historyFileURL else { return }

        do {
            let data = try Data(contentsOf: url)
            let history = try JSONDecoder().decode(PersistedHistory.self, from: data)
            undoStack = history.undoStack
            redoStack = history.redoStack
        } catch {
            // File doesn't exist or is corrupted, start fresh
            undoStack = []
            redoStack = []
        }
    }

    private func deletePersistedHistory() {
        guard let url = historyFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Export/Import for Draft Persistence

    /// Exports the current history to Data for external storage.
    /// Use this to save undo history alongside file drafts.
    public func exportHistory() -> Data? {
        let history = PersistedHistory(
            undoStack: undoStack,
            redoStack: redoStack
        )
        return try? JSONEncoder().encode(history)
    }

    /// Imports history from Data that was previously exported.
    /// Use this to restore undo history when loading a draft.
    public func importHistory(from data: Data) {
        do {
            let history = try JSONDecoder().decode(PersistedHistory.self, from: data)
            undoStack = history.undoStack
            redoStack = history.redoStack
        } catch {
            // Data is corrupted, start fresh
            undoStack = []
            redoStack = []
        }
    }
}

/// Container for persisted undo/redo history.
private struct PersistedHistory: Codable {
    let undoStack: [EditOperation]
    let redoStack: [EditOperation]
}

// MARK: - Text Comparison Utilities

extension UndoHistoryManager {
    /// Creates an edit operation by comparing old and new text.
    /// - Parameters:
    ///   - oldText: The original text.
    ///   - newText: The modified text.
    ///   - cursorOffset: The current cursor offset.
    /// - Returns: An edit operation representing the change.
    public static func createOperation(
        oldText: String,
        newText: String,
        cursorOffset: Int
    ) -> EditOperation {
        let editType: EditType
        if newText.count > oldText.count {
            editType = .insert
        } else if newText.count < oldText.count {
            editType = .delete
        } else {
            editType = .replace
        }

        return EditOperation(
            oldText: oldText,
            newText: newText,
            oldCursorOffset: cursorOffset,
            newCursorOffset: cursorOffset,
            editType: editType
        )
    }
}
