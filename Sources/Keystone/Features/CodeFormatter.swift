//
//  CodeFormatter.swift
//  Keystone
//
//  Prettify and minify for JSON, CSS and HTML/XML. Token-based: only whitespace
//  (and, when minifying, comments) changes, so output is semantically the input.
//  JavaScript/TypeScript go through js-beautify and terser in JavaScriptCore
//  (see JavaScriptFormatter.swift); minify is JavaScript-only. In HTML, the
//  contents of <style> and JavaScript <script> elements go through the CSS and
//  JavaScript formatters. Prettier's ignore comments are honoured: a region
//  marked `prettier-ignore` (next node / rule / declaration / statement) or
//  `prettier-ignore-start` … `prettier-ignore-end` (HTML) is left byte for byte.
//

import Foundation

public enum CodeFormatter {
    public enum Operation { case prettify, minify }

    /// Whether `language` can be formatted.
    public static func supports(_ language: KeystoneLanguage) -> Bool {
        formatterKind(for: language) != nil
    }

    /// The formatted text, or nil when the language is unsupported.
    public static func format(_ text: String, language: KeystoneLanguage, operation: Operation, indent: String = "  ") -> String? {
        switch formatterKind(for: language) {
        case .json: return operation == .prettify ? JSONReformatter.prettify(text, indent: indent) : JSONReformatter.minify(text)
        case .css: return operation == .prettify ? CSSReformatter.prettify(text, indent: indent) : CSSReformatter.minify(text)
        case .markup(let isHTML): return operation == .prettify ? MarkupReformatter.prettify(text, indent: indent, isHTML: isHTML) : MarkupReformatter.minify(text, isHTML: isHTML)
        case .javascript(let isTypeScript): return operation == .prettify ? JavaScriptFormatter.prettify(text, indent: indent, isTypeScript: isTypeScript) : JavaScriptFormatter.minify(text, isTypeScript: isTypeScript)
        case nil: return nil
        }
    }

    enum Kind { case json, css, markup(isHTML: Bool), javascript(isTypeScript: Bool) }

    static func formatterKind(for language: KeystoneLanguage) -> Kind? {
        switch language.rawValue.lowercased() {
        case "json", "json5", "jsonc": return .json
        case "css", "scss", "less": return .css
        case "html", "htm", "svelte", "vue", "astro": return .markup(isHTML: true)
        case "xml", "svg", "plist", "xaml": return .markup(isHTML: false)
        case "javascript", "js", "mjs", "cjs", "jsx": return .javascript(isTypeScript: false)
        case "typescript", "ts", "mts", "cts", "tsx": return .javascript(isTypeScript: true)
        default: return nil
        }
    }
}

// MARK: - prettier-ignore

enum PrettierIgnore {
    /// Whether `comment` (with its delimiters, e.g. "<!-- prettier-ignore -->" or "/* prettier-ignore */") is the given directive.
    static func isDirective(_ comment: String, _ directive: String) -> Bool {
        var body = Substring(comment)
        for (open, close) in [("<!--", "-->"), ("/*", "*/"), ("//", "")] where body.hasPrefix(open) {
            body = body.dropFirst(open.count)
            if !close.isEmpty, body.hasSuffix(close) { body = body.dropLast(close.count) }
            break
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines) == directive
    }

    /// `region` without a leading whitespace-only first line and without the whitespace after its last line break:
    /// the lines between two markers, verbatim, ready to be emitted as lines of their own.
    static func innerLines(of region: String) -> String {
        var text = Substring(region)
        if let newline = text.firstIndex(where: { $0 == "\n" || $0 == "\r\n" }), text[..<newline].allSatisfy({ $0 == " " || $0 == "\t" }) {
            text = text[text.index(after: newline)...]
        }
        if let newline = text.lastIndex(where: { $0 == "\n" || $0 == "\r\n" }), text[text.index(after: newline)...].allSatisfy({ $0 == " " || $0 == "\t" }) {
            text = text[..<newline]
        }
        return String(text)
    }
}

// MARK: - JSON

enum JSONReformatter {
    enum Token { case open(unichar), close(unichar), comma, colon, literal(String), comment(String) }

