//
//  OrientationArrayFromEulerNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class OrientationArrayFromEulerNode : Node
{
    public override class var name: String { "Orientation Array From Euler" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts an array of Euler angles (degrees, X=pitch, Y=yaw, Z=roll per element) into an array of quaternion orientations, composed X → Y → Z." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputEulerAngles", NodePort<ContiguousArray<simd_float3>>(name: "Euler Angles", kind: .Inlet, description: "Per-element Euler angles in degrees (X=pitch, Y=yaw, Z=roll)")),
            ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
        ]
    }

    public var inputEulerAngles: NodePort<ContiguousArray<simd_float3>> { port(named: "inputEulerAngles") }
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "outputOrientations") }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputEulerAngles.valueDidChange else { return }
        guard let eulerAngles = self.inputEulerAngles.value else {
            self.outputOrientations.send(ContiguousArray<simd_float4>())
            return
        }

        var output = ContiguousArray<simd_float4>()
        output.reserveCapacity(eulerAngles.count)
        for angles in eulerAngles {
            output.append(simd_quatf(eulerAnglesDegrees: angles).vector)
        }
        self.outputOrientations.send(output)
    }
}
