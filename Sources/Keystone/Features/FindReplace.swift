//
//  FindReplace.swift
//  Keystone
//
//  Find and replace functionality for the code editor.
//

import Foundation
import SwiftUI

/// Represents a search match in the text.
public struct SearchMatch: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The range of the match in the text.
    public let range: Range<String.Index>
    /// The line number where the match occurs (1-based).
    public let lineNumber: Int
    /// The column where the match starts (1-based).
    public let column: Int
    /// The matched text.
    public let matchedText: String

    public init(
        id: UUID = UUID(),
        range: Range<String.Index>,
        lineNumber: Int,
        column: Int,
        matchedText: String
    ) {
        self.id = id
        self.range = range
        self.lineNumber = lineNumber
        self.column = column
        self.matchedText = matchedText
    }
}

/// Options for search operations.
public struct SearchOptions: Equatable, Sendable {
    /// Whether the search is case sensitive.
    public var caseSensitive: Bool
    /// Whether to match whole words only.
    public var wholeWord: Bool
    /// Whether to use regular expressions.
    public var useRegex: Bool
    /// Whether to wrap around when reaching the end.
    public var wrapAround: Bool

    public init(
        caseSensitive: Bool = false,
        wholeWord: Bool = false,
        useRegex: Bool = false,
        wrapAround: Bool = true
    ) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.useRegex = useRegex
        self.wrapAround = wrapAround
    }
}

/// Manages find and replace operations.
@MainActor
public class FindReplaceManager: ObservableObject {
    /// The current search query.
    @Published public var searchQuery: String = ""

    /// The replacement text.
    @Published public var replaceText: String = ""

    /// Search options.
    @Published public var options: SearchOptions = SearchOptions()

    /// All matches found.
    @Published public private(set) var matches: [SearchMatch] = []

    /// The index of the currently selected match.
    @Published public var currentMatchIndex: Int = 0

    /// Whether the search bar is visible.
    @Published public var isVisible: Bool = false

    /// Whether the replace bar is expanded.
    @Published public var showReplace: Bool = false

    /// Whether a search is currently in progress
    @Published public private(set) var isSearching: Bool = false

    /// Minimum characters required before search runs
    public static let minimumSearchLength: Int = 3

    /// Background queue for search operations
    private let searchQueue = DispatchQueue(label: "com.keystone.search", qos: .userInitiated)

    /// The current match, if any.
    public var currentMatch: SearchMatch? {
        guard !matches.isEmpty && currentMatchIndex >= 0 && currentMatchIndex < matches.count else {
            return nil
        }
        return matches[currentMatchIndex]
    }

    /// Status text showing match count.
    public var statusText: String {
        if searchQuery.isEmpty {
            return ""
        }
        if isSearching {
            return "Searching..."
        }
        // Show hint if no search has been performed yet
        if matches.isEmpty && !hasSearched {
            return "Press Return"
        }
        if matches.isEmpty {
            return "No results"
        }
        return "\(currentMatchIndex + 1) of \(matches.count)"
    }

    /// Whether a search has been performed for the current query
    @Published private var hasSearched: Bool = false

    /// Tracks the last query that was searched to detect changes
    private var lastSearchedQuery: String = ""

    public init() {}

