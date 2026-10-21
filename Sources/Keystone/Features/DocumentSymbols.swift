//
//  DocumentSymbols.swift
//  Keystone
//
//  Symbols (functions, types, headings, keys…) from the syntax tree, for the
//  outline, go-to-symbol and breadcrumbs.
//

import Foundation

public enum SymbolKind: String, Sendable, CaseIterable {
    case function, method, `class`, `struct`, `enum`, interface, module, type, variable, property, section, key, selector, tag

    /// SF Symbol name for the kind.
    public var systemImage: String {
        switch self {
        case .function: return "f.cursive"
        case .method: return "m.square"
        case .class: return "c.square"
        case .struct: return "s.square"
        case .enum: return "e.square"
        case .interface: return "p.square"
        case .module: return "shippingbox"
        case .type: return "t.square"
        case .variable: return "v.square"
        case .property: return "p.circle"
        case .section: return "number"
        case .key: return "key"
        case .selector: return "paintbrush"
        case .tag: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// One entry of the document outline.
public struct DocumentSymbol: Identifiable, Equatable, Sendable {
    public var id: String { "\(range.location):\(range.length):\(name)" }
    public let kind: SymbolKind
    public let name: String
    /// The whole construct, in UTF-16 units.
    public let range: NSRange
    /// Where to put the caret when jumping to it: the name, or the construct's start.
    public let selectionRange: NSRange
    /// 0-based line of `selectionRange`.
    public let line: Int
    /// Nesting depth in the outline.
    public let depth: Int

    public init(kind: SymbolKind, name: String, range: NSRange, selectionRange: NSRange, line: Int, depth: Int) {
        self.kind = kind
        self.name = name
        self.range = range
        self.selectionRange = selectionRange
        self.line = line
        self.depth = depth
    }
}

extension Array where Element == DocumentSymbol {
    /// The symbols enclosing `offset`, outermost first: the breadcrumb path.
    public func path(containing offset: Int) -> [DocumentSymbol] {
        var path: [DocumentSymbol] = []
        for symbol in self where symbol.range.location <= offset && offset <= symbol.range.upperBound {
            // The list is in document order, so a deeper symbol always follows its parents.
            while let last = path.last, last.depth >= symbol.depth { path.removeLast() }
            path.append(symbol)
        }
        return path
    }
}

/// Symbol extraction over the tree. Grammar-agnostic: declaration-like node types
/// plus the usual `name`/`declarator`/`key` fields, with per-language touches.
extension TreeSitterLanguageLayer {
    static let symbolLimit = 5_000
    static let symbolNodeBudget = 300_000

    func documentSymbols() -> [DocumentSymbol] {
        var symbols: [DocumentSymbol] = []
        var budget = Self.symbolNodeBudget
        collectSymbols(into: &symbols, budget: &budget, depth: 0)
        return symbols
    }

    func collectSymbols(into symbols: inout [DocumentSymbol], budget: inout Int, depth: Int) {
        if let root = tree?.rootNode {
            walk(from: root, into: &symbols, budget: &budget, depth: depth)
        }
        for child in childLanguageLayers {
            child.collectSymbols(into: &symbols, budget: &budget, depth: depth)
        }
    }

    struct SymbolContext {
        var insideFunction = false
        var insideType = false
    }

    /// Iterative, explicit-stack walk: error recovery can nest trees thousands deep,
    /// and this runs on a background thread with a small stack.
    private func walk(from root: TreeSitterNode, into symbols: inout [DocumentSymbol], budget: inout Int, depth rootDepth: Int) {
        var stack: [(node: TreeSitterNode, depth: Int, context: SymbolContext)] = [(root, rootDepth, SymbolContext())]
        while let (node, depth, context) = stack.popLast(), budget > 0, symbols.count < Self.symbolLimit {
            budget -= 1
            var childDepth = depth
            var childContext = context
            // The root (`module`, `source_file`, `program`…) is the document, not a symbol.
            if node.isNamed, node.parent != nil, let type = node.type, let (kind, nameNode) = symbolKind(for: node, type: type, context: context) {
                if let name = symbolName(for: node, type: type, nameNode: nameNode), !name.isEmpty {
                    let range = NSRange(node.byteRange)
                    let selection = nameNode.map { NSRange($0.byteRange) } ?? NSRange(location: range.location, length: 0)
                    symbols.append(DocumentSymbol(
                        kind: kind,
                        name: name,
                        range: range,
                        selectionRange: selection,
                        line: Int((nameNode ?? node).startPoint.row),
                        depth: depth
                    ))
                    childDepth = depth + 1
                    switch kind {
                    case .function, .method:
                        childContext.insideFunction = true
                    case .class, .struct, .enum, .interface, .module:
                        childContext.insideType = true
                        childContext.insideFunction = false
                    default:
                        break
                    }
                }
            }
            // Push children in reverse so they pop in document order.
            var index = node.childCount - 1
            while index >= 0 {
                if let child = node.child(at: index) {
                    stack.append((child, childDepth, childContext))
                }
                index -= 1
            }
        }
    }

    /// Swift's grammar uses `class_declaration` for class, struct, enum, actor and extension;
    /// the leading keyword tells them apart.
    private func swiftDeclarationKind(_ node: TreeSitterNode) -> SymbolKind? {
        let count = min(node.childCount, 4)
        var index = 0
        while index < count {
            if let child = node.child(at: index), !child.isNamed, let type = child.type {
                switch type {
                case "struct": return .struct
                case "enum": return .enum
                case "actor", "class": return .class
                case "extension": return .class
                case "protocol": return .interface
                default: break
                }
            }
            index += 1
        }
        return nil
    }

    private static let functionTypes: Set<String> = ["function_declaration", "function_definition", "function_item", "method_definition", "method_declaration", "method", "singleton_method", "function_signature", "init_declaration", "deinit_declaration", "constructor_declaration", "arrow_function_declaration", "subroutine", "function", "func_literal", "macro_definition"]
    private static let typeLikeTypes: [String: SymbolKind] = [
        "class_declaration": .class, "class_definition": .class, "class": .class, "class_specifier": .class, "impl_item": .class,
        "struct_declaration": .struct, "struct_item": .struct, "struct_specifier": .struct, "struct": .struct,
        "enum_declaration": .enum, "enum_item": .enum, "enum_specifier": .enum, "enum": .enum,
        "protocol_declaration": .interface, "interface_declaration": .interface, "trait_item": .interface, "trait_declaration": .interface,
        "module": .module, "mod_item": .module, "namespace_definition": .module, "namespace_declaration": .module, "package_clause": .module,
        "type_alias": .type, "type_alias_declaration": .type, "typealias_declaration": .type, "type_spec": .type, "type_item": .type, "type_declaration": .type, "typedef_declaration": .type, "extension_declaration": .class,
        "atx_heading": .section, "setext_heading": .section,
        "rule_set": .selector,
        "table": .module, "table_array_element": .module,
    ]
    private static let variableTypes: Set<String> = ["variable_declarator", "property_declaration", "field_declaration", "const_item", "static_item", "let_declaration", "const_declaration", "var_declaration", "short_var_declaration", "assignment", "property_signature", "public_field_definition", "field_definition"]
    private static let keyTypes: Set<String> = ["pair", "block_mapping_pair", "flow_pair"]

    private func symbolKind(for node: TreeSitterNode, type: String, context: SymbolContext) -> (SymbolKind, TreeSitterNode?)? {
        if Self.functionTypes.contains(type) || (type.hasSuffix("_declaration") && type.contains("function")) {
            let name = node.child(forFieldName: "name") ?? node.child(forFieldName: "declarator")?.firstDescendant { $0 == "identifier" || $0 == "field_identifier" }
            return (context.insideType ? .method : .function, name)
        }
        if let kind = Self.typeLikeTypes[type] {
            if type == "atx_heading" || type == "setext_heading" { return (kind, nil) }
            if type == "rule_set" { return (kind, node.child(forFieldName: "selectors") ?? node.child(at: 0)) }
            if type == "table" || type == "table_array_element" { return (kind, node.firstDescendant(maxDepth: 2) { $0.contains("key") }) }
            let name = node.child(forFieldName: "name") ?? node.child(forFieldName: "type") ?? node.firstDescendant(maxDepth: 2) { $0 == "type_identifier" || $0 == "identifier" || $0 == "simple_identifier" || $0 == "user_type" }
            if type == "class_declaration", let swiftKind = swiftDeclarationKind(node) {
                return (swiftKind, name)
            }
            return (kind, name)
        }
        if Self.keyTypes.contains(type) {
            return (.key, node.child(forFieldName: "key"))
        }
        if Self.variableTypes.contains(type), !context.insideFunction {
            // Arrow functions and closures assigned to names count as functions.
            let value = node.child(forFieldName: "value")
            let kind: SymbolKind = (value?.type.map { $0.contains("function") || $0.contains("lambda") || $0.contains("closure") } ?? false) ? .function : .variable
            let name = node.child(forFieldName: "name") ?? node.child(forFieldName: "left") ?? node.child(forFieldName: "pattern") ?? node.firstDescendant(maxDepth: 3) { $0 == "identifier" || $0 == "simple_identifier" || $0 == "pattern" || $0 == "property_identifier" }
            return (context.insideType && kind == .variable ? .property : kind, name)
        }
        if type == "element" || type == "script_element" || type == "style_element" {
            // HTML: only elements with an id are worth an outline entry
            guard let startTag = node.child(at: 0), startTag.type == "start_tag" else { return nil }
            let count = startTag.childCount
            var index = 0
            while index < count {
                if let attribute = startTag.child(at: index), attribute.type == "attribute",
                   let attributeName = attribute.child(forFieldName: "name") ?? attribute.child(at: 0),
                   text(of: attributeName) == "id" {
                    return (.tag, attribute)
                }
                index += 1
            }
            return nil
        }
        return nil
    }

    private func symbolName(for node: TreeSitterNode, type: String, nameNode: TreeSitterNode?) -> String? {
        switch type {
        case "atx_heading", "setext_heading":
            let raw = text(of: node).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return raw.trimmingCharacters(in: CharacterSet(charactersIn: "# =-").union(.whitespaces))
        case "element", "script_element", "style_element":
            guard let attribute = nameNode else { return nil }
            let raw = text(of: attribute)
            let value = raw.split(separator: "=", maxSplits: 1).last.map(String.init) ?? raw
            return "#" + value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        case "pair", "block_mapping_pair", "flow_pair":
            guard let key = nameNode else { return nil }
            return text(of: key).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        case "rule_set":
            return nameNode.map { text(of: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
        default:
            guard let nameNode else { return nil }
            let name = text(of: nameNode).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.count > 80 ? String(name.prefix(80)) : name
        }
    }

    private func text(of node: TreeSitterNode) -> String {
        let string = textSourceString
        let range = NSRange(node.byteRange)
        guard range.location >= 0, range.upperBound <= string.length, range.length < 4_000 else { return "" }
        return string.substring(with: range)
    }
}
