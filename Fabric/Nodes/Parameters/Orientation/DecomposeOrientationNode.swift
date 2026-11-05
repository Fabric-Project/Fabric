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

    /// `strategy`, typed before each reconcile, so execute switches on it without a cast.
    private var typedStrategy: OrientationDecompositionMode?

    override public func prepareDeclarations()
    {
        super.prepareDeclarations()
        typedStrategy = strategyOption(as: OrientationDecompositionMode.self)
    }

    override public func declaredPorts() -> [PortDeclaration]
    {
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

        return super.declaredPorts() + wanted.map { PortDeclaration(key: $0.name, port: $0.port) }
    }

    private var boundInputOrientation: ParameterPort<simd_float4>?
    private var boundOutputX: NodePort<Float>?
    private var boundOutputY: NodePort<Float>?
    private var boundOutputZ: NodePort<Float>?
    private var boundOutputAxis: NodePort<simd_float3>?
    private var boundOutputAngle: NodePort<Float>?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputOrientation = findPort(named: "inputOrientation")
        self.boundOutputX = findPort(named: "outputX")
        self.boundOutputY = findPort(named: "outputY")
        self.boundOutputZ = findPort(named: "outputZ")
        self.boundOutputAxis = findPort(named: "outputAxis")
        self.boundOutputAngle = findPort(named: "outputAngle")
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputOrientation: ParameterPort<simd_float4> = self.boundInputOrientation,
              inputOrientation.valueDidChange,
              let orientationVector = inputOrientation.value
        else { return }

        let quat = simd_quatf(safeVector: orientationVector)

        switch typedStrategy
        {
        case .toEuler:
            guard let outputX: NodePort<Float> = self.boundOutputX,
                  let outputY: NodePort<Float> = self.boundOutputY,
                  let outputZ: NodePort<Float> = self.boundOutputZ
            else { return }

            let euler = quat.eulerAnglesDegreesXYZ
            outputX.send(euler.x)
            outputY.send(euler.y)
            outputZ.send(euler.z)

        case .toAxisAngle:
            guard let outputAxis: NodePort<simd_float3> = self.boundOutputAxis,
                  let outputAngle: NodePort<Float> = self.boundOutputAngle
            else { return }

            let (axis, angleDegrees) = quat.axisAngleDegrees
            outputAxis.send(axis)
            outputAngle.send(angleDegrees)

        case nil:
            break
        }
    }
}
