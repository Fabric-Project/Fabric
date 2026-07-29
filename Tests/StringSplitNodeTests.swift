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
                == ["Custom", "Comma", "Space", "Newline"]
        )

        #expect(StringSplitNode.strategies == StringSplitMode.allCases.map(\.rawValue))
        #expect(StringSplitNode.defaultStrategy == StringSplitMode.custom.rawValue)
    }

    @Test("Every split mode explains itself in the Settings pane")
    func splitModeGuidance()
    {
        for mode in StringSplitMode.allCases
        {
            #expect(mode.usageGuidance.isEmpty == false)
        }
    }

    @Test("Separator inlet exists only in Custom mode")
    func separatorPortFollowsMode() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let node = StringSplitNode(context: harness.context, strategy: StringSplitMode.custom)
        #expect(node.splitMode == .custom)
        #expect(node.inputSeparator != nil)

        node.strategy = StringSplitMode.newline.rawValue
        #expect(node.splitMode == .newline)
        #expect(node.inputSeparator == nil)

        node.strategy = StringSplitMode.custom.rawValue
        #expect(node.inputSeparator != nil)
    }

    @Test("A typed separator survives a trip through another mode")
    func customSeparatorIsParkedAcrossModes() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let node = StringSplitNode(context: harness.context, strategy: StringSplitMode.custom)
        try #require(node.inputSeparator).value = #"\t"#

        node.strategy = StringSplitMode.comma.rawValue
        #expect(node.customSeparator == #"\t"#)

        node.strategy = StringSplitMode.custom.rawValue
        #expect(node.inputSeparator?.value == #"\t"#)
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

    @Test("Space splits on any whitespace and removes empty values")
    func spaceMode()
    {
        let result = StringSplitNode.split(
            "  first\tsecond\nthird\u{00A0}fourth  ",
            separator: ", ",
            mode: .space
        )

        #expect(result == ["first", "second", "third", "fourth"])
    }

    @Test("Comma trims whitespace and removes empty values")
    func commaMode()
    {
        let result = StringSplitNode.split(
            " first, second ,, \nthird, ",
            separator: ", ",
            mode: .comma
        )

        #expect(result == ["first", "second", "third"])
    }

    @Test("Newline recognizes Unicode newlines, trims whitespace, and removes empty values")
    func newlineMode()
    {
        let result = StringSplitNode.split(
            " first\r\nsecond\u{2028} \nthird ",
            separator: ", ",
            mode: .newline
        )

        #expect(result == ["first", "second", "third"])
    }

    @Test("Custom separator retains empty and untrimmed values")
    func customModePreservesExistingBehavior()
    {
        let result = StringSplitNode.split(
            " first, second,,",
            separator: ",",
            mode: .custom
        )

        #expect(result == [" first", " second", "", ""])
    }

    @Test("Custom separator decodes the shared escape sequences")
    func customSeparatorDecodesEscapes()
    {
        // The vocabulary itself is covered by StringEscapeSequenceTests; this
        // pins that Custom mode runs the separator through it.
        #expect(StringSplitNode.split("a\tb", separator: #"\t"#) == ["a", "b"])
        #expect(StringSplitNode.split(#"a\nb"#, separator: #"\\n"#) == ["a", "b"])
    }
}
