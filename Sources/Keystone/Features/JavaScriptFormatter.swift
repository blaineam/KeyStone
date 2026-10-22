//
//  JavaScriptFormatter.swift
//  Keystone
//
//  JavaScript/TypeScript prettify and minify, run in-process in JavaScriptCore.
//  Prettify is js-beautify (MIT); minify is terser (BSD-2). Both ship as package
//  resources under Resources/Formatters and are evaluated lazily, once, into a
//  JSContext each. Nothing is executed outside the JS virtual machine and nothing
//  touches the network.
//

import Foundation
import JavaScriptCore

enum JavaScriptFormatter {
    /// Inputs above this size return nil; js-beautify and terser are O(n) but a
    /// multi-megabyte run on the main thread would freeze the editor.
    static let maxInputBytes = 2 * 1024 * 1024

    /// Beautified `source`, or nil when the input is too large or js-beautify throws.
    /// `isTypeScript` is accepted for symmetry; js-beautify handles TS syntax
    /// (annotations, generics, decorators) with its JavaScript beautifier.
    static func prettify(_ source: String, indent: String, isTypeScript: Bool = false) -> String? {
        guard source.utf8.count <= maxInputBytes else { return nil }
        let ignored = IgnoredRegions(source)
        return queue.sync {
            guard let beautify = Library.beautify.function else { return nil }
            let usesTabs = indent.first == "\t"
            let options: [String: Any] = [
                "indent_size": max(1, indent.count),
                "indent_char": usesTabs ? "\t" : " ",
                "indent_with_tabs": usesTabs,
                "end_with_newline": true,
                "preserve_newlines": true,
                "max_preserve_newlines": 2,
            ]
            if let formatted = Library.beautify.callReturningString(beautify, arguments: [ignored.protected, options]) {
                return ignored.restore(formatted)
            }
            // Placeholders in a position js-beautify could not take: format without honouring the ignores.
            return ignored.isEmpty ? nil : Library.beautify.callReturningString(beautify, arguments: [source, options])
        }
    }

    /// Minified `source`, or nil when the input is too large, is TypeScript, or
    /// terser cannot parse it. Terser parses JavaScript only, so TypeScript
    /// (type annotations, interfaces, enums) is refused rather than mangled.
    ///
    /// Real minification: terser's compressor and local-name mangler run, comments
    /// go; top-level names are kept (`toplevel: false`) so the result stays usable
    /// as a drop-in script. Behaviour is preserved, text is not round-trippable.
    static func minify(_ source: String, isTypeScript: Bool = false) -> String? {
        guard !isTypeScript, source.utf8.count <= maxInputBytes else { return nil }
        let ignored = IgnoredRegions(source)
        return queue.sync {
            guard let terser = Library.terser.function else { return nil }
            // An ignored statement is pasted back verbatim after terser, so with ignores present
            // terser only strips whitespace and comments: compression could move or merge the
            // placeholder (sequences, hoisting) and mangling could rename what the region refers to.
            let options: [String: Any] = ignored.isEmpty ? [
                "compress": ["passes": 1],
                "mangle": ["toplevel": false],
                "format": ["comments": false],
            ] : [
                "compress": false,
                "mangle": false,
                "format": ["comments": false],
            ]
            // minify_sync returns { code } or throws; the async `minify` would
            // need the context's microtask queue drained, which this avoids.
            func run(_ text: String) -> String? {
                guard let result = Library.terser.call(terser, arguments: [text, options]),
                      result.isObject,
                      let code = result.forProperty("code"), code.isString else { return nil }
                return code.toString()
            }
            if let code = run(ignored.protected) { return ignored.restore(code, separateStatements: true) }
            return ignored.isEmpty ? nil : run(source)
        }
    }

    // MARK: - prettier-ignore

