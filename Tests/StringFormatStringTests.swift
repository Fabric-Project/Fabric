import Foundation
import Testing
@testable import Fabric

@Suite("String Format Strings")
struct StringFormatStringTests
{
    // MARK: - Parsing

    @Test("Literal text and placeholders are parsed in source order")
    func literalAndPlaceholderOrder()
    {
        let parsed = parseFormatString("Frame {n:d} at {t:f}s")

        #expect(parsed.tokens == [
            .literal("Frame "),
            .placeholder(FormatPlaceholder(name: "n", formatSpecifier: "d")),
            .literal(" at "),
            .placeholder(FormatPlaceholder(name: "t", formatSpecifier: "f")),
            .literal("s"),
        ])
    }

    @Test("Literals decode the shared escape sequences")
    func literalsDecodeEscapes()
    {
        let parsed = parseFormatString(#"{a}\n{b}\tend"#)

        #expect(parsed.tokens == [
            .placeholder(FormatPlaceholder(name: "a", formatSpecifier: nil)),
            .literal("\n"),
            .placeholder(FormatPlaceholder(name: "b", formatSpecifier: nil)),
            .literal("\tend"),
        ])
    }

    @Test("Escaped braces are literal text, not a placeholder")
    func escapedBracesAreLiteral()
    {
        let parsed = parseFormatString(#"\{n:d\} is {n:d}"#)

        #expect(parsed.tokens == [
            .literal("{n:d} is "),
            .placeholder(FormatPlaceholder(name: "n", formatSpecifier: "d")),
        ])
        #expect(parsed.placeholders.map(\.name) == ["n"])
    }

    @Test("An escaped backslash still leaves the next brace as a placeholder")
    func escapedBackslashBeforePlaceholder()
    {
        let parsed = parseFormatString(#"\\{n}"#)

        #expect(parsed.tokens == [
            .literal("\\"),
            .placeholder(FormatPlaceholder(name: "n", formatSpecifier: nil)),
        ])
    }

    @Test("Malformed braces stay literal")
    func malformedBracesStayLiteral()
    {
        #expect(parseFormatString("{}").tokens == [.literal("{}")])
        #expect(parseFormatString("{ n }").tokens == [.literal("{ n }")])
        #expect(parseFormatString("{n").tokens == [.literal("{n")])
        #expect(parseFormatString("{n:}").tokens == [.literal("{n:}")])
    }

    @Test("A repeated name yields one placeholder, keeping its first specifier")
    func repeatedNameKeepsFirstSpecifier()
    {
        let parsed = parseFormatString("{n:d} {n:s}")

        #expect(parsed.placeholders == [FormatPlaceholder(name: "n", formatSpecifier: "d")])
        #expect(parsed.tokens.count == 3)
    }

    // MARK: - Specifiers

    @Test("Well-formed specifiers keep their flags, width and precision")
    func wellFormedSpecifiers()
    {
        #expect(FormatSpecifier("d") == .integer(printfFormat: "%ld"))
        #expect(FormatSpecifier("i") == .integer(printfFormat: "%ld"))
        #expect(FormatSpecifier("5d") == .integer(printfFormat: "%5ld"))
        #expect(FormatSpecifier("f") == .floatingPoint(printfFormat: "%f"))
        #expect(FormatSpecifier(".2f") == .floatingPoint(printfFormat: "%.2f"))
        #expect(FormatSpecifier("-8.3e") == .floatingPoint(printfFormat: "%-8.3e"))
    }

    @Test("A specifier holding more than one conversion is not honoured")
    func multipleConversionsAreRefused()
    {
        // Each of these would otherwise reach String(format:) with one argument
        // and read a vararg that was never supplied.
        #expect(FormatSpecifier("f%f") == .string)
        #expect(FormatSpecifier("f%s") == .string)
        #expect(FormatSpecifier(".2f%@") == .string)
        #expect(FormatSpecifier("%s") == .string)
    }

    @Test("Unreadable specifiers fall back to plain string conversion")
    func unreadableSpecifiers()
    {
        #expect(FormatSpecifier(nil) == .string)
        #expect(FormatSpecifier("s") == .string)
        #expect(FormatSpecifier("b") == .bool)
        #expect(FormatSpecifier("zz") == .string)
        #expect(FormatSpecifier("2") == .string)
    }

    // MARK: - String Formatter

    @Test("Formatter writes escape sequences into its output")
    func formatterDecodesEscapes() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let formatter = StringFormatterNode(context: harness.context, formatString: #"{a}\n{b}"#)

        let inputA = try #require(formatter.findPort(named: "a", as: ParameterPort<String>.self))
        let inputB = try #require(formatter.findPort(named: "b", as: ParameterPort<String>.self))
        inputA.value = "first"
        inputB.value = "second"

        try harness.execute(formatter)

        #expect(formatter.outputString.value == "first\nsecond")
    }

    @Test("Formatter emits literal braces for an escaped placeholder")
    func formatterEmitsLiteralBraces() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let formatter = StringFormatterNode(context: harness.context, formatString: #"\{a\} {a}"#)

        let inputA = try #require(formatter.findPort(named: "a", as: ParameterPort<String>.self))
        inputA.value = "value"

        try harness.execute(formatter)

        #expect(formatter.outputString.value == "{a} value")
    }

    @Test("A value that looks like a placeholder is not substituted into")
    func placeholderShapedValueIsLeftAlone() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let formatter = StringFormatterNode(context: harness.context, formatString: "{a} {b}")

        let inputA = try #require(formatter.findPort(named: "a", as: ParameterPort<String>.self))
        let inputB = try #require(formatter.findPort(named: "b", as: ParameterPort<String>.self))
        inputA.value = "{b}"
        inputB.value = "second"

        try harness.execute(formatter)

        #expect(formatter.outputString.value == "{b} second")
    }

    @Test("Int placeholders render their full 64-bit range")
    func formatterRendersLargeIntegers() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let formatter = StringFormatterNode(context: harness.context, formatString: "{ms:d}")

        let milliseconds = try #require(formatter.findPort(named: "ms", as: ParameterPort<Int>.self))
        milliseconds.value = 5_000_000_000

        try harness.execute(formatter)

        #expect(formatter.outputString.value == "5000000000")
    }

    @Test("Float placeholders keep their width and precision")
    func formatterRendersFloatPrecision() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let formatter = StringFormatterNode(context: harness.context, formatString: "[{x:8.2f}]")

        let x = try #require(formatter.findPort(named: "x", as: ParameterPort<Float>.self))
        x.value = 3.14159

        try harness.execute(formatter)

        #expect(formatter.outputString.value == "[    3.14]")
    }

    @Test("A format string of pure literal text still emits")
    func formatterEmitsWithoutPlaceholders() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let formatter = StringFormatterNode(context: harness.context, formatString: #"Line one\nLine two"#)

        try harness.execute(formatter)

        #expect(formatter.outputString.value == "Line one\nLine two")
    }

    @Test("Editing the format string re-emits from unchanged inputs")
    func formatterReEmitsAfterFormatEdit() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let formatter = StringFormatterNode(context: harness.context, formatString: "Hello {name}")

        let name = try #require(formatter.findPort(named: "name", as: ParameterPort<String>.self))
        name.value = "Bob"

        try harness.execute(formatter)
        #expect(formatter.outputString.value == "Hello Bob")

        // What a pass through the renderer would leave behind.
        formatter.markClean()

        formatter.setFormatString("Goodbye {name}")
        #expect(formatter.isDirty)

        try harness.execute(formatter)
        #expect(formatter.outputString.value == "Goodbye Bob")
    }

    // MARK: - String Scanner

    @Test("Scanner matches across an escaped newline")
    func scannerMatchesMultipleLines() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let scanner = StringScannerNode(context: harness.context, formatString: #"Frame {n:d}\nTime {t:f}"#)
        scanner.inputString.value = "Frame 12\nTime 1.5"

        try harness.execute(scanner)

        let frameNumber = try #require(scanner.findPort(named: "n", as: NodePort<Int>.self))
        let time = try #require(scanner.findPort(named: "t", as: NodePort<Float>.self))

        #expect(scanner.outputMatched.value == true)
        #expect(frameNumber.value == 12)
        #expect(time.value == 1.5)
    }

    @Test("A String capture spans newlines")
    func scannerCaptureSpansNewlines() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let scanner = StringScannerNode(context: harness.context, formatString: "Body: {body}")
        scanner.inputString.value = "Body: first\nsecond"

        try harness.execute(scanner)

        let body = try #require(scanner.findPort(named: "body", as: NodePort<String>.self))

        #expect(scanner.outputMatched.value == true)
        #expect(body.value == "first\nsecond")
    }

    @Test("Scanner treats an escaped brace as literal input text")
    func scannerMatchesLiteralBraces() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let scanner = StringScannerNode(context: harness.context, formatString: #"\{{n:d}\}"#)
        scanner.inputString.value = "{7}"

        try harness.execute(scanner)

        let number = try #require(scanner.findPort(named: "n", as: NodePort<Int>.self))

        #expect(scanner.outputMatched.value == true)
        #expect(number.value == 7)
    }

    @Test("Editing the format string re-scans the unchanged input")
    func scannerReScansAfterFormatEdit() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let scanner = StringScannerNode(context: harness.context, formatString: "Frame {n:d}")
        scanner.inputString.value = "Frame 12 at 1.5s"

        try harness.execute(scanner)
        #expect(scanner.outputMatched.value == false)

        // What a pass through the renderer would leave behind.
        scanner.markClean()

        scanner.setFormatString("Frame {n:d} at {t:f}s")
        #expect(scanner.isDirty)

        try harness.execute(scanner)

        let frameNumber = try #require(scanner.findPort(named: "n", as: NodePort<Int>.self))
        let time = try #require(scanner.findPort(named: "t", as: NodePort<Float>.self))

        #expect(scanner.outputMatched.value == true)
        #expect(frameNumber.value == 12)
        #expect(time.value == 1.5)
    }

    @Test("A repeated name does not shift the captures that follow it")
    func scannerRepeatedNameKeepsLaterCapturesAligned() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let scanner = StringScannerNode(context: harness.context, formatString: "{a:d} {a:d} {b:d}")
        scanner.inputString.value = "1 2 3"

        try harness.execute(scanner)

        let a = try #require(scanner.findPort(named: "a", as: NodePort<Int>.self))
        let b = try #require(scanner.findPort(named: "b", as: NodePort<Int>.self))

        #expect(scanner.outputMatched.value == true)
        // Each occurrence captures independently; the port keeps the last.
        #expect(a.value == 2)
        #expect(b.value == 3)
    }

    @Test("Regex metacharacters in literal text match themselves")
    func scannerEscapesRegexMetacharacters() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let scanner = StringScannerNode(context: harness.context, formatString: "({n:d})")
        scanner.inputString.value = "(7)"

        try harness.execute(scanner)

        let number = try #require(scanner.findPort(named: "n", as: NodePort<Int>.self))

        #expect(scanner.outputMatched.value == true)
        #expect(number.value == 7)
    }
}
