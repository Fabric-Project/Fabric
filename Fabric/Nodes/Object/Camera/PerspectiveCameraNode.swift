//
//  PerspectiveCameraNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import simd
import Metal

public class PerspectiveCameraNode : ObjectNode<PerspectiveCamera>
{
    public static let defaultFOV: Float = 30.0
    /// Z distance derived so that width = 2 world units at the origin: Z = 1 / tan(hfov/2)
    public static let defaultPosition: simd_float3 = .init(0, 0, 1.0 / tan(degToRad(defaultFOV) / 2.0))
    public static let defaultSizingDimension: String = "Width"

    /// Create a `PerspectiveCamera` configured with the node's default values.
    /// Used by `GraphRenderer` as the fallback when no camera node is in the graph.
    public static func makeDefaultCamera() -> PerspectiveCamera {
        let cam = PerspectiveCamera(position: defaultPosition,
                                    near: 0.01,
                                    far: 500.0,
                                    fov: defaultFOV)
        cam.lookAt(target: .zero)
        return cam
    }

    /// Resize a `PerspectiveCamera` using the node's default FOV and sizing dimension.
    public static func resizeDefaultCamera(_ camera: PerspectiveCamera, size: (width: Float, height: Float)) {
        camera.aspect = size.width / size.height
        camera.setFOV(defaultFOV, sizing: defaultSizingDimension)
    }

    override public class var name:String { "Perspective Camera" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Object(objectType: .Camera) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provides a Perspective Camera for the Scene."}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return  [
                    ("inputLookAt", ParameterPort(parameter:Float3Parameter("Look At", simd_float3(repeating:0), .inputfield, "Target position the camera points toward")) ),
                    ("inputFOV", ParameterPort(parameter:FloatParameter("FOV", 30.0, 1.0, 179.0, .inputfield, "Field of view in degrees")) ),
                    ("inputSizingDimension", ParameterPort(parameter:StringParameter("Sizing Dimension", "Width", ["Width", "Height"], .dropdown, "Which dimension the FOV applies to")) ),
                ] + ports
    }

    // Proxy Ports
    public var inputLookAt:ParameterPort<simd_float3> { port(named: "inputLookAt") }
    public var inputFOV:ParameterPort<Float> { port(named: "inputFOV") }
    public var inputSizingDimension:ParameterPort<String> { port(named: "inputSizingDimension") }
    
    override public var object: PerspectiveCamera?
    {
        camera
    }

    private let camera = PerspectiveCamera(position: defaultPosition, near: 0.01, far: 500.0, fov: defaultFOV)
    private var viewportSize: (width: Float, height: Float) = (1, 1)

    override public func startExecution(context:GraphExecutionContext)
    {
        super.startExecution(context: context)

        self.inputPosition.value = Self.defaultPosition

        self.camera.lookAt(target: self.inputLookAt.value ?? .zero)
        self.camera.position = self.inputPosition.value ?? Self.defaultPosition
        self.camera.scale = self.inputScale.value ?? .one

        let orientation = self.inputOrientation.value ?? .zero
        self.camera.orientation = simd_quatf(vector:orientation)
    }

    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        let shouldUpdate = super.evaluate(object: object, atTime: atTime)

        // This needs to fire every frame
        self.camera.lookAt(target: self.inputLookAt.value ?? .zero)

        if self.inputFOV.valueDidChange || self.inputSizingDimension.valueDidChange {
            self.camera.setFOV(self.inputFOV.value ?? Self.defaultFOV,
                                          sizing: self.inputSizingDimension.value ?? Self.defaultSizingDimension)
        }

        return shouldUpdate
    }

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let _ = self.evaluate(object: self.camera, atTime: context.timing.time)
    }

    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.viewportSize = size
        self.camera.aspect = size.width / size.height
        self.camera.setFOV(self.inputFOV.value ?? Self.defaultFOV,
                           sizing: self.inputSizingDimension.value ?? Self.defaultSizingDimension)
    }
}

