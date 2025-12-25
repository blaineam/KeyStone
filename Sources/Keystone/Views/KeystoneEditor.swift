//
//  KeystoneEditor.swift
//  Keystone
//
//  The main code editor view component for SwiftUI.
//

import SwiftUI

/// A full-featured code editor view for SwiftUI.
///
/// KeystoneEditor provides syntax highlighting, line numbers, bracket matching,
/// and many other features expected in a modern code editor.
///
/// Example usage:
/// ```swift
/// @State private var code = "func hello() {\n    print(\"Hello!\")\n}"
/// @StateObject private var config = KeystoneConfiguration()
///
/// var body: some View {
///     KeystoneEditor(text: $code, language: .swift, configuration: config)
/// }
/// ```
public struct KeystoneEditor: View {
    // MARK: - Properties

    /// The text content being edited.
    @Binding public var text: String

    /// The programming language for syntax highlighting.
    public let language: KeystoneLanguage

    /// The editor configuration.
    @ObservedObject public var configuration: KeystoneConfiguration

    /// Callback when the cursor position changes.
    public var onCursorChange: ((CursorPosition) -> Void)?

    /// Callback when the scroll position changes.
    public var onScrollChange: ((CGFloat) -> Void)?

    // MARK: - Internal State

    @State private var cursorPosition = CursorPosition()
    @State private var scrollOffset: CGFloat = 0
    @State private var lineCount: Int = 1
    @State private var matchingBracket: BracketMatch?

    // MARK: - Initialization

    /// Creates a new code editor.
    /// - Parameters:
    ///   - text: Binding to the text content.
    ///   - language: The programming language for syntax highlighting.
    ///   - configuration: The editor configuration.
    ///   - onCursorChange: Optional callback when cursor position changes.
    ///   - onScrollChange: Optional callback when scroll position changes.
    public init(
        text: Binding<String>,
        language: KeystoneLanguage = .plainText,
        configuration: KeystoneConfiguration,
        onCursorChange: ((CursorPosition) -> Void)? = nil,
        onScrollChange: ((CGFloat) -> Void)? = nil
    ) {
        self._text = text
        self.language = language
        self.configuration = configuration
        self.onCursorChange = onCursorChange
        self.onScrollChange = onScrollChange
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Line numbers gutter
                if configuration.showLineNumbers {
                    LineNumbersGutter(
                        lineCount: lineCount,
                        currentLine: cursorPosition.line,
                        scrollOffset: scrollOffset,
                        fontSize: configuration.fontSize,
                        lineHeight: configuration.fontSize * configuration.lineHeightMultiplier,
                        theme: configuration.theme,
                        highlightCurrentLine: configuration.highlightCurrentLine
                    )
                }

                // Main editor area
                KeystoneTextView(
                    text: $text,
                    language: language,
                    configuration: configuration,
                    cursorPosition: $cursorPosition,
                    scrollOffset: $scrollOffset,
                    matchingBracket: $matchingBracket
                )
            }
        }
        .background(configuration.theme.background)
        .onChange(of: text) { _, newValue in
            updateLineCount(from: newValue)
            updateMatchingBracket()
        }
        .onChange(of: cursorPosition) { _, newPosition in
            onCursorChange?(newPosition)
            updateMatchingBracket()
        }
        .onChange(of: scrollOffset) { _, newOffset in
            onScrollChange?(newOffset)
        }
        .onAppear {
            updateLineCount(from: text)
        }
    }

    // MARK: - Private Methods

    private func updateLineCount(from text: String) {
        lineCount = text.filter { $0 == "\n" }.count + 1
    }

    private func updateMatchingBracket() {
        guard configuration.highlightMatchingBrackets else {
            matchingBracket = nil
            return
        }

        if cursorPosition.offset > 0 {
            // Check character before cursor
            matchingBracket = BracketMatcher.findMatch(in: text, at: cursorPosition.offset - 1)
        } else {
            matchingBracket = nil
        }
    }
}

// MARK: - Line Numbers Gutter

struct LineNumbersGutter: View {
    let lineCount: Int
    let currentLine: Int
    let scrollOffset: CGFloat
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let theme: KeystoneTheme
    let highlightCurrentLine: Bool

    private var gutterWidth: CGFloat {
        let digitCount = String(max(1, lineCount)).count
        return CGFloat(max(3, digitCount)) * (fontSize * 0.6) + 16
    }

    var body: some View {
        GeometryReader { geometry in
            let topPadding: CGFloat = 8
            let visibleHeight = geometry.size.height
            let firstVisibleLine = max(1, Int((scrollOffset - topPadding) / lineHeight) + 1)
            let visibleLineCount = Int(visibleHeight / lineHeight) + 4
            let lastVisibleLine = min(lineCount, firstVisibleLine + visibleLineCount)
            let offset = CGFloat(firstVisibleLine - 1) * lineHeight + topPadding - scrollOffset

            if firstVisibleLine <= lastVisibleLine {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(firstVisibleLine...lastVisibleLine, id: \.self) { lineNum in
                        Text("\(lineNum)")
                            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                            .foregroundColor(lineNum == currentLine ? .accentColor : theme.lineNumber)
                            .frame(height: lineHeight)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 4)
                            .background(
                                highlightCurrentLine && lineNum == currentLine
                                    ? theme.currentLineHighlight
                                    : Color.clear
                            )
                    }
                }
                .offset(y: offset)
            }
        }
        .frame(width: gutterWidth)
        .clipped()
        .background(theme.gutterBackground)
    }
}

// MARK: - Preview

#Preview("Keystone Editor") {
    struct PreviewWrapper: View {
        @State private var text = """
            func hello() {
                let message = "Hello, World!"
                print(message)
            }

            // Call the function
            hello()
            """
        @StateObject private var config = KeystoneConfiguration()

        var body: some View {
            KeystoneEditor(
                text: $text,
                language: .swift,
                configuration: config
            )
            .frame(minHeight: 300)
        }
    }

    return PreviewWrapper()
}
