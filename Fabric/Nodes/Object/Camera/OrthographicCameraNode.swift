//
//  OrthographicCameraNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import simd
import Metal

public class OrthographicCameraNode : ObjectNode<OrthographicCamera>
{
    public static let defaultSize: Float = 2.0
    public static let defaultSizingDimension: String = "Width"
    public static let defaultPosition: simd_float3 = .init(0, 0, 2)

    public override class var name:String { "Orthographic Camera" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Object(objectType: .Camera) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provides an Orthographic Camera for the Scene."}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return  [
                    ("inputLookAt", ParameterPort(parameter:Float3Parameter("Look At", simd_float3(repeating:0), .inputfield, "Target position the camera points toward")) ),
                    ("inputSize", ParameterPort(parameter:FloatParameter("Size", 2.0, 0.001, 10000.0, .inputfield, "Visible world units along the sizing dimension")) ),
                    ("inputSizingDimension", ParameterPort(parameter:StringParameter("Sizing Dimension", "Width", ["Width", "Height"], .dropdown, "Which dimension the size applies to")) ),
                ] + ports
    }

    // Proxy Ports
    public var inputLookAt:ParameterPort<simd_float3> { port(named: "inputLookAt") }
    public var inputSize:ParameterPort<Float> { port(named: "inputSize") }
    public var inputSizingDimension:ParameterPort<String> { port(named: "inputSizingDimension") }

    override public var object: OrthographicCamera?
    {
        camera
    }

    private let camera = OrthographicCamera(left: -1, right: 1, bottom: -1, top: 1, near: 0.01, far: 500.0)
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

        if self.inputSize.valueDidChange || self.inputSizingDimension.valueDidChange {
            self.updateBounds()
        }

        return shouldUpdate
    }

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let _ = self.evaluate(object: self.object, atTime: context.timing.time)
    }

    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.viewportSize = size
        self.updateBounds()
    }

    private func updateBounds()
    {
        let size = self.inputSize.value ?? Self.defaultSize
        let halfSize = size / 2.0
        let aspect = viewportSize.width / viewportSize.height
        let sizing = self.inputSizingDimension.value ?? Self.defaultSizingDimension

        if sizing == "Width" {
            self.camera.left = -halfSize
            self.camera.right = halfSize
            self.camera.bottom = -halfSize / aspect
            self.camera.top = halfSize / aspect
        } else {
            self.camera.bottom = -halfSize
            self.camera.top = halfSize
            self.camera.left = -halfSize * aspect
            self.camera.right = halfSize * aspect
        }
    }
}
