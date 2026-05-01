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

public class OrthographicCameraNode : ObjectNode<OrthographicCamera>
{
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
                    ("inputSizingDimension", ParameterPort(parameter:StringParameter("Sizing Dimension", "Height", ["Width", "Height"], .dropdown, "Which dimension maps to -1,+1")) ),
                ] + ports
    }

    // Proxy Ports
    public var inputLookAt:ParameterPort<simd_float3> { port(named: "inputLookAt") }
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
        
        self.inputPosition.value = .init(repeating: 5.0)
        
        self.camera.lookAt(target: self.inputLookAt.value ?? .zero)
        self.camera.position = self.inputPosition.value ?? .zero
        self.camera.scale = self.inputScale.value ?? .one
        
        let orientation = self.inputOrientation.value ?? .zero
        self.camera.orientation = simd_quatf(vector:orientation)
    }

    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        let shouldUpdate = super.evaluate(object: object, atTime: atTime)

        // This needs to fire every frame
        self.camera.lookAt(target: self.inputLookAt.value ?? .zero)

        if self.inputSizingDimension.valueDidChange {
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
        let aspect = viewportSize.width / viewportSize.height
        let sizing = self.inputSizingDimension.value ?? "Height"

        if sizing == "Width" {
            self.camera.left = -1
            self.camera.right = 1
            self.camera.bottom = -1 / aspect
            self.camera.top = 1 / aspect
        } else {
            self.camera.bottom = -1
            self.camera.top = 1
            self.camera.left = -aspect / 2.0
            self.camera.right = aspect / 2.0
        }
    }
}

