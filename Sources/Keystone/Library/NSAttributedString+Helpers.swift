import Foundation

extension NSAttributedString {
    func isWhitespaceCharacter(at location: Int) -> Bool {
        (string as NSString).isWhitespaceCharacter(at: location)
    }
}

extension NSString {
    /// Whether the UTF-16 unit at `location` is a whitespace character (`CharacterSet.whitespaces`).
    ///
    /// A lone surrogate is not whitespace. Reads one unit instead of making a substring,
    /// which matters when typesetting looks at characters one by one.
    func isWhitespaceCharacter(at location: Int) -> Bool {
        guard location >= 0 && location < length else {
            return false
        }
        guard let scalar = Unicode.Scalar(character(at: location)) else {
            return false
        }
        return CharacterSet.whitespaces.contains(scalar)
    }

    /// Whether the UTF-16 unit at `location` is whitespace or punctuation: a place a soft
    /// wrap prefers to break after. A lone surrogate is neither.
    func isLineBreakableCharacter(at location: Int) -> Bool {
        guard location >= 0 && location < length else {
            return false
        }
        guard let scalar = Unicode.Scalar(character(at: location)) else {
            return false
        }
        return CharacterSet.whitespaces.contains(scalar) || CharacterSet.punctuationCharacters.contains(scalar)
    }
}