    /// The `// prettier-ignore` / `/* prettier-ignore */` regions of a program: each comment and the
    /// statement after it, replaced in `protected` by a placeholder call the formatters pass through
    /// unchanged, and pasted back verbatim by `restore`.
    struct IgnoredRegions {
        private(set) var protected: String
        private var regions: [String] = []
        var isEmpty: Bool { regions.isEmpty }

        private static let placeholderPrefix = "__KEYSTONE_PRETTIER_IGNORE_"

        init(_ source: String) {
            let s = source as NSString
            let n = s.length
            var out = ""
            var copiedUpTo = 0
            var scanner = Scanner(s)
            var i = 0
            while i < n {
                let (end, isComment) = scanner.advance(from: i)
                if isComment, PrettierIgnore.isDirective(s.substring(with: NSRange(location: i, length: end - i)), "prettier-ignore") {
                    var statementStart = end
                    while statementStart < n, Scanner.isWhitespace(s.character(at: statementStart)) { statementStart += 1 }
                    var statementScanner = Scanner(s)
                    if statementStart < n, let statementEnd = statementScanner.statementEnd(from: statementStart) {
                        out += s.substring(with: NSRange(location: copiedUpTo, length: i - copiedUpTo))
                        out += "\(Self.placeholderPrefix)\(regions.count)__();"
                        regions.append(s.substring(with: NSRange(location: i, length: statementEnd - i)))
                        copiedUpTo = statementEnd
                        scanner = Scanner(s)
                        i = statementEnd
                        continue
                    }
                }
                i = end
            }
            out += s.substring(with: NSRange(location: copiedUpTo, length: n - copiedUpTo))
            protected = out
        }

        /// `formatted` with every placeholder replaced by its region. With `separateStatements`, a region
        /// that does not end in `;` or `}` is followed by a line break so the next statement is not glued
        /// to it (terser prints statements back to back).
        func restore(_ formatted: String, separateStatements: Bool = false) -> String {
            guard !regions.isEmpty else { return formatted }
            var result = formatted
            for (index, region) in regions.enumerated().reversed() {
                let placeholder = "\(Self.placeholderPrefix)\(index)__()"
                var replacement = region
                if separateStatements, !(region.hasSuffix(";") || region.hasSuffix("}")) { replacement += "\n" }
                result = result.replacingOccurrences(of: placeholder + ";", with: replacement)
                result = result.replacingOccurrences(of: placeholder, with: replacement)
            }
            return result
        }

        /// A lexer-lite that steps over strings, template literals, regular-expression literals and comments.
        struct Scanner {
            let s: NSString
            /// The last significant (non-whitespace, non-comment) character, for regex-vs-division.
            var lastSignificant: unichar = 0

            init(_ s: NSString) { self.s = s }

