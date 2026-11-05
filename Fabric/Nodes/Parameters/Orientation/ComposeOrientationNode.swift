//
//  ComposeOrientationNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ComposeOrientationNode: StrategyNode
{
    public override class var name: String { "Orientation Compose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Quaternion) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds an Orientation quaternion via one of several strategies: Euler angles, Axis + Angle, or aiming at a Target." }

    public override class var strategyOptions: [any NodeStrategyOption] { OrientationCompositionMode.allCases }

    /// `strategy`, typed before each reconcile, so execute switches on it without a cast.
    private var typedStrategy: OrientationCompositionMode?

    override public func prepareDeclarations()
    {
        super.prepareDeclarations()
        typedStrategy = strategyOption(as: OrientationCompositionMode.self)
    }

    override public func declaredPorts() -> [PortDeclaration]
    {
        let wanted: [(name: String, port: Port)]
        switch typedStrategy
        {
        case .euler:
            wanted =
            [
                ("inputX", ParameterPort(parameter: FloatParameter("X (Pitch)", 0.0, .inputfield, "Rotation around the X axis in degrees"))),
                ("inputY", ParameterPort(parameter: FloatParameter("Y (Yaw)", 0.0, .inputfield, "Rotation around the Y axis in degrees"))),
                ("inputZ", ParameterPort(parameter: FloatParameter("Z (Roll)", 0.0, .inputfield, "Rotation around the Z axis in degrees"))),
                ("outputOrientation", NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Quaternion orientation (X, Y, Z, W)")),
            ]

        case .axisAngle:
            wanted =
            [
                ("inputAngle", ParameterPort(parameter: FloatParameter("Angle", 0.0, .inputfield, "Rotation angle in degrees"))),
                ("inputAxis", ParameterPort(parameter: Float3Parameter("Axis", simd_float3(0, 1, 0), .inputfield, "Axis of rotation (will be normalized)"))),
                ("outputOrientation", NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Quaternion orientation (X, Y, Z, W)")),
            ]

        case .target:
            wanted =
            [
                ("inputPosition", ParameterPort(parameter: Float3Parameter("Position", simd_float3(0, 0, 0), .inputfield, "Viewpoint position (XYZ)"))),
                ("inputTarget", ParameterPort(parameter: Float3Parameter("Target", simd_float3(0, 0, 1), .inputfield, "World-space target to face (XYZ)"))),
                ("inputAimOffset", ParameterPort(parameter: Float4Parameter("Aim Offset", simd_float4(0, 0, 0, 1), .inputfield, "Rotation in the look frame after aiming (identity looks at, 180° looks away). Quaternion (X, Y, Z, W)"))),
                ("outputOrientation", NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Quaternion orientation (X, Y, Z, W)")),
            ]

        case nil:
            wanted = []
        }

        return super.declaredPorts() + wanted.map { PortDeclaration(key: $0.name, port: $0.port) }
    }

    private var boundOutputOrientation: NodePort<simd_float4>?
    private var boundInputX: ParameterPort<Float>?
    private var boundInputY: ParameterPort<Float>?
    private var boundInputZ: ParameterPort<Float>?
    private var boundInputAngle: ParameterPort<Float>?
    private var boundInputAxis: ParameterPort<simd_float3>?
    private var boundInputPosition: ParameterPort<simd_float3>?
    private var boundInputTarget: ParameterPort<simd_float3>?
    private var boundInputAimOffset: ParameterPort<simd_float4>?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundOutputOrientation = findPort(named: "outputOrientation")
        self.boundInputX = findPort(named: "inputX")
        self.boundInputY = findPort(named: "inputY")
        self.boundInputZ = findPort(named: "inputZ")
        self.boundInputAngle = findPort(named: "inputAngle")
        self.boundInputAxis = findPort(named: "inputAxis")
        self.boundInputPosition = findPort(named: "inputPosition")
        self.boundInputTarget = findPort(named: "inputTarget")
        self.boundInputAimOffset = findPort(named: "inputAimOffset")
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let outputOrientation: NodePort<simd_float4> = self.boundOutputOrientation else { return }

        switch typedStrategy
        {
        case .euler:
            guard let inputX: ParameterPort<Float> = self.boundInputX,
                  let inputY: ParameterPort<Float> = self.boundInputY,
                  let inputZ: ParameterPort<Float> = self.boundInputZ
            else { return }
            guard inputX.valueDidChange || inputY.valueDidChange || inputZ.valueDidChange else { return }

            let euler = simd_float3(inputX.value ?? 0, inputY.value ?? 0, inputZ.value ?? 0)
            outputOrientation.send(simd_quatf(eulerAnglesDegrees: euler).vector)

        case .axisAngle:
            guard let inputAngle: ParameterPort<Float> = self.boundInputAngle,
                  let inputAxis: ParameterPort<simd_float3> = self.boundInputAxis
            else { return }
            guard inputAngle.valueDidChange || inputAxis.valueDidChange else { return }

            let quat = simd_quatf(axis: inputAxis.value ?? simd_float3(0, 1, 0), angleDegrees: inputAngle.value ?? 0)
            outputOrientation.send(quat.vector)

        case .target:
            guard let inputPosition: ParameterPort<simd_float3> = self.boundInputPosition,
                  let inputTarget: ParameterPort<simd_float3> = self.boundInputTarget,
                  let inputAimOffset: ParameterPort<simd_float4> = self.boundInputAimOffset
            else { return }
            guard inputPosition.valueDidChange || inputTarget.valueDidChange
                || inputAimOffset.valueDidChange
            else { return }

            let position = inputPosition.value ?? simd_float3(0, 0, 0)
            let target = inputTarget.value ?? simd_float3(0, 0, 1)
            let offset = simd_quatf(safeVector: inputAimOffset.value ?? simd_float4(0, 0, 0, 1))

            let look = simd_quatf(lookingAlong: position - target , up: Satin.worldUpDirection)
            outputOrientation.send((look * offset).vector)

        case nil:
            break
        }
    }
}