    static func tokenize(_ text: String) -> [Token] {
        let s = text as NSString
        let n = s.length
        var tokens: [Token] = []
        var i = 0
        func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
        while i < n {
            let c = s.character(at: i)
            if isSpace(c) { i += 1; continue }
            switch c {
            case 0x7B, 0x5B: tokens.append(.open(c)); i += 1
            case 0x7D, 0x5D: tokens.append(.close(c)); i += 1
            case 0x2C: tokens.append(.comma); i += 1
            case 0x3A: tokens.append(.colon); i += 1
            case 0x22: // string
                var j = i + 1
                while j < n {
                    let d = s.character(at: j)
                    if d == 0x5C { j += 2; continue }
                    if d == 0x22 { break }
                    j += 1
                }
                let end = min(j + 1, n)
                tokens.append(.literal(s.substring(with: NSRange(location: i, length: end - i))))
                i = end
            case 0x2F where i + 1 < n && s.character(at: i + 1) == 0x2F: // line comment (JSONC)
                var j = i
                while j < n, s.character(at: j) != 0x0A { j += 1 }
                tokens.append(.comment(s.substring(with: NSRange(location: i, length: j - i)).trimmingCharacters(in: .whitespaces)))
                i = j
            case 0x2F where i + 1 < n && s.character(at: i + 1) == 0x2A: // block comment
                let close = s.range(of: "*/", options: [], range: NSRange(location: i + 2, length: n - i - 2))
                let end = close.location == NSNotFound ? n : close.upperBound
                tokens.append(.comment(s.substring(with: NSRange(location: i, length: end - i))))
                i = end
            default: // number, true, false, null, or anything else up to a delimiter
                var j = i
                while j < n {
                    let d = s.character(at: j)
                    if isSpace(d) || d == 0x2C || d == 0x3A || d == 0x7D || d == 0x5D || d == 0x7B || d == 0x5B { break }
                    j += 1
                }
                if j == i { j = i + 1 }
                tokens.append(.literal(s.substring(with: NSRange(location: i, length: j - i))))
                i = j
            }
        }
        return tokens
    }

    static func prettify(_ text: String, indent: String) -> String {
        let tokens = tokenize(text)
        var out = ""
        var depth = 0
        var atLineStart = true
        func newline() {
            out.append("\n")
            out.append(String(repeating: indent, count: depth))
            atLineStart = true
        }
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case .open(let c):
                let next = index + 1 < tokens.count ? tokens[index + 1] : nil
                if case .close? = next {
                    out.append(c == 0x7B ? "{}" : "[]")
                    index += 1
                } else {
                    out.append(c == 0x7B ? "{" : "[")
                    depth += 1
                    newline()
                }
            case .close(let c):
                depth = max(0, depth - 1)
                newline()
                out.append(c == 0x7D ? "}" : "]")
            case .comma:
                out.append(",")
                newline()
            case .colon:
                out.append(": ")
            case .literal(let value):
                out.append(value)
            case .comment(let value):
                if !atLineStart { out.append(" ") }
                out.append(value)
                // A comment ends the line unless a closing bracket follows (which starts its own line).
                let next = index + 1 < tokens.count ? tokens[index + 1] : nil
                if case .close? = next {} else { newline() }
            }
            if case .comment = token {} else { atLineStart = false }
            index += 1
        }
        // Collapse the blank line a comma-then-comment or trailing newline may have left.
        while out.hasSuffix("\n") || out.hasSuffix(" ") { out.removeLast() }
        return out + "\n"
    }

    static func minify(_ text: String) -> String {
        var out = ""
        for token in tokenize(text) {
            switch token {
            case .open(let c): out.append(c == 0x7B ? "{" : "[")
            case .close(let c): out.append(c == 0x7D ? "}" : "]")
            case .comma: out.append(",")
            case .colon: out.append(":")
            case .literal(let value): out.append(value)
            case .comment: break
            }
        }
        return out
    }
}

// MARK: - CSS

enum CSSReformatter {
    enum Token { case open, close, semicolon, text(String), comment(String) }