            static func isWhitespace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
            static func isIdentifier(_ c: unichar) -> Bool {
                (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x24 || c > 0x7F
            }

            /// The end of the token starting at `i` (a literal or comment is stepped over whole; anything
            /// else is one character), and whether it was a comment.
            mutating func advance(from i: Int) -> (end: Int, isComment: Bool) {
                let n = s.length
                let c = s.character(at: i)
                let next: unichar = i + 1 < n ? s.character(at: i + 1) : 0
                if c == 0x2F && next == 0x2F { // line comment
                    var j = i + 2
                    while j < n, s.character(at: j) != 0x0A { j += 1 }
                    return (j, true)
                }
                if c == 0x2F && next == 0x2A { // block comment
                    let close = s.range(of: "*/", options: [], range: NSRange(location: i + 2, length: n - i - 2))
                    return (close.location == NSNotFound ? n : close.upperBound, true)
                }
                if c == 0x22 || c == 0x27 { // string
                    var j = i + 1
                    while j < n {
                        let d = s.character(at: j)
                        if d == 0x5C { j += 2; continue }
                        if d == c || d == 0x0A { break }
                        j += 1
                    }
                    lastSignificant = c
                    return (min(j + 1, n), false)
                }
                if c == 0x60 { // template literal, with nested ${ … } (which may hold templates of its own)
                    lastSignificant = c
                    return (templateEnd(from: i), false)
                }
                if c == 0x2F, regexAllowed { // regular expression literal
                    var j = i + 1
                    var inClass = false
                    while j < n {
                        let d = s.character(at: j)
                        if d == 0x5C { j += 2; continue }
                        if d == 0x0A { break }
                        if inClass { if d == 0x5D { inClass = false } }
                        else if d == 0x5B { inClass = true }
                        else if d == 0x2F { break }
                        j += 1
                    }
                    j = min(j + 1, n)
                    while j < n, Self.isIdentifier(s.character(at: j)) { j += 1 } // flags
                    lastSignificant = c
                    return (j, false)
                }
                if !Self.isWhitespace(c) { lastSignificant = c }
                return (i + 1, false)
            }

            private var regexAllowed: Bool {
                switch lastSignificant {
                case 0, 0x28, 0x2C, 0x3D, 0x3A, 0x5B, 0x21, 0x26, 0x7C, 0x3F, 0x7B, 0x7D, 0x3B, 0x2B, 0x2D, 0x2A, 0x25, 0x3C, 0x3E, 0x5E, 0x7E, 0x0A: return true
                default: return false
                }
            }

            private func templateEnd(from i: Int) -> Int {
                let n = s.length
                var j = i + 1
                while j < n {
                    let d = s.character(at: j)
                    if d == 0x5C { j += 2; continue }
                    if d == 0x60 { return j + 1 }
                    if d == 0x24, j + 1 < n, s.character(at: j + 1) == 0x7B { // ${ … }
                        var inner = Scanner(s)
                        var depth = 0
                        var k = j + 1
                        while k < n {
                            let e = s.character(at: k)
                            if e == 0x7B { depth += 1 }
                            if e == 0x7D { depth -= 1; if depth == 0 { break } }
                            k = inner.advance(from: k).end
                        }
                        j = k + 1
                        continue
                    }
                    j += 1
                }
                return n
            }

            /// The end of the statement that starts at `start`: at its `;`, at the `}` that closes it,
            /// or at the line break where automatic semicolon insertion would end it.
            mutating func statementEnd(from start: Int) -> Int? {
                let n = s.length
                var depth = 0
                var i = start
                var firstWord = ""
                var w = start
                while w < n, Self.isIdentifier(s.character(at: w)) { firstWord.append(Character(UnicodeScalar(s.character(at: w)) ?? " ")); w += 1 }
                var lastEnd = start
                while i < n {
                    let c = s.character(at: i)
                    let (end, _) = advance(from: i)
                    if end > i + 1 { lastEnd = end; i = end; continue } // literal or comment
                    switch c {
                    case 0x28, 0x5B, 0x7B: depth += 1
                    case 0x29, 0x5D: depth = max(0, depth - 1)
                    case 0x7D:
                        depth = max(0, depth - 1)
                        if depth == 0 {
                            // `}` closing a block or object: ends the statement unless the same line or a
                            // continuation (`;`, `else`, `catch`, `finally`, do-while, `.`, operators) goes on.
                            var j = i + 1
                            while j < n, s.character(at: j) == 0x20 || s.character(at: j) == 0x09 { j += 1 }
                            if j < n, s.character(at: j) == 0x3B { return j + 1 }
                            if j < n, s.character(at: j) != 0x0A, s.character(at: j) != 0x0D { lastEnd = i + 1; i += 1; continue }
                            if continues(at: j, firstWord: firstWord) { lastEnd = i + 1; i += 1; continue }
                            return i + 1
                        }
                    case 0x3B where depth == 0:
                        return i + 1
                    case 0x0A where depth == 0:
                        if continuesAfterLineBreak(lastSignificant) || continues(at: i + 1, firstWord: firstWord) { i += 1; continue }
                        return lastEnd
                    default: break
                    }
                    if !Self.isWhitespace(c) { lastEnd = i + 1 }
                    i += 1
                }
                return lastEnd > start ? lastEnd : nil
            }

            /// Whether the character before a line break leaves the statement open.
            private func continuesAfterLineBreak(_ c: unichar) -> Bool {
                switch c {
                case 0x2C, 0x2E, 0x28, 0x5B, 0x7B, 0x3D, 0x2B, 0x2D, 0x2A, 0x2F, 0x25, 0x3C, 0x3E, 0x26, 0x7C, 0x5E, 0x3F, 0x3A, 0x21, 0x7E: return true
                default: return false
                }
            }

            /// Whether what follows the line break at `position` continues the current statement.
            private func continues(at position: Int, firstWord: String) -> Bool {
                let n = s.length
                var j = position
                while j < n, Self.isWhitespace(s.character(at: j)) { j += 1 }
                guard j < n else { return false }
                let c = s.character(at: j)
                if c == 0x2E || c == 0x3F || c == 0x3A || c == 0x26 || c == 0x7C || c == 0x3D { return true } // . ? : && || =
                var word = ""
                var k = j
                while k < n, Self.isIdentifier(s.character(at: k)) { word.append(Character(UnicodeScalar(s.character(at: k)) ?? " ")); k += 1 }
                switch word {
                case "else", "catch", "finally": return true
                case "while": return firstWord == "do"
                default: return false
                }
            }
        }
    }

