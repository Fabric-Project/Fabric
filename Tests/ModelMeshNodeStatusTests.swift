import Testing
import Foundation
@testable import Fabric
import Satin

/// The two nodes that load a model file through ModelFileLoader.
enum ModelFileNodeKind: CaseIterable, CustomTestStringConvertible
{
    case modelMesh
    case instancedModelMesh

    var testDescription: String
    {
        switch self
        {
        case .modelMesh: ModelMeshNode.name
        case .instancedModelMesh: InstancedModelMeshNode.name
        }
    }

    @MainActor
    func makeNode(context: Context) -> any ModelFileNode
    {
        switch self
        {
        case .modelMesh: ModelMeshNode(context: context)
        case .instancedModelMesh: InstancedModelMeshNode(context: context)
        }
    }
}

protocol ModelFileNode: Node
{
    var inputFilePathParam: ParameterPort<String> { get }
    func getObject() -> Object?
    func loadModelFromInputValue() throws
}

extension ModelMeshNode: ModelFileNode {}
extension InstancedModelMeshNode: ModelFileNode {}

/// Whether the node says on the canvas that its model file did not load.
@Suite("Model Mesh status")
@MainActor
struct ModelMeshNodeStatusTests
{
    private static let triangleOBJ = """
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """

    private func modelFile(named fileName: String, contents: String) throws -> URL
    {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "ModelMeshNodeStatusTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appending(path: fileName)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func load(_ fileURL: URL, into node: any ModelFileNode)
    {
        node.inputFilePathParam.value = fileURL.path
        _ = try? node.loadModelFromInputValue()
    }

    @Test("A model that loads reports nothing", arguments: ModelFileNodeKind.allCases)
    func aLoadedModelHasNoStatus(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        load(try modelFile(named: "triangle.obj", contents: Self.triangleOBJ), into: node)

        #expect(node.deriveStatuses().isEmpty)
        #expect(node.getObject() != nil)
    }

    @Test("A file of a type ModelIO cannot import is the node's error",
          arguments: ModelFileNodeKind.allCases, ["model.fbx", "model.gltf"])
    func anUnsupportedTypeIsANodeError(kind: ModelFileNodeKind, fileName: String) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        load(try modelFile(named: fileName, contents: Self.triangleOBJ), into: node)

        #expect(node.status.map { if case .error = $0 { true } else { false } } == true)
        #expect(node.getObject() == nil)
    }

    @Test("A file with no mesh in it is the node's warning", arguments: ModelFileNodeKind.allCases)
    func aFileWithNoMeshIsANodeWarning(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        load(try modelFile(named: "empty.obj", contents: "# nothing here\n"), into: node)

        #expect(node.status.map { if case .warning = $0 { true } else { false } } == true)
        #expect(node.getObject() == nil)
    }

    @Test("A missing file is the node's error, and the error clears once a model loads", arguments: ModelFileNodeKind.allCases)
    func aMissingFileErrorClearsOnLoad(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)
        let fileURL = try modelFile(named: "triangle.obj", contents: Self.triangleOBJ)

        load(fileURL.deletingLastPathComponent().appending(path: "absent.obj"), into: node)
        #expect(node.deriveStatuses().isEmpty == false)

        load(fileURL, into: node)
        #expect(node.deriveStatuses().isEmpty)
    }

    @Test("Naming the same file again after it failed retries the load", arguments: ModelFileNodeKind.allCases)
    func aFailedFileIsRetried(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)
        let fileURL = try modelFile(named: "late.obj", contents: "")
        try FileManager.default.removeItem(at: fileURL)

        load(fileURL, into: node)
        #expect(node.deriveStatuses().isEmpty == false)

        try Self.triangleOBJ.write(to: fileURL, atomically: true, encoding: .utf8)
        load(fileURL, into: node)
        #expect(node.deriveStatuses().isEmpty)
    }
}
