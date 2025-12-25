//
//  EditorStatusBar.swift
//  Keystone
//

import SwiftUI

/// A status bar showing editor information like cursor position and file settings.
public struct EditorStatusBar: View {
    let cursorPosition: CursorPosition
    let lineCount: Int
    @ObservedObject var configuration: KeystoneConfiguration
    let hasUnsavedChanges: Bool
    var onSettingsTap: (() -> Void)?

    public init(
        cursorPosition: CursorPosition,
        lineCount: Int,
        configuration: KeystoneConfiguration,
        hasUnsavedChanges: Bool = false,
        onSettingsTap: (() -> Void)? = nil
    ) {
        self.cursorPosition = cursorPosition
        self.lineCount = lineCount
        self.configuration = configuration
        self.hasUnsavedChanges = hasUnsavedChanges
        self.onSettingsTap = onSettingsTap
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Line count
            Text("Lines: \(lineCount)")
                .font(.caption)
                .foregroundColor(.secondary)

            // Cursor position
            Text("Ln \(cursorPosition.line), Col \(cursorPosition.column)")
                .font(.caption)
                .foregroundColor(.secondary)

            // Selection length
            if cursorPosition.selectionLength > 0 {
                Text("Sel: \(cursorPosition.selectionLength)")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            Spacer()

            // Line ending indicator
            Button(action: { onSettingsTap?() }) {
                Text(configuration.lineEnding.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            // Indentation indicator
            Button(action: { onSettingsTap?() }) {
                Text(configuration.indentation.type == .tabs ? "Tab" : "\(configuration.indentation.width) Spaces")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            if hasUnsavedChanges {
                Text("Modified")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.keystoneStatusBar)
    }
}

// MARK: - Preview

#Preview("Editor Status Bar") {
    EditorStatusBar(
        cursorPosition: CursorPosition(line: 42, column: 15, selectionLength: 10),
        lineCount: 256,
        configuration: KeystoneConfiguration(),
        hasUnsavedChanges: true
    )
}