    /// The tokens of `text` with, for each, its range in `text` (a `.text` token's range covers its trimmed source).
    struct Tokens {
        var tokens: [Token] = []
        var ranges: [NSRange] = []
        var count: Int { tokens.count }
        subscript(index: Int) -> Token { tokens[index] }
        func token(at index: Int) -> Token? { index < tokens.count ? tokens[index] : nil }
    }

    static func tokenize(_ text: String) -> [Token] { tokenizeWithRanges(text).tokens }

    static func tokenizeWithRanges(_ text: String) -> Tokens {
        let s = text as NSString
        let n = s.length
        var result = Tokens()
        var buffer = ""
        var bufferStart = NSNotFound
        var bufferEnd = 0
        func append(_ piece: String, from start: Int, to end: Int) {
            buffer += piece
            if bufferStart == NSNotFound { bufferStart = start }
            bufferEnd = end
        }
        func flush() {
            let trimmed = collapseWhitespace(buffer)
            if !trimmed.isEmpty {
                result.tokens.append(.text(trimmed))
                result.ranges.append(NSRange(location: bufferStart, length: bufferEnd - bufferStart))
            }
            buffer = ""
            bufferStart = NSNotFound
        }
        func single(_ token: Token, at index: Int) {
            flush()
            result.tokens.append(token)
            result.ranges.append(NSRange(location: index, length: 1))
        }
        var i = 0
        while i < n {
            let c = s.character(at: i)
            if c == 0x2F, i + 1 < n, s.character(at: i + 1) == 0x2A {
                flush()
                let close = s.range(of: "*/", options: [], range: NSRange(location: i + 2, length: n - i - 2))
                let end = close.location == NSNotFound ? n : close.upperBound
                result.tokens.append(.comment(s.substring(with: NSRange(location: i, length: end - i))))
                result.ranges.append(NSRange(location: i, length: end - i))
                i = end
                continue
            }
            if c == 0x22 || c == 0x27 { // string: copy verbatim
                var j = i + 1
                while j < n {
                    let d = s.character(at: j)
                    if d == 0x5C { j += 2; continue }
                    if d == c { break }
                    j += 1
                }
                let end = min(j + 1, n)
                append(s.substring(with: NSRange(location: i, length: end - i)), from: i, to: end)
                i = end
                continue
            }
            if c == 0x28 { // url(...) and friends: verbatim up to the matching paren
                let close = s.range(of: ")", options: [], range: NSRange(location: i, length: n - i))
                let end = close.location == NSNotFound ? n : close.upperBound
                append(s.substring(with: NSRange(location: i, length: end - i)), from: i, to: end)
                i = end
                continue
            }
            switch c {
            case 0x7B: single(.open, at: i)
            case 0x7D: single(.close, at: i)
            case 0x3B: single(.semicolon, at: i)
            case 0x20, 0x09, 0x0A, 0x0D: buffer.append(Character(UnicodeScalar(c)!))
            default: append(String(Character(UnicodeScalar(c) ?? " ")), from: i, to: i + 1)
            }
            i += 1
        }
        flush()
        return result
    }

