//
//  EulerOrientationNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Converts Euler angles (in degrees) to a quaternion suitable for
/// the Orientation port on Mesh, Camera, and other object nodes.
///
/// Rotation order is X → Y → Z (pitch → yaw → roll).
public class EulerOrientationNode : Node
{
    override public class var name:String { "Orientation From Euler" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts Euler angles in degrees to a quaternion orientation" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputX", ParameterPort(parameter: FloatParameter("X (Pitch)", 0.0, .inputfield, "Rotation around the X axis in degrees"))),
            ("inputY", ParameterPort(parameter: FloatParameter("Y (Yaw)", 0.0, .inputfield, "Rotation around the Y axis in degrees"))),
            ("inputZ", ParameterPort(parameter: FloatParameter("Z (Roll)", 0.0, .inputfield, "Rotation around the Z axis in degrees"))),
            ("outputOrientation", NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Quaternion orientation (X, Y, Z, W)")),
        ]
    }

    // Port Proxies
    public var inputX:ParameterPort<Float> { port(named: "inputX") }
    public var inputY:ParameterPort<Float> { port(named: "inputY") }
    public var inputZ:ParameterPort<Float> { port(named: "inputZ") }
    public var outputOrientation:NodePort<simd_float4> { port(named: "outputOrientation") }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputX.valueDidChange
              || self.inputY.valueDidChange
              || self.inputZ.valueDidChange
        else { return }

        let euler = simd_float3(self.inputX.value ?? 0, self.inputY.value ?? 0, self.inputZ.value ?? 0)
        self.outputOrientation.send(simd_quatf(eulerAnglesDegrees: euler).vector)
    }
}