    /// Performs a search in the given text.
    /// Only runs when explicitly triggered (Return key). Runs on background thread.
    /// - Parameter text: The text to search in.
    public func search(in text: String) {
        guard !searchQuery.isEmpty else {
            matches = []
            currentMatchIndex = 0
            hasSearched = false
            return
        }

        // Capture search parameters
        let query = searchQuery
        let searchOptions = options

        isSearching = true
        hasSearched = true
        lastSearchedQuery = query

        // Run search on background thread
        searchQueue.async { [weak self] in
            let foundMatches = Self.performSearch(query: query, in: text, options: searchOptions)

            // Update results on main thread
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Only update if query hasn't changed while searching
                guard self.searchQuery == query else {
                    return
                }

                self.matches = foundMatches
                self.isSearching = false

                // Adjust current match index if needed
                if self.matches.isEmpty {
                    self.currentMatchIndex = 0
                } else if self.currentMatchIndex >= self.matches.count {
                    self.currentMatchIndex = self.matches.count - 1
                }
            }
        }
    }

    /// Resets search state when query changes (called by view)
    public func queryDidChange() {
        if searchQuery != lastSearchedQuery {
            hasSearched = false
        }
    }

    /// Performs the actual search work (can be called from any thread)
    private nonisolated static func performSearch(query: String, in text: String, options: SearchOptions) -> [SearchMatch] {
        var foundMatches: [SearchMatch] = []
        let lines = text.components(separatedBy: .newlines)

        // Build the search pattern
        var pattern = query
        if !options.useRegex {
            pattern = NSRegularExpression.escapedPattern(for: pattern)
        }
        if options.wholeWord {
            pattern = "\\b\(pattern)\\b"
        }

        var regexOptions: NSRegularExpression.Options = []
        if !options.caseSensitive {
            regexOptions.insert(.caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        var currentLineStart = 0
        var currentLine = 1

        regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }

            // Calculate line number and column
            while currentLineStart + lines[currentLine - 1].count < match.range.location && currentLine < lines.count {
                currentLineStart += lines[currentLine - 1].count + 1 // +1 for newline
                currentLine += 1
            }

            let column = match.range.location - currentLineStart + 1

            if let swiftRange = Range(match.range, in: text) {
                let matchedText = String(text[swiftRange])
                foundMatches.append(SearchMatch(
                    range: swiftRange,
                    lineNumber: currentLine,
                    column: column,
                    matchedText: matchedText
                ))
            }
        }

        return foundMatches
    }

    /// Moves to the next match.
    public func findNext() {
        guard !matches.isEmpty else { return }

        if currentMatchIndex < matches.count - 1 {
            currentMatchIndex += 1
        } else if options.wrapAround {
            currentMatchIndex = 0
        }
    }

    /// Moves to the previous match.
    public func findPrevious() {
        guard !matches.isEmpty else { return }

        if currentMatchIndex > 0 {
            currentMatchIndex -= 1
        } else if options.wrapAround {
            currentMatchIndex = matches.count - 1
        }
    }

    /// Replaces the current match.
    /// - Parameter text: The full text being edited.
    /// - Returns: The text with the replacement made, or nil if no current match.
    public func replaceCurrent(in text: String) -> String? {
        guard let match = currentMatch else { return nil }

        var newText = text
        newText.replaceSubrange(match.range, with: replaceText)

        // Re-search to update matches
        search(in: newText)

        return newText
    }

    /// Replaces all matches.
    /// - Parameter text: The full text being edited.
    /// - Returns: The text with all replacements made.
    public func replaceAll(in text: String) -> String {
        guard !matches.isEmpty else { return text }

        var newText = text

        // Replace in reverse order to preserve indices
        for match in matches.reversed() {
            newText.replaceSubrange(match.range, with: replaceText)
        }

        // Clear matches after replace all
        matches = []
        currentMatchIndex = 0

        return newText
    }

    /// Shows the find bar.
    public func show() {
        isVisible = true
    }

    /// Hides the find bar.
    public func hide() {
        isVisible = false
        showReplace = false
    }

    /// Toggles the find bar visibility.
    public func toggle() {
        isVisible.toggle()
        if !isVisible {
            showReplace = false
        }
    }

    /// Clears the search.
    public func clear() {
        searchQuery = ""
        replaceText = ""
        matches = []
        currentMatchIndex = 0
    }
}

// MARK: - Find Replace Bar View

/// A SwiftUI view for the find and replace bar.
public struct FindReplaceBar: View {
    @ObservedObject var manager: FindReplaceManager
    let text: String
    let isLargeFile: Bool
    let onReplace: (String) -> Void
    let onNavigateToMatch: (SearchMatch) -> Void