    /// The source of the rule or declaration that follows the `/* prettier-ignore */` at `commentIndex`,
    /// verbatim, with the index of the first token after it; nil when nothing ignorable follows.
    static func ignoredRegion(after commentIndex: Int, in tokens: Tokens, source: NSString) -> (text: String, next: Int, isRule: Bool)? {
        let start = commentIndex + 1
        guard case .text? = tokens.token(at: start) else { return nil }
        let from = tokens.ranges[start].location
        switch tokens.token(at: start + 1) {
        case .open?:
            var depth = 0
            var index = start + 1
            while index < tokens.count {
                if case .open = tokens[index] { depth += 1 }
                if case .close = tokens[index] { depth -= 1; if depth == 0 { break } }
                index += 1
            }
            let end = index < tokens.count ? tokens.ranges[index].upperBound : source.length
            return (source.substring(with: NSRange(location: from, length: end - from)), min(index + 1, tokens.count), true)
        case .semicolon?:
            let end = tokens.ranges[start + 1].upperBound
            return (source.substring(with: NSRange(location: from, length: end - from)), start + 2, false)
        default:
            let end = tokens.ranges[start].upperBound
            return (source.substring(with: NSRange(location: from, length: end - from)), start + 1, false)
        }
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " ")
    }

    static func prettify(_ text: String, indent: String) -> String {
        let tokens = tokenizeWithRanges(text)
        let source = text as NSString
        var out = ""
        var depth = 0
        func pad() { out.append(String(repeating: indent, count: depth)) }
        var index = 0
        while index < tokens.count {
            switch tokens[index] {
            case .text(let value):
                let next = tokens.token(at: index + 1)
                pad()
                if case .open? = next {
                    // Selector or at-rule prelude: one selector per line after top-level commas.
                    let separator = ",\n" + String(repeating: indent, count: depth)
                    out.append(value.hasPrefix("@") ? value : splitSelectors(value).joined(separator: separator))
                    out.append(" {\n")
                    depth += 1
                    index += 1
                } else {
                    // Declaration: normalise "prop:value" to "prop: value".
                    out.append(normalizeDeclaration(value))
                    if case .semicolon? = next { out.append(";"); index += 1 }
                    else if case .close? = next { out.append(";") }
                    out.append("\n")
                }
            case .open:
                pad(); out.append("{\n"); depth += 1
            case .close:
                depth = max(0, depth - 1)
                pad(); out.append("}\n")
                if depth == 0 { out.append("\n") }
            case .semicolon:
                break
            case .comment(let value):
                pad(); out.append(value); out.append("\n")
                if PrettierIgnore.isDirective(value, "prettier-ignore"),
                   let region = ignoredRegion(after: index, in: tokens, source: source) {
                    pad(); out.append(region.text); out.append("\n")
                    if region.isRule && depth == 0 { out.append("\n") }
                    index = region.next
                    continue
                }
            }
            index += 1
        }
        while out.hasSuffix("\n\n") { out.removeLast() }
        return out.isEmpty ? out : (out.hasSuffix("\n") ? out : out + "\n")
    }

    /// Splits a selector list on commas that are not inside parentheses, trimming each part.
    static func splitSelectors(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            switch character {
            case "(": depth += 1; current.append(character)
            case ")": depth = max(0, depth - 1); current.append(character)
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default: current.append(character)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts.filter { !$0.isEmpty }
    }

    private static func normalizeDeclaration(_ declaration: String) -> String {
        guard let colon = declaration.firstIndex(of: ":"), !declaration.hasPrefix("@") else { return declaration }
        let name = declaration[..<colon].trimmingCharacters(in: .whitespaces)
        let value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return "\(name): \(value)"
    }

    static func minify(_ text: String) -> String {
        var out = ""
        let tokens = tokenizeWithRanges(text)
        let source = text as NSString
        var index = 0
        var lastWasIgnored = false
        while index < tokens.count {
            let wasIgnored = lastWasIgnored
            lastWasIgnored = false
            switch tokens[index] {
            case .text(let value):
                var piece = value
                for separator in [": ", " :", ", ", " ,", " >", "> ", " +", "+ ", " ~", "~ "] where !piece.hasPrefix("@") {
                    piece = piece.replacingOccurrences(of: separator, with: String(separator.trimmingCharacters(in: .whitespaces)))
                }
                out.append(piece)
            case .open: out.append("{")
            case .close:
                if out.hasSuffix(";") && !wasIgnored { out.removeLast() }
                out.append("}")
            case .semicolon:
                if case .close? = tokens.token(at: index + 1) {} else { out.append(";") }
            case .comment(let value):
                if PrettierIgnore.isDirective(value, "prettier-ignore"),
                   let region = ignoredRegion(after: index, in: tokens, source: source) {
                    out.append(value)
                    out.append(region.text)
                    lastWasIgnored = true
                    index = region.next
                    continue
                }
            }
            index += 1
        }
        return out
    }
}

// MARK: - HTML / XML

