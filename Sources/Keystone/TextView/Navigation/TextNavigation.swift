import Foundation

/// Word and line boundary rules shared by keyboard navigation and selection.
/// Matches what NSTextView does: a word is a run of letters, digits and `_`; a run
/// of other printable characters moves as one unit; whitespace is skipped.
enum TextNavigation {
    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    static func isWordCharacter(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return true } // surrogate halves: treat as word
        return wordCharacters.contains(scalar)
    }

    static func isWhitespace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0
    }

    static func isNewline(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D
    }

    /// The word (or punctuation run) containing `index`, or an empty range in whitespace.
    static func wordRange(at index: Int, in string: NSString) -> NSRange {
        let length = string.length
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        var probe = min(index, length - 1)
        if index == length || isWhitespace(string.character(at: probe)) {
            // Prefer the word just before the caret, as NSTextView does.
            if probe > 0, !isWhitespace(string.character(at: probe - 1)) {
                probe -= 1
            } else {
                return NSRange(location: index, length: 0)
            }
        }
        let isWord = isWordCharacter(string.character(at: probe))
        var start = probe
        while start > 0 {
            let unit = string.character(at: start - 1)
            guard !isWhitespace(unit), isWordCharacter(unit) == isWord else { break }
            start -= 1
        }
        var end = probe + 1
        while end < length {
            let unit = string.character(at: end)
            guard !isWhitespace(unit), isWordCharacter(unit) == isWord else { break }
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    /// Where ⌥← lands from `index`: before the previous word or punctuation run.
    static func wordStart(before index: Int, in string: NSString) -> Int {
        var position = min(index, string.length)
        // Skip whitespace, but stop at a line break so ⌥← doesn't leap across lines silently.
        while position > 0 {
            let unit = string.character(at: position - 1)
            if isNewline(unit) {
                return position == index ? position - 1 : position
            }
            guard isWhitespace(unit) else { break }
            position -= 1
        }
        guard position > 0 else { return 0 }
        let isWord = isWordCharacter(string.character(at: position - 1))
        while position > 0 {
            let unit = string.character(at: position - 1)
            guard !isWhitespace(unit), isWordCharacter(unit) == isWord else { break }
            position -= 1
        }
        return position
    }

    /// Where ⌥→ lands from `index`: after the next word or punctuation run.
    static func wordEnd(after index: Int, in string: NSString) -> Int {
        let length = string.length
        var position = max(0, min(index, length))
        while position < length {
            let unit = string.character(at: position)
            if isNewline(unit) {
                return position == index ? position + 1 : position
            }
            guard isWhitespace(unit) else { break }
            position += 1
        }
        guard position < length else { return length }
        let isWord = isWordCharacter(string.character(at: position))
        while position < length {
            let unit = string.character(at: position)
            guard !isWhitespace(unit), isWordCharacter(unit) == isWord else { break }
            position += 1
        }
        return position
    }

    /// First non-blank column of a line, or the line start when the line is blank.
    static func firstNonWhitespace(in lineContentRange: NSRange, of string: NSString) -> Int {
        var position = lineContentRange.location
        let end = lineContentRange.upperBound
        while position < end {
            let unit = string.character(at: position)
            guard unit == 0x20 || unit == 0x09 else { break }
            position += 1
        }
        return position == end ? lineContentRange.location : position
    }

    /// Splits pasted text into lines for distributing over the same number of carets.
    static func lines(forDistributing text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }
}

/// One cursor: where it was placed (`anchor`) and where it is now (`head`).
/// `head < anchor` for a selection made backwards. Equal means a bare caret.
struct CaretSelection: Equatable {
    var anchor: Int
    var head: Int

    var range: NSRange {
        NSRange(location: min(anchor, head), length: abs(head - anchor))
    }

    var isCaret: Bool { anchor == head }

    init(anchor: Int, head: Int) {
        self.anchor = anchor
        self.head = head
    }

    init(caretAt location: Int) {
        self.init(anchor: location, head: location)
    }

    init(range: NSRange) {
        self.init(anchor: range.location, head: range.upperBound)
    }

    func collapsed(to location: Int) -> CaretSelection {
        CaretSelection(caretAt: location)
    }

    /// Sorts by location and merges carets that coincide or selections that overlap.
    /// Returns the merged list and the index the given primary ended up at.
    static func normalized(_ carets: [CaretSelection], primary primaryIndex: Int) -> (carets: [CaretSelection], primary: Int) {
        guard !carets.isEmpty else { return ([], 0) }
        let indexed = carets.enumerated().sorted { lhs, rhs in
            let l = lhs.element.range, r = rhs.element.range
            return l.location == r.location ? l.length < r.length : l.location < r.location
        }
        var merged: [(caret: CaretSelection, isPrimary: Bool)] = []
        for (index, caret) in indexed {
            let isPrimary = index == primaryIndex
            if let last = merged.last {
                let lastRange = last.caret.range
                let range = caret.range
                let overlaps = range.location < lastRange.upperBound || (range.length == 0 && lastRange.length == 0 && range.location == lastRange.location)
                    || (range.location == lastRange.upperBound && range.length > 0 && lastRange.length > 0)
                if overlaps {
                    let union = NSRange(location: lastRange.location, length: max(lastRange.upperBound, range.upperBound) - lastRange.location)
                    let keep = isPrimary ? caret : last.caret
                    let anchorFirst = keep.anchor <= keep.head
                    merged[merged.count - 1] = (
                        CaretSelection(anchor: anchorFirst ? union.location : union.upperBound, head: anchorFirst ? union.upperBound : union.location),
                        last.isPrimary || isPrimary
                    )
                    continue
                }
            }
            merged.append((caret, isPrimary))
        }
        let primary = merged.firstIndex { $0.isPrimary } ?? merged.count - 1
        return (merged.map(\.caret), primary)
    }
}
