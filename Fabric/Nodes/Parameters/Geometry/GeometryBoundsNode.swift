//
//  GeometryBoundsNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class GeometryBoundsNode : Node
{
    public override class var name:String { "Geometry Bounds" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Output the axis-aligned bounding box of an input Geometry as min, max, size, and center vectors." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputGeometry", NodePort<SatinGeometry>(name: "Geometry", kind: .Inlet, description: "Geometry to measure")),
            ("inputContinuous", ParameterPort(parameter: BoolParameter("Continuous", false, .button, "When on, recomputes every frame — useful for animated / live geometry whose vertex buffer is rewritten under a stable reference. When off, recomputes only when the geometry input itself changes."))),
            ("outputMin",     NodePort<simd_float3>(name: "Min", kind: .Outlet, description: "Minimum corner of the axis-aligned bounding box")),
            ("outputMax",     NodePort<simd_float3>(name: "Max", kind: .Outlet, description: "Maximum corner of the axis-aligned bounding box")),
            ("outputSize",    NodePort<simd_float3>(name: "Size", kind: .Outlet, description: "Size of the bounding box (max − min)")),
            ("outputCenter",  NodePort<simd_float3>(name: "Center", kind: .Outlet, description: "Center of the bounding box ((min + max) / 2)")),
        ]
    }

    public var inputGeometry: NodePort<SatinGeometry>   { port(named: "inputGeometry") }
    public var inputContinuous: ParameterPort<Bool>     { port(named: "inputContinuous") }
    public var outputMin:     NodePort<simd_float3>     { port(named: "outputMin") }
    public var outputMax:     NodePort<simd_float3>     { port(named: "outputMax") }
    public var outputSize:    NodePort<simd_float3>     { port(named: "outputSize") }
    public var outputCenter:  NodePort<simd_float3>     { port(named: "outputCenter") }

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let geometry = self.inputGeometry.value else { return }

        // Default path: only resample when the geometry input value
        // changes. A SatinGeometry's reference identity can stay the
        // same while its vertex buffer is rewritten under it (the same
        // caveat `GeometryToTransformArrayNode` notes), so users with
        // animated / live geometry can flip `Continuous` on to force a
        // per-frame resample.
        let continuous = self.inputContinuous.value ?? false
        guard continuous || self.inputGeometry.valueDidChange else { return }

        // Geometries not attached to a mesh don't get their `update()`
        // called automatically — call it ourselves so the buffer
        // reflects the latest vertex data before we sample bounds.
        geometry.update()

        let bounds = geometry.bounds
        let size = bounds.max - bounds.min
        let center = (bounds.min + bounds.max) * 0.5

        self.outputMin.send(bounds.min)
        self.outputMax.send(bounds.max)
        self.outputSize.send(size)
        self.outputCenter.send(center)
    }
}
