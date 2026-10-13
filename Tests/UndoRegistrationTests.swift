import Foundation
import Testing

/// Every undo step in core code is registered through Graph.registerUndo, on
/// the graph the edit was made in, so the graph sees each edit. This reads the
/// sources: a step registered on the undo manager directly is invisible to
/// the graph, and nothing would fail until something that relies on seeing
/// edits did.
@Suite("Undo Registration")
struct UndoRegistrationTests
{
    /// Registering on the undo manager itself, which only Graph.registerUndo may do.
    private static let directRegistration = #/undoManager\??\.(registerUndo|prepare)\(/#

    private var repositoryRoot: URL
    {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("Undo steps in core code register through Graph.registerUndo")
    func undoRegistersThroughTheGraph() throws
    {
        var offenders: [String] = []
        for directory in ["Fabric", "Fabric Editor"]
        {
            let root = repositoryRoot.appending(path: directory, directoryHint: .isDirectory)
            let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift"
            {
                let source = try String(contentsOf: file, encoding: .utf8)
                let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
                let funnel = Self.funnelLines(in: lines)
                for (index, line) in lines.enumerated()
                    where line.contains(Self.directRegistration) && !funnel.contains(index)
                {
                    offenders.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offenders.isEmpty, "register undo through Graph.registerUndo:\n\(offenders.joined(separator: "\n"))")
    }

    /// The lines of Graph.registerUndo's own body, where the undo manager is
    /// called: from its declaration to the brace that closes it.
    private static func funnelLines(in lines: [Substring]) -> Range<Int>
    {
        guard let start = lines.firstIndex(where: { $0.contains("public func registerUndo(_ handler") }) else { return 0..<0 }
        var depth = 0
        var opened = false
        for index in start..<lines.count
        {
            for character in lines[index]
            {
                if character == "{" { depth += 1; opened = true }
                if character == "}" { depth -= 1 }
            }
            if opened && depth == 0 { return start..<(index + 1) }
        }
        return start..<lines.count
    }
}
