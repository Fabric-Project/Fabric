import Foundation
import Testing
@testable import Fabric

@Suite("String Escape Sequences")
struct StringEscapeSequenceTests
{
    @Test("Invisible characters are expressible")
    func invisibleCharacters()
    {
        #expect(decodeEscapeSequences(#"\n"#) == "\n")
        #expect(decodeEscapeSequences(#"\r"#) == "\r")
        #expect(decodeEscapeSequences(#"\t"#) == "\t")
        #expect(decodeEscapeSequences(#"\r\n"#) == "\r\n")
    }

    @Test("Escaped backslash yields a literal backslash, and shields the next character")
    func escapedBackslash()
    {
        #expect(decodeEscapeSequences(#"\\"#) == "\\")
        #expect(decodeEscapeSequences(#"\\n"#) == #"\n"#)
    }

    @Test("Unknown and trailing escapes are preserved literally")
    func unknownEscapesRemainLiteral()
    {
        #expect(decodeEscapeSequences(#"\q"#) == #"\q"#)
        #expect(decodeEscapeSequences(#"ends\"#) == #"ends\"#)
    }

    @Test("Braces decode only where they are syntax")
    func bracesAreOptedInto()
    {
        #expect(decodeEscapeSequences(#"\{n\}"#) == #"\{n\}"#)
        #expect(decodeEscapeSequences(#"\{n\}"#, including: [.invisibleCharacters, .braces]) == "{n}")
    }

    @Test("An unwanted sequence is left as typed")
    func unwantedSequencesRemainLiteral()
    {
        #expect(decodeEscapeSequences(#"\n"#, including: []) == #"\n"#)
        #expect(decodeEscapeSequences(#"\{"#, including: .braces) == "{")
        #expect(decodeEscapeSequences(#"\t"#, including: .braces) == #"\t"#)
    }

    @Test("The backslash escape holds regardless of the sequences wanted")
    func backslashIsAlwaysDecoded()
    {
        #expect(decodeEscapeSequences(#"\\"#, including: []) == "\\")
        #expect(decodeEscapeSequences(#"\\n"#, including: []) == #"\n"#)
    }

    @Test("Text without escapes passes through untouched")
    func plainTextIsUntouched()
    {
        #expect(decodeEscapeSequences(", ") == ", ")
        #expect(decodeEscapeSequences("") == "")
    }

    @Test("String Join reverses a String Split on the same separator")
    func splitAndJoinRoundTrip() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let separator = #"\n"#
        let input = "first\nsecond\nthird"

        let join = StringJoinNode(context: harness.context)
        join.inputPort.value = StringSplitNode.split(input, separator: separator, mode: .custom)
        join.separatorPort.value = separator

        try harness.execute(join)

        #expect(join.outputPort.value == input)
    }
}
