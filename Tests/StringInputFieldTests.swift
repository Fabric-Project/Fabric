import Testing
import Foundation
@testable import Fabric
import Satin

/// The string input field against values longer than it can show.
///
/// A parameter's value is the document's; the field is a view of it. Anything a
/// field does to fit a value on screen has to stay on screen, because the model
/// it edits against is also the one it writes back from.
@Suite("String input field")
@MainActor
struct StringInputFieldTests
{
    /// Longer than any single-line field renders, and the size a pasted-in
    /// document reaches — the JSON behind a graph's geometry runs to thousands.
    private static let longValue = String(repeating: "abcdefghij", count: 500)

    private func parameter(_ value: String) -> StringParameter
    {
        StringParameter("Spec", value, .inputfield, "")
    }

    @Test("A value longer than the field shows still reaches it whole")
    func aLongValueArrivesWhole() throws
    {
        let param = parameter(Self.longValue)
        let field = InputFieldView(param: param)

        #expect(field.vm.uiValue == Self.longValue,
                "the field holds \(field.vm.uiValue.count) of \(Self.longValue.count) characters")
    }

    /// Reopening a node's settings builds a second field over the same
    /// parameter. If that field seeds itself from a shortened read, the next
    /// keystroke writes the shortening back.
    @Test("Editing a rebuilt field keeps the value it was not shown")
    func anEditAfterRebuildKeepsTheWholeValue() throws
    {
        let param = parameter(Self.longValue)

        _ = InputFieldView(param: param)
        let reopened = InputFieldView(param: param)
        reopened.vm.uiValue += "!"

        #expect(param.value == Self.longValue + "!",
                "parameter kept \(param.value.count) of \(Self.longValue.count + 1) characters")
    }

    @Test("An edit still reaches the parameter")
    func anEditIsWrittenBack() throws
    {
        let param = parameter("short")
        let field = InputFieldView(param: param)

        field.vm.uiValue = "shorter"

        #expect(param.value == "shorter")
    }
}
