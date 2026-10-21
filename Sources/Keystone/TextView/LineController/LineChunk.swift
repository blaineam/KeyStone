import CoreText
import Foundation

/// One piece of a line's attributed text with its own `CTTypesetter`.
///
/// Short lines are a single chunk. Lines longer than `LineController.maximumHighlightedLineLength`
/// are split into pieces of at most `LineController.chunkLength` UTF-16 units so an edit
/// rebuilds (and re-typesets) only the chunk containing it; the chunks after it are shifted,
/// their attributed strings and typesetters untouched. Line fragments never cross a chunk
/// boundary, so a soft wrap can fall there.
final class LineChunk {
    /// Line-local location of the chunk's first character.
    var location: Int
    /// The chunk's text; indices are chunk-local.
    let attributedString: NSMutableAttributedString
    /// The same text as an `NSString`, for character lookups without `attributedSubstring`.
    let string: NSString
    /// Set until the default attributes have been applied after a rebuild.
    var needsDefaultAttributes = true
    var length: Int {
        attributedString.length
    }
    var range: NSRange {
        NSRange(location: location, length: attributedString.length)
    }
    /// Created on first use and kept until the text or its attributes change.
    var typesetter: CTTypesetter {
        if let cachedTypesetter {
            return cachedTypesetter
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        cachedTypesetter = typesetter
        return typesetter
    }
    private var cachedTypesetter: CTTypesetter?

    init(location: Int, attributedString: NSMutableAttributedString) {
        self.location = location
        self.attributedString = attributedString
        self.string = attributedString.string as NSString
    }

    convenience init(location: Int, string: String) {
        self.init(location: location, attributedString: NSMutableAttributedString(string: string))
    }

    /// Drops the cached typesetter; call after mutating `attributedString`.
    func invalidateTypesetter() {
        cachedTypesetter = nil
    }

    /// Splits `string` into even chunks of at most `chunkLength` starting at `location`.
    ///
    /// Even pieces, so a chunk that grew one character past the limit becomes two halves
    /// rather than a full chunk and a one-character sliver (which would wrap as a one-character line).
    static func chunks(of string: String, startingAt location: Int, chunkLength: Int) -> [LineChunk] {
        let nsString = string as NSString
        let totalLength = nsString.length
        guard totalLength > chunkLength else {
            return totalLength > 0 ? [LineChunk(location: location, string: string)] : []
        }
        let pieceCount = (totalLength + chunkLength - 1) / chunkLength
        let pieceLength = (totalLength + pieceCount - 1) / pieceCount
        var chunks: [LineChunk] = []
        var offset = 0
        while offset < totalLength {
            var length = min(pieceLength, totalLength - offset)
            // Don't split a surrogate pair or CRLF across chunks.
            if offset + length < totalLength {
                let last = nsString.character(at: offset + length - 1)
                let next = nsString.character(at: offset + length)
                if UTF16.isLeadSurrogate(last) || (last == 0x0D && next == 0x0A) {
                    length += 1
                }
            }
            let piece = nsString.substring(with: NSRange(location: offset, length: length))
            chunks.append(LineChunk(location: location + offset, string: piece))
            offset += length
        }
        return chunks
    }
}
