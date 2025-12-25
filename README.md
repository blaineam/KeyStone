<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2017.0%2B%20%7C%20macOS%2014.0%2B-blue?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?style=for-the-badge&logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/SPM-Compatible-brightgreen?style=for-the-badge&logo=swift" alt="SPM">
</p>

<h1 align="center">🗝️ Keystone</h1>

<p align="center">
  <strong>A powerful, cross-platform code editor component for SwiftUI</strong><br>
  <em>Syntax highlighting • Line numbers • Bracket matching • Find & Replace • And more!</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.0%2B-000000?style=flat&logo=apple" alt="iOS">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat&logo=apple" alt="macOS">
  <img src="https://img.shields.io/github/v/release/blaineam/KeyStone?style=flat&color=blue" alt="Release">
  <img src="https://github.com/blaineam/KeyStone/workflows/CI/badge.svg" alt="CI">
</p>

---

## ✨ Features

### 📝 Core Editor Features
- 🎨 **Syntax Highlighting** — Regex-based highlighting for 20+ programming languages including Swift, Python, JavaScript, TypeScript, HTML, CSS, JSON, and more
- 🔢 **Line Numbers** — Configurable line number gutter with current line highlighting
- 🔗 **Bracket Matching** — Automatic detection and highlighting of matching brackets, parentheses, and braces
- ⌨️ **Character Pair Insertion** — Auto-insert closing quotes, brackets, and parentheses
- 📏 **Line Wrapping** — Toggle between wrapped and horizontal scrolling modes
- 💡 **Current Line Highlighting** — Visual indicator for the line containing the cursor

### 🧠 Text Intelligence
- 📄 **Line Ending Detection** — Automatically detects LF, CRLF, CR, or mixed line endings
- 🔄 **Line Ending Conversion** — Convert between different line ending formats
- ⇥ **Indentation Detection** — Detects whether the file uses tabs or spaces
- 🎹 **Tab Key Support** — Configurable tab behavior (insert tab or spaces)

### 🎨 Visual Customization
- 🌙 **Multiple Themes** — Built-in themes including Default, Monokai, Solarized (Dark/Light), GitHub, and Xcode
- 🔠 **Configurable Font Size** — Adjustable editor font size (8-32pt)
- 📐 **Line Height** — Adjustable line spacing multiplier (1.0x to 2.0x)
- 👁️ **Invisible Characters** — Optional display of tabs, spaces, and line breaks

### 🧩 Advanced Features
- 🔍 **Find & Replace** — Full-featured find and replace with regex support, case sensitivity, and whole word matching
- 📁 **Code Folding** — Collapse and expand code regions based on syntax structure
- ↩️ **Undo/Redo History** — Persistent undo/redo with optional disk persistence
- 🌳 **TreeSitter Ready** — Optional TreeSitter integration for advanced syntax analysis

### 🖥️ UI Components
- 📊 **Status Bar** — Shows cursor position, line count, line ending type, and indentation settings
- ⚙️ **Settings View** — Pre-built settings UI for all editor configuration options
- 🎹 **Symbol Keyboard** (iOS) — Accessory keyboard with programming symbols and a Tab key

---

## 📦 Requirements

| Requirement | Version |
|-------------|---------|
| 📱 iOS | 17.0+ |
| 💻 macOS | 14.0+ |
| 🐦 Swift | 5.9+ |
| 🔨 Xcode | 15.0+ |

---

## 🚀 Installation

### Swift Package Manager

Add Keystone to your project using Swift Package Manager:

1. In Xcode, go to **File → Add Package Dependencies...**
2. Enter the repository URL:
   ```
   https://github.com/blaineam/KeyStone
   ```
3. Select your version rules and click **Add Package**

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/blaineam/KeyStone", from: "1.1.0")
]
```

Then add "Keystone" as a dependency to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["Keystone"]
)
```

---

## ⚡ Quick Start

### Basic Usage

```swift
import SwiftUI
import Keystone

struct ContentView: View {
    @State private var code = """
    func greet(name: String) {
        print("Hello, \\(name)!")
    }

    greet(name: "World")
    """
    @StateObject private var config = KeystoneConfiguration()

    var body: some View {
        KeystoneEditor(
            text: $code,
            language: .swift,
            configuration: config
        )
    }
}
```

