//
//  DecomposeOrientationNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class DecomposeOrientationNode: StrategyNode
{
    public override class var name: String { "Orientation Decompose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Quaternion) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits an Orientation quaternion into its Euler angles or Axis + Angle, depending on strategy." }

    public override class var strategyOptions: [any NodeStrategyOption] { OrientationDecompositionMode.allCases }

    private static let allDynamicNames: Set<String> = [
        "inputOrientation",
        "outputX", "outputY", "outputZ",
        "outputAxis", "outputAngle",
    ]

    /// `strategy`, typed once per rebuild, so execute never compares strategy strings.
    private var typedStrategy: OrientationDecompositionMode?

    public override func rebuildPorts(forStrategy strategy: (any NodeStrategyOption)?)
    {
        typedStrategy = strategy as? OrientationDecompositionMode

        let wanted: [(name: String, port: Port)]
        switch typedStrategy
        {
        case .toEuler:
            wanted =
            [
                ("inputOrientation", ParameterPort(parameter: Float4Parameter("Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Quaternion orientation (X, Y, Z, W)"))),
                ("outputX", NodePort<Float>(name: "X (Pitch)", kind: .Outlet, description: "Rotation around the X axis in degrees")),
                ("outputY", NodePort<Float>(name: "Y (Yaw)", kind: .Outlet, description: "Rotation around the Y axis in degrees")),
                ("outputZ", NodePort<Float>(name: "Z (Roll)", kind: .Outlet, description: "Rotation around the Z axis in degrees")),
            ]

        case .toAxisAngle:
            wanted =
            [
                ("inputOrientation", ParameterPort(parameter: Float4Parameter("Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Quaternion orientation (X, Y, Z, W)"))),
                ("outputAxis", NodePort<simd_float3>(name: "Axis", kind: .Outlet, description: "Normalized rotation axis")),
                ("outputAngle", NodePort<Float>(name: "Angle", kind: .Outlet, description: "Rotation angle in degrees")),
            ]

        case nil:
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
    throws
    {
        guard let inputOrientation: ParameterPort<simd_float4> = findPort(named: "inputOrientation"),
              inputOrientation.valueDidChange,
              let orientationVector = inputOrientation.value
        else { return }

        let quat = simd_quatf(safeVector: orientationVector)

        switch typedStrategy
        {
        case .toEuler:
            guard let outputX: NodePort<Float> = findPort(named: "outputX"),
                  let outputY: NodePort<Float> = findPort(named: "outputY"),
                  let outputZ: NodePort<Float> = findPort(named: "outputZ")
            else { return }

            let euler = quat.eulerAnglesDegreesXYZ
            outputX.send(euler.x)
            outputY.send(euler.y)
            outputZ.send(euler.z)

        case .toAxisAngle:
            guard let outputAxis: NodePort<simd_float3> = findPort(named: "outputAxis"),
                  let outputAngle: NodePort<Float> = findPort(named: "outputAngle")
            else { return }

            let (axis, angleDegrees) = quat.axisAngleDegrees
            outputAxis.send(axis)
            outputAngle.send(angleDegrees)

        case nil:
            break
        }
    }
}
