//
//  StringEscapeSequences.swift
//  Fabric
//

import Foundation

/// Decodes the escape sequences the String nodes accept wherever a user types a
/// pattern — String Split's and String Join's separators today. One vocabulary
/// across all of them, so a separator typed into one node means the same thing
/// in another: `\n`, `\r` and `\t` name the invisible characters, and `\\` is a
/// literal backslash.
///
/// Deliberately lenient. An unrecognized escape (`\q`) and a trailing lone
/// backslash are both preserved verbatim rather than swallowed or flagged, so a
/// pattern mid-typing never silently loses characters, and adding a sequence to
/// the vocabulary later is the only way a pattern's meaning can change.
func decodeEscapeSequences(_ pattern: String) -> String
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

        switch pattern[escapedCharacterIndex]
        {
        case "n":
            decoded.append("\n")
        case "r":
            decoded.append("\r")
        case "t":
            decoded.append("\t")
        case "\\":
            decoded.append("\\")
        default:
            decoded.append(character)
            decoded.append(pattern[escapedCharacterIndex])
        }

        currentIndex = pattern.index(after: escapedCharacterIndex)
    }

    return decoded
}
