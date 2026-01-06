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
    let language: KeystoneLanguage
    var onSettingsTap: (() -> Void)?
    var onLanguageChange: ((KeystoneLanguage) -> Void)?

    @State private var showingLanguagePicker = false

    public init(
        cursorPosition: CursorPosition,
        lineCount: Int,
        configuration: KeystoneConfiguration,
        hasUnsavedChanges: Bool = false,
        language: KeystoneLanguage = .plainText,
        onSettingsTap: (() -> Void)? = nil,
        onLanguageChange: ((KeystoneLanguage) -> Void)? = nil
    ) {
        self.cursorPosition = cursorPosition
        self.lineCount = lineCount
        self.configuration = configuration
        self.hasUnsavedChanges = hasUnsavedChanges
        self.language = language
        self.onSettingsTap = onSettingsTap
        self.onLanguageChange = onLanguageChange
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
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

                    Spacer(minLength: 20)

                    // Language selector (disabled in large file mode - syntax highlighting is off)
                    if configuration.isLargeFileMode {
                        HStack(spacing: 4) {
                            Text(language.displayName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .foregroundColor(.secondary)
                        .help("Language selection disabled for large files")
                    } else {
                        Menu {
                            ForEach(KeystoneLanguage.allCases, id: \.self) { lang in
                                Button(action: {
                                    onLanguageChange?(lang)
                                }) {
                                    HStack {
                                        Text(lang.displayName)
                                        if lang == language {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(language.displayName)
                                    .font(.caption)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                        }
                        .menuStyle(.borderlessButton)
                        #if os(macOS)
                        .menuIndicator(.hidden)
                        #endif
                    }

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
                // Ensure content fills available width (allows Spacer to work) but can exceed it for scrolling
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .center)
            }
        }
        .frame(height: 32) // Fixed height for the status bar with proper vertical padding
        .background(Color.keystoneStatusBar)
    }
}

// MARK: - Preview

#Preview("Editor Status Bar") {
    EditorStatusBar(
        cursorPosition: CursorPosition(line: 42, column: 15, selectionLength: 10),
        lineCount: 256,
        configuration: KeystoneConfiguration(),
        hasUnsavedChanges: true,
        language: .swift
    )
}
