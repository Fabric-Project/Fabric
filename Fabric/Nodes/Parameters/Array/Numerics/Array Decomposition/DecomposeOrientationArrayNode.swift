//
//  DecomposeOrientationArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class DecomposeOrientationArrayNode: StrategyNode
{
    public override class var name: String { "Orientation Array Decompose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Quaternion) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits an array of Orientation quaternions into per-element Euler angles or Axis + Angle, depending on strategy." }

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
                ("inputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Inlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
                ("outputX", NodePort<ContiguousArray<Float>>(name: "X (Pitch)", kind: .Outlet, description: "Per-element rotation around the X axis in degrees")),
                ("outputY", NodePort<ContiguousArray<Float>>(name: "Y (Yaw)", kind: .Outlet, description: "Per-element rotation around the Y axis in degrees")),
                ("outputZ", NodePort<ContiguousArray<Float>>(name: "Z (Roll)", kind: .Outlet, description: "Per-element rotation around the Z axis in degrees")),
            ]

        case .toAxisAngle:
            wanted =
            [
                ("inputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Inlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
                ("outputAxes", NodePort<ContiguousArray<simd_float3>>(name: "Axes", kind: .Outlet, description: "Per-element normalized rotation axis")),
                ("outputAngles", NodePort<ContiguousArray<Float>>(name: "Angles", kind: .Outlet, description: "Per-element rotation angle in degrees")),
            ]

        case nil:
            wanted = []
        }

        return super.declaredPorts() + wanted.map { PortDeclaration(key: $0.name, port: $0.port) }
    }

    private var boundInputOrientations: NodePort<ContiguousArray<simd_float4>>?
    private var boundOutputX: NodePort<ContiguousArray<Float>>?
    private var boundOutputY: NodePort<ContiguousArray<Float>>?
    private var boundOutputZ: NodePort<ContiguousArray<Float>>?
    private var boundOutputAxes: NodePort<ContiguousArray<simd_float3>>?
    private var boundOutputAngles: NodePort<ContiguousArray<Float>>?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputOrientations = findPort(named: "inputOrientations")
        self.boundOutputX = findPort(named: "outputX")
        self.boundOutputY = findPort(named: "outputY")
        self.boundOutputZ = findPort(named: "outputZ")
        self.boundOutputAxes = findPort(named: "outputAxes")
        self.boundOutputAngles = findPort(named: "outputAngles")
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputOrientations: NodePort<ContiguousArray<simd_float4>> = self.boundInputOrientations,
              inputOrientations.valueDidChange
        else { return }

        let orientations = inputOrientations.value ?? ContiguousArray<simd_float4>()
        let quats = orientations.map { simd_quatf(safeVector: $0) }

        switch typedStrategy
        {
        case .toEuler:
            guard let outputX: NodePort<ContiguousArray<Float>> = self.boundOutputX,
                  let outputY: NodePort<ContiguousArray<Float>> = self.boundOutputY,
                  let outputZ: NodePort<ContiguousArray<Float>> = self.boundOutputZ
            else { return }

            var xs = ContiguousArray<Float>(); xs.reserveCapacity(quats.count)
            var ys = ContiguousArray<Float>(); ys.reserveCapacity(quats.count)
            var zs = ContiguousArray<Float>(); zs.reserveCapacity(quats.count)
            for q in quats {
                let euler = q.eulerAnglesDegreesXYZ
                xs.append(euler.x)
                ys.append(euler.y)
                zs.append(euler.z)
            }
            outputX.send(xs)
            outputY.send(ys)
            outputZ.send(zs)

        case .toAxisAngle:
            guard let outputAxes: NodePort<ContiguousArray<simd_float3>> = self.boundOutputAxes,
                  let outputAngles: NodePort<ContiguousArray<Float>> = self.boundOutputAngles
            else { return }

            var axes = ContiguousArray<simd_float3>(); axes.reserveCapacity(quats.count)
            var angles = ContiguousArray<Float>(); angles.reserveCapacity(quats.count)
            for q in quats {
                let (axis, angleDegrees) = q.axisAngleDegrees
                axes.append(axis)
                angles.append(angleDegrees)
            }
            outputAxes.send(axes)
            outputAngles.send(angles)

        case nil:
            break
        }
    }
}
