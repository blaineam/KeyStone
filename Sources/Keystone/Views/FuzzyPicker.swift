//
//  FuzzyPicker.swift
//  Keystone
//
//  The filterable list behind Go to Symbol and the command palette.
//

import SwiftUI

/// Subsequence matching with a score: consecutive runs and word starts score higher.
public enum FuzzyMatcher {
    /// `nil` when `query` is not a subsequence of `candidate`. Higher is better.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased().unicodeScalars)
        guard !q.isEmpty else { return 0 }
        let c = Array(candidate.lowercased().unicodeScalars)
        let original = Array(candidate.unicodeScalars)
        var qi = 0
        var score = 0
        var previousMatch = -2
        for (ci, scalar) in c.enumerated() where qi < q.count && scalar == q[qi] {
            score += 1
            if ci == previousMatch + 1 { score += 3 }                       // consecutive
            if ci == 0 { score += 4 }                                        // start of string
            else {
                let prev = original[ci - 1]
                let isBoundary = prev == "_" || prev == "." || prev == " " || prev == "/" || prev == "-" || prev == ":"
                    || (CharacterSet.uppercaseLetters.contains(original[ci]) && CharacterSet.lowercaseLetters.contains(prev))
                if isBoundary { score += 3 }                                 // word start
            }
            previousMatch = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        return score - (c.count - q.count) / 8                                // slight preference for shorter
    }
}

/// An entry in a ``FuzzyPickerView``.
struct FuzzyPickerItem: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    var systemImage: String?
    var detail: String?
    var indent: Int = 0
    /// Text the filter matches against; defaults to the title.
    var searchText: String?
}

/// A search field over a list, driven by the keyboard: ↑/↓ move, ⏎ picks, ⎋ closes.
struct FuzzyPickerView: View {
    let placeholder: String
    let items: [FuzzyPickerItem]
    var emptyText: String = ""
    let onSelect: (FuzzyPickerItem) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFieldFocused: Bool

    private var filtered: [FuzzyPickerItem] {
        guard !query.isEmpty else { return items }
        return items
            .compactMap { item -> (FuzzyPickerItem, Int)? in
                let haystack = item.searchText ?? (item.subtitle.map { "\(item.title) \($0)" } ?? item.title)
                return FuzzyMatcher.score(query, in: haystack).map { (item, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        let results = filtered
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit { pick(results) }
                    .onKeyPress(.upArrow) { moveSelection(-1, count: results.count); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(1, count: results.count); return .handled }
                    .onKeyPress(.escape) { onDismiss(); return .handled }
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            if results.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, isSelected: index == min(selectedIndex, results.count - 1))
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(item) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) { _, newValue in
                        if results.indices.contains(newValue) {
                            proxy.scrollTo(results[newValue].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color.keystoneStatusBar)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.secondary.opacity(0.25)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private func row(_ item: FuzzyPickerItem, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            if item.indent > 0 {
                Spacer().frame(width: CGFloat(item.indent) * 14)
            }
            if let image = item.systemImage {
                Image(systemName: image)
                    .frame(width: 18)
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let detail = item.detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color.clear)
        .foregroundColor(isSelected ? .white : .primary)
    }

    private func moveSelection(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func pick(_ results: [FuzzyPickerItem]) {
        guard !results.isEmpty else { return }
        onSelect(results[min(selectedIndex, results.count - 1)])
    }
}