enum MarkupReformatter {
    enum Node {
        case text(String)
        case comment(String)
        case declaration(String)       // <!DOCTYPE …>, <?xml …?>, <![CDATA[…]]>
        case open(name: String, raw: String, selfClosing: Bool)
        case close(name: String)
    }

    static let voidElements: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
    static let rawTextElements: Set<String> = ["script", "style", "textarea", "pre"]
    static let inlineElements: Set<String> = ["a", "abbr", "b", "bdi", "bdo", "cite", "code", "data", "dfn", "em", "i", "kbd", "mark", "q", "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u", "var", "img", "br", "wbr", "label", "button", "input", "select", "textarea"]

    /// The nodes of `text` with, for each, its range in `text`.
    struct Nodes {
        var nodes: [Node] = []
        var ranges: [NSRange] = []
        var count: Int { nodes.count }
        subscript(index: Int) -> Node { nodes[index] }
        mutating func append(_ node: Node, _ range: NSRange) { nodes.append(node); ranges.append(range) }
    }

    static func tokenize(_ text: String, isHTML: Bool) -> [Node] { tokenizeWithRanges(text, isHTML: isHTML).nodes }

    static func tokenizeWithRanges(_ text: String, isHTML: Bool) -> Nodes {
        let s = text as NSString
        let n = s.length
        var nodes = Nodes()
        var i = 0
        var rawUntil: String?
        while i < n {
            if let raw = rawUntil {
                let closeTag = s.range(of: "</\(raw)", options: [.caseInsensitive], range: NSRange(location: i, length: n - i))
                let end = closeTag.location == NSNotFound ? n : closeTag.location
                if end > i { nodes.append(.text(s.substring(with: NSRange(location: i, length: end - i))), NSRange(location: i, length: end - i)) }
                i = end
                rawUntil = nil
                continue
            }
            if s.character(at: i) == 0x3C { // <
                let rest = NSRange(location: i, length: n - i)
                if s.substring(with: NSRange(location: i, length: min(4, n - i))) == "<!--" {
                    let close = s.range(of: "-->", options: [], range: NSRange(location: i + 4, length: n - i - 4))
                    let end = close.location == NSNotFound ? n : close.upperBound
                    nodes.append(.comment(s.substring(with: NSRange(location: i, length: end - i))), NSRange(location: i, length: end - i))
                    i = end
                    continue
                }
                if s.substring(with: NSRange(location: i, length: min(9, n - i))) == "<![CDATA[" {
                    let close = s.range(of: "]]>", options: [], range: NSRange(location: i + 9, length: n - i - 9))
                    let end = close.location == NSNotFound ? n : close.upperBound
                    nodes.append(.declaration(s.substring(with: NSRange(location: i, length: end - i))), NSRange(location: i, length: end - i))
                    i = end
                    continue
                }
                if i + 1 < n, s.character(at: i + 1) == 0x21 || s.character(at: i + 1) == 0x3F { // <! or <?
                    let close = s.range(of: ">", options: [], range: rest)
                    let end = close.location == NSNotFound ? n : close.upperBound
                    nodes.append(.declaration(s.substring(with: NSRange(location: i, length: end - i))), NSRange(location: i, length: end - i))
                    i = end
                    continue
                }
                // A tag: find the closing '>' outside quotes.
                var j = i + 1
                var quote: unichar = 0
                while j < n {
                    let c = s.character(at: j)
                    if quote != 0 { if c == quote { quote = 0 } }
                    else if c == 0x22 || c == 0x27 { quote = c }
                    else if c == 0x3E { break }
                    j += 1
                }
                let end = min(j + 1, n)
                let raw = s.substring(with: NSRange(location: i, length: end - i))
                let inner = raw.dropFirst().dropLast()
                if inner.hasPrefix("/") {
                    nodes.append(.close(name: tagName(String(inner.dropFirst()))), NSRange(location: i, length: end - i))
                } else {
                    let name = tagName(String(inner))
                    let selfClosing = inner.hasSuffix("/") || (isHTML && voidElements.contains(name))
                    nodes.append(.open(name: name, raw: raw, selfClosing: selfClosing), NSRange(location: i, length: end - i))
                    if isHTML && rawTextElements.contains(name) && !selfClosing { rawUntil = name }
                }
                i = end
            } else {
                var j = i
                while j < n, s.character(at: j) != 0x3C { j += 1 }
                nodes.append(.text(s.substring(with: NSRange(location: i, length: j - i))), NSRange(location: i, length: j - i))
                i = j
            }
        }
        return nodes
    }

