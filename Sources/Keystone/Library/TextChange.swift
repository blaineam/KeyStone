import Foundation

struct TextChange {
    let byteRange: ByteRange
    let bytesAdded: ByteCount
    let oldEndLinePosition: LinePosition
    let startLinePosition: LinePosition
    let newEndLinePosition: LinePosition

    /// The change as a UTF-16 replacement.
    var replacement: TextReplacement {
        TextReplacement(range: NSRange(byteRange), replacementLength: bytesAdded.utf16Length)
    }
}
