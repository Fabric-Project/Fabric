//
//  ComposeOrientationNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

@Observable public class ComposeOrientationNode: StrategyNode
{
    public override class var name: String { "Orientation Compose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Quaternion) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds an Orientation quaternion via one of several strategies: Euler angles, Axis + Angle, or aiming at a Target." }

    public override class var strategies: [String] { ["Euler", "Axis Angle", "Target"] }

    private static let allDynamicNames: Set<String> = [
        "inputX", "inputY", "inputZ",
        "inputAngle", "inputAxis",
        "inputPosition", "inputTarget", "inputUpOrientation", "inputAimOffset",
        "outputOrientation",
    ]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        let wanted: [(name: String, port: Port)]
        switch strategy
        {
        case "Euler":
            wanted =
            [
                ("inputX", ParameterPort(parameter: FloatParameter("X (Pitch)", 0.0, .inputfield, "Rotation around the X axis in degrees"))),
                ("inputY", ParameterPort(parameter: FloatParameter("Y (Yaw)", 0.0, .inputfield, "Rotation around the Y axis in degrees"))),
                ("inputZ", ParameterPort(parameter: FloatParameter("Z (Roll)", 0.0, .inputfield, "Rotation around the Z axis in degrees"))),
                ("outputOrientation", NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Quaternion orientation (X, Y, Z, W)")),
            ]

        case "Axis Angle":
            wanted =
            [
                ("inputAngle", ParameterPort(parameter: FloatParameter("Angle", 0.0, .inputfield, "Rotation angle in degrees"))),
                ("inputAxis", ParameterPort(parameter: Float3Parameter("Axis", simd_float3(0, 1, 0), .inputfield, "Axis of rotation (will be normalized)"))),
                ("outputOrientation", NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Quaternion orientation (X, Y, Z, W)")),
            ]

        case "Target":
            wanted =
            [
                ("inputPosition", ParameterPort(parameter: Float3Parameter("Position", simd_float3(0, 0, 0), .inputfield, "Viewpoint position (XYZ)"))),
                ("inputTarget", ParameterPort(parameter: Float3Parameter("Target", simd_float3(0, 0, 1), .inputfield, "World-space target to face (XYZ)"))),
                ("inputUpOrientation", ParameterPort(parameter: Float4Parameter("Up Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Roll reference; local +Z is the up direction (identity gives world +Z). Quaternion (X, Y, Z, W)"))),
                ("inputAimOffset", ParameterPort(parameter: Float4Parameter("Aim Offset", simd_float4(0, 0, 0, 1), .inputfield, "Rotation in the look frame after aiming (identity looks at, 180° looks away). Quaternion (X, Y, Z, W)"))),
                ("outputOrientation", NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Quaternion orientation (X, Y, Z, W)")),
            ]

        default:
            wanted = []
        }

        let wantedNames = Set(wanted.map(\.name))
        for name in Self.allDynamicNames.subtracting(wantedNames)
        {
            if let p = findPort(named: name) { removePort(p) }
        }
        for (name, p) in wanted where findPort(named: name) == nil
        {
            addDynamicPort(p, name: name)
        }
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let outputOrientation: NodePort<simd_float4> = findPort(named: "outputOrientation") else { return }

        switch self.strategy
        {
        case "Euler":
            guard let inputX: ParameterPort<Float> = findPort(named: "inputX"),
                  let inputY: ParameterPort<Float> = findPort(named: "inputY"),
                  let inputZ: ParameterPort<Float> = findPort(named: "inputZ")
            else { return }
            guard inputX.valueDidChange || inputY.valueDidChange || inputZ.valueDidChange else { return }

            let euler = simd_float3(inputX.value ?? 0, inputY.value ?? 0, inputZ.value ?? 0)
            outputOrientation.send(simd_quatf(eulerAnglesDegrees: euler).vector)

        case "Axis Angle":
            guard let inputAngle: ParameterPort<Float> = findPort(named: "inputAngle"),
                  let inputAxis: ParameterPort<simd_float3> = findPort(named: "inputAxis")
            else { return }
            guard inputAngle.valueDidChange || inputAxis.valueDidChange else { return }

            let quat = simd_quatf(axis: inputAxis.value ?? simd_float3(0, 1, 0), angleDegrees: inputAngle.value ?? 0)
            outputOrientation.send(quat.vector)

        case "Target":
            guard let inputPosition: ParameterPort<simd_float3> = findPort(named: "inputPosition"),
                  let inputTarget: ParameterPort<simd_float3> = findPort(named: "inputTarget"),
                  let inputUpOrientation: ParameterPort<simd_float4> = findPort(named: "inputUpOrientation"),
                  let inputAimOffset: ParameterPort<simd_float4> = findPort(named: "inputAimOffset")
            else { return }
            guard inputPosition.valueDidChange || inputTarget.valueDidChange
                || inputUpOrientation.valueDidChange || inputAimOffset.valueDidChange
            else { return }

            let position = inputPosition.value ?? simd_float3(0, 0, 0)
            let target = inputTarget.value ?? simd_float3(0, 0, 1)
            let up = simd_quatf.upDirection(from: inputUpOrientation.value ?? simd_float4(0, 0, 0, 1))
            let offset = simd_quatf(safeVector: inputAimOffset.value ?? simd_float4(0, 0, 0, 1))

            let look = simd_quatf(lookingAlong: target - position, up: up)
            outputOrientation.send((look * offset).vector)

        default:
            break
        }
    }
}
