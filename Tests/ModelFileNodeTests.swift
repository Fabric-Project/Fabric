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
    var outputDuration: NodePort<Float> { get }
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

/// Two triangles, one red and one blue: ModelIO gives the mesh a submesh per
/// material.
private let twoMaterialOBJ = """
    mtllib colors.mtl
    v 0 0 0
    v 1 0 0
    v 0 1 0
    v 1 1 0
    usemtl Red
    f 1 2 3
    usemtl Blue
    f 2 4 3
    """

private let twoMaterialMTL = """
    newmtl Red
    Kd 1 0 0
    newmtl Blue
    Kd 0 0 1
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

/// A triangle that moves 5 along x over two seconds.
private let movingTriangleUSDA = """
    #usda 1.0
    (
        startTimeCode = 0
        endTimeCode = 48
        timeCodesPerSecond = 24
    )

    def Xform "Root"
    {
        double3 xformOp:translate.timeSamples = {
            0: (0, 0, 0),
            48: (5, 0, 0),
        }
        uniform token[] xformOpOrder = ["xformOp:translate"]

        def Mesh "Triangle"
        {
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
        }
    }
    """

/// A folder for one test's model files, removed when the test ends. Swift
/// Testing runs each test, and each test case, on its own suite instance, so a
/// suite holding one drops it with the test.
final class ModelFileFolder
{
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ModelFiles-\(UUID().uuidString)", directoryHint: .isDirectory)

    func file(named fileName: String, contents: String) throws -> URL
    {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let fileURL = url.appending(path: fileName)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    deinit
    {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Whether the node says on the canvas that its model file did not load.
@Suite("Model Mesh status")
@MainActor
struct ModelMeshNodeStatusTests
{
    private let files = ModelFileFolder()

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

        load(try files.file(named: "triangle.obj", contents: triangleOBJ), into: node)

        #expect(node.deriveStatuses().isEmpty)
        #expect(node.getObject() != nil)
    }

    @Test("A part keeps the placement its file gives it", arguments: ModelFileNodeKind.allCases)
    func aPartKeepsItsPlacement(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        load(try files.file(named: "translated.usda", contents: translatedTriangleUSDA), into: node)

        let meshes = try #require(node.getObject()).getChildren(true).compactMap { $0 as? Mesh }
        #expect(meshes.isEmpty == false)
        #expect(meshes.allSatisfy { $0.localMatrix.columns.3 == simd_float4(5, 0, 0, 1) })
    }

    @Test("Instanced Model Mesh keeps a mesh's material per submesh")
    func instancedModelKeepsSubmeshes() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = InstancedModelMeshNode(context: harness.context)
        let fileURL = try files.file(named: "two.obj", contents: twoMaterialOBJ)
        _ = try files.file(named: "colors.mtl", contents: twoMaterialMTL)

        load(fileURL, into: node)

        let meshes = try #require(node.getObject()).getChildren(true).compactMap { $0 as? InstancedMesh }
        #expect(meshes.contains { $0.submeshes.count == 2 })
    }

    @Test("A file of a type ModelIO cannot import is the node's error",
          arguments: ModelFileNodeKind.allCases, ["model.fbx", "model.gltf"])
    func anUnsupportedTypeIsANodeError(kind: ModelFileNodeKind, fileName: String) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        load(try files.file(named: fileName, contents: triangleOBJ), into: node)

        #expect(node.status.map { if case .error = $0 { true } else { false } } == true)
        #expect(node.getObject() == nil)
    }

    @Test("A file with no mesh in it is the node's warning", arguments: ModelFileNodeKind.allCases)
    func aFileWithNoMeshIsANodeWarning(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        load(try files.file(named: "empty.obj", contents: "# nothing here\n"), into: node)

        #expect(node.status.map { if case .warning = $0 { true } else { false } } == true)
        #expect(node.getObject() == nil)
    }

    @Test("A missing file is the node's error, and the error clears once a model loads", arguments: ModelFileNodeKind.allCases)
    func aMissingFileErrorClearsOnLoad(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)
        let fileURL = try files.file(named: "triangle.obj", contents: triangleOBJ)

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

        load(try files.file(named: "triangle.obj", contents: triangleOBJ), into: node)
        #expect(node.getObject() != nil)

        node.inputFilePathParam.value = ""
        _ = try? node.loadModelFromInputValue()

        #expect(node.getObject() == nil)
        #expect(node.deriveStatuses().isEmpty)
    }

    @Test("Clearing the path, a missing file or a file with no mesh leaves Duration with no value",
          arguments: ModelFileNodeKind.allCases, ["", "missing.usda", "empty.obj"])
    func noModelHasNoDuration(kind: ModelFileNodeKind, nextFileName: String) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)

        let movingURL = try files.file(named: "moving.usda", contents: movingTriangleUSDA)
        load(movingURL, into: node)
        #expect(node.outputDuration.value == 2)

        switch nextFileName
        {
        case "":
            node.inputFilePathParam.value = ""
            _ = try? node.loadModelFromInputValue()
        case "empty.obj":
            load(try files.file(named: nextFileName, contents: "# nothing here\n"), into: node)
        default:
            load(files.url.appending(path: nextFileName), into: node)
        }

        #expect(node.getObject() == nil)
        #expect(node.outputDuration.value == nil)
    }

    @Test("Naming the same file again after it failed retries the load", arguments: ModelFileNodeKind.allCases)
    func aFailedFileIsRetried(kind: ModelFileNodeKind) throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = kind.makeNode(context: harness.context)
        let fileURL = try files.file(named: "late.obj", contents: "")
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
    private let files = ModelFileFolder()

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
        node.inputFilePathParam.value = try files.file(named: "first.obj", contents: triangleOBJ).path
        try runFrame(node, harness: harness)

        node.inputFilePathParam.value = try files.file(named: "second.obj", contents: triangleOBJ).path
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
        node.inputFilePathParam.value = try files.file(named: "first.obj", contents: triangleOBJ).path
        try runFrame(node, harness: harness)

        node.inputFilePathParam.value = try files.file(named: "second.obj", contents: triangleOBJ).path
        try runFrame(node, harness: harness)

        let meshes = try #require(node.getObject()).getChildren(true).compactMap { $0 as? InstancedMesh }
        #expect(meshes.isEmpty == false)
        #expect(meshes.allSatisfy { $0.drawCount == transforms.count })
    }

    @Test("An instance transform turns the whole model, its parts placed within it")
    func anInstanceTransformTurnsTheWholeModel() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let node = InstancedModelMeshNode(context: harness.context)

        // The file places its triangle 5 along x. A quarter turn about z carries
        // the model, and that placement with it, to 5 along y; applied within the
        // part instead, it would turn the triangle where it sits, 5 along x.
        node.inputTransforms.value = [simd_float4x4(simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))]
        node.inputFilePathParam.value = try files.file(named: "translated.usda", contents: translatedTriangleUSDA).path
        try runFrame(node, harness: harness)

        let parts = try #require(node.getObject()).getChildren(true).compactMap { $0 as? InstancedMesh }
        #expect(parts.isEmpty == false)
        for part in parts
        {
            part.update()
            let origin = part.getWorldMatrixAt(index: 0).columns.3
            #expect(simd_distance(simd_make_float3(origin), [0, 5, 0]) < 1e-4)
        }
    }
}
