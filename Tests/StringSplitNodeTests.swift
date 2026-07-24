import Foundation
import Testing
@testable import Fabric

@Suite("String Split Node")
struct StringSplitNodeTests
{
    @Test("Split modes retain their user-facing serialized names")
    func splitModeNames() throws
    {
        #expect(
            StringSplitMode.allCases.map(\.rawValue)
                == ["Exact Separator", "Words", "Commas", "Lines"]
        )

        let encodedMode = try JSONEncoder().encode(StringSplitMode.lines)
        let decodedMode = try JSONDecoder().decode(StringSplitMode.self, from: encodedMode)

        #expect(decodedMode == .lines)
    }

    @Test("Escaped newline separates file contents into lines")
    func escapedNewlineSeparator()
    {
        let result = StringSplitNode.split("first\nsecond\nthird", separator: #"\n"#)

        #expect(result == ["first", "second", "third"])
    }

    @Test("Escaped Windows newline is decoded as one separator")
    func escapedWindowsNewlineSeparator()
    {
        let result = StringSplitNode.split("first\r\nsecond", separator: #"\r\n"#)

        #expect(result == ["first", "second"])
    }

    @Test("Words split on any whitespace and remove empty values")
    func wordsMode()
    {
        let result = StringSplitNode.split(
            "  first\tsecond\nthird\u{00A0}fourth  ",
            separator: ", ",
            mode: .words
        )

        #expect(result == ["first", "second", "third", "fourth"])
    }

    @Test("Commas trim whitespace and remove empty values")
    func commasMode()
    {
        let result = StringSplitNode.split(
            " first, second ,, \nthird, ",
            separator: ", ",
            mode: .commas
        )

        #expect(result == ["first", "second", "third"])
    }

    @Test("Lines recognize Unicode newlines, trim whitespace, and remove empty values")
    func linesMode()
    {
        let result = StringSplitNode.split(
            " first\r\nsecond\u{2028} \nthird ",
            separator: ", ",
            mode: .lines
        )

        #expect(result == ["first", "second", "third"])
    }

    @Test("Exact separator retains empty and untrimmed values")
    func exactSeparatorModePreservesExistingBehavior()
    {
        let result = StringSplitNode.split(
            " first, second,,",
            separator: ",",
            mode: .exactSeparator
        )

        #expect(result == [" first", " second", "", ""])
    }

    @Test("Escaped tab and backslash separators remain expressible")
    func escapedTabAndBackslashSeparators()
    {
        #expect(StringSplitNode.decodedSeparator(#"\t"#) == "\t")
        #expect(StringSplitNode.decodedSeparator(#"\\"#) == "\\")
        #expect(StringSplitNode.decodedSeparator(#"\\n"#) == #"\n"#)
    }

    @Test("Unknown and trailing escapes are preserved literally")
    func unknownEscapesRemainLiteral()
    {
        #expect(StringSplitNode.decodedSeparator(#"\q"#) == #"\q"#)
        #expect(StringSplitNode.decodedSeparator(#"ends\"#) == #"ends\"#)
    }
}
