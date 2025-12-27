//
//  SymbolKeyboard.swift
//  Keystone
//
//  Keyboard accessory view with programming symbols organized by category.
//

import SwiftUI

#if os(iOS)
/// A keyboard accessory view with programming symbols organized into categories.
public struct SymbolKeyboard: View {
    /// Callback when a symbol is tapped.
    let onSymbol: (String) -> Void
    /// The string to insert when tab is pressed.
    let indentString: String

    @State private var selectedCategory: SymbolCategory = .brackets

    public init(indentString: String = "    ", onSymbol: @escaping (String) -> Void) {
        self.indentString = indentString
        self.onSymbol = onSymbol
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(SymbolCategory.allCases, id: \.self) { category in
                        categoryTab(category)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color(UIColor.tertiarySystemBackground))

            Divider()

            // Symbol buttons for selected category
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Tab/Indent button - always first
                    tabButton

                    Divider()
                        .frame(height: 30)

                    // Symbols for selected category
                    ForEach(selectedCategory.symbols, id: \.self) { symbol in
                        symbolButton(symbol)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 48)
            .background(Color(UIColor.secondarySystemBackground))
        }
    }

    private func categoryTab(_ category: SymbolCategory) -> some View {
        Button(action: { selectedCategory = category }) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 12))
                Text(category.name)
                    .font(.system(size: 12, weight: selectedCategory == category ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selectedCategory == category
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .foregroundColor(selectedCategory == category ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var tabButton: some View {
        Button(action: { onSymbol(indentString) }) {
            VStack(spacing: 2) {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 14))
                Text("Tab")
                    .font(.system(size: 9))
            }
            .frame(minWidth: 44, minHeight: 38)
            .background(Color.accentColor.opacity(0.2))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func symbolButton(_ symbol: String) -> some View {
        Button(action: { onSymbol(symbol) }) {
            Text(symbol)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 38, minHeight: 38)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Symbol Categories

enum SymbolCategory: CaseIterable {
    case brackets
    case operators
    case punctuation
    case special
    case numbers

    var name: String {
        switch self {
        case .brackets: return "Brackets"
        case .operators: return "Operators"
        case .punctuation: return "Punctuation"
        case .special: return "Special"
        case .numbers: return "Numbers"
        }
    }

    var icon: String {
        switch self {
        case .brackets: return "curlybraces"
        case .operators: return "plus.forwardslash.minus"
        case .punctuation: return "textformat"
        case .special: return "number"
        case .numbers: return "123.rectangle"
        }
    }

    var symbols: [String] {
        switch self {
        case .brackets:
            return ["(", ")", "[", "]", "{", "}", "<", ">"]
        case .operators:
            return ["=", "+", "-", "*", "/", "%", "^", "&", "|", "!", "?", "~"]
        case .punctuation:
            return [":", ";", ",", ".", "_", "'", "\"", "`", "\\"]
        case .special:
            return ["#", "@", "$", "->", "=>", "??", "...", "::", "&&", "||"]
        case .numbers:
            return ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        }
    }
}

// MARK: - Preview

#Preview("Symbol Keyboard") {
    VStack {
        Spacer()
        SymbolKeyboard(indentString: "    ") { symbol in
            print("Tapped: \(symbol)")
        }
    }
}
#endif
