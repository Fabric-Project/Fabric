//
//  PointsToLineGeometryNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import simd

/// Strokes points into ribbon geometry, on the GPU or the CPU, for a Mesh with any material.
///
/// The GPU tessellator strokes any points with no readback, including ones a GPU pass wrote. The
/// CPU tessellator is Stroke Geometry's, for points built on the CPU, such as the Points node's,
/// and the only one that makes pieces. The two are a best-effort match: same inputs, near-same
/// pictures.
public final class PointsToLineGeometryNode: BaseGeometryNode
{
    override public class var name: String { "Points to Line Geometry" }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Strokes points into ribbon geometry, one ribbon per strip, with joins, caps, trim, dashes and texture. GPU strokes any points with no readback; CPU strokes points built on the CPU, like Stroke Geometry, and makes pieces. Sizes multiply the width and Colors carry along. Connect the geometry to a Mesh, with any material." }

    static let tessellatorGPU = "GPU"
    static let tessellatorCPU = "CPU"

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        [
            ("inputPoints", NodePort<Satin.Points>(name: "Points", kind: .Inlet, description: "The points to stroke, along their strips")),
            ("inputTessellator", ParameterPort(parameter: StringParameter("Tessellator", Self.tessellatorGPU, [Self.tessellatorGPU, Self.tessellatorCPU], .dropdown, "GPU strokes any points with no readback. CPU strokes points built on the CPU, and makes pieces"))),
            ("inputWidth", ParameterPort(parameter: FloatParameter("Width", 0.1, .inputfield, "Ribbon width in world units"))),
            ("inputJoin", ParameterPort(parameter: StringParameter("Join", "Round", StrokeGeometryNode.joinTitles, .dropdown, "The shape where two segments meet"))),
            ("inputCap", ParameterPort(parameter: StringParameter("Cap", "Round", StrokeGeometryNode.capTitles, .dropdown, "The shape at each end of an open strip, and of each dash"))),
            ("inputMiterLimit", ParameterPort(parameter: FloatParameter("Miter Limit", 4, .inputfield, "How far a Miter join may reach, in half-widths, before it becomes a Bevel"))),
            ("inputRoundResolution", ParameterPort(parameter: IntParameter("Round Segments", 8, .inputfield, "Segments in each round join and cap"))),
            ("inputClosed", ParameterPort(parameter: BoolParameter("Close All", false, .button, "When enabled, every strip returns to its first point"))),
            ("inputBend", ParameterPort(parameter: FloatParameter("Bend", 0, 0, 1, .slider, "Tilts the normals toward each edge so a flat ribbon lights like a tube: 0 faces straight out, 1 faces sideways at the edges"))),
            ("inputLayerDepth", ParameterPort(parameter: FloatParameter("Layer Depth", 0, 0, 10, .inputfield, "How far the lines rise off their plane from first point to last, in world units, so a later part always draws over an earlier one where they cross"))),
            ("inputTrimStart", ParameterPort(parameter: FloatParameter("Trim Start", 0, 0, 1, .slider, "Where the lines begin, as a fraction of their length. Wire time into this or Trim End to reveal them"))),
            ("inputTrimEnd", ParameterPort(parameter: FloatParameter("Trim End", 1, 0, 1, .slider, "Where the lines end, as a fraction of their length"))),
            ("inputTrimMode", ParameterPort(parameter: StringParameter("Trim Mode", StrokeGeometryNode.trimEachStroke, [StrokeGeometryNode.trimEachStroke, StrokeGeometryNode.trimAllInOrder], .dropdown, "Trims every strip by its own length, or treats the strips as one line drawn in order"))),
            ("inputTextureMode", ParameterPort(parameter: StringParameter("Texture Mode", StrokeGeometryNode.textureStretch, [StrokeGeometryNode.textureStretch, StrokeGeometryNode.textureReveal], .dropdown, "Stretches the whole texture over what a trim or dash leaves, or holds the texture still on the line so they reveal it"))),
            ("inputTextureSpan", ParameterPort(parameter: StringParameter("Texture Span", StrokeGeometryNode.textureEachPiece, [StrokeGeometryNode.textureEachPiece, StrokeGeometryNode.textureWholePath], .dropdown, "Runs the texture from 0 to 1 along each piece, or once along the whole path"))),
            ("inputDashLength", ParameterPort(parameter: FloatParameter("Dash Length", 0, 0, 100, .inputfield, "The length of each dash along the line, in world units. 0 draws solid lines"))),
            ("inputGapLength", ParameterPort(parameter: FloatParameter("Gap Length", 0.1, 0, 100, .inputfield, "The space between dashes, in world units. 0 draws solid lines"))),
            ("inputDashOffset", ParameterPort(parameter: FloatParameter("Dash Offset", 0, -1000, 1000, .inputfield, "Slides the dashes along the line, in world units. Wire time into this to make them march"))),
            ("inputDashesPerSegment", ParameterPort(parameter: IntParameter("Dashes per Segment", 4, .inputfield, "GPU only: the most dashes one segment between two points draws. Raise it for dashes much shorter than the segments"))),
            ("inputPieces", ParameterPort(parameter: StringParameter("Pieces", StrokeGeometryNode.piecesNone, [StrokeGeometryNode.piecesNone, StrokeGeometryNode.piecesStrokes, StrokeGeometryNode.piecesStrokesAndDashes], .dropdown, "CPU only: divides the geometry into pieces for Transform Pieces and Piece Info, one per strip, or one per strip with its dashes as children"))),
        ] + super.registerPorts(context: context)
    }

    public var inputPoints: NodePort<Satin.Points> { port(named: "inputPoints") }
    public var inputTessellator: ParameterPort<String> { port(named: "inputTessellator") }
    public var inputWidth: ParameterPort<Float> { port(named: "inputWidth") }
    public var inputJoin: ParameterPort<String> { port(named: "inputJoin") }
    public var inputCap: ParameterPort<String> { port(named: "inputCap") }
    public var inputMiterLimit: ParameterPort<Float> { port(named: "inputMiterLimit") }
    public var inputRoundResolution: ParameterPort<Int> { port(named: "inputRoundResolution") }
    public var inputClosed: ParameterPort<Bool> { port(named: "inputClosed") }
    public var inputBend: ParameterPort<Float> { port(named: "inputBend") }
    public var inputLayerDepth: ParameterPort<Float> { port(named: "inputLayerDepth") }
    public var inputTrimStart: ParameterPort<Float> { port(named: "inputTrimStart") }
    public var inputTrimEnd: ParameterPort<Float> { port(named: "inputTrimEnd") }
    public var inputTrimMode: ParameterPort<String> { port(named: "inputTrimMode") }
    public var inputTextureMode: ParameterPort<String> { port(named: "inputTextureMode") }
    public var inputTextureSpan: ParameterPort<String> { port(named: "inputTextureSpan") }
    public var inputDashLength: ParameterPort<Float> { port(named: "inputDashLength") }
    public var inputGapLength: ParameterPort<Float> { port(named: "inputGapLength") }
    public var inputDashOffset: ParameterPort<Float> { port(named: "inputDashOffset") }
    public var inputDashesPerSegment: ParameterPort<Int> { port(named: "inputDashesPerSegment") }
    public var inputPieces: ParameterPort<String> { port(named: "inputPieces") }

    private var usesCPU: Bool { inputTessellator.value == Self.tessellatorCPU }

    override public var geometry: Geometry { usesCPU ? cpuGeometry : gpuGeometry }

    private lazy var gpuGeometry = Geometry(context: self.context, primitiveType: self.primitiveType())
    private lazy var cpuGeometry = StrokeGeometry(context: self.context)

    private let kernel = ComputeKernel()

    /// Compiles the GPU tessellator here, never in `execute`.
    override public func enableExecution(renderer: GraphRenderer) throws
    {
        kernel.compile(source: GPUStrokeTessellation.source, functionNames: GPUStrokeTessellation.functionNames, device: context.device)
        subtitleSubject.send()
        try super.enableExecution(renderer: renderer)
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        kernel.release()
        try super.disableExecution(renderer: renderer)
    }
    /// Why the last execution drew nothing or less than asked, other than a kernel that didn't compile.
    private var executionStatus: NodeStatus?

    override public func deriveStatuses() -> [NodeStatus]
    {
        [kernel.failure.map { NodeStatus.error($0) }, executionStatus].compactMap { $0 }
    }

    private func setExecutionStatus(_ status: NodeStatus?)
    {
        guard status != executionStatus else { return }
        executionStatus = status
        subtitleSubject.send()
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        var shouldOutput = evaluate(geometry: geometry, atTime: executionInfo.timing.time)

        if ports.contains(where: { $0.kind == .Inlet && $0.valueDidChange })
        {
            guard let points = inputPoints.value else
            {
                setExecutionStatus(nil)
                outputGeometry.send(nil, force: true)
                return
            }
            let drew = usesCPU ? strokeOnCPU(points) : try strokeOnGPU(points, commandBuffer: commandBuffer)
            guard drew else
            {
                outputGeometry.send(nil, force: true)
                return
            }
            shouldOutput = true
        }

        if shouldOutput
        {
            outputGeometry.send(geometry, force: true)
        }
    }

    private var style: Stroke.Style
    {
        Stroke.Style(width: inputWidth.value ?? 0.1,
                     join: StrokeGeometryNode.join(named: inputJoin.value),
                     cap: StrokeGeometryNode.cap(named: inputCap.value),
                     miterLimit: inputMiterLimit.value ?? 4,
                     roundResolution: inputRoundResolution.value ?? 8)
    }

    /// Stroke Geometry's tessellator, for points the CPU wrote.
    private func strokeOnCPU(_ points: Satin.Points) -> Bool
    {
        guard let strokes = Stroke.strokes(from: points, style: style, closesAll: inputClosed.value ?? false) else
        {
            setExecutionStatus(.error("These points were written on the GPU, so only the GPU tessellator can stroke them."))
            return false
        }
        setExecutionStatus(nil)
        let finished = StrokeGeometryNode.finished(strokes, options: StrokeGeometryNode.StrokeOptions(
            layerDepth: inputLayerDepth.value ?? 0,
            dashLength: inputDashLength.value ?? 0,
            gapLength: inputGapLength.value ?? 0,
            dashOffset: inputDashOffset.value ?? 0,
            trimStart: inputTrimStart.value ?? 0,
            trimEnd: inputTrimEnd.value ?? 1,
            trimMode: inputTrimMode.value,
            textureMode: inputTextureMode.value,
            textureSpan: inputTextureSpan.value,
            pieces: inputPieces.value))
        cpuGeometry.update(strokes: finished.strokes, pieces: finished.pieces, bend: inputBend.value ?? 0)
        return true
    }

    /// The GPU tessellator, for any points; it makes no pieces.
    private func strokeOnGPU(_ points: Satin.Points, commandBuffer: MTLCommandBuffer) throws -> Bool
    {
        guard let compiled = kernel.pipelines, let pipelines = GPUStrokeTessellation.Pipelines(compiled) else { return false }

        let wantsPieces = (inputPieces.value ?? StrokeGeometryNode.piecesNone) != StrokeGeometryNode.piecesNone
        setExecutionStatus(wantsPieces ? .warning("Pieces need the CPU tessellator; the GPU one makes none.") : nil)

        let options = GPUStrokeTessellation.Options(
            closesAll: inputClosed.value ?? false,
            bend: inputBend.value ?? 0,
            layerDepth: inputLayerDepth.value ?? 0,
            trimStart: inputTrimStart.value ?? 0,
            trimEnd: inputTrimEnd.value ?? 1,
            trimInOrder: inputTrimMode.value == StrokeGeometryNode.trimAllInOrder,
            dashLength: inputDashLength.value ?? 0,
            gapLength: inputGapLength.value ?? 0,
            dashOffset: inputDashOffset.value ?? 0,
            dashesPerSegment: inputDashesPerSegment.value ?? 4,
            textureMode: inputTextureMode.value == StrokeGeometryNode.textureReveal ? .reveal : .stretch,
            textureSpan: inputTextureSpan.value == StrokeGeometryNode.textureWholePath ? .wholePath : .eachPiece)
        do
        {
            guard let ribbons = try GPUStrokeTessellation.encode(points: points, style: style, options: options, pipelines: pipelines,
                                                                 commandBuffer: commandBuffer, allocator: context.gpuAllocator)
            else { return false }
            gpuGeometry.setPoints(ribbons)
            return true
        }
        catch GPUStrokeTessellation.TessellationError.unsupportedLayout(let attribute)
        {
            throw FabricError(.execution(.failed), severity: .recoverable,
                              message: "Points to Line Geometry can't read these points' \(attribute) attribute: it needs floats.")
        }
        catch GPUStrokeTessellation.TessellationError.tooManyVertices(let vertexCount)
        {
            throw FabricError(.execution(.failed), severity: .recoverable,
                              message: "These lines could need \(vertexCount) vertices, more than the GPU tessellator's \(GPUStrokeTessellation.maximumVertexCount(device: context.device)) on this device. Lower Round Segments or Dashes per Segment, or stroke fewer points.")
        }
    }
}
