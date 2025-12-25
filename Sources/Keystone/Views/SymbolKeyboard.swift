//
//  SymbolKeyboard.swift
//  Keystone
//

import SwiftUI

#if os(iOS)
/// A keyboard accessory view with programming symbols.
public struct SymbolKeyboard: View {
    /// Callback when a symbol is tapped.
    let onSymbol: (String) -> Void
    /// The string to insert when tab is pressed.
    let indentString: String

    private let symbols = [
        "(", ")", "[", "]", "{", "}", "<", ">",
        "=", "+", "-", "*", "/", "%", "^", "&",
        "|", "!", "?", ":", ";", ",", ".", "_",
        "\\", "'", "\"", "`", "#", "@", "$", "~"
    ]

    public init(indentString: String = "    ", onSymbol: @escaping (String) -> Void) {
        self.indentString = indentString
        self.onSymbol = onSymbol
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Tab/Indent button - placed first
                tabButton

                Divider()
                    .frame(height: 30)

                // Symbol buttons
                ForEach(symbols, id: \.self) { symbol in
                    symbolButton(symbol)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 52)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var tabButton: some View {
        Button(action: { onSymbol(indentString) }) {
            VStack(spacing: 2) {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 14))
                Text("Tab")
                    .font(.system(size: 9))
            }
            .frame(minWidth: 44, minHeight: 40)
            .background(Color.accentColor.opacity(0.2))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func symbolButton(_ symbol: String) -> some View {
        Button(action: { onSymbol(symbol) }) {
            Text(symbol)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 40, minHeight: 40)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
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
