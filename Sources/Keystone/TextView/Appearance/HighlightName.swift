#if DEBUG
private var previousUnrecognizedHighlightNames: [String] = []
#endif

enum HighlightName: String {
    case attribute
    case boolean
    case character
    case comment
    case conditional
    case constant
    case constantBuiltin = "constant.builtin"
    case constantCharacter = "constant.character"
    case constructor
    case delimiter
    case escape
    case field
    case float
    case function
    case include
    case keyword
    case label
    case method
    case module
    case namespace
    case number
    case `operator`
    case parameter
    case property
    case punctuation
    case `repeat`
    case string
    case symbol
    case tag
    case text
    case type
    case variable
    case variableBuiltin = "variable.builtin"

    init?(_ rawHighlightName: String) {
        var comps = rawHighlightName.split(separator: ".")
        while !comps.isEmpty {
            let candidateRawHighlightName = comps.joined(separator: ".")
            if let highlightName = Self(rawValue: candidateRawHighlightName) {
                self = highlightName
                return
            }
            comps.removeLast()
        }
#if DEBUG
        if !previousUnrecognizedHighlightNames.contains(rawHighlightName) {
            previousUnrecognizedHighlightNames.append(rawHighlightName)
            print("Unrecognized highlight name: '\(rawHighlightName)'."
                  + " Add the highlight name to HighlightName.swift if you want to add support for syntax highlighting it."
                  + " This message will only be shown once per highlight name.")
        }
#endif
        return nil
    }
}
