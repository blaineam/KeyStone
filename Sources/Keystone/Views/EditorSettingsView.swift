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
    var onConvertIndentation: ((IndentationSettings) -> Void)?

    public init(
        configuration: KeystoneConfiguration,
        isPresented: Binding<Bool>,
        onConvertLineEndings: ((LineEnding) -> Void)? = nil,
        onConvertIndentation: ((IndentationSettings) -> Void)? = nil
    ) {
        self.configuration = configuration
        self._isPresented = isPresented
        self.onConvertLineEndings = onConvertLineEndings
        self.onConvertIndentation = onConvertIndentation
    }

    public var body: some View {
        #if os(iOS)
        iOSSettingsView
        #else
        macOSSettingsView
        #endif
    }

    // MARK: - iOS Settings View

    #if os(iOS)
    private var iOSSettingsView: some View {
        NavigationStack {
            Form {
                // Appearance Section
                Section("Appearance") {
                    Toggle("Show Line Numbers", isOn: $configuration.showLineNumbers)
                    Toggle("Highlight Current Line", isOn: $configuration.highlightCurrentLine)
                    Toggle("Show Invisible Characters", isOn: $configuration.showInvisibleCharacters)
                    Toggle("Line Wrapping", isOn: $configuration.lineWrapping)
                    Toggle("Code Folding", isOn: $configuration.showCodeFolding)

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

                    if let onConvert = onConvertIndentation {
                        Menu("Convert Indentation To...") {
                            Button("Tabs") {
                                let newSettings = IndentationSettings(type: .tabs, width: configuration.indentation.width)
                                configuration.indentation = newSettings
                                onConvert(newSettings)
                            }
                            ForEach([2, 4, 8], id: \.self) { width in
                                Button("\(width) Spaces") {
                                    let newSettings = IndentationSettings(type: .spaces, width: width)
                                    configuration.indentation = newSettings
                                    onConvert(newSettings)
                                }
                            }
                        }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
    #endif

    // MARK: - macOS Settings View

    #if os(macOS)
    private var macOSSettingsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Editor Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Appearance Section
                    GroupBox("Appearance") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Show Line Numbers", isOn: $configuration.showLineNumbers)
                            Toggle("Highlight Current Line", isOn: $configuration.highlightCurrentLine)
                            Toggle("Show Invisible Characters", isOn: $configuration.showInvisibleCharacters)
                            Toggle("Line Wrapping", isOn: $configuration.lineWrapping)
                            Toggle("Code Folding", isOn: $configuration.showCodeFolding)

                            HStack {
                                Text("Font Size")
                                Spacer()
                                Stepper("\(Int(configuration.fontSize))pt", value: $configuration.fontSize, in: 8...32)
                            }

                            HStack {
                                Text("Line Height")
                                Spacer()
                                Slider(value: $configuration.lineHeightMultiplier, in: 1.0...2.0, step: 0.1)
                                    .frame(width: 100)
                                Text(String(format: "%.1fx", configuration.lineHeightMultiplier))
                                    .frame(width: 35)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // Behavior Section
                    GroupBox("Behavior") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Auto-insert Pairs", isOn: $configuration.autoInsertPairs)
                            Toggle("Highlight Matching Brackets", isOn: $configuration.highlightMatchingBrackets)
                            Toggle("Tab Key Inserts Tab", isOn: $configuration.tabKeyInsertsTab)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // Indentation Section
                    GroupBox("Indentation") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Type", selection: $configuration.indentation.type) {
                                ForEach(IndentationType.allCases) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)

                            if configuration.indentation.type == .spaces {
                                Stepper("Width: \(configuration.indentation.width) spaces",
                                       value: $configuration.indentation.width, in: 1...8)
                            }

                            if let onConvert = onConvertIndentation {
                                Menu("Convert Indentation To...") {
                                    Button("Tabs") {
                                        let newSettings = IndentationSettings(type: .tabs, width: configuration.indentation.width)
                                        configuration.indentation = newSettings
                                        onConvert(newSettings)
                                    }
                                    ForEach([2, 4, 8], id: \.self) { width in
                                        Button("\(width) Spaces") {
                                            let newSettings = IndentationSettings(type: .spaces, width: width)
                                            configuration.indentation = newSettings
                                            onConvert(newSettings)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // Line Endings Section
                    GroupBox("Line Endings") {
                        VStack(alignment: .leading, spacing: 8) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // Theme Section
                    GroupBox("Theme") {
                        VStack(alignment: .leading, spacing: 4) {
                            themePicker
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 580)
    }
    #endif

    // MARK: - Shared Components

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
                    #if os(iOS)
                    Circle().fill(theme.keyword).frame(width: 12, height: 12)
                    Circle().fill(theme.string).frame(width: 12, height: 12)
                    Circle().fill(theme.type).frame(width: 12, height: 12)
                    Circle().fill(theme.comment).frame(width: 12, height: 12)
                    #else
                    Circle().fill(theme.keyword).frame(width: 10, height: 10)
                    Circle().fill(theme.string).frame(width: 10, height: 10)
                    Circle().fill(theme.type).frame(width: 10, height: 10)
                    Circle().fill(theme.comment).frame(width: 10, height: 10)
                    #endif
                }
                #if os(iOS)
                .padding(4)
                #else
                .padding(3)
                #endif
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
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }
}

// MARK: - Preview

#Preview("Editor Settings") {
    EditorSettingsView(
        configuration: KeystoneConfiguration(),
        isPresented: .constant(true)
    )
}
