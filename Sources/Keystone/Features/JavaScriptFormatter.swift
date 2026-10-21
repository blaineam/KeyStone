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
            return Library.beautify.callReturningString(beautify, arguments: [source, options])
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
        return queue.sync {
            guard let terser = Library.terser.function else { return nil }
            let options: [String: Any] = [
                "compress": ["passes": 1],
                "mangle": ["toplevel": false],
                "format": ["comments": false],
            ]
            // minify_sync returns { code } or throws; the async `minify` would
            // need the context's microtask queue drained, which this avoids.
            guard let result = Library.terser.call(terser, arguments: [source, options]),
                  result.isObject,
                  let code = result.forProperty("code"), code.isString else { return nil }
            return code.toString()
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