    /// Debounce timer for auto-search
    @State private var searchDebounceTask: DispatchWorkItem?

    /// Debounce delay for auto-search (2 seconds)
    private static let autoSearchDelay: TimeInterval = 2.0

    public init(
        manager: FindReplaceManager,
        text: String,
        isLargeFile: Bool = false,
        onReplace: @escaping (String) -> Void,
        onNavigateToMatch: @escaping (SearchMatch) -> Void
    ) {
        self.manager = manager
        self.text = text
        self.isLargeFile = isLargeFile
        self.onReplace = onReplace
        self.onNavigateToMatch = onNavigateToMatch
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Find row
            HStack(spacing: 8) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Find", text: $manager.searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            manager.search(in: text)
                            if let match = manager.currentMatch {
                                onNavigateToMatch(match)
                            }
                        }
                        .onChange(of: manager.searchQuery) { _, newValue in
                            manager.queryDidChange()

                            // Cancel any pending debounce
                            searchDebounceTask?.cancel()
                            searchDebounceTask = nil

                            // For small files, auto-search with debounce after 2s of idle
                            if !isLargeFile && newValue.count >= FindReplaceManager.minimumSearchLength {
                                let task = DispatchWorkItem { [weak manager] in
                                    manager?.search(in: text)
                                }
                                searchDebounceTask = task
                                DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoSearchDelay, execute: task)
                            }
                        }
                    if !manager.searchQuery.isEmpty {
                        Button(action: { manager.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

                // Match status
                Text(manager.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 60)

                // Navigation buttons
                Button(action: {
                    manager.findPrevious()
                    if let match = manager.currentMatch {
                        onNavigateToMatch(match)
                    }
                }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(manager.matches.isEmpty)

                Button(action: {
                    manager.findNext()
                    if let match = manager.currentMatch {
                        onNavigateToMatch(match)
                    }
                }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(manager.matches.isEmpty)

                // Options menu
                Menu {
                    Toggle("Case Sensitive", isOn: $manager.options.caseSensitive)
                    Toggle("Whole Word", isOn: $manager.options.wholeWord)
                    Toggle("Regular Expression", isOn: $manager.options.useRegex)
                    Toggle("Wrap Around", isOn: $manager.options.wrapAround)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .onChange(of: manager.options) { _, _ in
                    manager.search(in: text)
                }

                // Toggle replace
                Button(action: { manager.showReplace.toggle() }) {
                    Image(systemName: manager.showReplace ? "chevron.up.square" : "chevron.down.square")
                }
                .buttonStyle(.plain)

                // Close button
                Button(action: { manager.hide() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            // Replace row (if visible)
            if manager.showReplace {
                HStack(spacing: 8) {
                    // Replace field
                    HStack {
                        Image(systemName: "arrow.right.arrow.left")
                            .foregroundColor(.secondary)
                        TextField("Replace", text: $manager.replaceText)
                            .textFieldStyle(.plain)
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)

                    // Replace buttons
                    #if os(iOS)
                    Button("Replace") {
                        if let newText = manager.replaceCurrent(in: text) {
                            onReplace(newText)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.currentMatch == nil)

                    Button("Replace All") {
                        let newText = manager.replaceAll(in: text)
                        onReplace(newText)
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.matches.isEmpty)
                    #else
                    // macOS: Use plain text buttons to avoid double border
                    Button(action: {
                        if let newText = manager.replaceCurrent(in: text) {
                            onReplace(newText)
                        }
                    }) {
                        Text("Replace")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(manager.currentMatch == nil)

                    Button(action: {
                        let newText = manager.replaceAll(in: text)
                        onReplace(newText)
                    }) {
                        Text("Replace All")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(manager.matches.isEmpty)
                    #endif
                }
            }
        }
        .padding(8)
        .background(Color.keystoneStatusBar)
    }
}
