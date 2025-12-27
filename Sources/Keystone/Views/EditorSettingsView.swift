//
//  EditorSettingsView.swift
//  Keystone
//

import SwiftUI

/// A view for editing editor configuration settings.
public struct EditorSettingsView: View {
    @ObservedObject var configuration: KeystoneConfiguration
    @Binding var isPresented: Bool
    var onConvertLineEndings: ((LineEnding) -> Void)?

    public init(
        configuration: KeystoneConfiguration,
        isPresented: Binding<Bool>,
        onConvertLineEndings: ((LineEnding) -> Void)? = nil
    ) {
        self.configuration = configuration
        self._isPresented = isPresented
        self.onConvertLineEndings = onConvertLineEndings
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Appearance Section
                Section("Appearance") {
                    Toggle("Show Line Numbers", isOn: $configuration.showLineNumbers)
                    Toggle("Highlight Current Line", isOn: $configuration.highlightCurrentLine)
                    Toggle("Show Invisible Characters", isOn: $configuration.showInvisibleCharacters)
                    Toggle("Line Wrapping", isOn: $configuration.lineWrapping)

                    HStack {
                        Text("Font Size")
                        Spacer()
                        Stepper("\(Int(configuration.fontSize))pt", value: $configuration.fontSize, in: 8...32)
                    }

                    HStack {
                        Text("Line Height")
                        Spacer()
                        Slider(value: $configuration.lineHeightMultiplier, in: 1.0...2.0, step: 0.1)
                            .frame(width: 120)
                        Text(String(format: "%.1fx", configuration.lineHeightMultiplier))
                            .frame(width: 40)
                    }
                }

                // Behavior Section
                Section("Behavior") {
                    Toggle("Auto-insert Pairs", isOn: $configuration.autoInsertPairs)
                    Toggle("Highlight Matching Brackets", isOn: $configuration.highlightMatchingBrackets)
                    Toggle("Tab Key Inserts Tab", isOn: $configuration.tabKeyInsertsTab)
                }

                // Indentation Section
                Section("Indentation") {
                    Picker("Type", selection: $configuration.indentation.type) {
                        ForEach(IndentationType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if configuration.indentation.type == .spaces {
                        Stepper("Width: \(configuration.indentation.width) spaces",
                               value: $configuration.indentation.width, in: 1...8)
                    }
                }

                // Line Endings Section
                Section("Line Endings") {
                    HStack {
                        Text("Current")
                        Spacer()
                        Text(configuration.lineEnding.displayName)
                            .foregroundColor(.secondary)
                    }

                    if let onConvert = onConvertLineEndings {
                        Menu("Convert To...") {
                            ForEach(LineEnding.allCases.filter { $0 != .mixed && $0 != configuration.lineEnding }) { ending in
                                Button(ending.displayName) {
                                    onConvert(ending)
                                }
                            }
                        }
                    }
                }

                // Theme Section
                Section("Theme") {
                    themePicker
                }
            }
            .navigationTitle("Editor Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private var themePicker: some View {
        ForEach(KeystoneTheme.allThemes, id: \.name) { item in
            themeButton(item.name, theme: item.theme)
        }
    }

    private func themeButton(_ name: String, theme: KeystoneTheme) -> some View {
        Button(action: { configuration.theme = theme }) {
            HStack {
                // Theme color preview
                HStack(spacing: 2) {
                    Circle().fill(theme.keyword).frame(width: 12, height: 12)
                    Circle().fill(theme.string).frame(width: 12, height: 12)
                    Circle().fill(theme.type).frame(width: 12, height: 12)
                    Circle().fill(theme.comment).frame(width: 12, height: 12)
                }
                .padding(4)
                .background(theme.background)
                .cornerRadius(4)

                Text(name)
                    .foregroundColor(.primary)
                Spacer()
                if configuration.theme == theme {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Editor Settings") {
    EditorSettingsView(
        configuration: KeystoneConfiguration(),
        isPresented: .constant(true)
    )
}