### 📊 With Status Bar

```swift
import SwiftUI
import Keystone

struct EditorWithStatusBar: View {
    @State private var code = "// Your code here"
    @State private var cursorPosition = CursorPosition()
    @StateObject private var config = KeystoneConfiguration()

    var body: some View {
        VStack(spacing: 0) {
            KeystoneEditor(
                text: $code,
                language: .swift,
                configuration: config,
                onCursorChange: { position in
                    cursorPosition = position
                }
            )

            EditorStatusBar(
                cursorPosition: cursorPosition,
                lineCount: code.components(separatedBy: "\n").count,
                configuration: config,
                hasUnsavedChanges: false
            )
        }
    }
}
```

### ⚙️ With Settings Panel

```swift
import SwiftUI
import Keystone

struct EditorWithSettings: View {
    @State private var code = "// Your code here"
    @State private var showSettings = false
    @StateObject private var config = KeystoneConfiguration()

    var body: some View {
        NavigationStack {
            KeystoneEditor(
                text: $code,
                language: .swift,
                configuration: config
            )
            .toolbar {
                ToolbarItem {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                EditorSettingsView(
                    configuration: config,
                    isPresented: $showSettings,
                    onConvertLineEndings: { newEnding in
                        code = LineEnding.convert(code, to: newEnding)
                        config.lineEnding = newEnding
                    }
                )
            }
        }
    }
}
```

### 🔍 Auto-Detect Language and Settings

```swift
import SwiftUI
import Keystone

struct SmartEditor: View {
    @State private var code = ""
    @State private var language: KeystoneLanguage = .plainText
    @StateObject private var config = KeystoneConfiguration()

    let filename: String

    var body: some View {
        KeystoneEditor(
            text: $code,
            language: language,
            configuration: config
        )
        .onAppear {
            // Detect language from filename
            language = KeystoneLanguage.detect(from: filename)

            // Load file content
            if let content = loadFile(filename) {
                code = content

                // Auto-detect settings from content
                config.detectSettings(from: content)
            }
        }
    }

    func loadFile(_ name: String) -> String? {
        // Your file loading logic
        return nil
    }
}
```

### 🎹 iOS Symbol Keyboard

```swift
import SwiftUI
import Keystone

struct iOSEditor: View {
    @State private var code = ""
    @StateObject private var config = KeystoneConfiguration()

    var body: some View {
        VStack(spacing: 0) {
            KeystoneEditor(
                text: $code,
                language: .swift,
                configuration: config
            )

            #if os(iOS)
            SymbolKeyboard(indentString: config.indentation.indentString) { symbol in
                code += symbol
            }
            #endif
        }
    }
}
```

---

## ⚙️ Configuration

### KeystoneConfiguration

The main configuration object for the editor. It's an `ObservableObject` that can be shared and persisted.

```swift
let config = KeystoneConfiguration()

// 🎨 Appearance
config.fontSize = 14.0                    // Font size in points (8-32)
config.lineHeightMultiplier = 1.4         // Line spacing multiplier (1.0-2.0)
config.showLineNumbers = true             // Show/hide line number gutter
config.highlightCurrentLine = true        // Highlight the current line
config.showInvisibleCharacters = false    // Show tabs, spaces, line breaks
config.lineWrapping = true                // Enable/disable line wrapping

// ⌨️ Behavior
config.autoInsertPairs = true             // Auto-insert closing brackets/quotes
config.highlightMatchingBrackets = true   // Highlight matching bracket pairs
config.tabKeyInsertsTab = true            // Tab key inserts tab vs spaces

// ⇥ Indentation
config.indentation = IndentationSettings(type: .spaces, width: 4)

// 📄 Line Endings
config.lineEnding = .lf                   // LF, CRLF, or CR

// 🌙 Theme
config.theme = .monokai                   // Syntax highlighting theme
```

### 🎨 Available Themes

| Theme | Description |
|-------|-------------|
| `KeystoneTheme.default` | 🌗 System-aware dark/light theme |
| `KeystoneTheme.monokai` | 🌙 Classic Monokai dark theme |
| `KeystoneTheme.solarizedDark` | 🌑 Solarized Dark |
| `KeystoneTheme.solarizedLight` | ☀️ Solarized Light |
| `KeystoneTheme.github` | 📝 GitHub-inspired light theme |
| `KeystoneTheme.xcode` | 🔨 Xcode default colors |

