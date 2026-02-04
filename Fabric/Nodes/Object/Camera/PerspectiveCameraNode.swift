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
                ] + ports
    }
    
    // Proxy Port
    public var inputLookAt:ParameterPort<simd_float3> { port(named: "inputLookAt") }
    
    override public var object: PerspectiveCamera?
    {
        camera
    }
    
    private let camera = PerspectiveCamera(position: .init(repeating: 5.0), near: 0.01, far: 500.0, fov: 30)

    override public func startExecution(context:GraphExecutionContext)
    {
        super.startExecution(context: context)
                
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
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let _ = self.evaluate(object: self.camera, atTime: context.timing.time)
    }
    
    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.camera.aspect = size.width / size.height
    }
    
  
}

