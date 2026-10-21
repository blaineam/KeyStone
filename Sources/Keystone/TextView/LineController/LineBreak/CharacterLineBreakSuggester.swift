import CoreText
import Foundation

struct CharacterLineBreakSuggester {
    let typesetter: CTTypesetter
    let attributedString: NSAttributedString
    let constrainingWidth: CGFloat

    func suggestLineBreak(startingAt startOffset: Int) -> Int {
        let length = CTTypesetterSuggestClusterBreak(typesetter, startOffset, Double(constrainingWidth))
        guard startOffset + length < attributedString.length else {
            // There is no character after suggested line break.
            return length
        }
        let lastCharacterIndex = startOffset + length - 1
        let string = attributedString.string as NSString
        if string.character(at: lastCharacterIndex) == 0x0D && string.character(at: lastCharacterIndex + 1) == 0x0A {
            // Suggested line break is in the middle of CRLF so return one position ahead which is after the character pair.
            return length + 1
        }
        return length
    }
}
