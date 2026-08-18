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
    override public class var nodeDescription: String { "Provides an Orthographic Camera for the Scene. Its view is two world units tall and as many wide as the render target's aspect, before Scale. Aim it with Orientation — Orientation Compose builds one from a target."}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
                    ("inputLookAt", ParameterPort(parameter:Float3Parameter("Look At", simd_float3(repeating:0), .inputfield, "Target position the camera points toward")) ),
                ] + ports
    }
    
    // Proxy Port
    public var inputLookAt:ParameterPort<simd_float3> { port(named: "inputLookAt") }
    
    override public var object: OrthographicCamera?
    {
        camera
    }
    
    private lazy var camera = OrthographicCamera(context:self.context, left: -1, right: 1, bottom: -1, top: 1, near: 0.01, far: 500.0)

    override public func startExecution(renderer:GraphRenderer) throws
    {
        try super.startExecution(renderer: renderer)
        
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
        
        return shouldUpdate
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let _ = self.evaluate(object: self.object, atTime: executionInfo.timing.time)
    }
    
    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        // Two world units tall, and as many wide as the aspect allows, so a
        // world unit measures the same across as it does down. Half of the
        // aspect would not: the vertical extent is the ±1 the camera is
        // constructed with, which no resize changes.
        let aspect = size.width / size.height

        self.camera.left = -aspect
        self.camera.right = aspect
    }
}