    // MARK: prettier-ignore

    /// The verbatim source of the node that follows the `<!-- prettier-ignore -->` at `commentIndex`
    /// (an element with everything up to its closing tag, or a single node), with the index of the
    /// first node after it; nil when only whitespace follows.
    static func ignoredNode(after commentIndex: Int, in nodes: Nodes, source: NSString) -> (text: String, next: Int)? {
        var start = commentIndex + 1
        while start < nodes.count, case .text(let value) = nodes[start], value.allSatisfy(\.isWhitespace) { start += 1 }
        guard start < nodes.count else { return nil }
        switch nodes[start] {
        case .open(let name, _, let selfClosing) where !selfClosing:
            var nesting = 0
            var index = start + 1
            while index < nodes.count {
                if case .open(let other, _, let selfClosingChild) = nodes[index], other == name, !selfClosingChild { nesting += 1 }
                if case .close(let other) = nodes[index], other == name {
                    if nesting == 0 { break }
                    nesting -= 1
                }
                index += 1
            }
            let from = nodes.ranges[start].location
            let end = index < nodes.count ? nodes.ranges[index].upperBound : source.length
            return (source.substring(with: NSRange(location: from, length: end - from)), min(index + 1, nodes.count))
        case .text(let value):
            return (value.trimmingCharacters(in: .whitespacesAndNewlines), start + 1)
        default:
            return (source.substring(with: nodes.ranges[start]), start + 1)
        }
    }

    /// The verbatim source between the `<!-- prettier-ignore-start -->` at `startIndex` and the matching
    /// end comment, with that end comment's index; nil when there is no end comment.
    static func ignoredRange(from startIndex: Int, in nodes: Nodes, source: NSString) -> (text: String, endIndex: Int)? {
        var index = startIndex + 1
        while index < nodes.count {
            if case .comment(let value) = nodes[index], PrettierIgnore.isDirective(value, "prettier-ignore-end") {
                let from = nodes.ranges[startIndex].upperBound
                let end = nodes.ranges[index].location
                return (source.substring(with: NSRange(location: from, length: end - from)), index)
            }
            index += 1
        }
        return nil
    }

    // MARK: Embedded CSS / JavaScript

