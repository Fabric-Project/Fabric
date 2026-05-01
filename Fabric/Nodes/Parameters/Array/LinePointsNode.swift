//
//  LinePointsNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class LinePointsNode : Node
{
    public override class var name: String { "Line Points" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Generates N points evenly spaced along a line, centred on the origin. The Orientation quaternion rotates a canonical local frame (line runs along local +X) into world space. Identity orientation places the line along the world +X axis." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of points to emit"))),
            ("inputSpread", ParameterPort(parameter: FloatParameter("Spread", 1.0, 0.0, 1000.0, .inputfield, "Total length of the line"))),
            ("inputOrientation", ParameterPort(parameter: Float4Parameter("Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Quaternion rotating the canonical frame (line along local +X) into world space"))),
            ("outputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Outlet, description: "Array of per-point world-space positions")),
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputSpread: ParameterPort<Float> { port(named: "inputSpread") }
    public var inputOrientation: ParameterPort<simd_float4> { port(named: "inputOrientation") }
    public var outputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "outputPositions") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputCount.valueDidChange
            || self.inputSpread.valueDidChange
            || self.inputOrientation.valueDidChange
        else { return }

        let count = max(0, self.inputCount.value ?? 0)
        guard count > 0 else {
            self.outputPositions.send(ContiguousArray<simd_float3>())
            return
        }

        let spread = max(0.0, self.inputSpread.value ?? 1.0)
        let orientation = simd_quatf(vector: self.inputOrientation.value ?? simd_float4(0, 0, 0, 1)).normalized

        let step = spread / Float(count)
        var x = -spread * 0.5 + step * 0.5

        var output = ContiguousArray<simd_float3>()
        output.reserveCapacity(count)
        for _ in 0..<count {
            let local = simd_float3(x, 0, 0)
            output.append(orientation.act(local))
            x += step
        }
        self.outputPositions.send(output)
    }
}
