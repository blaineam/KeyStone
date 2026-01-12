//
//  Base64Toggle.swift
//  Keystone
//
//  Toggle Base64 encoding/decoding on selected text.
//

import Foundation

/// Result of a Base64 toggle operation with range information.
public struct Base64ToggleResult {
    /// The range in the original text that was replaced.
    public let replacedRange: NSRange
    /// The replacement text for that range.
    public let replacementText: String
    /// The new cursor position after the operation.
    public let newCursorOffset: Int
}

/// Utility for toggling Base64 encoding/decoding on selected text.
public struct Base64Toggle {

    /// Toggles Base64 encoding/decoding on the selected text.
    /// Returns the range that was replaced and the replacement text (for efficient partial updates).
    /// - Parameters:
    ///   - text: The full text content.
    ///   - selectedRange: The NSRange of the current selection.
    /// - Returns: A Base64ToggleResult with the replaced range and replacement text, or nil if no selection.
    public static func toggleBase64WithRange(
        text: String,
        selectedRange: NSRange
    ) -> Base64ToggleResult? {
        // Need a selection to encode/decode
        guard selectedRange.length > 0 else {
            return nil
        }

        let nsText = text as NSString

        // Ensure the range is valid
        guard selectedRange.location >= 0,
              selectedRange.location + selectedRange.length <= nsText.length else {
            return nil
        }

        let selectedText = nsText.substring(with: selectedRange)

        // Try to decode as Base64 first
        if let decoded = decodeBase64(selectedText) {
            // The selection was valid Base64, return decoded text
            return Base64ToggleResult(
                replacedRange: selectedRange,
                replacementText: decoded,
                newCursorOffset: selectedRange.location + decoded.count
            )
        }

        // Not valid Base64, so encode it
        let encoded = encodeBase64(selectedText)
        return Base64ToggleResult(
            replacedRange: selectedRange,
            replacementText: encoded,
            newCursorOffset: selectedRange.location + encoded.count
        )
    }

    /// Toggles Base64 encoding/decoding on the selected text.
    /// - Parameters:
    ///   - text: The full text content.
    ///   - selectedRange: The NSRange of the current selection.
    /// - Returns: A tuple with the new text and the new selection range, or nil if no selection.
    public static func toggleBase64(
        text: String,
        selectedRange: NSRange
    ) -> (newText: String, newSelection: NSRange)? {
        guard let result = toggleBase64WithRange(text: text, selectedRange: selectedRange) else {
            return nil
        }

        let nsText = text as NSString
        let newText = nsText.replacingCharacters(in: result.replacedRange, with: result.replacementText)

        // Select the new text
        let newSelection = NSRange(location: result.replacedRange.location, length: result.replacementText.count)

        return (newText, newSelection)
    }

    /// Checks if the given string appears to be valid Base64 encoded.
    /// - Parameter string: The string to check.
    /// - Returns: True if the string is valid Base64.
    public static func isBase64Encoded(_ string: String) -> Bool {
        return decodeBase64(string) != nil
    }

    /// Attempts to decode a Base64 string.
    /// - Parameter string: The Base64 encoded string.
    /// - Returns: The decoded string, or nil if decoding fails.
    private static func decodeBase64(_ string: String) -> String? {
        // Trim whitespace and newlines
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty string is not valid Base64
        guard !trimmed.isEmpty else {
            return nil
        }

        // Check for valid Base64 characters (standard + URL-safe variants)
        let base64Regex = "^[A-Za-z0-9+/\\-_=\\s]+$"
        guard let regex = try? NSRegularExpression(pattern: base64Regex),
              regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else {
            return nil
        }

        // Normalize: replace URL-safe characters with standard ones
        var normalized = trimmed
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        // Add padding if needed
        let paddingNeeded = normalized.count % 4
        if paddingNeeded > 0 {
            normalized += String(repeating: "=", count: 4 - paddingNeeded)
        }

        // Attempt to decode
        guard let data = Data(base64Encoded: normalized, options: .ignoreUnknownCharacters),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Sanity check: the decoded result should be valid UTF-8 and different from input
        // Also, if the decoded string looks like garbage (too many control chars), it's probably not Base64
        let controlCharCount = decoded.filter { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            // Allow common whitespace and printable characters
            return scalar.value < 32 && scalar.value != 9 && scalar.value != 10 && scalar.value != 13
        }.count

        // If more than 10% are control characters, probably not valid text
        if decoded.count > 0 && Double(controlCharCount) / Double(decoded.count) > 0.1 {
            return nil
        }

        return decoded
    }

    /// Encodes a string to Base64.
    /// - Parameter string: The string to encode.
    /// - Returns: The Base64 encoded string.
    private static func encodeBase64(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else {
            return string
        }
        return data.base64EncodedString()
    }
}