    // MARK: - Libraries

    /// All JSContext use is confined to this queue.
    private static let queue = DispatchQueue(label: "io.keystone.JavaScriptFormatter")

    final class Library {
        static let beautify = Library(resource: "beautify", entry: { context in
            // beautify.js exports through `exports` when present.
            context.evaluateScript("var exports = {};")
            return nil
        }, lookup: { context in
            context.evaluateScript("exports.js_beautify")
        })

        static let terser = Library(resource: "terser.bundle.min", entry: { _ in nil }, lookup: { context in
            // UMD: with no `exports`/`define` the bundle installs `globalThis.Terser`.
            context.evaluateScript("Terser.minify_sync")
        })

        private let resource: String
        private let entry: (JSContext) -> JSValue?
        private let lookup: (JSContext) -> JSValue?
        private var loaded = false
        private var context: JSContext?
        private var cachedFunction: JSValue?
        private(set) var lastError: String?

        init(resource: String, entry: @escaping (JSContext) -> JSValue?, lookup: @escaping (JSContext) -> JSValue?) {
            self.resource = resource
            self.entry = entry
            self.lookup = lookup
        }

        /// The library's entry function, loading the script on first use. Nil
        /// when the resource is missing or failed to evaluate.
        var function: JSValue? {
            if loaded { return cachedFunction }
            loaded = true
            guard let url = Bundle.module.url(forResource: resource, withExtension: "js", subdirectory: "Formatters"),
                  let script = try? String(contentsOf: url, encoding: .utf8),
                  let context = JSContext() else {
                lastError = "resource \(resource).js not found"
                return nil
            }
            context.exceptionHandler = { [weak self] _, exception in
                self?.lastError = exception?.toString()
            }
            self.context = context
            _ = entry(context)
            context.evaluateScript(script, withSourceURL: url)
            guard lastError == nil, let function = lookup(context), function.isObject else {
                self.context = nil
                return nil
            }
            cachedFunction = function
            return function
        }

        /// Calls `function` and returns its result, or nil when it threw.
        func call(_ function: JSValue, arguments: [Any]) -> JSValue? {
            lastError = nil
            let result = function.call(withArguments: arguments)
            return lastError == nil ? result : nil
        }

        func callReturningString(_ function: JSValue, arguments: [Any]) -> String? {
            guard let result = call(function, arguments: arguments), result.isString else { return nil }
            return result.toString()
        }
    }
}
