import Metal
import simd
@testable import Fabric
import Satin

/// A test-only points producer, and a graph helper that draws its points through Points Geometry.

/// Publishes a square of two triangles at x = `offsets[iteration]`, or at `fixedOffset` when set:
/// new points on every execution, or only on the first when `publishesOnce`, as a static input would.
final class IterationPointsNode: Node
{
    override class var name: String { "Iteration Points" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Publishes an iteration-placed square as points" }

    var offsets: [Float] = [0]
    var fixedOffset: Float?
    var halfSize: Float = 0.15
    var publishesOnce = false
    private(set) var publishCount = 0

    var outputPoints: NodePort<Satin.Points> { port(named: "outputPoints") }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("outputPoints", NodePort<Satin.Points>(name: "Points", kind: .Outlet)),
        ]
    }

    override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        if publishesOnce, publishCount > 0 { return }
        let iteration = executionInfo.iterationInfo?.currentIteration ?? 0
        let x = fixedOffset ?? offsets[min(iteration, offsets.count - 1)]
        let size = halfSize
        let square: ContiguousArray<simd_float3> = [
            [x - size, -size, 0], [x + size, -size, 0], [x + size, size, 0],
            [x - size, -size, 0], [x + size, size, 0], [x - size, size, 0],
        ]
        outputPoints.send(try Satin.Points(positions: square, allocator: context.gpuAllocator), force: true)
        publishCount += 1
    }
}

/// Points → triangles → mesh with a basic colour material, in `graph`. Returns the producer.
@discardableResult
func addPointsMesh(to graph: Graph, context: Context, offsets: [Float], fixedOffset: Float? = nil, publishesOnce: Bool = false) -> IterationPointsNode
{
    let points = IterationPointsNode(context: context)
    points.offsets = offsets
    points.fixedOffset = fixedOffset
    points.publishesOnce = publishesOnce
    let triangles = PointsGeometryNode(context: context)
    triangles.inputPrimitiveType.value = "Triangle"
    let material = BasicColorMaterialNode(context: context)
    let mesh = MeshNode(context: context)
    mesh.inputCullingMode.value = "None"
    for node in [points, triangles, material, mesh] as [Node] { graph.addNode(node) }
    graph.connect(points.outputPoints, to: triangles.inputPoints)
    graph.connect(triangles.outputGeometry, to: mesh.inputGeometry)
    graph.connect(material.outputMaterial, to: mesh.inputMaterial)
    return points
}
