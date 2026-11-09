//
//  PointsGeometryNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import simd

/// Draws published Points as geometry, binding their attributes without copying them, for any
/// material: point sprites sized by a Sizes attribute, lines, or triangles.
public final class PointsGeometryNode: BaseGeometryNode
{
    override public class var name: String { "Points Geometry" }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }

    override public class var nodeDescription: String { "Draws points as geometry for any material: as points, sized by their Sizes; as lines or triangles through them in order; or, for Line Strip and Triangle Strip, along their strips. Their attributes are bound as they are, without copying." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        [
            ("inputPoints", NodePort<Satin.Points>(name: "Points", kind: .Inlet, description: "The points to draw")),
        ] + super.registerPorts(context: context)
    }

    public var inputPoints: NodePort<Satin.Points> { port(named: "inputPoints") }

    public required init(context: Context)
    {
        super.init(context: context)
        inputPrimitiveType.value = "Point"
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }

    override public var geometry: Geometry { _geometry }

    private lazy var _geometry = Geometry(context: self.context, primitiveType: self.primitiveType())

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        let primitiveChanged = inputPrimitiveType.valueDidChange
        var shouldOutput = evaluate(geometry: geometry, atTime: executionInfo.timing.time)

        guard let points = inputPoints.value else
        {
            if inputPoints.valueDidChange { outputGeometry.send(nil, force: true) }
            return
        }

        // Which indices apply depends on the primitive, so a primitive change binds the points again.
        if inputPoints.valueDidChange || primitiveChanged
        {
            geometry.setPoints(points)
            shouldOutput = true
        }

        if shouldOutput
        {
            outputGeometry.send(geometry, force: true)
        }
    }
}
