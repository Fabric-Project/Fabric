import Testing
@testable import Fabric

@Suite("String Split Node")
struct StringSplitNodeTests
{
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