### 🎨 Creating Custom Themes

```swift
let customTheme = KeystoneTheme(
    // Editor colors
    background: Color(hex: "#1a1a2e"),
    text: Color(hex: "#eaeaea"),
    gutterBackground: Color(hex: "#16163a"),
    lineNumber: Color(hex: "#666688"),
    currentLineHighlight: Color(hex: "#2a2a4e"),
    selection: Color(hex: "#3a3a6e"),
    cursor: Color(hex: "#ffffff"),
    matchingBracket: Color(hex: "#4a4a8e"),

    // Syntax colors
    keyword: Color(hex: "#c678dd"),
    type: Color(hex: "#e5c07b"),
    string: Color(hex: "#98c379"),
    comment: Color(hex: "#5c6370"),
    number: Color(hex: "#d19a66"),
    function: Color(hex: "#61afef"),
    tag: Color(hex: "#e06c75"),
    attribute: Color(hex: "#d19a66")
)
```

---

## 🌐 Supported Languages

| Language | Extensions | Highlights |
|----------|------------|------------|
| 🍎 Swift | `.swift` | Keywords, types, attributes |
| 🐍 Python | `.py` | Keywords, decorators, builtins |
| 🟨 JavaScript | `.js`, `.jsx` | Keywords, functions, classes |
| 🔷 TypeScript | `.ts`, `.tsx` | Types, interfaces, generics |
| ☕ Java | `.java` | Keywords, annotations, types |
| ⚡ C | `.c`, `.h` | Keywords, types, preprocessor |
| 🔧 C++ | `.cpp`, `.hpp` | Templates, namespaces, types |
| 💜 C# | `.cs` | Keywords, attributes, LINQ |
| 🐹 Go | `.go` | Keywords, types, functions |
| 🦀 Rust | `.rs` | Keywords, macros, lifetimes |
| 💎 Ruby | `.rb` | Keywords, symbols, blocks |
| 🐘 PHP | `.php` | Keywords, variables, types |
| 📄 HTML | `.html`, `.htm` | Tags, attributes, entities |
| 🎨 CSS | `.css`, `.scss` | Selectors, properties, values |
| 📦 JSON | `.json` | Keys, strings, numbers |
| 📋 YAML | `.yaml`, `.yml` | Keys, values, anchors |
| 📝 Markdown | `.md` | Headers, emphasis, code |
| 🐚 Shell | `.sh`, `.bash` | Keywords, variables, commands |
| 🗄️ SQL | `.sql` | Keywords, functions, operators |
| ⚙️ Config | `.conf`, `.ini` | Sections, keys, comments |
| 📄 Plain Text | `.txt` | No highlighting |

---

## 📚 API Reference

### 📝 KeystoneEditor

The main editor view component.

```swift
public struct KeystoneEditor: View {
    public init(
        text: Binding<String>,
        language: KeystoneLanguage = .plainText,
        configuration: KeystoneConfiguration,
        onCursorChange: ((CursorPosition) -> Void)? = nil,
        onScrollChange: ((CGFloat) -> Void)? = nil
    )
}
```

### 📊 EditorStatusBar

A status bar showing cursor position and file settings.

```swift
public struct EditorStatusBar: View {
    public init(
        cursorPosition: CursorPosition,
        lineCount: Int,
        configuration: KeystoneConfiguration,
        hasUnsavedChanges: Bool = false,
        onSettingsTap: (() -> Void)? = nil
    )
}
```

### ⚙️ EditorSettingsView

A pre-built settings panel for editor configuration.

```swift
public struct EditorSettingsView: View {
    public init(
        configuration: KeystoneConfiguration,
        isPresented: Binding<Bool>,
        onConvertLineEndings: ((LineEnding) -> Void)? = nil
    )
}
```

### 🎹 SymbolKeyboard (iOS only)

A keyboard accessory with programming symbols.

```swift
public struct SymbolKeyboard: View {
    public init(
        indentString: String = "    ",
        onSymbol: @escaping (String) -> Void
    )
}
```

