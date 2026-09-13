import Foundation
import Testing
@testable import Fabric

@Suite("String Wrap Node")
struct StringWrapNodeTests
{
    private static let sentence = "the quick brown fox jumps over the lazy dog and then it ran away"

    private static func words(_ string: String) -> [String]
    {
        string.split(omittingEmptySubsequences: false, whereSeparator: \.isWhitespace).map(String.init)
    }

    @Test("Wrap modes retain their user-facing serialized names")
    func wrapModeNames()
    {
        #expect(WrapMode.allCases.map(\.rawValue) == ["Characters", "Words", "Aspect"])
    }

    @Test("Characters mode breaks before the limit, not after it")
    func charactersModeStaysWithinLimit()
    {
        for limit in [8, 10, 16, 20, 40]
        {
            let lines = StringWrapNode.wrapToCharLimit(Self.words(Self.sentence), charLimit: limit)
                .split(separator: "\n", omittingEmptySubsequences: false)

            for line in lines
            {
                #expect(line.count <= limit, "\(line.count) chars exceeds limit \(limit): \"\(line)\"")
            }
        }
    }

    @Test("Characters mode fills each line as far as it fits")
    func charactersModeIsGreedy()
    {
        #expect(
            StringWrapNode.wrapToCharLimit(Self.words("the quick brown fox jumps"), charLimit: 10)
                == "the quick\nbrown fox\njumps"
        )
    }

    @Test("A word longer than the limit takes a line of its own")
    func charactersModeKeepsLongWordsWhole()
    {
        #expect(
            StringWrapNode.wrapToCharLimit(Self.words("supercalifragilistic a b"), charLimit: 8)
                == "supercalifragilistic\na b"
        )
    }

    @Test("Words mode puts exactly the requested number of words on every full line")
    func wordsModeIsExact()
    {
        for limit in [1, 2, 3, 5, 10]
        {
            let all = Self.words(Self.sentence)
            let lines = StringWrapNode.wrapToWordLimit(all, wordLimit: limit)
                .split(separator: "\n", omittingEmptySubsequences: false)

            for line in lines.dropLast()
            {
                #expect(line.split(separator: " ").count == limit)
            }
            #expect(lines.count == (all.count + limit - 1) / limit)
            #expect(lines.joined(separator: " ") == Self.sentence)
        }
    }

    @Test("Words mode is unaffected by how long the words are")
    func wordsModeIgnoresWordLength()
    {
        // The average-word-length approximation this replaced skewed badly here:
        // one long word raised the derived character limit for every line.
        #expect(
            StringWrapNode.wrapToWordLimit(Self.words("a b supercalifragilistic c d e"), wordLimit: 2)
                == "a b\nsupercalifragilistic c\nd e"
        )
    }

    @Test("Aspect mode derives a character limit the wrap then respects")
    func aspectModeStaysWithinDerivedLimit()
    {
        let all = Self.words(Self.sentence)
        let limit = StringWrapNode.aspectToCharLimit(words: all, aspect: 4.0)
        let lines = StringWrapNode.wrapToCharLimit(all, charLimit: limit)
            .split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines
        {
            #expect(line.count <= limit)
        }
    }

    @Test("The String inlet is a parameter port, so it is editable in the inspector")
    func stringInletIsEditable() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let node = StringWrapNode(context: harness.context)

        #expect(node.inputPort.parameter != nil)
        #expect(node.parameterGroup.params.contains { $0.label == "String" })
    }

    @Test("A wrap runs end to end through the node's ports")
    func wrapsThroughPorts() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let node = StringWrapNode(context: harness.context)
        node.inputMode.value = WrapMode.Characters.rawValue
        node.inputLimit.value = 10
        node.inputPort.value = "the quick brown fox jumps"

        try harness.execute(node)

        #expect(node.outputPort.value == "the quick\nbrown fox\njumps")
    }
}
