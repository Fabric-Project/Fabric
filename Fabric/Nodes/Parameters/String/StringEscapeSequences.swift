//
//  StringEscapeSequences.swift
//  Fabric
//

import Foundation

/// The escape sequences a pattern may use. One vocabulary shared across the
/// String nodes, so a sequence typed into one means the same thing in another;
/// each node opts in to the part of it that its syntax calls for.
struct EscapeSequences: OptionSet
{
    let rawValue: Int

    /// `\n`, `\r` and `\t` — the characters that cannot be typed into a
    /// single-line field. Wanted wherever a user writes a pattern.
    static let invisibleCharacters = EscapeSequences(rawValue: 1 << 0)

    /// `\{` and `\}` — a literal brace. Only meaningful where braces are syntax,
    /// as in the String Formatter and String Scanner format strings; elsewhere a
    /// brace needs no escaping and `\{` is better left as typed.
    static let braces = EscapeSequences(rawValue: 1 << 1)

    /// The character an escape stands for, or nil when this set does not
    /// recognize it. `\\` is always recognized and so has no option of its own:
    /// without it, no sequence could be written out literally.
    func substitution(forEscaped character: Character) -> Character?
    {
        switch character
        {
        case "\\":
            return "\\"
        case "n" where contains(.invisibleCharacters):
            return "\n"
        case "r" where contains(.invisibleCharacters):
            return "\r"
        case "t" where contains(.invisibleCharacters):
            return "\t"
        case "{" where contains(.braces):
            return "{"
        case "}" where contains(.braces):
            return "}"
        default:
            return nil
        }
    }
}

/// Decodes the escape sequences in a user-typed pattern — String Split's and
/// String Join's separators, the String Formatter and String Scanner format
/// strings.
///
/// Deliberately lenient. An escape this set does not recognize (`\q`, or `\{`
/// where braces are not syntax) and a trailing lone backslash are preserved
/// verbatim rather than swallowed or flagged, so a pattern mid-typing never
/// silently loses characters, and widening the set is the only way a pattern's
/// meaning can change.
func decodeEscapeSequences(
    _ pattern: String,
    including sequences: EscapeSequences = .invisibleCharacters
) -> String
{
    var decoded = ""
    var currentIndex = pattern.startIndex

    while currentIndex < pattern.endIndex
    {
        let character = pattern[currentIndex]
        guard character == "\\" else
        {
            decoded.append(character)
            currentIndex = pattern.index(after: currentIndex)
            continue
        }

        let escapedCharacterIndex = pattern.index(after: currentIndex)
        guard escapedCharacterIndex < pattern.endIndex else
        {
            decoded.append(character)
            break
        }

        let escapedCharacter = pattern[escapedCharacterIndex]

        if let substitution = sequences.substitution(forEscaped: escapedCharacter)
        {
            decoded.append(substitution)
        }
        else
        {
            decoded.append(character)
            decoded.append(escapedCharacter)
        }

        currentIndex = pattern.index(after: escapedCharacterIndex)
    }

    return decoded
}
