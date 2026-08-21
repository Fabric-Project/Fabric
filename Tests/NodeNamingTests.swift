import Foundation
import Metal
import Satin
import Testing
@testable import Fabric

private final class NamingTestNode: Node
{
    override class var name: String { "Naming Test" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Exercises the Node naming contract" }

    private var nodeDerivedSubtitle: String?
    private var nodeDerivedTitle: String?

    override func deriveTitle() -> String
    {
        nodeDerivedTitle ?? Self.name
    }

    override func deriveSubtitle() -> String?
    {
        nodeDerivedSubtitle
    }

    func setDerivedSubtitle(_ subtitle: String?)
    {
        nodeDerivedSubtitle = subtitle
        subtitleSubject.send()
    }

    func setDerivedTitle(_ title: String?)
    {
        nodeDerivedTitle = title
        subtitleSubject.send()
    }
}

@Suite struct NodeNamingTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
    }

    @Test("Title defaults to the registered node name and ignores user renames")
    func titleDefaultsToRegisteredName() throws
    {
        guard let context = makeContext() else { return }
        let node = NamingTestNode(context: context)

        #expect(node.title == NamingTestNode.name)

        node.userName = "Renamed Instance"
        #expect(node.title == NamingTestNode.name)
    }

    @Test("An instance can derive a more specific title")
    func titleCanBeInstanceSpecific() throws
    {
        guard let context = makeContext() else { return }
        let node = NamingTestNode(context: context)

        node.setDerivedTitle("Instance Title")
        #expect(node.title == "Instance Title")

        node.setDerivedTitle("")
        #expect(node.title == NamingTestNode.name)
    }

    @Test("Shader-backed BaseImageNode uses its shader name as its title")
    func baseImageNodeUsesShaderNameAsTitle() throws
    {
        guard let context = makeContext() else { return }
        let registry = try NodeRegistry()
        let wrapper = try #require(registry.availableNodes.first { wrapper in
            wrapper.nodeClass == BaseImageNode.self && wrapper.fileURL != nil
        })
        let node = try wrapper.initializeNode(context: context)

        #expect(node.title == wrapper.nodeName)
        #expect(node.subtitle == nil)

        node.userName = "Renamed Effect"
        #expect(node.title == wrapper.nodeName)
        #expect(node.subtitle == "Renamed Effect")
    }

    @Test("Subtitle normalizes node-derived values")
    func subtitleNormalizesDerivedValues() throws
    {
        guard let context = makeContext() else { return }
        let node = NamingTestNode(context: context)

        #expect(node.subtitle == nil)

        node.setDerivedSubtitle("Derived Context")
        #expect(node.subtitle == "Derived Context")

        node.setDerivedSubtitle("")
        #expect(node.subtitle == nil)

        node.setDerivedSubtitle(NamingTestNode.name)
        #expect(node.subtitle == nil)
    }

    @Test("User rename overrides the derived subtitle and clearing reveals the latest value")
    func userRenameOverridesDerivedSubtitle() throws
    {
        guard let context = makeContext() else { return }
        let node = NamingTestNode(context: context)

        node.setDerivedSubtitle("First Derived Context")
        node.userName = "Renamed Instance"
        #expect(node.subtitle == "Renamed Instance")

        node.setDerivedSubtitle("Latest Derived Context")
        #expect(node.subtitle == "Renamed Instance")

        node.userName = nil
        #expect(node.subtitle == "Latest Derived Context")

        node.userName = ""
        #expect(node.userName == nil)
        #expect(node.subtitle == "Latest Derived Context")
    }

    @Test("Debug description combines the title and resolved subtitle")
    func debugDescriptionUsesResolvedSubtitle() throws
    {
        guard let context = makeContext() else { return }
        let node = NamingTestNode(context: context)

        #expect(node.debugDescription == "Naming Test")

        node.setDerivedSubtitle("Derived Context")
        #expect(node.debugDescription == "Naming Test (Derived Context)")

        node.userName = "Renamed Instance"
        #expect(node.debugDescription == "Naming Test (Renamed Instance)")
    }

    @Test("Decoded empty user rename is normalized to nil")
    func decodedEmptyUserNameIsNormalized() throws
    {
        guard let context = makeContext() else { return }
        let node = NamingTestNode(context: context)
        node.userName = "Temporary Rename"

        let encodedData = try JSONEncoder().encode(node)
        var encodedObject = try #require(
            JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )
        encodedObject["userName"] = ""

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decodedNode = try decoder.decode(
            NamingTestNode.self,
            from: JSONSerialization.data(withJSONObject: encodedObject)
        )

        #expect(decodedNode.userName == nil)
        #expect(decodedNode.title == NamingTestNode.name)
        #expect(decodedNode.subtitle == nil)
    }

    @Test("NodeViewModel mirrors rename and derived subtitle changes")
    func viewModelMirrorsResolvedSubtitle() async throws
    {
        guard let context = makeContext() else { return }
        let node = NamingTestNode(context: context)
        node.setDerivedSubtitle("Initial Context")
        let nodeViewModel = NodeViewModel(node: node)

        #expect(nodeViewModel.title == NamingTestNode.name)
        #expect(nodeViewModel.subtitle == "Initial Context")

        nodeViewModel.userName = "Renamed Instance"
        #expect(nodeViewModel.title == NamingTestNode.name)
        #expect(nodeViewModel.subtitle == "Renamed Instance")

        node.setDerivedSubtitle("Latest Context")
        nodeViewModel.userName = nil
        #expect(nodeViewModel.subtitle == "Latest Context")

        node.setDerivedSubtitle("Subject Update")
        for _ in 0..<50 where nodeViewModel.subtitle != "Subject Update"
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(nodeViewModel.subtitle == "Subject Update")

        node.userName = "Direct Node Rename"
        for _ in 0..<50 where nodeViewModel.subtitle != "Direct Node Rename"
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(nodeViewModel.userName == "Direct Node Rename")
        #expect(nodeViewModel.subtitle == "Direct Node Rename")

        node.userName = nil
        for _ in 0..<50 where nodeViewModel.subtitle != "Subject Update"
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(nodeViewModel.userName == nil)
        #expect(nodeViewModel.subtitle == "Subject Update")
    }

    @Test("NodeViewModel mirrors instance title changes")
    func viewModelMirrorsInstanceTitleChanges() async throws
    {
        guard let context = makeContext() else { return }
        let node = NamingTestNode(context: context)
        let nodeViewModel = NodeViewModel(node: node)

        node.setDerivedTitle("Updated Instance Title")
        for _ in 0..<50 where nodeViewModel.title != "Updated Instance Title"
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(nodeViewModel.title == "Updated Instance Title")
    }
}
