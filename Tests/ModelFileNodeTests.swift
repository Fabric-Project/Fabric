import Testing
import Foundation
import Metal
import simd
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
    var inputPosition: ParameterPort<simd_float3> { get }
    var inputCullingMode: ParameterPort<String> { get }
    func getObject() -> Object?
    func loadModelFromInputValue() throws
}

extension ModelMeshNode: ModelFileNode {}
extension InstancedModelMeshNode: ModelFileNode {}

private let triangleOBJ = """
    v 0 0 0
    v 1 0 0
    v 0 1 0
    f 1 2 3
    """

/// A triangle under a parent that moves it 5 along x.
private let translatedTriangleUSDA = """
    #usda 1.0

    def Xform "Root"
    {
        double3 xformOp:translate = (5, 0, 0)
        uniform token[] xformOpOrder = ["xformOp:translate"]

        def Mesh "Triangle"
        {
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
        }
    }
    """

private func modelFile(named fileName: String, contents: String) throws -> URL
{
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "ModelFileNodeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let fileURL = directoryURL.appending(path: fileName)
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}

/// Whether the node says on the canvas that its model file did not load.
@Suite("Model Mesh status")
@MainActor
struct ModelMeshNodeStatusTests
{
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

        load(try modelFile(named: "triangle.obj", contents: triangleOBJ), into: node)

        #expect(node.deriveStatuses().isEmpty)
        #expect(node.getObject() != nil)
    }

    @Test("A part keeps the placement its file gives it", arguments: ModelFileNodeKind.allCases)
    func aPartKeepsItsPlacement(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        load(try modelFile(named: "translated.usda", contents: translatedTriangleUSDA), into: node)

        let meshes = try #require(node.getObject()).getChildren(true).compactMap { $0 as? Mesh }
        #expect(meshes.isEmpty == false)
        #expect(meshes.allSatisfy { $0.localMatrix.columns.3 == simd_float4(5, 0, 0, 1) })
    }

    @Test("A file of a type ModelIO cannot import is the node's error",
          arguments: ModelFileNodeKind.allCases, ["model.fbx", "model.gltf"])
    func anUnsupportedTypeIsANodeError(kind: ModelFileNodeKind, fileName: String) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        load(try modelFile(named: fileName, contents: triangleOBJ), into: node)

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
        let fileURL = try modelFile(named: "triangle.obj", contents: triangleOBJ)

        load(fileURL.deletingLastPathComponent().appending(path: "absent.obj"), into: node)
        #expect(node.deriveStatuses().isEmpty == false)

        load(fileURL, into: node)
        #expect(node.deriveStatuses().isEmpty)
    }

    @Test("Clearing the path removes the model and reports nothing", arguments: ModelFileNodeKind.allCases)
    func clearingThePathRemovesTheModel(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        load(try modelFile(named: "triangle.obj", contents: triangleOBJ), into: node)
        #expect(node.getObject() != nil)

        node.inputFilePathParam.value = ""
        _ = try? node.loadModelFromInputValue()

        #expect(node.getObject() == nil)
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

        try triangleOBJ.write(to: fileURL, atomically: true, encoding: .utf8)
        load(fileURL, into: node)
        #expect(node.deriveStatuses().isEmpty)
    }
}

/// Whether a model loaded once the node's inlets have settled takes their
/// values, as one loaded on the node's first frame does.
@Suite("Model Mesh state")
@MainActor
struct ModelFileNodeStateTests
{
    private func runFrame(_ node: Node, harness: GraphExecutionTestHarness) throws
    {
        let commandBuffer = try #require(harness.context.device.makeCommandQueue()?.makeCommandBuffer())
        try node.execute(renderer: harness.renderer,
                         executionInfo: harness.makeExecutionInfo(),
                         renderPassDescriptor: MTLRenderPassDescriptor(),
                         commandBuffer: commandBuffer)
        node.markClean()
    }

    @Test("A model loaded after the first frame takes the node's settled inlets",
          arguments: ModelFileNodeKind.allCases)
    func aLaterModelTakesSettledInlets(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)
        let position = simd_float3(1, 2, 3)

        node.inputPosition.value = position
        node.inputCullingMode.value = "Front"
        node.inputFilePathParam.value = try modelFile(named: "first.obj", contents: triangleOBJ).path
        try runFrame(node, harness: harness)

        node.inputFilePathParam.value = try modelFile(named: "second.obj", contents: triangleOBJ).path
        try runFrame(node, harness: harness)

        let model = try #require(node.getObject())
        #expect(model.position == position)

        let meshes = model.getChildren(true).compactMap { $0 as? Mesh }
        #expect(meshes.isEmpty == false)
        #expect(meshes.allSatisfy { $0.cullMode == .front })
    }

    @Test("An instanced model loaded after the first frame takes the settled transforms")
    func aLaterInstancedModelTakesSettledTransforms() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = InstancedModelMeshNode(context: harness.context)
        let transforms = ContiguousArray(repeating: matrix_identity_float4x4, count: 3)

        node.inputTransforms.value = transforms
        node.inputFilePathParam.value = try modelFile(named: "first.obj", contents: triangleOBJ).path
        try runFrame(node, harness: harness)

        node.inputFilePathParam.value = try modelFile(named: "second.obj", contents: triangleOBJ).path
        try runFrame(node, harness: harness)

        let meshes = try #require(node.getObject()).getChildren(true).compactMap { $0 as? InstancedMesh }
        #expect(meshes.isEmpty == false)
        #expect(meshes.allSatisfy { $0.drawCount == transforms.count })
    }
}