    /// Whether a `<script>` tag holds JavaScript (no `type`, a JavaScript MIME type, or `module`).
    static func isJavaScriptTag(_ raw: String) -> Bool {
        guard let match = raw.range(of: #"\btype\s*=\s*["']?([^"'\s>]*)"#, options: [.regularExpression, .caseInsensitive]) else { return true }
        var type = String(raw[match]).drop { $0 != "=" }.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
        type = type.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return type.isEmpty || type == "module" || type.hasSuffix("javascript") || type.hasSuffix("ecmascript") || type == "text/jsx"
    }

    /// `content` of a `<style>` or JavaScript `<script>` run through the CSS / JavaScript formatter;
    /// nil for other raw elements, empty content, or JavaScript the formatter cannot parse.
    static func formatEmbedded(_ content: String, element: String, tag: String, operation: CodeFormatter.Operation, indent: String, isHTML: Bool) -> String? {
        guard isHTML, !content.allSatisfy(\.isWhitespace) else { return nil }
        switch element {
        case "style":
            return operation == .prettify ? CSSReformatter.prettify(content, indent: indent) : CSSReformatter.minify(content)
        case "script" where isJavaScriptTag(tag):
            return operation == .prettify ? JavaScriptFormatter.prettify(content, indent: indent) : JavaScriptFormatter.minify(content)
        default:
            return nil
        }
    }

    private static func tagName(_ inner: String) -> String {
        String(inner.prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" }).lowercased()
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func prettify(_ text: String, indent: String, isHTML: Bool) -> String {
        let nodes = tokenizeWithRanges(text, isHTML: isHTML)
        let source = text as NSString
        var lines: [String] = []
        var depth = 0
        var flow = ""          // current inline run (text + inline elements)
        var flowDepth = 0
        func flushFlow() {
            let trimmed = flow.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { lines.append(String(repeating: indent, count: flowDepth) + trimmed) }
            flow = ""
        }
        var index = 0
        var rawElement: String?
        var rawTag = ""
        while index < nodes.count {
            let node = nodes[index]
            switch node {
            case .text(let value):
                if let element = rawElement {
                    // Raw content: <style> and JavaScript <script> are formatted; otherwise (pre, textarea,
                    // templates, unparsable scripts) lines are kept as they are. Either way re-indented to the element.
                    flushFlow()
                    let content = formatEmbedded(value, element: element, tag: rawTag, operation: .prettify, indent: indent, isHTML: isHTML) ?? value
                    lines.append(contentsOf: reindent(content, to: String(repeating: indent, count: depth)))
                } else {
                    let collapsed = collapse(value)
                    if !collapsed.isEmpty {
                        if flow.isEmpty { flowDepth = depth }
                        let needsSpace = !flow.isEmpty && !flow.hasSuffix(" ") && (value.first?.isWhitespace ?? false)
                        flow += (needsSpace ? " " : "") + collapsed + ((value.last?.isWhitespace ?? false) ? " " : "")
                    }
                }
            case .comment(let value):
                flushFlow()
                lines.append(String(repeating: indent, count: depth) + value)
                if PrettierIgnore.isDirective(value, "prettier-ignore"),
                   let ignored = ignoredNode(after: index, in: nodes, source: source) {
                    lines.append(String(repeating: indent, count: depth) + ignored.text)
                    index = ignored.next
                    continue
                }
                if PrettierIgnore.isDirective(value, "prettier-ignore-start"),
                   let ignored = ignoredRange(from: index, in: nodes, source: source) {
                    let inner = PrettierIgnore.innerLines(of: ignored.text)
                    if !inner.allSatisfy(\.isWhitespace) { lines.append(inner) }
                    guard case .comment(let endComment) = nodes[ignored.endIndex] else { break }
                    lines.append(String(repeating: indent, count: depth) + endComment)
                    index = ignored.endIndex + 1
                    continue
                }
            case .declaration(let value):
                flushFlow()
                lines.append(String(repeating: indent, count: depth) + value)
            case .open(let name, let raw, let selfClosing):
                let isInline = isHTML && inlineElements.contains(name)
                // "<p>short text <b>with</b> inline tags</p>" stays on one line.
                if !selfClosing, !isInline, !(isHTML && rawTextElements.contains(name)),
                   let (content, endIndex) = inlineContent(of: name, startingAfter: index, in: nodes.nodes, isHTML: isHTML),
                   content.count + raw.count < 100 {
                    flushFlow()
                    lines.append(String(repeating: indent, count: depth) + raw + content + "</\(name)>")
                    index = endIndex + 1
                    continue
                }
                if isInline {
                    if flow.isEmpty { flowDepth = depth }
                    flow += raw
                } else {
                    flushFlow()
                    lines.append(String(repeating: indent, count: depth) + raw)
                    if !selfClosing {
                        depth += 1
                        if isHTML && rawTextElements.contains(name) { rawElement = name; rawTag = raw }
                    }
                }
            case .close(let name):
                let isInline = isHTML && inlineElements.contains(name)
                if isInline && rawElement == nil {
                    flow += "</\(name)>"
                } else {
                    flushFlow()
                    depth = max(0, depth - 1)
                    lines.append(String(repeating: indent, count: depth) + "</\(name)>")
                    if rawElement == name { rawElement = nil }
                }
            }
            index += 1
        }
        flushFlow()
        return lines.joined(separator: "\n") + "\n"
    }

    /// The collapsed content of an element when it holds only text and inline elements,
    /// with the index of its closing tag; nil otherwise.
    private static func inlineContent(of name: String, startingAfter openIndex: Int, in nodes: [Node], isHTML: Bool) -> (String, Int)? {
        var content = ""
        var index = openIndex + 1
        var nesting = 0
        while index < nodes.count {
            switch nodes[index] {
            case .text(let value):
                let collapsed = collapse(value)
                if !collapsed.isEmpty {
                    if (value.first?.isWhitespace ?? false) && !content.isEmpty && !content.hasSuffix(" ") { content += " " }
                    content += collapsed
                    if value.last?.isWhitespace ?? false { content += " " }
                }
            case .open(let childName, let raw, let selfClosing):
                guard isHTML && inlineElements.contains(childName) else { return nil }
                content += raw
                if !selfClosing { nesting += 1 }
            case .close(let closeName):
                if closeName == name && nesting == 0 {
                    return (content.trimmingCharacters(in: .whitespaces), index)
                }
                guard isHTML && inlineElements.contains(closeName), nesting > 0 else { return nil }
                nesting -= 1
                content += "</\(closeName)>"
            case .comment, .declaration:
                return nil
            }
            index += 1
        }
        return nil
    }

    /// Strips blank edge lines and the common leading indentation, then indents every line by `prefix`.
    private static func reindent(_ raw: String, to prefix: String) -> [String] {
        var lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        let common = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " || $0 == "\t" }.count }
            .min() ?? 0
        return lines.map { line in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : prefix + String(line.dropFirst(common))
        }
    }

    static func minify(_ text: String, isHTML: Bool) -> String {
        let nodes = tokenizeWithRanges(text, isHTML: isHTML)
        let source = text as NSString
        var out = ""
        var rawElement: String?
        var rawTag = ""
        var lastWasBlockBoundary = true
        var index = 0
        while index < nodes.count {
            let node = nodes[index]
            defer { index += 1 }
            switch node {
            case .text(let value):
                if let element = rawElement {
                    out.append(formatEmbedded(value, element: element, tag: rawTag, operation: .minify, indent: "", isHTML: isHTML)
                               ?? value.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    var collapsed = collapse(value)
                    if collapsed.isEmpty {
                        // Whitespace-only text between inline elements keeps one space.
                        if !lastWasBlockBoundary, index + 1 < nodes.count, case .open(let name, _, _) = nodes[index + 1], isHTML && inlineElements.contains(name) { out.append(" ") }
                        continue
                    }
                    if (value.first?.isWhitespace ?? false) && !lastWasBlockBoundary { collapsed = " " + collapsed }
                    if (value.last?.isWhitespace ?? false), index + 1 < nodes.count, case .open(let name, _, _) = nodes[index + 1], isHTML && inlineElements.contains(name) { collapsed += " " }
                    out.append(collapsed)
                    lastWasBlockBoundary = false
                }
            case .comment(let value):
                if value.hasPrefix("<!--[if") || value.hasPrefix("<!--<![") { out.append(value) }   // conditional comments
                if PrettierIgnore.isDirective(value, "prettier-ignore"),
                   let ignored = ignoredNode(after: index, in: nodes, source: source) {
                    out.append(value)
                    out.append(ignored.text)
                    lastWasBlockBoundary = true
                    index = ignored.next - 1
                }
                if PrettierIgnore.isDirective(value, "prettier-ignore-start"),
                   let ignored = ignoredRange(from: index, in: nodes, source: source),
                   case .comment(let endComment) = nodes[ignored.endIndex] {
                    out.append(value)
                    out.append(ignored.text)
                    out.append(endComment)
                    lastWasBlockBoundary = true
                    index = ignored.endIndex
                }
            case .declaration(let value):
                out.append(value)
                lastWasBlockBoundary = true
            case .open(let name, let raw, let selfClosing):
                out.append(collapse(raw))
                let isInline = isHTML && inlineElements.contains(name)
                lastWasBlockBoundary = !isInline
                if !selfClosing && isHTML && rawTextElements.contains(name) { rawElement = name; rawTag = raw }
            case .close(let name):
                out.append("</\(name)>")
                lastWasBlockBoundary = !(isHTML && inlineElements.contains(name))
                if rawElement == name { rawElement = nil }
            }
        }
        return out
    }
}
