//
//  EditorCommands.swift
//  Keystone
//
//  Go to Symbol (⌘⇧O) and the command palette (⌘⇧P).
//

import SwiftUI

/// A command shown in the palette. Hosts add their own with ``KeystoneEditor/commands(_:)``.
public struct EditorCommand: Identifiable {
    public let id: String
    public let title: String
    public var subtitle: String?
    public var systemImage: String?
    /// Shown at the trailing edge, e.g. "⌘⇧O".
    public var shortcut: String?
    public let action: () -> Void

    public init(id: String, title: String, subtitle: String? = nil, systemImage: String? = nil, shortcut: String? = nil, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.action = action
    }
}

/// Closures the text view coordinator fills in, so SwiftUI-level commands can reach
/// the platform text view (folding, multiple cursors). ``KeystoneEditor`` owns one;
/// hosts embedding ``KeystoneTextView`` directly may pass their own.
public final class EditorActions {
    public var foldAll: (() -> Void)?
    public var unfoldAll: (() -> Void)?
    public var selectNextOccurrence: (() -> Void)?
    public var selectAllOccurrences: (() -> Void)?
    public var addCaretAbove: (() -> Void)?
    public var addCaretBelow: (() -> Void)?
    public var collapseSelections: (() -> Void)?

    public init() {}
}

struct SymbolOutlineView: View {
    @ObservedObject var document: KeystoneDocument
    let onSelect: (DocumentSymbol) -> Void
    let onDismiss: () -> Void

    var body: some View {
        let symbols = document.symbols
        FuzzyPickerView(
            placeholder: String(localized: "Go to Symbol", bundle: .module),
            items: symbols.map { symbol in
                FuzzyPickerItem(
                    id: symbol.id,
                    title: symbol.name,
                    systemImage: symbol.kind.systemImage,
                    detail: "Ln \(symbol.line + 1)",
                    indent: symbol.depth
                )
            },
            emptyText: symbols.isEmpty ? String(localized: "No symbols in this file", bundle: .module) : String(localized: "No matches", bundle: .module),
            onSelect: { item in
                if let symbol = symbols.first(where: { $0.id == item.id }) {
                    onSelect(symbol)
                }
            },
            onDismiss: onDismiss
        )
        .onAppear {
            // Big documents don't refresh symbols on every parse; do it now.
            if document.symbols.isEmpty {
                document.refreshSymbols()
            }
        }
    }
}

struct CommandPaletteView: View {
    let commands: [EditorCommand]
    let onDismiss: () -> Void

    var body: some View {
        FuzzyPickerView(
            placeholder: String(localized: "Type a command", bundle: .module),
            items: commands.map { command in
                FuzzyPickerItem(id: command.id, title: command.title, subtitle: command.subtitle, systemImage: command.systemImage, detail: command.shortcut)
            },
            emptyText: String(localized: "No matching command", bundle: .module),
            onSelect: { item in
                onDismiss()
                commands.first { $0.id == item.id }?.action()
            },
            onDismiss: onDismiss
        )
    }
}