### 🔍 FindReplaceManager

Manages find and replace operations.

```swift
@MainActor
public class FindReplaceManager: ObservableObject {
    public var searchQuery: String
    public var replaceText: String
    public var options: SearchOptions
    public var matches: [SearchMatch]

    public func search(in text: String)
    public func findNext()
    public func findPrevious()
    public func replaceCurrent(in text: String) -> String?
    public func replaceAll(in text: String) -> String
}
```

### 📁 CodeFoldingManager

Manages code folding regions.

```swift
@MainActor
public class CodeFoldingManager: ObservableObject {
    public var regions: [FoldableRegion]

    public func analyze(_ text: String)
    public func toggleFold(_ region: FoldableRegion)
    public func foldAll()
    public func unfoldAll()
    public func isLineHidden(_ lineNumber: Int) -> Bool
}
```

### ↩️ UndoHistoryManager

Manages undo/redo with optional persistence.

```swift
@MainActor
public class UndoHistoryManager: ObservableObject {
    public var canUndo: Bool
    public var canRedo: Bool

    public func recordEdit(_ operation: EditOperation)
    public func undo() -> EditOperation?
    public func redo() -> EditOperation?
    public func clearHistory()
}
```

### 🔧 Utility Types

```swift
// 📍 Cursor position information
public struct CursorPosition {
    public var line: Int           // 1-based line number
    public var column: Int         // 1-based column number
    public var offset: Int         // Character offset from start
    public var selectionLength: Int // Number of selected characters
}

// 📄 Line ending types
public enum LineEnding {
    case lf      // Unix/macOS (\n)
    case crlf    // Windows (\r\n)
    case cr      // Classic Mac (\r)
    case mixed   // File has mixed endings

    static func detect(in text: String) -> LineEnding
    static func convert(_ text: String, to ending: LineEnding) -> String
}

// ⇥ Indentation settings
public struct IndentationSettings {
    public var type: IndentationType  // .tabs or .spaces
    public var width: Int             // Number of spaces (1-8)
    public var indentString: String   // The actual indent string

    static func detect(in text: String) -> IndentationSettings
}
```

---

## 🏗️ Architecture

```
Keystone/
├── 📁 Configuration/
│   ├── KeystoneConfiguration.swift  // Main config ObservableObject
│   └── KeystoneTheme.swift          // Theme definitions
├── 📁 Features/
│   ├── CodeFolding.swift            // Code folding manager
│   ├── FindReplace.swift            // Find & replace manager
│   └── UndoHistory.swift            // Undo/redo with persistence
├── 📁 Platform/
│   └── PlatformTypes.swift          // Cross-platform type aliases
├── 📁 Syntax/
│   ├── KeystoneLanguage.swift       // Language definitions
│   ├── SyntaxHighlighter.swift      // Highlighting engine
│   └── TreeSitterHighlighter.swift  // TreeSitter integration
├── 📁 Types/
│   ├── BracketMatching.swift        // Bracket matching logic
│   ├── CursorPosition.swift         // Cursor utilities
│   ├── Indentation.swift            // Indentation detection
│   └── LineEnding.swift             // Line ending utilities
└── 📁 Views/
    ├── KeystoneEditor.swift         // Main editor view
    ├── KeystoneTextView.swift       // Platform text views
    ├── EditorStatusBar.swift        // Status bar component
    ├── EditorSettingsView.swift     // Settings UI
    └── SymbolKeyboard.swift         // iOS symbol keyboard
```

---

## 📜 License

Keystone is available under the MIT License. See the [LICENSE](LICENSE) file for more information.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. 🍴 Fork the repository
2. 🌿 Create your feature branch (`git checkout -b feature/amazing-feature`)
3. 💾 Commit your changes (`git commit -m 'Add some amazing feature'`)
4. 📤 Push to the branch (`git push origin feature/amazing-feature`)
5. 🎉 Open a Pull Request

---

## 🙏 Acknowledgments

- 🛠️ Built with SwiftUI for modern Apple platforms
- 💡 Inspired by great code editors like VS Code, Sublime Text, and Xcode
- 🌳 TreeSitter integration for advanced syntax analysis

---

<p align="center">
  Made with ❤️ for the Swift community
</p>
